# -*- coding: utf-8 -*-
"""gen_pokedex.py — genera game/data/pokedex.lua a partir de js/data/pokedex.js.

El JS trae un objeto JSON por línea dentro de `G.DEX = [ ... ];`. Aquí se
leen esas líneas y se escriben como tabla Lua (una línea por Pokémon) con
TODOS los campos: dex, name, types, hp, spd, atk, rarity, bst, starter, gen y
leg (false si el JS no lo trae, para que siempre sea booleano).

Uso:
    python tools/gen_pokedex.py [ruta/a/pokedex.js] [ruta/salida/pokedex.lua]
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_SRC = os.path.join(
    os.environ.get("LOCALAPPDATA", ""), "Temp", "claude", "C--Users-lepay",
    "7caef775-80b7-4d4a-9262-16318d5bee08", "scratchpad", "pokesurvivor-repo",
    "js", "data", "pokedex.js")
DEFAULT_OUT = os.path.join(ROOT, "game", "data", "pokedex.lua")

# Orden fijo de campos para que el fichero sea estable y legible.
ORDER = ["dex", "name", "types", "hp", "spd", "atk", "rarity", "bst", "starter", "gen", "leg"]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        # repr da el decimal más corto que reproduce el double (igual que JS).
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ",".join(lua_val(x) for x in v) + "}"
    raise TypeError("valor no soportado: %r" % (v,))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT
    entries = []
    with open(src, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"^\s*(\{.*\})\s*,?\s*$", line)
            if not m:
                continue
            entries.append(json.loads(m.group(1)))
    if not entries:
        sys.exit("no se encontró ninguna entrada en " + src)

    lines = [
        "-- GENERADO por tools/gen_pokedex.py a partir de js/data/pokedex.js: no editar a mano.",
        "-- hp/spd/atk son stats de juego derivados de los stats base.",
        "-- rarity 1-5 para el gacha · gen = generación · starter = test · leg = legendario/singular (solo en grietas).",
        "return {",
    ]
    for p in entries:
        p = dict(p)
        p.setdefault("leg", False)
        keys = [k for k in ORDER if k in p] + sorted(k for k in p if k not in ORDER)
        fields = ",".join("%s=%s" % (k, lua_val(p[k])) for k in keys)
        lines.append("{" + fields + "},")
    lines.append("}")
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("escritas %d entradas en %s" % (len(entries), out))


if __name__ == "__main__":
    main()
