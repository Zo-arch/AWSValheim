#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

VALHEIM_USER="${VALHEIM_USER:-valheim}"
VALHEIM_GROUP="${VALHEIM_GROUP:-valheim}"
VALHEIM_HOME="${VALHEIM_HOME:-/var/lib/valheim}"
VALHEIM_SERVER_DIR="${VALHEIM_SERVER_DIR:-/opt/valheim}"
VALHEIM_DATA_DIR="${VALHEIM_DATA_DIR:-/srv/valheim}"
STEAMCMD_DIR="${STEAMCMD_DIR:-/opt/steamcmd}"
ENV_DIR="/etc/valheim"
ENV_FILE="${ENV_DIR}/valheim.env"
SERVICE_FILE="/etc/systemd/system/valheim.service"
START_SCRIPT="${VALHEIM_SERVER_DIR}/start-valheim.sh"

SERVER_NAME="${SERVER_NAME:-Valheim Server}"
WORLD_NAME="${WORLD_NAME:-Dedicated}"
SERVER_PORT="${SERVER_PORT:-2456}"
SERVER_PASSWORD="${SERVER_PASSWORD:-ChangeMe123}"
SERVER_PUBLIC="${SERVER_PUBLIC:-1}"

export DEBIAN_FRONTEND=noninteractive

dpkg --add-architecture i386
apt-get update
apt-get upgrade -y
apt-get install -y \
  ca-certificates \
  curl \
  lib32gcc-s1 \
  libc6:i386 \
  libstdc++6:i386 \
  tar

if ! getent group "${VALHEIM_GROUP}" >/dev/null; then
  groupadd --system "${VALHEIM_GROUP}"
fi

if ! id "${VALHEIM_USER}" >/dev/null 2>&1; then
  useradd \
    --system \
    --gid "${VALHEIM_GROUP}" \
    --create-home \
    --home-dir "${VALHEIM_HOME}" \
    --shell /usr/sbin/nologin \
    "${VALHEIM_USER}"
fi

mkdir -p \
  "${VALHEIM_HOME}" \
  "${VALHEIM_HOME}/.steam/sdk64" \
  "${VALHEIM_SERVER_DIR}" \
  "${VALHEIM_DATA_DIR}/worlds_local" \
  "${STEAMCMD_DIR}" \
  "${ENV_DIR}"
chown -R "${VALHEIM_USER}:${VALHEIM_GROUP}" "${VALHEIM_HOME}" "${VALHEIM_SERVER_DIR}" "${VALHEIM_DATA_DIR}" "${STEAMCMD_DIR}"

if [[ ! -f "${STEAMCMD_DIR}/steamcmd.sh" ]]; then
  curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" -o /tmp/steamcmd_linux.tar.gz
  tar -xzf /tmp/steamcmd_linux.tar.gz -C "${STEAMCMD_DIR}"
  chown -R "${VALHEIM_USER}:${VALHEIM_GROUP}" "${STEAMCMD_DIR}"
fi

runuser -u "${VALHEIM_USER}" -- "${STEAMCMD_DIR}/steamcmd.sh" \
  +force_install_dir "${VALHEIM_SERVER_DIR}" \
  +login anonymous \
  +app_update 896660 validate \
  +quit

ln -sf "${STEAMCMD_DIR}/linux64/steamclient.so" "${VALHEIM_HOME}/.steam/sdk64/steamclient.so"
chown -h "${VALHEIM_USER}:${VALHEIM_GROUP}" "${VALHEIM_HOME}/.steam/sdk64/steamclient.so"

cat > "${START_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/valheim/valheim.env

export SteamAppId=892970

if [[ -f /opt/valheim/BepInEx/core/BepInEx.Preloader.dll ]] && [[ -d /opt/valheim/doorstop_libs ]]; then
  export DOORSTOP_ENABLED=1
  export DOORSTOP_TARGET_ASSEMBLY=/opt/valheim/BepInEx/core/BepInEx.Preloader.dll
  export LD_LIBRARY_PATH="/opt/valheim/doorstop_libs:/opt/valheim/linux64:${LD_LIBRARY_PATH:-}"
  export LD_PRELOAD="libdoorstop_x64.so:${LD_PRELOAD:-}"
else
  export LD_LIBRARY_PATH="/opt/valheim/linux64:${LD_LIBRARY_PATH:-}"
fi

cd /opt/valheim
exec /opt/valheim/valheim_server.x86_64 \
  -name "${SERVER_NAME}" \
  -world "${WORLD_NAME}" \
  -port "${SERVER_PORT}" \
  -password "${SERVER_PASSWORD}" \
  -public "${SERVER_PUBLIC}" \
  -savedir /srv/valheim
EOF

chmod 0755 "${START_SCRIPT}"
chown "${VALHEIM_USER}:${VALHEIM_GROUP}" "${START_SCRIPT}"

cat > "${ENV_FILE}" <<EOF
SERVER_NAME="${SERVER_NAME}"
WORLD_NAME="${WORLD_NAME}"
SERVER_PORT="${SERVER_PORT}"
SERVER_PASSWORD="${SERVER_PASSWORD}"
SERVER_PUBLIC="${SERVER_PUBLIC}"
EOF

chown root:"${VALHEIM_GROUP}" "${ENV_FILE}"
chmod 0640 "${ENV_FILE}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Valheim Dedicated Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${VALHEIM_USER}
Group=${VALHEIM_GROUP}
WorkingDirectory=${VALHEIM_SERVER_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${START_SCRIPT}
Restart=on-failure
RestartSec=10
TimeoutStopSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable valheim.service

echo "Valheim installed."
echo "Edit ${ENV_FILE} if needed, then start with: systemctl start valheim"
echo "Logs: journalctl -u valheim -f"
echo "Server files: ${VALHEIM_SERVER_DIR}"
echo "World files: ${VALHEIM_DATA_DIR}/worlds_local"
echo "If BepInEx files are copied into ${VALHEIM_SERVER_DIR}, the same start script will load them automatically."
