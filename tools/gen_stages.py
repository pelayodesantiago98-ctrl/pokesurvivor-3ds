#!/usr/bin/env python3
"""
Convierte las fases de Poké World Survivors (giovanneluna/poke-survivors, MIT) en
game/data/stages.lua: 8 fases de 20 oleadas (30 s cada una) y 3-4 jefes.

    python tools/gen_stages.py [ruta_al_repo]

Las claves de enemigo del TS se traducen a números de la Pokédex. Los tiempos de
los jefes se reparten dentro de los 10 minutos de cada fase (el último, al final:
derrotarlo supera la fase).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\lepay\3ds-tools\src\poke-survivors'
OUT = os.path.join(os.path.dirname(HERE), 'game', 'data', 'stages.lua')
PH = os.path.join(REPO, 'src', 'data', 'enemies', 'phases')

DEX = {
    'rattata': 19, 'caterpie': 10, 'weedle': 13, 'pidgey': 16, 'zubat': 41, 'geodude': 74, 'spearow': 21,
    'ekans': 23, 'oddish': 43, 'mankey': 56, 'gastly': 92, 'haunter': 93, 'machop': 66, 'golbat': 42,
    'raticate': 20, 'arbok': 24, 'nidoking': 34, 'snorlax': 143, 'metapod': 11, 'kakuna': 14, 'gloom': 44,
    'paras': 46, 'venonat': 48, 'drowzee': 96, 'cubone': 104, 'pidgeotto': 17, 'butterfree': 12,
    'parasect': 47, 'venomoth': 49, 'hypno': 97, 'marowak': 105, 'crobat': 169, 'graveler': 75,
    'machoke': 67, 'koffing': 109, 'magnemite': 81, 'tentacool': 72, 'rhyhorn': 111, 'alakazam': 65,
    'electrode': 101, 'weezing': 110, 'magneton': 82, 'tentacruel': 73, 'rhydon': 112, 'scyther': 123,
    'mr-mime': 122, 'hitmonlee': 106, 'electabuzz': 125, 'beedrill': 15, 'vileplume': 45, 'primeape': 57,
    'gengar': 94, 'fearow': 22, 'pidgeot': 18, 'machamp': 68, 'golem': 76, 'alakazam-boss': 65,
    'pikachu': 25, 'sandshrew': 27, 'vulpix': 37, 'diglett': 50, 'meowth': 52, 'psyduck': 54,
    'growlithe': 58, 'poliwag': 60, 'bellsprout': 69, 'ponyta': 77, 'slowpoke': 79, 'farfetchd': 83,
    'doduo': 84, 'seel': 86, 'grimer-p2': 88, 'shellder': 90, 'krabby': 98, 'exeggcute': 102,
    'horsea': 116, 'goldeen': 118, 'staryu': 120, 'jigglypuff': 39, 'arcanine': 59, 'ninetales': 38,
    'victreebel': 71, 'golduck': 55, 'cloyster': 91, 'muk': 89, 'rapidash': 78, 'starmie': 121,
    'slowbro': 80, 'poliwrath': 62, 'lapras': 131,
}

# (fichero, nombre en castellano, bioma 0..2 del mundo normal)
STAGES = [
    ('phase1.ts', 'Bosque Verde I', 0), ('phase2.ts', 'Bosque Verde II', 0),
    ('phase3.ts', 'Cueva Cristal I', 1), ('phase4.ts', 'Cueva Cristal II', 1),
    ('coast-sp1.ts', 'Bosque Verde III', 0), ('coast-sp2.ts', 'Bosque Verde IV', 0),
    ('coast-sp3.ts', 'Monte Ascuas I', 2), ('coast-sp4.ts', 'Monte Ascuas II', 2),
]
STAGE_LEN = 600


def parse(path):
    src = open(path, encoding='utf-8').read()
    waves = []
    for m in re.finditer(r'\{\s*enemies:\s*\[(.*?)\],\s*spawnRate:\s*(\d+),\s*maxEnemies:\s*(\d+)\s*\}', src, re.S):
        ens = re.findall(r"type:\s*'([\w-]+)',\s*weight:\s*(\d+)", m.group(1))
        waves.append(([(DEX[t], int(w)) for t, w in ens], int(m.group(2)), int(m.group(3))))
    bosses = re.findall(r"\{\s*type:\s*'([\w-]+)',\s*timeSeconds:\s*(\d+)\s*\}", src[src.index('bosses:'):])
    return waves, [DEX[t] for t, _ in bosses]


def main():
    lines = ['-- GENERADO por tools/gen_stages.py a partir de giovanneluna/poke-survivors (MIT).',
             '-- Cada fase: 20 oleadas de 30 s ({ {dex, peso}, ..., rate = ms entre apariciones, cap = tope }) y jefes',
             '-- repartidos en los 600 s; el último jefe marca el final de la fase.',
             'return {']
    for i, (fn, name, biome) in enumerate(STAGES):
        waves, bosses = parse(os.path.join(PH, fn))
        n = len(bosses)
        times = [round(STAGE_LEN * (k + 1) / n) for k in range(n)]
        lines.append('  { id = %d, name = "%s", biome = %d, length = %d,' % (i + 1, name, biome, STAGE_LEN))
        lines.append('    bosses = { %s },' % ', '.join('{ dex = %d, at = %d }' % (d, t) for d, t in zip(bosses, times)))
        lines.append('    waves = {')
        for ens, rate, cap in waves:
            lines.append('      { %s, rate = %d, cap = %d },' % (', '.join('{%d,%d}' % e for e in ens), rate, cap))
        lines.append('    } },')
    lines.append('}')
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('escrito', OUT)


if __name__ == '__main__':
    main()
