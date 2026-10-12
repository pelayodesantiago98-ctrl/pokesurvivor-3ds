#!/usr/bin/env python3
"""
Genera game/data/evolutions.lua con las cadenas evolutivas y el NIVEL REAL de cada
evolución, a partir de los datos públicos de PokeAPI (repo PokeAPI/api-data).

    python tools/gen_evolutions.py

Salida:
  M[dex]    = { evoluciones directas }  (las ramas, como Eevee, traen varias)
  M.LV[dex] = nivel al que se llega a ese Pokémon evolucionando por nivel
              (Charmeleon 16, Charizard 36...). Sin entrada: evoluciona por piedra,
              intercambio, amistad... (el juego usa un nivel por defecto).
Caché en tools/cache/evochain/.
"""
import json
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

RAW = 'https://raw.githubusercontent.com/PokeAPI/api-data/master/data/api/v2/evolution-chain/%d/index.json'
HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, 'cache', 'evochain')
OUT = os.path.join(os.path.dirname(HERE), 'game', 'data', 'evolutions.lua')
MAX_CHAIN = 560
MAX_DEX = 1025


def fetch(cid):
    path = os.path.join(CACHE, '%d.json' % cid)
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    try:
        req = urllib.request.Request(RAW % cid, headers={'User-Agent': 'pokesurvivor-3ds/1.0'})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode('utf-8'))
    except Exception:          # 404: ese id de cadena no existe
        data = None
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f)
    return data


def dex_of(species):
    return int(species['url'].rstrip('/').split('/')[-1])


def walk(node, nxt, lv):
    p = dex_of(node['species'])
    for child in node.get('evolves_to', []):
        c = dex_of(child['species'])
        if p <= MAX_DEX and c <= MAX_DEX:
            nxt.setdefault(p, []).append(c)
            # Nivel: el menor min_level entre las formas de evolucionar por nivel.
            levels = [d['min_level'] for d in child.get('evolution_details', [])
                      if d.get('trigger', {}).get('name') == 'level-up' and d.get('min_level')]
            if levels:
                lv[c] = min(levels)
        walk(child, nxt, lv)


def main():
    os.makedirs(CACHE, exist_ok=True)
    with ThreadPoolExecutor(max_workers=16) as ex:
        chains = list(ex.map(fetch, range(1, MAX_CHAIN + 1)))
    nxt, lv = {}, {}
    for ch in chains:
        if ch and ch.get('chain'):
            walk(ch['chain'], nxt, lv)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERADO por tools/gen_evolutions.py (datos de PokeAPI).\n')
        f.write('-- M[dex] = evoluciones directas; M.LV[dex] = nivel real al que se evoluciona a él.\n')
        f.write('local M = { LV = {} }\n')
        for p in sorted(nxt):
            f.write('M[%d]={%s}\n' % (p, ','.join(str(c) for c in sorted(set(nxt[p])))))
        for c in sorted(lv):
            f.write('M.LV[%d]=%d\n' % (c, lv[c]))
        f.write('return M\n')
    print('%d especies con evolución, %d por nivel; escrito %s' % (len(nxt), len(lv), OUT))


if __name__ == '__main__':
    main()
