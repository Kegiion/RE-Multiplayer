# So arbeiten wir im Duo

Claude schreibt den Code in einer Cloud-Umgebung **ohne das Spiel**. Du testest im echten Spiel und gibst Rückmeldung. Je genauer die Rückmeldung, desto schneller geht es voran.

## Der Ablauf

1. **Claude** ändert Code, testet ihn automatisch (ohne Spiel) und pusht ihn ins Repo.
2. **GitHub Actions** baut daraus das fertige Paket (Reiter *Actions* → Lauf → *Artifacts*).
3. **Du** lädst das Paket herunter, entpackst es in den Spielordner und testest.
4. **Du** gibst Rückmeldung (siehe unten).

Kleine Lua-Änderungen kannst du auch direkt testen: Datei austauschen, im REFramework-Menü auf **Script Runner → Reset Scripts** klicken, fertig. Ein Neustart des Spiels ist dafür nicht nötig.

## Was ich (Claude) von dir brauche

| Was | Wo zu finden | Wann |
|---|---|---|
| **Diagnose-Datei** | `<RE2-Ordner>/reframework/data/re2r_coop_diag.json` (Button „Diagnose speichern“) | Nach jedem neuen Test, am besten in verschiedenen Situationen (Menü, im Spiel, nach Raumwechsel) |
| **REFramework-Log** | `<RE2-Ordner>/re2_framework_log.txt` | Wenn etwas nicht lädt oder abstürzt |
| **Was du beobachtet hast** | Text oder Screenshot | Immer: Was hast du gemacht, was ist passiert, was hast du erwartet? |
| **Inhalt des „Log“-Bereichs im Menü** | Menü „RE2 Koop“ → „Log“ | Bei Verbindungsproblemen |

**Am einfachsten:** Lege Diagnose-Dateien in `games/re2r/research/` ab (Upload über GitHub im Browser geht auch) oder kopiere den Inhalt direkt in den Chat.

## Nützliche Werkzeuge in REFramework

- **Object Explorer** (Menü → DeveloperTools → Object Explorer): zeigt alle Spielobjekte, Klassen, Felder und Methoden live. Damit finden wir gemeinsam heraus, wo z. B. Gegner-Lebenspunkte gespeichert sind.
- **Script Runner → Reset Scripts**: lädt alle Lua-Skripte neu.
- **Spawn Debug Console**: zeigt Lua-Fehler sofort an.

## Testen ohne zweiten PC

Mit dem **Testbot** (Paket *REMods-Tools*):
1. Spiel starten, im Menü „RE2 Koop“ auf **Hosten** klicken.
2. `testbot.bat` starten.
3. Der Testbot verbindet sich und läuft dir mit einer Sekunde Verzögerung als Markierung hinterher. Chat-Nachrichten beantwortet er mit einem Echo.

## Mit einem echten Mitspieler

Der Host muss für den Client erreichbar sein. Das geht auf drei Wegen:
- **Einfachste Lösung: ein virtuelles LAN** wie Tailscale, ZeroTier oder Radmin VPN. Beide installieren es und treten demselben Netz bei. Als IP nimmt der Client die VPN-IP des Hosts.
- **Portfreigabe:** UDP-Port 27350 im Router auf den PC des Hosts weiterleiten.
- **Gleiches Heimnetz:** lokale IP des Hosts verwenden (z. B. `192.168.x.x`).

Beim ersten Start fragt die Windows-Firewall, ob RE2 ins Netzwerk darf. Das musst du erlauben.
