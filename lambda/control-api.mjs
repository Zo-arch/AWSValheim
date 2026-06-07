import { DescribeInstancesCommand, EC2Client, StartInstancesCommand, StopInstancesCommand } from "@aws-sdk/client-ec2";
import { GetCommandInvocationCommand, SendCommandCommand, SSMClient } from "@aws-sdk/client-ssm";
import { createHash, timingSafeEqual } from "node:crypto";

const ec2 = new EC2Client({});
const ssm = new SSMClient({});

const {
  BACKUP_BUCKET_NAME,
  BACKUP_PREFIX,
  CONTROL_PASSWORD_HASH,
  INSTANCE_HOURLY_USD,
  INSTANCE_ID,
  INSTANCE_TYPE,
  USD_TO_BRL_RATE,
  VALHEIM_PORT,
} = process.env;

export async function handler(event) {
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? "GET";
  const path = normalizePath(event.rawPath ?? event.path ?? "/");

  if (method === "OPTIONS") {
    return response(204, "");
  }

  try {
    if (!isAuthorized(event)) {
      return response(401, { error: "Senha invalida." });
    }

    if (method === "GET" && path === "/status") {
      return response(200, await buildStatus("Status atualizado."));
    }

    if (method === "POST" && path === "/start") {
      return response(200, await startServer());
    }

    if (method === "POST" && path === "/stop") {
      return response(200, await stopServer());
    }

    return response(404, { error: "Rota nao encontrada." });
  } catch (error) {
    console.error(error);
    return response(500, { error: error.message });
  }
}

