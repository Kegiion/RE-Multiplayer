// Legt pro Projekt eine Kategorie mit Channels auf dem Discord-Server an (mehrfach ausfuehrbar:
// Vorhandenes mit gleichem Namen bleibt, alte Namen aus "was" werden umbenannt, nichts wird geloescht). Struktur in channels.json.
//   DISCORD_BOT_TOKEN=... node setup-channels.js   (Server = der einzige, auf dem der Bot ist; sonst GUILD_ID setzen)
// Gibt am Ende die patch-notes-Channel-IDs pro Mod aus (fuer die Repo-Variablen DISCORD_PATCHNOTES_CHANNEL_<MOD>).
const fs = require('fs');
const path = require('path');

const token = process.env.DISCORD_BOT_TOKEN;
if (!token) { console.error('DISCORD_BOT_TOKEN setzen.'); process.exit(1); }

const API = 'https://discord.com/api/v10';
const headers = {
  Authorization: `Bot ${token}`,
  'User-Agent': 'DiscordBot (https://github.com/Kegiion/RE-Multiplayer, 1.0)',
  'Content-Type': 'application/json',
};

async function api(method, url, body) {
  const res = await fetch(API + url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url} -> ${res.status} ${text.slice(0, 200)}`);
  return text ? JSON.parse(text) : null;
}

(async () => {
  const config = JSON.parse(fs.readFileSync(path.join(__dirname, 'channels.json'), 'utf8'));
  let guild = process.env.GUILD_ID;
  if (!guild) {
    const guilds = await api('GET', '/users/@me/guilds');
    if (guilds.length !== 1) throw new Error(`Bot ist auf ${guilds.length} Servern, bitte GUILD_ID setzen.`);
    guild = guilds[0].id;
  }
  let all = await api('GET', `/guilds/${guild}/channels`);
  const result = {};

  for (const cat of config.categories) {
    const catNames = [cat.name, ...(cat.was || [])].map((n) => n.toLowerCase());
    let parent = all.find((c) => c.type === 4 && catNames.includes(c.name.toLowerCase()));
    if (parent && parent.name !== cat.name) {
      parent = Object.assign(parent, await api('PATCH', `/channels/${parent.id}`, { name: cat.name }));
      console.log(`Kategorie umbenannt: ${cat.name}`);
    }
    if (!parent) {
      parent = await api('POST', `/guilds/${guild}/channels`, { name: cat.name, type: 4 });
      all.push(parent);
      console.log(`Kategorie angelegt: ${cat.name}`);
    } else console.log(`Kategorie da: ${cat.name}`);

    for (const ch of cat.channels) {
      const names = [ch.name, ...(ch.was || [])];
      let c = all.find((x) => x.parent_id === parent.id && names.includes(x.name));
      if (c && (c.name !== ch.name || (c.topic || '') !== ch.topic)) {
        c = Object.assign(c, await api('PATCH', `/channels/${c.id}`, { name: ch.name, topic: ch.topic }));
        console.log(`  Channel aktualisiert: #${ch.name}`);
      }
      if (!c) {
        c = await api('POST', `/guilds/${guild}/channels`, { name: ch.name, type: 0, parent_id: parent.id, topic: ch.topic });
        all.push(c);
        console.log(`  Channel angelegt: #${ch.name}`);
      }
      if (ch.name === 'patch-notes' && cat.mod) result[cat.mod] = c.id;
    }
  }
  console.log('PATCHNOTES ' + JSON.stringify(result));
  const known = new Set(all.filter((c) => c.parent_id && config.categories.some((k) => k.name === (all.find((p) => p.id === c.parent_id) || {}).name)).map((c) => c.id));
  const keepCats = new Set(config.categories.map((k) => k.name));
  const extra = all.filter((c) => !known.has(c.id) && !(c.type === 4 && keepCats.has(c.name)));
  console.log('NICHT IN channels.json (von Hand loeschen, falls unnoetig): ' + extra.map((c) => `${c.type === 4 ? '[Kategorie] ' : '#'}${c.name}`).join(', '));
})().catch((e) => { console.error(e.message); process.exit(1); });
