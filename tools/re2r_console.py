"""Schickt Lua-Code an die RE2-Entwickler-Konsole und wartet auf das Ergebnis.

Aufruf:
    python tools/re2r_console.py "out(game.get_local_state())"
    python tools/re2r_console.py -f befehl.lua

Voraussetzung: Im Spiel unter "RE2 Koop" ist "Entwickler-Konsole fuer Claude"
angehakt. Der Datenordner kann mit --data oder REMULTIPLAYER_RE2R_DATA geaendert werden.
"""

import argparse
import json
import os
import sys
import time

DEFAULT_DATA = (r"C:\Program Files (x86)\Steam\steamapps\common"
                r"\RESIDENT EVIL 2  BIOHAZARD RE2\reframework\data")


def main():
    # Spieltexte enthalten z. B. Japanisch, die Windows-Konsole (cp1252) nicht.
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("code", nargs="?", help="Lua-Code")
    parser.add_argument("-f", "--file", help="Lua-Code aus Datei")
    parser.add_argument("--data", default=os.environ.get("REMULTIPLAYER_RE2R_DATA", DEFAULT_DATA))
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()

    if args.file:
        with open(args.file, encoding="utf-8") as f:
            code = f.read()
    elif args.code:
        code = args.code
    else:
        parser.error("Lua-Code oder -f angeben")

    cmd_path = os.path.join(args.data, "claude_cmd.json")
    out_path = os.path.join(args.data, "claude_out.json")
    cmd_id = int(time.time() * 1000)  # steigt immer, auch nach Neustarts

    tmp_path = cmd_path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump({"id": cmd_id, "code": code}, f)
    os.replace(tmp_path, cmd_path)  # atomar, damit das Spiel nie eine halbe Datei liest

    deadline = time.time() + args.timeout
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


if __name__ == "__main__":
    sys.exit(main())
