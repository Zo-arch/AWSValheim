import { EC2Client, DescribeInstancesCommand, StartInstancesCommand, StopInstancesCommand } from "@aws-sdk/client-ec2";
import { InvokeCommand, LambdaClient } from "@aws-sdk/client-lambda";
import { createPublicKey, verify } from "node:crypto";

const ec2 = new EC2Client({});
const lambda = new LambdaClient({});

const {
  DISCORD_ALLOWED_ROLE_ID,
  DISCORD_APPLICATION_ID,
  DISCORD_GUILD_ID,
  DISCORD_PUBLIC_KEY,
  INSTANCE_ID,
  LAMBDA_FUNCTION_NAME,
} = process.env;

const json = (statusCode, body) => ({
  statusCode,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

const text = (content) => ({ content });

export async function handler(event) {
  if (event.worker === true) {
    console.log(JSON.stringify({
      stage: "worker_start",
      command: event.command,
      hasInteractionToken: Boolean(event.interactionToken),
    }));
    await runWorker(event);
    return;
  }

  console.log(JSON.stringify({
    stage: "request_received",
    requestId: event.requestContext?.requestId,
    hasBody: Boolean(event.body),
    headers: Object.keys(event.headers ?? {}),
  }));

  if (!isValidDiscordRequest(event)) {
    console.warn(JSON.stringify({
      stage: "invalid_signature",
      requestId: event.requestContext?.requestId,
    }));
    return json(401, { error: "invalid request signature" });
  }

  const interaction = JSON.parse(event.body ?? "{}");
  console.log(JSON.stringify({
    stage: "interaction_parsed",
    requestId: event.requestContext?.requestId,
    type: interaction.type,
    guildId: interaction.guild_id,
    commandName: interaction.data?.name,
    subcommand: interaction.data?.options?.[0]?.name,
  }));

  if (interaction.type === 1) {
    return json(200, { type: 1 });
  }

  if (interaction.guild_id !== DISCORD_GUILD_ID) {
    return json(200, {
      type: 4,
      data: text("Este comando nao esta liberado neste servidor Discord."),
    });
  }

  const roles = interaction.member?.roles ?? [];
  if (!roles.includes(DISCORD_ALLOWED_ROLE_ID)) {
    return json(200, {
      type: 4,
      data: text("Voce nao tem permissao para controlar o servidor Valheim."),
    });
  }

  const subcommand = interaction.data?.options?.[0]?.name;
  if (!["start", "ip", "stop"].includes(subcommand)) {
    return json(200, {
      type: 4,
      data: text("Comando invalido. Use /valheim start, /valheim ip ou /valheim stop."),
    });
  }

  console.log(JSON.stringify({
    stage: "invoking_worker",
    requestId: event.requestContext?.requestId,
    subcommand,
  }));

  await lambda.send(new InvokeCommand({
    FunctionName: LAMBDA_FUNCTION_NAME,
    InvocationType: "Event",
    Payload: Buffer.from(JSON.stringify({
      worker: true,
      command: subcommand,
      interactionToken: interaction.token,
    })),
  }));

  return json(200, {
    type: 5,
  });
}

function isValidDiscordRequest(event) {
  const signature = getHeader(event, "x-signature-ed25519");
  const timestamp = getHeader(event, "x-signature-timestamp");
  const body = event.body ?? "";

  if (!signature || !timestamp || !DISCORD_PUBLIC_KEY) {
    return false;
  }

  const publicKey = createPublicKey({
    key: Buffer.from(`302a300506032b6570032100${DISCORD_PUBLIC_KEY}`, "hex"),
    format: "der",
    type: "spki",
  });

  return verify(
    null,
    Buffer.from(`${timestamp}${body}`),
    publicKey,
    Buffer.from(signature, "hex"),
  );
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

async function runWorker(event) {
  const command = event.command;

  try {
    if (command === "start") {
      await ec2.send(new StartInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
      const instance = await waitForState("running");
      const ip = instance.PublicIpAddress;
      console.log(JSON.stringify({ stage: "worker_complete", command, state: "running", ip }));
      await editDiscordResponse(event.interactionToken, `Servidor iniciado. IP publico: ${ip}`);
      return;
    }

    if (command === "ip") {
      const instance = await describeInstance();
      const state = instance.State?.Name;
      const ip = instance.PublicIpAddress;
      const message = state === "running" && ip
        ? `Servidor rodando. IP publico: ${ip}`
        : `Servidor parado ou sem IP publico no momento. Estado atual: ${state ?? "desconhecido"}.`;
      console.log(JSON.stringify({ stage: "worker_complete", command, state, ip }));
      await editDiscordResponse(event.interactionToken, message);
      return;
    }

    if (command === "stop") {
      await ec2.send(new StopInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
      await waitForState("stopped");
      console.log(JSON.stringify({ stage: "worker_complete", command, state: "stopped" }));
      await editDiscordResponse(event.interactionToken, "Servidor parado.");
    }
  } catch (error) {
    console.error(error);
    await editDiscordResponse(event.interactionToken, `Erro ao executar comando: ${error.message}`);
  }
}

async function describeInstance() {
  const response = await ec2.send(new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID] }));
  return response.Reservations?.[0]?.Instances?.[0] ?? {};
}

async function waitForState(expectedState) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    const instance = await describeInstance();

    if (instance.State?.Name === expectedState) {
      return instance;
    }

    await sleep(5000);
  }

  throw new Error(`Timeout aguardando instancia chegar em ${expectedState}.`);
}

async function editDiscordResponse(interactionToken, content) {
  const url = `https://discord.com/api/v10/webhooks/${DISCORD_APPLICATION_ID}/${interactionToken}/messages/@original`;
  console.log(JSON.stringify({
    stage: "editing_discord_response",
    contentPreview: content.slice(0, 120),
  }));

  const response = await fetch(url, {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(text(content)),
  });

  if (!response.ok) {
    const body = await response.text();
    console.error(JSON.stringify({
      stage: "discord_edit_failed",
      status: response.status,
      body,
    }));
    throw new Error(`Discord retornou HTTP ${response.status}`);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
