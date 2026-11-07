r"""Schickt Lua-Code an die RE2-Entwickler-Konsole und wartet auf das Ergebnis.

Aufruf:
    python tools/re2r_console.py "out(game.get_local_state())"
    python tools/re2r_console.py -f befehl.lua
    python tools/re2r_console.py --log 40 --grep Koop      (Ende des REFramework-Logs)

Zweite Instanz (z. B. VM): Spielordner der VM als Netzwerkfreigabe einbinden und
mit --game angeben, z. B. --game \\<VM-IP>\RE2  (oder REMULTIPLAYER_RE2R_GAME setzen).
Die Konsole arbeitet nur ueber Dateien in reframework/data, das geht auch ueber SMB.

Voraussetzung: Im Spiel unter "RE2 Koop" ist "Entwickler-Konsole fuer Claude"
angehakt. Der Datenordner kann mit --data oder REMULTIPLAYER_RE2R_DATA geaendert werden.
"""

import argparse
import json
import os
import re
import sys
import time

DEFAULT_GAME = (r"C:\Program Files (x86)\Steam\steamapps\common"
                r"\RESIDENT EVIL 2  BIOHAZARD RE2")
LOG_NAME = "re2_framework_log.txt"


def print_log(game_dir, lines, pattern):
    path = os.path.join(game_dir, LOG_NAME)
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            rows = f.read().splitlines()
    except OSError as e:
        print(f"Log nicht lesbar: {e}", file=sys.stderr)
        return 2
    if pattern:
        rx = re.compile(pattern, re.IGNORECASE)
        rows = [r for r in rows if rx.search(r)]
    for row in rows[-lines:]:
        print(row)
    return 0


def run_code(data_dir, code, timeout):
    cmd_path = os.path.join(data_dir, "claude_cmd.json")
    out_path = os.path.join(data_dir, "claude_out.json")
    cmd_id = int(time.time() * 1000)  # steigt immer, auch nach Neustarts

    tmp_path = cmd_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump({"id": cmd_id, "code": code}, f)
    os.replace(tmp_path, cmd_path)  # atomar, damit das Spiel nie eine halbe Datei liest

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with open(out_path, encoding="utf-8") as f:
                result = json.load(f)
            if result.get("id") == cmd_id:
                json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
                print()
                return 0 if result.get("ok") else 1
        except (OSError, ValueError):
            pass  # Datei fehlt oder wird gerade geschrieben
        time.sleep(0.2)

    print("Keine Antwort. Ist das Spiel offen und die Konsole im Menue angehakt?", file=sys.stderr)
    return 2


def main():
    # Spieltexte enthalten z. B. Japanisch, die Windows-Konsole (cp1252) nicht.
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("code", nargs="?", help="Lua-Code")
    parser.add_argument("-f", "--file", help="Lua-Code aus Datei")
    parser.add_argument("--game", default=os.environ.get("REMULTIPLAYER_RE2R_GAME", DEFAULT_GAME),
                        help="Spielordner (auch Netzwerkpfad der VM)")
    parser.add_argument("--data", default=os.environ.get("REMULTIPLAYER_RE2R_DATA"),
                        help="Datenordner (Standard: <game>/reframework/data)")
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--log", type=int, metavar="N", help="letzte N Zeilen des REFramework-Logs")
    parser.add_argument("--grep", help="nur Logzeilen mit diesem Muster (Regex, ohne Gross/Klein)")
    args = parser.parse_args()

    if args.log is not None:
        return print_log(args.game, args.log, args.grep)

    if args.file:
        with open(args.file, encoding="utf-8") as f:
            code = f.read()
    elif args.code:
        code = args.code
    else:
        parser.error("Lua-Code, -f oder --log angeben")

    data_dir = args.data or os.path.join(args.game, "reframework", "data")
    return run_code(data_dir, code, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