async function startServer() {
  const current = await describeInstance();
  const state = current.State?.Name ?? "unknown";

  if (state === "running") {
    return buildStatus("Servidor ja esta rodando.");
  }

  if (state !== "pending") {
    await ec2.send(new StartInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
  }

  await waitForState("running");
  return buildStatus("Servidor iniciado.");
}

async function stopServer() {
  const current = await describeInstance();
  const state = current.State?.Name ?? "unknown";

  if (state === "stopped") {
    return buildStatus("Servidor ja esta parado.");
  }

  if (state !== "stopping") {
    const backupS3Uri = await backupWorldFiles();
    await ec2.send(new StopInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
    await waitForState("stopped");
    return buildStatus(`Backup concluido em ${backupS3Uri}. Servidor parado.`);
  }

  await waitForState("stopped");
  return buildStatus("Servidor parado.");
}

async function buildStatus(message) {
  const instance = await describeInstance();
  const ec2State = instance.State?.Name ?? "unknown";
  const publicIp = instance.PublicIpAddress ?? null;
  const launchTime = instance.LaunchTime ? new Date(instance.LaunchTime).toISOString() : null;
  const runningSince = ec2State === "running" ? launchTime : null;
  const uptimeSeconds = runningSince ? Math.max(0, Math.floor((Date.now() - Date.parse(runningSince)) / 1000)) : 0;
  const hourlyUsd = Number(INSTANCE_HOURLY_USD ?? "0");
  const usdToBrl = Number(USD_TO_BRL_RATE ?? "0");
  const estimatedUsd = hourlyUsd > 0 ? (uptimeSeconds / 3600) * hourlyUsd : null;
  const estimatedBrl = estimatedUsd !== null && usdToBrl > 0 ? estimatedUsd * usdToBrl : null;

  return {
    message,
    checkedAt: new Date().toISOString(),
    server: {
      state: ec2State,
      publicIp,
      port: Number(VALHEIM_PORT ?? "2456"),
      address: publicIp ? `${publicIp}:${VALHEIM_PORT ?? "2456"}` : null,
      instanceId: INSTANCE_ID,
      instanceType: INSTANCE_TYPE,
      runningSince,
      uptimeSeconds,
    },
    cost: {
      hourlyUsd,
      usdToBrl,
      estimatedUsd,
      estimatedBrl,
    },
    operation: {
      status: "idle",
      message,
      updatedAt: new Date().toISOString(),
    },
  };
}

async function describeInstance() {
  const result = await ec2.send(new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
  return result.Reservations?.[0]?.Instances?.[0] ?? {};
}

async function backupWorldFiles() {
  const script = `
#!/usr/bin/env bash
set -euo pipefail
BACKUP_BUCKET_NAME="$1"
BACKUP_PREFIX="$2"
HELPER_SCRIPT="/usr/local/bin/backup-valheim-world.sh"

if [[ -x "$HELPER_SCRIPT" ]]; then
  BACKUP_BUCKET_NAME="$BACKUP_BUCKET_NAME" BACKUP_PREFIX="$BACKUP_PREFIX" "$HELPER_SCRIPT"
  exit 0
fi

VALHEIM_ENV_FILE="/etc/valheim/valheim.env"
VALHEIM_WORLDS_DIR="/srv/valheim/worlds_local"
VALHEIM_BACKUP_TMP_DIR="/tmp/valheim-backups"

if [[ ! -f "$VALHEIM_ENV_FILE" ]]; then
  echo "Valheim env file not found: $VALHEIM_ENV_FILE" >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is not installed." >&2
  exit 1
fi

source "$VALHEIM_ENV_FILE"

if [[ -z "\${WORLD_NAME:-}" ]]; then
  echo "WORLD_NAME is not set in $VALHEIM_ENV_FILE" >&2
  exit 1
fi

WORLD_DB="$VALHEIM_WORLDS_DIR/\${WORLD_NAME}.db"
WORLD_FWL="$VALHEIM_WORLDS_DIR/\${WORLD_NAME}.fwl"

if [[ ! -f "$WORLD_DB" || ! -f "$WORLD_FWL" ]]; then
  echo "World files not found for $WORLD_NAME" >&2
  exit 1
fi

mkdir -p "$VALHEIM_BACKUP_TMP_DIR"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
ARCHIVE_NAME="\${WORLD_NAME}-world-backup-\${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="$VALHEIM_BACKUP_TMP_DIR/$ARCHIVE_NAME"
S3_URI="s3://$BACKUP_BUCKET_NAME/\${BACKUP_PREFIX%/}/$ARCHIVE_NAME"

tar -czf "$ARCHIVE_PATH" -C "$VALHEIM_WORLDS_DIR" "\${WORLD_NAME}.db" "\${WORLD_NAME}.fwl"
aws s3 cp "$ARCHIVE_PATH" "$S3_URI"
rm -f "$ARCHIVE_PATH"

echo "backup_s3_uri=$S3_URI"
`;

  const sendResult = await ssm.send(new SendCommandCommand({
    DocumentName: "AWS-RunShellScript",
    InstanceIds: [INSTANCE_ID],
    Parameters: {
      commands: [
        `cat <<'EOF' >/tmp/valheim-backup-command.sh
${script.trim()}
EOF
chmod 700 /tmp/valheim-backup-command.sh
bash /tmp/valheim-backup-command.sh ${shellArg(BACKUP_BUCKET_NAME)} ${shellArg(BACKUP_PREFIX ?? "backups/worlds")}`,
      ],
    },
  }));

  const commandId = sendResult.Command?.CommandId;
  if (!commandId) {
    throw new Error("Nao foi possivel disparar o backup via SSM.");
  }

  for (let attempt = 0; attempt < 90; attempt += 1) {
    await sleep(5000);

    const invocation = await ssm.send(new GetCommandInvocationCommand({
      CommandId: commandId,
      InstanceId: INSTANCE_ID,
    }));

    if (["Pending", "InProgress", "Delayed"].includes(invocation.Status ?? "")) {
      continue;
    }

    if (invocation.Status !== "Success") {
      throw new Error(`Backup falhou via SSM: ${(invocation.StandardErrorContent ?? invocation.Status).trim()}`);
    }

    const output = invocation.StandardOutputContent ?? "";
    const match = output.match(/backup_s3_uri=(.+)/);
    if (!match) {
      throw new Error("Backup concluiu sem retornar o destino no S3.");
    }

    return match[1].trim();
  }

  throw new Error("Timeout aguardando backup via SSM.");
}

async function waitForState(expectedState) {
  for (let attempt = 0; attempt < 90; attempt += 1) {
    const instance = await describeInstance();

    if (instance.State?.Name === expectedState) {
      return instance;
    }

    await sleep(5000);
  }

  throw new Error(`Timeout aguardando instancia chegar em ${expectedState}.`);
}

function isAuthorized(event) {
  const expectedHash = normalizeHash(CONTROL_PASSWORD_HASH);
  const password = getHeader(event, "x-control-password") ?? getBearerToken(event);

  if (!expectedHash || !password) {
    return false;
  }

  const actualHash = createHash("sha256").update(password, "utf8").digest("hex");
  const expected = Buffer.from(expectedHash, "hex");
  const actual = Buffer.from(actualHash, "hex");

  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

function getBearerToken(event) {
  const authorization = getHeader(event, "authorization");
  const match = authorization?.match(/^Bearer\s+(.+)$/i);
  return match?.[1];
}

function normalizeHash(hash) {
  const normalized = hash?.trim().toLowerCase();
  return /^[a-f0-9]{64}$/.test(normalized ?? "") ? normalized : undefined;
}

function normalizePath(path) {
  const normalized = path.endsWith("/") && path !== "/" ? path.slice(0, -1) : path;
  return normalized || "/";
}

function getHeader(event, name) {
  const headers = event.headers ?? {};
  const lower = name.toLowerCase();

  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lower) {
      return value;
    }
  }

  return undefined;
}

function response(statusCode, body) {
  const isText = typeof body === "string";

  return {
    statusCode,
    headers: {
      "content-type": isText ? "text/plain; charset=utf-8" : "application/json",
    },
    body: isText ? body : JSON.stringify(body),
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function shellArg(value) {
  return `'${String(value).replace(/'/g, `'\"'\"'`)}'`;
}
