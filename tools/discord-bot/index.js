// RE:Multiplayer Discord-Bot. Laeuft dauerhaft auf dem VPS (systemd-Dienst re-multiplayer-bot).
// Zeigt einen wechselnden Aktivitaetsstatus. Spaeter kommen hier FAQ und Befehle dazu.
// Token aus der Umgebung DISCORD_BOT_TOKEN (auf dem Server: /etc/re-multiplayer-bot.env).
const { Client, GatewayIntentBits, ActivityType } = require('discord.js');

const token = process.env.DISCORD_BOT_TOKEN;
if (!token) {
  console.error('DISCORD_BOT_TOKEN fehlt (siehe /etc/re-multiplayer-bot.env).');
  process.exit(1);
}

// Status-Liste: wechselt alle STATUS_INTERVAL_MS
const STATUS = [
  { type: ActivityType.Playing, name: 'Resident Evil 2 im Koop' },
  { type: ActivityType.Watching, name: 'Raccoon City' },
  { type: ActivityType.Custom, name: 'custom', state: 'Überlebt zu zweit 🧟' },
  { type: ActivityType.Playing, name: 'Resident Evil 0 im Koop' },
];
const STATUS_INTERVAL_MS = 5 * 60 * 1000;

const client = new Client({ intents: [GatewayIntentBits.Guilds] });

let next = 0;
function rotateStatus() {
  const s = STATUS[next % STATUS.length];
  next++;
  client.user.setPresence({ status: 'online', activities: [s] });
}

client.once('clientReady', () => {
  console.log(`Eingeloggt als ${client.user.tag}`);
  rotateStatus();
  setInterval(rotateStatus, STATUS_INTERVAL_MS);
});

client.login(token);
