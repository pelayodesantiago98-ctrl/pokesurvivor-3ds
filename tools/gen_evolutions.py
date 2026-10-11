#!/usr/bin/env python3
"""
Genera game/data/evolutions.lua con las cadenas evolutivas de todos los Pokémon,
a partir de los datos públicos de PokeAPI (repo PokeAPI/api-data en GitHub).

    python tools/gen_evolutions.py [max_dex]

Salida: `return { [dex] = { dex_evolucion_1, dex_evolucion_2, ... } }` (solo las
evoluciones DIRECTAS; las ramas, como Eevee, traen varias). Se usa una caché en
tools/cache/species/ para poder relanzar.
"""
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

RAW = 'https://raw.githubusercontent.com/PokeAPI/api-data/master/data/api/v2/pokemon-species/%d/index.json'
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache', 'species')
OUT = os.path.join(os.path.dirname(HERE), 'game', 'data', 'evolutions.lua')


def fetch(dex):
    path = os.path.join(CACHE, '%d.json' % dex)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return dex, json.load(f)
    try:
        req = urllib.request.Request(RAW % dex, headers={'User-Agent': 'pokesurvivor-3ds/1.0'})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode('utf-8'))
    except Exception as e:  # 404 u otro fallo: sin datos
        return dex, None
    with open(path, 'w', encoding='utf-8') as f:
        json.dump({'evolves_from_species': data.get('evolves_from_species')}, f)
    return dex, data


def main():
    max_dex = int(sys.argv[1]) if len(sys.argv) > 1 else 1025
    os.makedirs(CACHE, exist_ok=True)
    parent = {}
    with ThreadPoolExecutor(max_workers=16) as ex:
        for dex, data in ex.map(fetch, range(1, max_dex + 1)):
            if not data:
                continue
            efs = data.get('evolves_from_species')
            if efs and efs.get('url'):
                # .../pokemon-species/4/ -> 4
                pid = int(efs['url'].rstrip('/').split('/')[-1])
                parent[dex] = pid
    nxt = {}
    for child, p in parent.items():
        nxt.setdefault(p, []).append(child)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERADO por tools/gen_evolutions.py (datos de PokeAPI). dex -> evoluciones directas.\n')
        f.write('local M = {}\n')
        for p in sorted(nxt):
            f.write('M[%d]={%s}\n' % (p, ','.join(str(c) for c in sorted(nxt[p]))))
        f.write('return M\n')
    print('%d especies con evolución; escrito %s' % (len(nxt), OUT))


if __name__ == '__main__':
    main()
