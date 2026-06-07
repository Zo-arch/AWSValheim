const config = window.VALHEIM_CONTROL_CONFIG ?? {};
const state = {
  authorized: false,
  password: "",
  polling: undefined,
};

const elements = {
  passwordInput: document.querySelector("#passwordInput"),
  unlockButton: document.querySelector("#unlockButton"),
  startButton: document.querySelector("#startButton"),
  stopButton: document.querySelector("#stopButton"),
  statePill: document.querySelector("#statePill"),
  serverAddress: document.querySelector("#serverAddress"),
  serverState: document.querySelector("#serverState"),
  operationState: document.querySelector("#operationState"),
  uptime: document.querySelector("#uptime"),
  sessionCost: document.querySelector("#sessionCost"),
  instanceType: document.querySelector("#instanceType"),
  checkedAt: document.querySelector("#checkedAt"),
  message: document.querySelector("#message"),
  operationUpdatedAt: document.querySelector("#operationUpdatedAt"),
};

elements.unlockButton.addEventListener("click", () => unlock());
elements.passwordInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    unlock();
  }
});
elements.startButton.addEventListener("click", () => sendCommand("start"));
elements.stopButton.addEventListener("click", () => sendCommand("stop"));

async function unlock() {
  state.password = elements.passwordInput.value;
  await refreshStatus();

  window.clearInterval(state.polling);
  state.polling = window.setInterval(refreshStatus, 5000);
}

async function sendCommand(command) {
  setBusy(true);

  try {
    const status = await apiFetch(`/${command}`, { method: "POST" });
    renderStatus(status);
  } catch (error) {
    renderError(error);
  } finally {
    setBusy(false);
  }
}

async function refreshStatus() {
  setBusy(true);

  try {
    const status = await apiFetch("/status");
    renderStatus(status);
  } catch (error) {
    renderError(error);
  } finally {
    setBusy(false);
  }
}

async function apiFetch(path, options = {}) {
  if (!config.apiUrl) {
    throw new Error("API URL nao configurada.");
  }

  const response = await fetch(new URL(path, config.apiUrl), {
    ...options,
    headers: {
      "content-type": "application/json",
      "x-control-password": state.password,
      ...(options.headers ?? {}),
    },
  });

  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(body.error ?? `HTTP ${response.status}`);
  }

  return body;
}

function renderStatus(status) {
  state.authorized = true;
  const server = status.server ?? {};
  const operation = status.operation ?? {};
  const cost = status.cost ?? {};

  elements.statePill.textContent = server.state ?? "desconhecido";
  elements.serverAddress.textContent = server.address ?? "sem IP";
  elements.serverState.textContent = server.state ?? "-";
  elements.operationState.textContent = operation.status ?? "idle";
  elements.uptime.textContent = formatDuration(server.uptimeSeconds ?? 0);
  elements.sessionCost.textContent = formatCost(cost);
  elements.instanceType.textContent = server.instanceType ?? "-";
  elements.checkedAt.textContent = formatDate(status.checkedAt);
  elements.message.textContent = status.message ?? operation.message ?? "Status atualizado.";
  elements.operationUpdatedAt.textContent = formatDate(operation.updatedAt);

  elements.startButton.disabled = false;
  elements.stopButton.disabled = false;
}

function renderError(error) {
  state.authorized = false;
  elements.message.textContent = error.message;
  elements.statePill.textContent = "erro";
}

function setBusy(isBusy) {
  elements.unlockButton.disabled = isBusy;
  elements.startButton.disabled = isBusy || !state.authorized;
  elements.stopButton.disabled = isBusy || !state.authorized;
}

function formatDuration(totalSeconds) {
  if (!totalSeconds) {
    return "0m";
  }

  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);

  if (hours <= 0) {
    return `${minutes}m`;
  }

  return `${hours}h ${minutes}m`;
}

function formatCost(cost) {
  if (cost.estimatedUsd === null || cost.estimatedUsd === undefined) {
    return "configure";
  }

  const usd = new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cost.estimatedUsd);
  const brl = cost.estimatedBrl === null || cost.estimatedBrl === undefined
    ? null
    : new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(cost.estimatedBrl);

  return brl ? `${brl} / ${usd}` : usd;
}

function formatDate(value) {
  if (!value) {
    return "-";
  }

  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "medium",
  }).format(new Date(value));
}
