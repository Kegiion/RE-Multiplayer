#!/bin/sh
# Fragt das Bot-Token ab (unsichtbare Eingabe), speichert es geschuetzt und startet den Bot neu.
#   ssh -t 91.99.132.249 /opt/re-multiplayer-bot/set-token.sh
set -e
printf 'Bot-Token: '
stty -echo
read -r TOKEN
stty echo
echo
[ -n "$TOKEN" ] || { echo 'Kein Token eingegeben.'; exit 1; }
umask 077
printf 'DISCORD_BOT_TOKEN=%s\n' "$TOKEN" > /etc/re-multiplayer-bot.env
systemctl enable --now re-multiplayer-bot >/dev/null 2>&1 || true
systemctl restart re-multiplayer-bot
sleep 5
journalctl -u re-multiplayer-bot -n 5 --no-pager
