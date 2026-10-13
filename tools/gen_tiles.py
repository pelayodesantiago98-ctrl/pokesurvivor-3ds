#!/usr/bin/env python3
"""
Genera el arte del mundo para la 3DS: un atlas PNG por bioma (suelo, tierra,
paredes, líquido y objetos del escenario) y los datos Lua que lo describen.

Por qué: en la web (js/world/tiles.js) el suelo se pinta píxel a píxel en el
navegador cada vez que se hornea un chunk. La 3DS no tiene CPU para eso, así
que aquí se PRE-GENERA todo con las mismas funciones de pintado (portadas a
Python) y el juego lo dibuja con SpriteBatch:

  - floor_0..5      suelo (0..2 lisos con distinto tramado; 3 matojo; 4 flor; 5 piedrecita)
  - dirt_<m>        tierra, autotile de 4 vecinos (1 N, 2 E, 4 S, 8 O = vecino también tierra),
                    sobre fondo transparente y con borde orgánico donde no hay vecino
  - wall_<m>        pared, mismo convenio; cara frontal de 6 px si no hay pared al sur
  - liquid_<m>      líquido, 8 vecinos (1 N, 2 NE, 4 E, 8 SE, 16 S, 32 SO, 64 O, 128 NO);
                    sólo las 47 máscaras canónicas (diagonal sólo si sus dos ortogonales)
  - wallshadow      sombra de contacto (2 filas) que el suelo lleva bajo una pared al norte
  - prop_<tipo>_<v> objetos: tree, rock(0,1), chest, grass(0,1), altar(0..7), spring(0,1),
                    bigchest, trap(0..2), rift(0..3)

Uso:  "C:\\Program Files\\Python314\\python.exe" tools/gen_tiles.py
Salida (en game/): img/tiles/<bi>.png (bi = 0..21; el 21 es la arena de Arceus) y data/tiles.lua
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')
OUT_IMG = os.path.join(GAME, 'img', 'tiles')
OUT_LUA = os.path.join(GAME, 'data', 'tiles.lua')

T = 16
PAD = 1                       # separación entre cuadros del atlas
SIZES = [(256, 256), (512, 256), (256, 512), (512, 512), (512, 1024)]

# ---------------- biomas (copia literal de tiles.js) ----------------

BIOMES = [
    # Hierba normal al estilo de la 4.ª generación: verde vivo con matitas en ʌ.
    {'name': 'Bosque Umbrío', 'liquid': 'water', 'gen4': True,
     # Suelo menta de HGSS (casillas reales en paint_floor_gen4); el camino, menta claro.
     'floor': ['#70c8a0', '#78d0a8', '#68c098'], 'dirt': ['#b8e8d0', '#b0e0c8', '#c0f0d8'],
     'speck': '#40b088', 'light': '#88d8b8', 'flowers': ['#f85858', '#f8f8f8', '#f8d040'],
     'wallTop': ['#5d6e49', '#677a50', '#566544'], 'wallLight': '#88a06e', 'wallEdge': '#26301f',
     'wallFace': ['#3e4934', '#363f2d'], 'wallFaceDark': '#232a1d',
     'liq': '#3b7fc6', 'liqDeep': '#2c64a6', 'foam': '#b3defa', 'shore': '#2b5b2a',
     'prop': 'tree', 'leaf': ['#235a2b', '#2f7535', '#45943f', '#64b252'], 'trunk': ['#5b3b22', '#7a5130'],
     'rock': ['#5e6670', '#7f8893', '#a1aab4'], 'grass': ['#2f6b2c', '#4c9a3f', '#7cc45a']},
    {'name': 'Cueva Cristal', 'liquid': 'water',
     'floor': ['#4d5778', '#535e81', '#47506f'], 'dirt': ['#3c4462', '#424a69', '#37405b'],
     'speck': '#3b4363', 'light': '#6a78a4', 'flowers': ['#8fe3ff', '#c9a6ff', '#7ef0d0'],
     'wallTop': ['#5f5089', '#695996', '#56497d'], 'wallLight': '#a08ddc', 'wallEdge': '#1f1934',
     'wallFace': ['#3f3463', '#382e59'], 'wallFaceDark': '#221c3a',
     'liq': '#2a9cab', 'liqDeep': '#1d7c8a', 'foam': '#aaf4f7', 'shore': '#33405e',
     'prop': 'crystal', 'leaf': ['#5ad1e8', '#8fe7f5', '#c8f7ff', '#ffffff'], 'trunk': ['#3a4a78', '#4e64a0'],
     'rock': ['#555d79', '#737c9c', '#959fc0'], 'grass': ['#3d5c8a', '#5a86c0', '#8ab8ee']},
    {'name': 'Monte Ascuas', 'liquid': 'lava',
     'floor': ['#5b4537', '#644c3c', '#533f32'], 'dirt': ['#403530', '#473b34', '#392f2b'],
     'speck': '#47362b', 'light': '#806452', 'flowers': ['#ff8d3d', '#ffc45e', '#e06a4a'],
     'wallTop': ['#3c3634', '#443d3a', '#35302e'], 'wallLight': '#625752', 'wallEdge': '#141110',
     'wallFace': ['#2b2624', '#25201f'], 'wallFaceDark': '#151211',
     'liq': '#e45a1f', 'liqDeep': '#b9401a', 'foam': '#ffd46a', 'shore': '#3a2a22',
     'prop': 'dead', 'leaf': ['#4a3a30', '#5e4a3c', '#6f5a49', '#806a58'], 'trunk': ['#3a2e27', '#52423a'],
     'rock': ['#4e4642', '#6a605b', '#877c76'], 'grass': ['#6b4a2a', '#94693a', '#c4914e']},
]
NORMAL = 3
ARENA = 3

# Orden = Object.keys(ARENA_THEMES) en tiles.js (índices de bioma 3..20).
ARENA_THEMES = [
    ('normal', {'name': 'Pradera Eterna', 'floor': '#6f8a4f', 'wall': '#8a7f6a', 'liquid': 'water', 'liq': '#4f8fd0', 'prop': 'tree',
                'leaf': '#5aa04a', 'trunk': '#6b4a2a', 'flowers': ['#f4d65c', '#ffffff', '#f39ac0'], 'grass': '#5a9a40', 'rock': '#8a8a8a',
                'pools': 0, 'pillars': 0.035, 'props': {'tree': 0.025, 'grass': 0.05}, 'weather': None}),
    ('fire', {'name': 'Monte Ascuas', 'floor': '#5b3a2e', 'wall': '#3a2826', 'liquid': 'lava', 'liq': '#e45a1f', 'foam': '#ffd46a', 'prop': 'dead',
              'leaf': '#5e4a3c', 'trunk': '#3a2e27', 'flowers': ['#ff8d3d', '#ffc45e', '#e06a4a'], 'grass': '#94693a', 'rock': '#6a605b',
              'pools': 0.31, 'pillars': 0.03, 'props': {'tree': 0.01}, 'weather': 'sun'}),
    ('water', {'name': 'Gruta Marina', 'floor': '#3c6a80', 'wall': '#2a4660', 'liquid': 'water', 'liq': '#2f86d6', 'foam': '#bfeaff', 'prop': 'crystal',
               'leaf': '#5fd0e8', 'trunk': '#2a4a78', 'flowers': ['#ff9ec4', '#7ef0d0', '#ffffff'], 'grass': '#3f8a9a', 'rock': '#5d7a90',
               'pools': 0.33, 'pillars': 0.02, 'props': {'tree': 0.015}, 'weather': 'rain'}),
    ('grass', {'name': 'Selva Esmeralda', 'floor': '#3a7a32', 'wall': '#4a6a36', 'liquid': 'swamp', 'liq': '#4f6b2a', 'foam': '#9ac25a', 'prop': 'tree',
               'leaf': '#3f9a3a', 'trunk': '#5b3b22', 'flowers': ['#f4d65c', '#ff8ad8', '#ffffff'], 'grass': '#4caa3f', 'rock': '#6a7a5a',
               'pools': 0.22, 'pillars': 0, 'props': {'tree': 0.05, 'grass': 0.12}, 'weather': None}),
    ('electric', {'name': 'Central Voltio', 'floor': '#4a4840', 'wall': '#3a3a48', 'liquid': 'spark', 'liq': '#e8c020', 'foam': '#fff6c0', 'prop': 'crystal',
                  'leaf': '#ffd23f', 'trunk': '#5a5030', 'flowers': ['#ffe14d', '#ffffff', '#7fd0ff'], 'grass': '#8a8a40', 'rock': '#70707a',
                  'pools': 0.28, 'pillars': 0.04, 'props': {'tree': 0.01}, 'weather': 'rain'}),
    ('ice', {'name': 'Glaciar Eterno', 'floor': '#b8cfe0', 'wall': '#7f9fc0', 'liquid': 'ice', 'liq': '#9fd8f0', 'foam': '#ffffff', 'prop': 'crystal',
             'leaf': '#bfe8ff', 'trunk': '#6f8fb0', 'flowers': ['#ffffff', '#9fe0ff', '#d8f1ff'], 'grass': '#9fc0d8', 'rock': '#8fa8c0',
             'pools': 0.36, 'pillars': 0.02, 'props': {'tree': 0.02}, 'weather': 'snow'}),
    ('fighting', {'name': 'Dojo Ancestral', 'floor': '#8a6a46', 'wall': '#5e4232', 'liquid': 'water', 'liq': '#4f8fd0', 'prop': 'tree',
                  'leaf': '#4f8a3a', 'trunk': '#5b3b22', 'flowers': ['#ff5f6d', '#f4d65c', '#ffffff'], 'grass': '#6a8a40', 'rock': '#8a7a6a',
                  'pools': 0, 'pillars': 0.075, 'props': {'tree': 0.008}, 'weather': None}),
    ('poison', {'name': 'Ciénaga Tóxica', 'floor': '#46384f', 'wall': '#33263f', 'liquid': 'poison', 'liq': '#9a4fc0', 'foam': '#e0a6ff', 'prop': 'dead',
                'leaf': '#5a4a6a', 'trunk': '#3a2f45', 'flowers': ['#c86bdc', '#8bd94a', '#e0a6ff'], 'grass': '#6a5a8a', 'rock': '#5a4f6a',
                'pools': 0.31, 'pillars': 0.015, 'props': {'tree': 0.02}, 'weather': None}),
    ('ground', {'name': 'Desierto Rojo', 'floor': '#b08a52', 'wall': '#8a5e34', 'liquid': 'swamp', 'liq': '#9a7a48', 'foam': '#d6b98a', 'prop': 'dead',
                'leaf': '#8a6a40', 'trunk': '#6a4a2a', 'flowers': ['#e06a4a', '#f4d65c', '#ffffff'], 'grass': '#b0904a', 'rock': '#9a7a5a',
                'pools': 0.25, 'pillars': 0.04, 'props': {'tree': 0.01, 'rock': 0.015}, 'weather': 'sand'}),
    ('flying', {'name': 'Pico Celeste', 'floor': '#9fb8d8', 'wall': '#dfe8f4', 'liquid': 'water', 'liq': '#7fb8ff', 'prop': 'tree',
                'leaf': '#e8f2ff', 'trunk': '#9aa8c0', 'flowers': ['#ffffff', '#ffe14d', '#bfe0ff'], 'grass': '#b8d0e8', 'rock': '#c0ccdc',
                'pools': 0, 'pillars': 0.02, 'props': {'tree': 0.025}, 'weather': None}),
    ('psychic', {'name': 'Templo Mental', 'floor': '#5e4470', 'wall': '#3e2a55', 'liquid': 'water', 'liq': '#8a5ad0', 'prop': 'crystal',
                 'leaf': '#ff8ad8', 'trunk': '#5a3a7a', 'flowers': ['#ff8ad8', '#c9a6ff', '#ffffff'], 'grass': '#8a5a9a', 'rock': '#7a6a8a',
                 'pools': 0, 'pillars': 0.045, 'props': {'tree': 0.02}, 'weather': None}),
    ('bug', {'name': 'Bosque Colmena', 'floor': '#5a6a2a', 'wall': '#5e4a26', 'liquid': 'swamp', 'liq': '#6a7a2a', 'foam': '#c4d65a', 'prop': 'tree',
             'leaf': '#8aaa30', 'trunk': '#5b3b22', 'flowers': ['#f4d65c', '#ffffff', '#c4d65a'], 'grass': '#8aaa30', 'rock': '#7a7a5a',
             'pools': 0.2, 'pillars': 0, 'props': {'tree': 0.04, 'grass': 0.12}, 'weather': None}),
    ('rock', {'name': 'Cantera Antigua', 'floor': '#7a6a58', 'wall': '#55473a', 'liquid': 'water', 'liq': '#4f8fd0', 'prop': 'dead',
              'leaf': '#6a5a4a', 'trunk': '#4a3e32', 'flowers': ['#c9b28a', '#ffffff', '#a89070'], 'grass': '#8a7a5a', 'rock': '#8a7a6a',
              'pools': 0, 'pillars': 0.08, 'props': {'rock': 0.03}, 'weather': 'sand'}),
    ('ghost', {'name': 'Cementerio Sombrío', 'floor': '#383447', 'wall': '#24202e', 'liquid': 'water', 'liq': '#3a3a6a', 'prop': 'dead',
               'leaf': '#4a4060', 'trunk': '#2e2838', 'flowers': ['#9a8ad0', '#5fe0c0', '#c9cfdc'], 'grass': '#4a4a60', 'rock': '#5a5670',
               'pools': 0, 'pillars': 0.03, 'props': {'tree': 0.03}, 'weather': 'fog'}),
    ('dragon', {'name': 'Santuario Dragón', 'floor': '#363a5e', 'wall': '#24264a', 'liquid': 'lava', 'liq': '#7b5cff', 'foam': '#c9a6ff', 'prop': 'crystal',
                'leaf': '#7b5cff', 'trunk': '#2a2a5a', 'flowers': ['#7b5cff', '#ffd23f', '#ffffff'], 'grass': '#4a4a8a', 'rock': '#5a5a8a',
                'pools': 0.22, 'pillars': 0.04, 'props': {'tree': 0.015}, 'weather': None}),
    ('dark', {'name': 'Callejón Oscuro', 'floor': '#2c282e', 'wall': '#1c181f', 'liquid': 'water', 'liq': '#2a2a3a', 'prop': 'dead',
              'leaf': '#3a3040', 'trunk': '#241e28', 'flowers': ['#ff5f6d', '#6b5c52', '#9a8a9a'], 'grass': '#3a343a', 'rock': '#4a444a',
              'pools': 0, 'pillars': 0.05, 'props': {'tree': 0.02}, 'weather': None}),
    ('steel', {'name': 'Fortaleza de Acero', 'floor': '#6d7888', 'wall': '#465060', 'liquid': 'water', 'liq': '#4f8fd0', 'prop': 'crystal',
               'leaf': '#c9d2de', 'trunk': '#5d6773', 'flowers': ['#c9d2de', '#ffd23f', '#ffffff'], 'grass': '#8a96a6', 'rock': '#9aa6b5',
               'pools': 0, 'pillars': 0.08, 'props': {'tree': 0.01}, 'weather': None}),
    ('fairy', {'name': 'Bosque Encantado', 'floor': '#4f7f5a', 'wall': '#7a5a8a', 'liquid': 'water', 'liq': '#8fd8ff', 'foam': '#ffe0f4', 'prop': 'tree',
               'leaf': '#e08ad0', 'trunk': '#6b4a5a', 'flowers': ['#ff8ad8', '#ffffff', '#c9a6ff'], 'grass': '#c48ad8', 'rock': '#9a8aa8',
               'pools': 0.16, 'pillars': 0, 'props': {'tree': 0.05, 'grass': 0.1}, 'weather': None}),
]
ARENA_TYPES = [t for t, _ in ARENA_THEMES]


# ---------------- utilidades de color / hash ----------------

def jsround(v):
    """Math.round de JS (los .5 van hacia +inf; round() de Python es bancario)."""
    return int(math.floor(v + 0.5))


def rgb(hex_):
    n = int(hex_[1:], 16)
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255]


def shade(hex_, k):
    c = [jsround(v + (255 - v) * k) if k >= 0 else jsround(v * (1 + k)) for v in rgb(hex_)]
    return '#' + ''.join('%02x' % v for v in c)


def arena_biome(th):
    f, w, L = th['floor'], th['wall'], th['liq']
    return {
        'name': 'Grieta · ' + th['name'], 'liquid': th['liquid'],
        'floor': [f, shade(f, 0.05), shade(f, -0.06)], 'dirt': [shade(f, -0.16), shade(f, -0.12), shade(f, -0.2)],
        'speck': shade(f, -0.25), 'light': shade(f, 0.22), 'flowers': th['flowers'],
        'wallTop': [w, shade(w, 0.07), shade(w, -0.07)], 'wallLight': shade(w, 0.32), 'wallEdge': shade(w, -0.7),
        'wallFace': [shade(w, -0.3), shade(w, -0.38)], 'wallFaceDark': shade(w, -0.55),
        'liq': L, 'liqDeep': shade(L, -0.22), 'foam': th.get('foam') or shade(L, 0.55), 'shore': shade(f, -0.32),
        'prop': th['prop'], 'leaf': [shade(th['leaf'], -0.35), shade(th['leaf'], -0.15), th['leaf'], shade(th['leaf'], 0.3)],
        'trunk': [shade(th['trunk'], -0.2), th['trunk']],
        'rock': [shade(th['rock'], -0.2), th['rock'], shade(th['rock'], 0.22)],
        'grass': [shade(th['grass'], -0.28), th['grass'], shade(th['grass'], 0.28)],
    }


for _t, _th in ARENA_THEMES:
    BIOMES.append(arena_biome(_th))
assert len(BIOMES) == 21

# La arena de Arceus al minuto 30 (src/judgment.lua): ceniza, ruinas y árboles
# muertos, con un claro donde aterriza (clear). No es de ninguna grieta, así que
# va aparte (bioma 21) y no entra en ARENA_TYPES.
JUDGMENT_THEME = {'name': 'Ruinas del Juicio', 'floor': '#4a4240', 'wall': '#2e2829', 'liquid': 'lava', 'liq': '#e8a82a',
                  'foam': '#fff1b8', 'prop': 'dead', 'leaf': '#3e3633', 'trunk': '#2a2321',
                  'flowers': ['#8a7f76', '#e8a82a', '#5a514c'], 'grass': '#5e544c', 'rock': '#6a625c',
                  'pools': 0, 'pillars': 0.03, 'props': {'tree': 0.012, 'rock': 0.02}, 'weather': None, 'clear': 4.5}
JUDGMENT = len(BIOMES)
BIOMES.append(dict(arena_biome(JUDGMENT_THEME), name=JUDGMENT_THEME['name']))
assert len(BIOMES) == 22


def pack(hex_, a=255):
    r, g, b = rgb(hex_)
    return bytes((r, g, b, a))


def mix_pack(h1, h2, t):
    a, b = rgb(h1), rgb(h2)
    return bytes(tuple(jsround(v + (b[i] - v) * t) for i, v in enumerate(a)) + (255,))


# Mismo hash que U.hash de game/src/util.lua (y determinista como G.U.hash en JS).
_P = 2147483647


def H(x, y, s):
    h = (int(math.floor(x)) * 73856093 + int(math.floor(y)) * 19349663 + int(s) * 83492791) % _P
    h = (h * 48271) % _P
    h = (h * 16807 + 12345) % _P
    h = (h * 48271) % _P
    return h / _P


class Pix:
    """Lienzo RGBA: set(x, y, color_bytes); fuera de rango se ignora (como en JS)."""
    __slots__ = ('w', 'h', 'buf')

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray(w * h * 4)

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            self.buf[i:i + 4] = c

    def opaque(self, x, y):
        return self.buf[(y * self.w + x) * 4 + 3] != 0

    def image(self):
        return Image.frombytes('RGBA', (self.w, self.h), bytes(self.buf))


def palette(B):
    C = {}
    for k in ('floor', 'dirt', 'wallTop', 'wallFace', 'flowers', 'grass'):
        C[k] = [pack(h) for h in B[k]]
    for k in ('speck', 'light', 'wallLight', 'wallEdge', 'wallFaceDark', 'liq', 'liqDeep', 'foam', 'shore'):
        C[k] = pack(B[k])
    C['liqLight'] = mix_pack(B['liq'], B['foam'], 0.28)
    return C


# ---------------- suelo / tierra ----------------

def floor_pixel(C, gx, gy, dirt):
    """Color base de un píxel de suelo o tierra (tono por ruido + tramado + motas)."""
    pal = C['dirt'] if dirt else C['floor']
    band = H(gx >> 3, gy >> 3, 11) * 0.7 + H(gx, gy, 12) * 0.5
    col = pal[min(len(pal) - 1, int(band * len(pal) / 1.2))]
    r = H(gx, gy, 13)
    if r < 0.035:
        col = C['speck']
    elif r > 0.985:
        col = C['light']
    return col, r


HGSS_GROUND = os.path.join(os.path.dirname(HERE), 'build', 'hgss')


def paint_floor_gen4(P, C, tx, ty, detail):
    """Suelo de hierba de HGSS (tileset de SirMaio, sacado por gen_hgss.py): las 5
    casillas de la primera fila. Si no están, hierba normal de DPPt dibujada a mano."""
    gp = os.path.join(HGSS_GROUND, 'ground_%d.png' % (tx % 5 + 1))
    if os.path.exists(gp):
        g = Image.open(gp).convert('RGB')
        for y in range(T):
            for x in range(T):
                P.set(x, y, bytes(g.getpixel((x, y))) + b'\xff')
        return
    base = C['floor'][0]
    for y in range(T):
        for x in range(T):
            col = base
            if H(tx * T + x, ty * T + y, 71) < 0.06:
                col = C['floor'][1 + int(H(x, y, 72) * 2) % 2]
            P.set(x, y, col)
    spots = [(2, 5), (10, 3), (6, 12), (13, 11)]
    for i, (sx, sy) in enumerate(spots):
        if H(tx, ty * 7 + i, 73) < 0.75:
            x, y = sx + int(H(tx, i, 74) * 2), sy
            # ʌ: dos píxeles oscuros abriéndose hacia abajo y la punta clara arriba
            P.set(x, y, C['speck']); P.set(x + 2, y, C['speck'])
            P.set(x + 1, y - 1, C['speck'])
            P.set(x + 1, y - 2, C['light'])
    if detail == 'flower':
        fc = C['flowers'][int(H(tx, ty, 17) * len(C['flowers']))]
        dx, dy = 7, 8
        P.set(dx, dy - 1, fc); P.set(dx - 1, dy, fc); P.set(dx + 1, dy, fc); P.set(dx, dy + 1, fc)
        P.set(dx, dy, pack('#f8e070'))
        P.set(dx + 1, dy + 2, C['speck'])
    elif detail == 'pebble':
        P.set(4, 9, C['light']); P.set(5, 9, C['light'])


def paint_floor(P, C, tx, ty, detail, B=None):
    """Tile de suelo sin tierra. detail: None | 'tuft' | 'flower' | 'pebble'."""
    if B is not None and B.get('gen4'):
        return paint_floor_gen4(P, C, tx, ty, detail)
    for y in range(T):
        for x in range(T):
            col, _ = floor_pixel(C, tx * T + x, ty * T + y, False)
            P.set(x, y, col)
    dx = 3 + int(H(tx, ty, 15) * 10)
    dy = 4 + int(H(tx, ty, 16) * 9)
    if detail == 'tuft':
        P.set(dx, dy, C['light']); P.set(dx - 1, dy - 1, C['light']); P.set(dx + 1, dy - 1, C['light'])
        P.set(dx, dy - 2, C['light']); P.set(dx, dy + 1, C['speck'])
    elif detail == 'flower':
        fc = C['flowers'][int(H(tx, ty, 17) * len(C['flowers']))]
        P.set(dx, dy - 1, fc); P.set(dx - 1, dy, fc); P.set(dx + 1, dy, fc); P.set(dx, dy + 1, fc)
        P.set(dx, dy, C['light'])
    elif detail == 'pebble':
        P.set(dx, dy, C['light']); P.set(dx + 1, dy, C['light']); P.set(dx, dy + 1, C['speck']); P.set(dx + 1, dy + 1, C['speck'])


DIRT_SEED = 500


def dirt_edge_depth(side, c):
    """Profundidad (px) a la que empieza la tierra desde un borde sin vecino.
    Ruido de valor periódico (periodo 16, nodos cada 4 px) para que el borde
    continúe de un tile al siguiente. Sólo depende del lado y la coordenada."""
    i, u = c // 4, (c % 4) / 4.0
    a = H(i % 4, side, DIRT_SEED)
    b = H((i + 1) % 4, side, DIRT_SEED)
    return 1.0 + (a + (b - a) * u) * 3.5


def dirt_mask(m):
    n, e, s, w = m & 1, m & 2, m & 4, m & 8
    rows = []
    for y in range(T):
        row = []
        for x in range(T):
            j = (H(x, y, DIRT_SEED + 9) - 0.5) * 1.5
            ok = True
            if not n and y + 0.5 + j < dirt_edge_depth(0, x): ok = False
            if not s and (T - 1 - y) + 0.5 + j < dirt_edge_depth(1, x): ok = False
            if not w and x + 0.5 + j < dirt_edge_depth(2, y): ok = False
            if not e and (T - 1 - x) + 0.5 + j < dirt_edge_depth(3, y): ok = False
            row.append(ok)
        rows.append(row)

    def at(x, y):
        if y < 0:
            return bool(n) and rows[0][x]      # el tile de arriba también es tierra
        return rows[y][x]
    return at


def paint_dirt(P, C, tx, ty, m, B=None):
    """Tierra sobre fondo transparente (se dibuja encima de floor_*)."""
    at = dirt_mask(m)
    if B is not None and B.get('gen4'):
        # Camino de HGSS: menta claro liso con puntitos blancos y un borde suave.
        base, edge, dot = pack('#b8e8d0'), pack('#98d8b8'), pack('#e8f8f0')

        def a2(x, y):
            # Fuera de la casilla: es camino si el vecino de ese lado también lo es.
            if x < 0: return bool(m & 8) and at(0, min(max(y, 0), T - 1))
            if x >= T: return bool(m & 2) and at(T - 1, min(max(y, 0), T - 1))
            if y < 0: return bool(m & 1) and at(x, 0)
            if y >= T: return bool(m & 4) and at(x, T - 1)
            return at(x, y)
        for y in range(T):
            for x in range(T):
                if not at(x, y):
                    continue
                border = not (a2(x - 1, y) and a2(x + 1, y) and a2(x, y - 1) and a2(x, y + 1))
                col = edge if border else base
                if not border and H(tx * T + x, ty * T + y, 81) < 0.03:
                    col = dot
                P.set(x, y, col)
        return
    for y in range(T):
        for x in range(T):
            dirt = at(x, y)
            above = at(x, y - 1)
            col, r = floor_pixel(C, tx * T + x, ty * T + y, True)
            if dirt:
                if not above:
                    col = C['speck']              # labio oscuro arriba
                P.set(x, y, col)
            elif above and r < 0.5:
                P.set(x, y, C['light'])           # hierba iluminada invadiendo por abajo


def paint_wallshadow(P, C):
    for x in range(T):
        P.set(x, 0, C['wallFaceDark'])
        if x % 2:
            P.set(x, 1, C['speck'])


# ---------------- pared ----------------

def canopy_tone(gx, gy, L):
    """Copas de árbol vistas desde arriba: bultos de 8 px con luz arriba a la
    izquierda y huecos oscuros entre ellos. Coordenadas globales: continúa entre tiles."""
    best, second, bdx, bdy = 99.0, 99.0, 0.0, 0.0
    cx0, cy0 = gx // 8, gy // 8
    for j in (-1, 0, 1):
        for i in (-1, 0, 1):
            cx, cy = cx0 + i, cy0 + j
            px = cx * 8 + 4 + (H(cx, cy, 61) - 0.5) * 3
            py = cy * 8 + 4 + (H(cx, cy, 62) - 0.5) * 3
            d = math.hypot(gx - px, gy - py)
            if d < best:
                second, best, bdx, bdy = best, d, gx - px, gy - py
            elif d < second:
                second = d
    if second - best < 0.9:
        return L[0]                                   # hueco entre copas
    r = 5.5
    lit = (-bdx * 0.6 - bdy * 0.8) / r + (H(gx, gy, 63) - 0.5) * 0.35
    if lit > 0.55: return L[3]
    if lit > 0.05: return L[2]
    if lit > -0.5: return L[1]
    return L[0]


def edge_wave(c, side):
    """Profundidad (px) del borde ondulado de la masa de copas (continúa entre tiles)."""
    i, u = c // 4, (c % 4) / 4.0
    a, b = H(i, side, 64), H(i + 1, side, 64)
    return 1.0 + (a + (b - a) * u) * 2.5


def paint_wall_canopy(P, C, B, tx, ty, m):
    """Pared en biomas verdes: maleza de copas de árbol (no un bloque liso)."""
    n, e, s, w = bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)
    L = [pack(h) for h in B['leaf']]
    Tr = [pack(h) for h in B['trunk']]
    edge = pack('#14200f')
    shadow = pack('#1c2a16')
    FACE = 0 if s else 6
    for y in range(T):
        for x in range(T):
            gx, gy = tx * T + x, ty * T + y
            # Borde ondulado donde no hay vecino (y esquinas redondeadas).
            dn = y - (edge_wave(gx, 0) if not n else -99)
            dw = x - (edge_wave(gy, 2) if not w else -99)
            de = (T - 1 - x) - (edge_wave(gy, 3) if not e else -99)
            if not n and not w and x + y < 4: continue
            if not n and not e and (T - 1 - x) + y < 4: continue
            if dn < 0 or dw < 0 or de < 0:
                continue
            if y >= T - FACE:
                # Cara frontal: la sombra bajo las copas y los troncos asomando.
                fy = y - (T - FACE)
                cut = edge_wave(gx, 1)
                if fy < cut:
                    col = canopy_tone(gx, gy, L)
                    if fy >= cut - 1: col = edge
                else:
                    k = gx % 8
                    if k in (3, 4) and fy < FACE - 1:
                        col = Tr[1] if k == 4 else Tr[0]
                    elif not s and not w and x < 2: continue
                    elif not s and not e and x > T - 3: continue
                    else:
                        col = shadow
                    if y == T - 1: col = edge
            else:
                col = canopy_tone(gx, gy, L)
                if dn < 1 or dw < 1 or de < 1:
                    col = edge
            P.set(x, y, col)


def paint_wall(P, C, tx, ty, m, B=None):
    if B is not None and B.get('prop') == 'tree':
        return paint_wall_canopy(P, C, B, tx, ty, m)
    n, e, s, w = bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)
    FACE = 0 if s else 6
    for y in range(T):
        for x in range(T):
            if not n and not w and x + y < 3: continue
            if not n and not e and (T - 1 - x) + y < 3: continue
            if not s and not w and x + (T - 1 - y) < 2: continue
            if not s and not e and (T - 1 - x) + (T - 1 - y) < 2: continue
            gx, gy = tx * T + x, ty * T + y
            if y >= T - FACE:
                fy = y - (T - FACE)
                col = C['wallFace'][1 if (x + (0 if H(gx, 0, 21) < 0.5 else 1)) % 3 == 0 else 0]
                if fy == 0: col = C['wallEdge']
                elif y == T - 1: col = C['wallFaceDark']
                elif H(gx, gy, 22) < 0.08: col = C['wallFaceDark']
            else:
                col = C['wallTop'][int(H(gx >> 1, gy >> 1, 23) * 2.2 + H(gx, gy, 24) * 0.8) % len(C['wallTop'])]
                if H(gx, gy, 25) < 0.05: col = C['wallLight']
                if not n and y == 0: col = C['wallEdge']
                elif not n and y == 1: col = C['wallLight']
                if not w and x == 0: col = C['wallEdge']
                if not e and x == T - 1: col = C['wallEdge']
            P.set(x, y, col)


# ---------------- líquido ----------------

def liquid_key(m):
    """Máscara canónica: una diagonal sólo cuenta si sus dos ortogonales están."""
    n, ne, e, se, s, sw, w, nw = [(m >> k) & 1 for k in range(8)]
    r = n * 1 + e * 4 + s * 16 + w * 64
    if ne and n and e: r |= 2
    if se and s and e: r |= 8
    if sw and s and w: r |= 32
    if nw and n and w: r |= 128
    return r


LIQUID_MASKS = sorted(set(liquid_key(m) for m in range(256)))
assert len(LIQUID_MASKS) == 47


def paint_liquid(P, C, tx, ty, m, B=None, frame=0):
    n, ne, e, se, s, sw, w, nw = [bool((m >> k) & 1) for k in range(8)]
    BIG = 99
    shallow = B is not None and B.get('gen4')
    for y in range(T):
        for x in range(T):
            # Bordes redondeados: esquinas salientes con radio RO y entrantes con RI
            # (la orilla se mete en el agua con un cuarto de círculo).
            RO, RI = 6.0, 5.0
            cxp, cyp = x + 0.5, y + 0.5
            ix, iy = T - cxp, T - cyp                     # distancias a los bordes este / sur
            d = min(BIG if n else y, BIG if s else T - 1 - y, BIG if w else x, BIG if e else T - 1 - x)
            skip = False
            for open_a, open_b, ux, uy in ((not n, not w, cxp, cyp), (not n, not e, ix, cyp),
                                           (not s, not w, cxp, iy), (not s, not e, ix, iy)):
                if open_a and open_b and ux < RO and uy < RO:
                    dist = math.hypot(RO - ux, RO - uy)
                    if dist > RO: skip = True
                    d = min(d, RO - dist)
            # Esquinas interiores (los dos lados son líquido pero la diagonal no): el
            # borde y los rebordes de las casillas vecinas giran aquí en ángulo, sin
            # meter hierba dentro del agua (antes quedaba un pegote verde).
            for solid_a, solid_b, diag, ux, uy in ((n, w, nw, cxp, cyp), (n, e, ne, ix, cyp),
                                                   (s, w, sw, cxp, iy), (s, e, se, ix, iy)):
                if solid_a and solid_b and not diag:
                    d = min(d, max(ux, uy) - 0.5)
            if skip:
                continue
            gx, gy = tx * T + x, ty * T + y
            r = H(gx, gy, 31)
            if B is not None and B.get('liquid') == 'lava':
                # Mar de Diamante/Perla/Platino teñido de lava: olas en escamas
                # horizontales (cresta clara, cuerpo, sombra), espuma amarilla y una
                # costra oscura en la orilla. No se pisa (ver W.collide).
                # Animación (4 fotogramas que cierran el ciclo): la ola avanza 4 px en
                # horizontal y sube 2 px por fotograma; la espuma de la orilla late.
                foam = 2.2 + (0.7 if frame % 2 else 0.0)
                if d < 1: col = pack('#4a2216')
                elif d < foam: col = pack('#fff0a0')
                elif d < foam + 1.0: col = pack('#ffc048')
                else:
                    ph = (gy + frame * 2 + 2.0 * math.sin((gx + 4 * frame) * math.pi / 8.0)) % 8.0
                    if ph < 1: col = pack('#ffd868')
                    elif ph < 2: col = pack('#ff9a38')
                    elif ph < 6: col = pack('#e85a1c')
                    else: col = pack('#c03c14')
                P.set(x, y, col)
                continue
            if shallow:
                # Agua poco profunda de Negro/Blanco (se camina por ella): contorno,
                # reborde claro junto a la orilla y vetas diagonales suaves.
                if d < 1: col = pack('#4ea8c4')
                elif d < 2: col = pack('#8ad8ec')
                elif d < 3: col = pack('#7bcde2')
                else:
                    col = pack('#69c0d9')
                    if (gx + gy * 2) % 13 in (0, 1) and H(gx // 6, gy // 3, 35) < 0.45: col = pack('#74c8dc')
                    if H(gx, gy, 34) < 0.006: col = pack('#a8e4f2')
                P.set(x, y, col)
                continue
            if d < 1: col = C['shore']
            elif d < 2: col = C['foam']
            elif d < 4: col = C['liqLight']
            elif d < 6: col = C['liq'] if r < 0.5 else C['liqLight']
            else: col = C['liq'] if (d < 8 and r < 0.5) else C['liqDeep']
            if d >= 6 and d < BIG and r < 0.08: col = C['liq']
            if d >= 3 and H(gx >> 2, gy, 33) < 0.045 and (gx & 3) != 3: col = C['liqLight']
            if d >= 3 and H(gx, gy, 34) < 0.004: col = C['foam']
            P.set(x, y, col)


# ---------------- objetos del escenario (PAINT de tiles.js) ----------------

def disc(P, cx, cy, r, col_fn):
    for y in range(int(math.floor(cy - r)), int(math.ceil(cy + r)) + 1):
        for x in range(int(math.floor(cx - r)), int(math.ceil(cx + r)) + 1):
            d = math.hypot(x - cx, y - cy)
            if d <= r:
                c = col_fn(x, y, d / r)
                if c is not None:
                    P.set(x, y, c)


def outline(P, col):
    marks = []
    for y in range(P.h):
        for x in range(P.w):
            if P.opaque(x, y):
                continue
            for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + a, y + b
                if 0 <= xx < P.w and 0 <= yy < P.h and P.opaque(xx, yy):
                    marks.append((x, y))
                    break
    for x, y in marks:
        P.set(x, y, col)


def paint_tree(B, variant=0):
    if B['prop'] == 'crystal':
        return paint_crystal(B)
    if B['prop'] == 'dead':
        return paint_deadtree(B)
    P = Pix(30, 40)
    L = [pack(h) for h in B['leaf']]
    Tr = [pack(h) for h in B['trunk']]
    edge = pack('#14200f')
    for y in range(26, 38):
        for x in range(13, 18):
            P.set(x, y, Tr[0 if x in (13, 17) else 1])
    P.set(12, 37, Tr[0]); P.set(18, 37, Tr[0]); P.set(11, 38, Tr[0]); P.set(19, 38, Tr[0])
    for bx, by, br in ((15, 20, 10), (9, 16, 7), (21, 16, 7), (15, 10, 8), (10, 23, 6), (20, 23, 6)):
        def fn(x, y, d, bx=bx, by=by, br=br):
            lit = ((x - bx) * -0.6 + (y - by) * -0.8) / br
            idx = 3 if lit > 0.45 else 2 if lit > 0.05 else 1 if lit > -0.45 else 0
            return L[idx - 1] if (H(x, y, 41) < 0.12 and idx > 0) else L[idx]
        disc(P, bx, by, br, fn)
    outline(P, edge)
    return P


def paint_crystal(B):
    P = Pix(26, 40)
    L = [pack(h) for h in B['leaf']]
    D = [pack(h) for h in B['trunk']]
    for cx, top, half, bot in ((13, 2, 5, 38), (7, 14, 4, 38), (19, 12, 4, 38)):
        for y in range(top, bot + 1):
            t = min(1.0, (y - top) / 8)
            hw = jsround(half * t)
            for x in range(cx - hw, cx + hw + 1):
                side = (3 if x == cx - hw else 2) if x < cx else (1 if x == cx else 0)
                P.set(x, y, L[side] if side >= 2 else (D[1] if y > bot - 4 else L[side]))
    outline(P, D[0])
    return P


def paint_deadtree(B):
    P = Pix(28, 40)
    Tr = [pack(h) for h in B['trunk']]
    L = [pack(h) for h in B['leaf']]
    for y in range(12, 38):
        for x in range(12, 16):
            P.set(x, y, Tr[0 if x < 14 else 1])

    def branch(x0, y0, dx, ln):
        for i in range(ln):
            P.set(x0 + dx * i, y0 - i, L[1])
            P.set(x0 + dx * i, y0 - i + 1, L[0])
    branch(12, 20, -1, 9); branch(15, 17, 1, 10); branch(13, 13, -1, 7); branch(14, 12, 1, 6)
    outline(P, pack('#0f0b09'))
    return P


def paint_rock(B, variant):
    P = Pix(22, 17)
    R = [pack(h) for h in B['rock']]
    shine = pack('#ffffff')
    for y in range(2, 16):
        for x in range(1, 21):
            nx, ny = (x - 10.5) / 9.5, (y - 9.5) / 7
            d = nx * nx + ny * ny + (H(x, y, 61) - 0.5) * 0.08
            if d > 1:
                continue
            lit = -nx * 0.55 - ny * 0.85 + (H(x, y, 62) - 0.5) * 0.25
            c = R[2 if lit > 0.4 else 1 if lit > -0.15 else 0]
            if y >= 14:
                c = R[0]
            P.set(x, y, c)
    for x, y in ((6, 5), (7, 5), (6, 6), (8, 4)): P.set(x, y, shine)
    for x, y in ((13, 8), (14, 9), (9, 11), (16, 11), (11, 7)): P.set(x, y, R[0])
    if variant == 1:
        dark = pack('#1b1d22')
        for x, y in ((9, 4), (10, 5), (10, 6), (11, 7), (10, 8), (12, 8), (13, 9), (8, 9), (7, 10)):
            P.set(x, y, dark)
    outline(P, pack('#17191d'))
    return P


def paint_grass(B, variant):
    P = Pix(20, 17)
    Gc = [pack(h) for h in B['grass']]
    dark = pack(B['speck'])
    sway = 1.2 if variant == 1 else 0
    blades = 11
    for pss in range(2):
        for b in range(pss, blades, 2):
            t = b / (blades - 1)
            x0 = 3 + t * 13 + (H(b, 7, 52) - 0.5) * 2
            hgt = 8 + int(H(b, 3, 51) * 6) + (3 if abs(t - 0.5) < 0.25 else 0)
            lean = (t - 0.5) * 7 + sway * (0.6 + H(b, 1, 53))
            for i in range(hgt + 1):
                k = i / hgt
                x = jsround(x0 + lean * k * k)
                y = 16 - i
                c = Gc[2] if k > 0.78 else Gc[1] if k > 0.25 else Gc[0]
                if pss == 0 and k <= 0.78:
                    c = Gc[0]
                P.set(x, y, c)
                if i < hgt * 0.45:
                    P.set(x + 1, y, dark if k < 0.15 else Gc[0])
    outline(P, pack('#0e1d0c'))
    return P


ORB = [['#ff5f6d', '#c23a4b', '#ffd3d8'], ['#5fd4ff', '#2a8fd0', '#d8f6ff'],
       ['#ff8ad8', '#b03d84', '#ffe0f4'], ['#ffd23f', '#c08a10', '#fff3b0']]


def paint_altar(B, variant):
    P = Pix(18, 27)
    R = [pack(h) for h in B['rock']]
    eff, used = variant >> 1, variant & 1
    O = [pack(h) for h in (['#6b7380', '#4a505c', '#9aa2ae'] if used else ORB[eff])]
    for y in range(21, 26):
        for x in range(1, 17):
            P.set(x, y, R[2 if y == 21 else 0 if y >= 24 else 1])
    for y in range(12, 21):
        for x in range(5, 13):
            P.set(x, y, R[2 if x == 5 else 0 if x >= 11 else 1])
    for y in range(10, 12):
        for x in range(3, 15):
            P.set(x, y, R[2 if y == 10 else 1])
    for x, y in ((7, 14), (8, 15), (10, 14), (9, 17), (7, 18), (10, 18)):
        P.set(x, y, O[1])

    def fn(x, y, d):
        lit = (8.5 - x) * 0.5 + (5.5 - y) * 0.7
        return O[2] if lit > 1.6 else O[1] if d > 0.75 else O[0]
    disc(P, 8.5, 5.5, 4.2, fn)
    outline(P, pack('#120e1a'))
    return P


def paint_spring(B, variant):
    P = Pix(34, 16)
    R = [pack(h) for h in B['rock']]
    W = [pack(h) for h in (['#2f5f68', '#3a6f7a', '#4f8a92'] if variant else ['#2ba8b8', '#5fe8d8', '#b8fff4'])]
    for y in range(16):
        for x in range(34):
            nx, ny = (x - 16.5) / 16.5, (y - 8) / 7.5
            d = nx * nx + ny * ny
            if d > 1:
                continue
            if d > 0.62:
                P.set(x, y, R[(1 if H(x, y, 71) < 0.5 else 0) + (1 if ny < -0.2 else 0)])
                continue
            wave = math.sin(x * 0.7 + y * 1.3) > 0.6
            P.set(x, y, W[2] if d < 0.18 else W[2] if wave else W[1] if d < 0.4 else W[0])
    if not variant:
        for x, y in ((10, 6), (11, 5), (22, 9), (23, 8), (16, 11)):
            P.set(x, y, pack('#ffffff'))
    outline(P, pack('#14161c'))
    return P


def paint_bigchest(B, variant=0):
    P = Pix(24, 20)
    wood, woodL, woodD = pack('#6b3a1e'), pack('#8e5329'), pack('#432210')
    iron, ironD, gold, goldD = pack('#9aa6b5'), pack('#5d6773'), pack('#f2c443'), pack('#b5832a')
    for y in range(2, 19):
        for x in range(1, 23):
            c = woodL if y < 8 else wood
            if y == 8 or y == 9: c = ironD
            if x == 1 or x == 22 or y == 18: c = woodD
            if x in (5, 6, 17, 18): c = iron if x in (5, 17) else ironD
            if y == 2 and 1 < x < 22: c = iron
            P.set(x, y, c)
    for x in range(10, 14):
        P.set(x, 5, iron)
    P.set(9, 6, iron); P.set(14, 6, iron); P.set(9, 7, iron); P.set(14, 7, iron)
    for y in range(8, 14):
        for x in range(8, 16):
            P.set(x, y, gold if (x + y) % 4 else goldD)
    P.set(11, 10, woodD); P.set(12, 10, woodD); P.set(11, 11, woodD); P.set(11, 12, woodD)
    outline(P, pack('#1e0f06'))
    return P


TRAP_COL = [['#b45ec4', '#e6a3f0'], ['#8bd94a', '#d2ff9a'], ['#ff7b3d', '#ffd08a']]
TRAP_SYM = [
    [(5, 4), (6, 4), (7, 4), (8, 4), (4, 5), (9, 5), (4, 6), (6, 6), (7, 6), (9, 6), (5, 7), (8, 7), (5, 8), (6, 8), (7, 8), (8, 8), (5, 9), (8, 9)],
    [(4, 4), (4, 5), (3, 6), (5, 6), (4, 7), (8, 5), (8, 6), (7, 7), (9, 7), (8, 8), (6, 9), (5, 10), (7, 10), (6, 11)],
    [(6, 3), (7, 3), (5, 4), (8, 4), (4, 5), (9, 5), (4, 6), (6, 6), (7, 6), (9, 6), (4, 7), (6, 7), (7, 7), (9, 7), (4, 8), (9, 8), (5, 9), (8, 9), (6, 10), (7, 10)],
]


def paint_trap(B, variant):
    P = Pix(14, 14)
    c, l = pack(TRAP_COL[variant][0]), pack(TRAP_COL[variant][1])
    base, baseL = pack('#2a2238'), pack('#3b3150')
    for y in range(1, 13):
        for x in range(1, 13):
            edge = x == 1 or y == 1 or x == 12 or y == 12
            P.set(x, y, c if edge else (base if (x + y) % 2 else baseL))
    for x, y in TRAP_SYM[variant]:
        P.set(x, y, l)
    outline(P, pack('#0c0812'))
    return P


def paint_rift(B, variant):
    P = Pix(30, 46)
    glow, mid, core, white = pack('#7b3cff'), pack('#b48aff'), pack('#140a26'), pack('#f2e6ff')
    for y in range(2, 44):
        t = (y - 2) / 42
        w = math.sin(t * math.pi) * 9 + 1
        off = jsround(math.sin(t * 9 + variant * 1.6) * 2.2 + (H(y, variant, 91) - 0.5) * 2)
        for x in range(-int(math.ceil(w)) - 2, int(math.ceil(w)) + 3):
            ax = abs(x) / w
            px = 15 + x + off
            if ax <= 0.45: P.set(px, y, core)
            elif ax <= 0.75: P.set(px, y, white if H(px, y, 92 + variant) < 0.15 else mid)
            elif ax <= 1.15 or H(px, y, 93 + variant) < 0.3: P.set(px, y, glow)
    for i in range(6):
        P.set(13 + int(H(i, variant, 94) * 5), 8 + int(H(i, variant, 95) * 30), white)
    return P


def paint_chest(B, variant=0):
    P = Pix(16, 14)
    gold, goldD, wood, woodD = pack('#f2c443'), pack('#b5832a'), pack('#8a4f2a'), pack('#5e3418')
    lid = pack('#c4662e')
    for y in range(2, 13):
        for x in range(1, 15):
            c = lid if y < 6 else wood
            if y == 6: c = goldD
            if x == 1 or x == 14: c = woodD
            if (x == 4 or x == 11) and y > 1: c = gold if y < 6 else goldD
            if y == 12: c = woodD
            P.set(x, y, c)
    for x in range(6, 10):
        for y in range(5, 9):
            P.set(x, y, gold if (x + y) % 3 else goldD)
    outline(P, pack('#2a160a'))
    return P


PROPS = [('tree', paint_tree, 1), ('rock', paint_rock, 2), ('chest', paint_chest, 1), ('grass', paint_grass, 2),
         ('altar', paint_altar, 8), ('spring', paint_spring, 2), ('bigchest', paint_bigchest, 1),
         ('trap', paint_trap, 3), ('rift', paint_rift, 4)]

FLOOR_DETAIL = [None, None, None, 'tuft', 'flower', 'pebble']


# ---------------- atlas ----------------

def build_sprites(bi):
    """Lista [(nombre, Pix)] de todos los cuadros de un bioma."""
    B = BIOMES[bi]
    C = palette(B)
    out = []
    # Coordenadas virtuales de tile distintas por clase para decorrelar los hashes.
    for v in range(6):
        P = Pix(T, T); paint_floor(P, C, v, 0, FLOOR_DETAIL[v], B); out.append(('floor_%d' % v, P))
    for m in range(16):
        P = Pix(T, T); paint_dirt(P, C, m, 4, m, B); out.append(('dirt_%d' % m, P))
    for m in range(16):
        P = Pix(T, T); paint_wall(P, C, m, 8, m); out.append(('wall_%d' % m, P))
    for m in LIQUID_MASKS:
        P = Pix(T, T); paint_liquid(P, C, m, 12, m, B); out.append(('liquid_%d' % m, P))
    if B.get('liquid') == 'lava':
        # Mar de lava animado: 3 fotogramas más (el 0 es liquid_m).
        for f in (1, 2, 3):
            for m in LIQUID_MASKS:
                P = Pix(T, T); paint_liquid(P, C, m, 12, m, B, f); out.append(('liquid_%d_f%d' % (m, f), P))
    P = Pix(T, T); paint_wallshadow(P, C); out.append(('wallshadow', P))
    for name, fn, nvar in PROPS:
        for v in range(nvar):
            out.append(('prop_%s_%d' % (name, v), fn(B, v)))
    return out


def shelf_pack(items, W, Hh):
    """Empaquetado por estantes. items: [(nombre, w, h)] -> {nombre: (x, y)} o None."""
    x = y = shelf = 0
    pos = {}
    for name, w, h in sorted(items, key=lambda it: (-it[2], -it[1], it[0])):
        if x + w > W:
            x, y, shelf = 0, y + shelf + PAD, 0
        if y + h > Hh or w > W:
            return None
        pos[name] = (x, y)
        x += w + PAD
        shelf = max(shelf, h)
    return pos


def build_atlas(bi):
    sprites = build_sprites(bi)
    items = [(name, P.w, P.h) for name, P in sprites]
    for W, Hh in SIZES:
        pos = shelf_pack(items, W, Hh)
        if pos:
            break
    else:
        sys.exit('bioma %d: no cabe en %dx%d' % (bi, SIZES[-1][0], SIZES[-1][1]))
    atlas = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    quads = {}
    for name, P in sprites:
        x, y = pos[name]
        atlas.paste(P.image(), (x, y))
        quads[name] = (x, y, P.w, P.h)
    return atlas, quads


# ---------------- salida Lua ----------------

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def lua_val(v):
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua_val(x) for x in v) + '}'
    if isinstance(v, dict):
        return '{' + ','.join('%s=%s' % (k, lua_val(x)) for k, x in v.items() if x is not None) + '}'
    raise TypeError(v)


def write_lua(atlas_info):
    L = []
    L.append('-- GENERADO por tools/gen_tiles.py: tiles y objetos del escenario por bioma. Ver docs/PORT.md §13.')
    L.append('-- biomes[bi]: paleta completa de tiles.js (hex) + atlas (ruta) y su tamaño.')
    L.append('-- quads[bi][nombre] = {x, y, w, h} en img/tiles/<bi>.png.')
    L.append('--   floor_0..5 (0..2 lisos, 3 matojo, 4 flor, 5 piedrecita) · dirt_m / wall_m (m = 1 N + 2 E + 4 S + 8 O)')
    L.append('--   liquid_m (m = 1 N + 2 NE + 4 E + 8 SE + 16 S + 32 SO + 64 O + 128 NO, canonizada con liquidKey)')
    L.append('--   wallshadow (2 filas bajo una pared al norte) · prop_<tipo>_<variante> (ancla: centro inferior)')
    L.append('local M = { T = %d, NORMAL = %d, ARENA = %d }' % (T, NORMAL, ARENA))
    L.append('M.ARENA_TYPES = ' + lua_val(ARENA_TYPES))
    L.append('M.JUDGMENT = %d   -- bioma de la arena de Arceus (Ruinas del Juicio)' % JUDGMENT)
    L.append('M.ARENA_THEMES = {')
    for t, th in ARENA_THEMES:
        L.append('  %s = %s,' % (t, lua_val(th)))
    L.append('}')
    L.append('M.biomes = {}')
    L.append('M.quads = {}')
    for bi, (B, (W, Hh), quads) in enumerate(atlas_info):
        d = dict(B)
        d['atlas'] = 'img/tiles/%d.png' % bi
        d['w'], d['h'] = W, Hh
        L.append('M.biomes[%d] = %s' % (bi, lua_val(d)))
    for bi, (B, (W, Hh), quads) in enumerate(atlas_info):
        L.append('M.quads[%d] = {' % bi)
        for name, q in quads.items():
            L.append('  %s = %s,' % (name, lua_val(q)))
        L.append('}')
    L.append('''
local floor = math.floor

-- Canoniza la máscara de 8 vecinos del líquido: una diagonal sólo cuenta si
-- sus dos ortogonales están (Lua 5.1: sin operadores de bits).
function M.liquidKey(m)
  local n = floor(m / 1) % 2
  local ne = floor(m / 2) % 2
  local e = floor(m / 4) % 2
  local se = floor(m / 8) % 2
  local s = floor(m / 16) % 2
  local sw = floor(m / 32) % 2
  local w = floor(m / 64) % 2
  local nw = floor(m / 128) % 2
  local r = n + e * 4 + s * 16 + w * 64
  if ne == 1 and n == 1 and e == 1 then r = r + 2 end
  if se == 1 and s == 1 and e == 1 then r = r + 8 end
  if sw == 1 and s == 1 and w == 1 then r = r + 32 end
  if nw == 1 and n == 1 and w == 1 then r = r + 128 end
  return r
end

-- Variante de suelo (0..5) a partir de un hash d en [0,1): misma distribución
-- de detalles que paintFloor en tiles.js (18% matojo, 8% flor, 6% piedrecita).
function M.floorVariant(d)
  if d < 0.18 then return 3 end
  if d < 0.26 then return 4 end
  if d < 0.32 then return 5 end
  return floor((d - 0.32) / 0.68 * 3) % 3
end

-- Índice de bioma de la arena de un tipo (como G.Tiles.arenaBiome en JS).
local ARENA_INDEX = {}
for i, t in ipairs(M.ARENA_TYPES) do ARENA_INDEX[t] = i - 1 end
function M.arenaBiome(type)
  return M.ARENA + (ARENA_INDEX[type] or 0)
end

return M''')
    with open(OUT_LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')


# ---------------- main ----------------

def main():
    os.makedirs(OUT_IMG, exist_ok=True)
    info = []
    for bi in range(len(BIOMES)):
        atlas, quads = build_atlas(bi)
        atlas.save(os.path.join(OUT_IMG, '%d.png' % bi), optimize=True)
        info.append((BIOMES[bi], atlas.size, quads))
        print('img/tiles/%d.png  %dx%d  %d cuadros  (%s)' % (bi, atlas.size[0], atlas.size[1], len(quads), BIOMES[bi]['name']))
    write_lua(info)
    print('data/tiles.lua  %d biomas, %d cuadros en total' % (len(info), sum(len(q) for _, _, q in info)))


if __name__ == '__main__':
    main()
