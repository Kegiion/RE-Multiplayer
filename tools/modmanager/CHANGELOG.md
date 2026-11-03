# Patch Notes: RE:Multiplayer Mod-Manager

Neueste Version oben. Der Release-Workflow übernimmt den Abschnitt `## <Version>` (Version aus `Directory.Build.props`).

## 1.1.1

- **RE2: REFramework lässt sich wieder installieren.** REFramework liefert keine Pakete pro Spiel mehr (`RE2.zip`), sondern nur noch `REFramework.zip`. Der Manager nimmt jetzt dieses Paket und weicht bei Bedarf auf den alten Namen aus.

## 1.1.0

- **Neuer Name: RE:Multiplayer.** Die exe heißt jetzt `RE-Multiplayer.exe`, das Repo `Kegiion/RE-Multiplayer`.
- Installationen mit den alten Namen (`remods/`, `remods_coopnet.dll`) werden beim Aktualisieren umgezogen. Einstellungen bleiben erhalten, eine gesicherte fremde `dinput8.dll` auch.
- Die Einstellungen des Managers ziehen von `%LOCALAPPDATA%\REMods` nach `%LOCALAPPDATA%\RE-Multiplayer` um.

## 1.0.1

- Die Versionszeile wird nicht mehr abgeschnitten.
- Spielordner werden in der richtigen Schreibweise angezeigt (statt `c:\program files (x86)\...`).
- Hinweis, wenn eine Mod nicht über den Manager installiert wurde und die Version deshalb unbekannt ist.

## 1.0.0

- Erste Version.
- Findet Resident Evil 0 HD und Resident Evil 2 (Remake) über Steam, auch in weiteren Steam-Bibliotheken. Andere Ordner kann man von Hand wählen.
- Installieren, Aktualisieren und Deinstallieren der Koop-Mods per Klick. Deine Einstellungen bleiben dabei erhalten.
- RE2: REFramework wird bei Bedarf automatisch mitinstalliert.
- Patch Notes aller Versionen direkt im Manager.
- **Fehler melden:** Logs landen als ZIP auf dem Desktop und GitHub öffnet sich mit einem vorausgefüllten Fehlerbericht.
- Der Manager aktualisiert sich selbst.
