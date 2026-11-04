# RE:Multiplayer Discord-Bot

Ein Bot für alles auf dem Discord-Server. Bisher: wechselnder Aktivitätsstatus (`index.js`, Liste `STATUS`). Später: FAQ und Befehle.
Die Patch Notes postet nicht dieser Dienst, sondern `release.yml` mit demselben Token über die Discord-API (siehe `docs/cheatsheet.md`).

## Server (VPS 91.99.132.249, Ubuntu 24.04, Node 22)

- Code: `/opt/re-multiplayer-bot` (Besitzer `root:remp-bot`), Dienst `re-multiplayer-bot` (systemd, läuft als Nutzer `remp-bot`).
- Token: `/etc/re-multiplayer-bot.env` (nur root lesbar). Setzen: `ssh -t 91.99.132.249 /opt/re-multiplayer-bot/set-token.sh`
- Log: `ssh 91.99.132.249 journalctl -u re-multiplayer-bot -n 30`
- Update nach Änderungen: Dateien nach `/opt/re-multiplayer-bot/` kopieren (`scp index.js package.json 91.99.132.249:/opt/re-multiplayer-bot/`), dort `npm install --omit=dev`, dann `systemctl restart re-multiplayer-bot`.
