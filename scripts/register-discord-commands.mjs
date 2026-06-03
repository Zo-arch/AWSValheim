const {
  DISCORD_APPLICATION_ID,
  DISCORD_BOT_TOKEN,
  DISCORD_GUILD_ID,
  DISCORD_COMMAND_NAME = "valheim",
} = process.env;

if (!DISCORD_APPLICATION_ID || !DISCORD_BOT_TOKEN || !DISCORD_GUILD_ID) {
  console.error("Set DISCORD_APPLICATION_ID, DISCORD_BOT_TOKEN and DISCORD_GUILD_ID.");
  process.exit(1);
}

const command = {
  name: DISCORD_COMMAND_NAME,
  description: "Controla o servidor Valheim",
  options: [
    {
      type: 1,
      name: "start",
      description: "Liga a EC2 e retorna o IP publico",
    },
    {
      type: 1,
      name: "ip",
      description: "Mostra o IP publico atual se o servidor estiver ligado",
    },
    {
      type: 1,
      name: "stop",
      description: "Desliga a EC2",
    },
  ],
};

const url = `https://discord.com/api/v10/applications/${DISCORD_APPLICATION_ID}/guilds/${DISCORD_GUILD_ID}/commands`;

const response = await fetch(url, {
  method: "POST",
  headers: {
    authorization: `Bot ${DISCORD_BOT_TOKEN}`,
    "content-type": "application/json",
  },
  body: JSON.stringify(command),
});

const body = await response.text();

if (!response.ok) {
  console.error(`Discord returned HTTP ${response.status}: ${body}`);
  process.exit(1);
}

console.log(body);
