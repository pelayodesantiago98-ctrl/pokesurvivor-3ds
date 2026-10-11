#!/usr/bin/env python3
"""
Genera el atlas de efectos (VFX) de PokéSurvivor para la 3DS a partir de las
formas de js/entities/vfx.js, reescritas aquí en Python píxel a píxel.

  python tools/gen_vfx.py            -> game/img/vfx.png + game/data/vfx.lua

En la web cada forma (llama, gota, burbuja...) se colorea con la paleta de su
tipo. Aquí cada forma se guarda UNA sola vez en escala de grises, y el juego la
tiñe con love.graphics.setColor del color del tipo. Tonos (gris, alfa):
  o  contorno   0.25
  d  oscuro     0.40
  m  base       0.55
  l  luz        0.80
  w  brillo     1.00
  L  luz semitransparente (0.80, alfa 0.5)   [burbuja]

Las formas, tamaños, fotogramas, `dir` (se rota con la dirección) y `spin`
(gira sola) son los de vfx.js. Todas miran a la DERECHA. Cada cuadro lleva
(ox, oy) = centro de la forma, para dibujar centrado y rotar en torno a él.

Determinista: usa la misma función hash que G.U.hash de la web (enteros de
32 bits), así que los fotogramas "aleatorios" (llama, roca, sombra) salen
iguales que en el navegador.
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')
OUT_PNG = os.path.join(GAME, 'img', 'vfx.png')
OUT_LUA = os.path.join(GAME, 'data', 'vfx.lua')
MAX_TEX = 512
PAD = 1                                   # separación entre cuadros

TONE = {'o': 0.25, 'd': 0.40, 'm': 0.55, 'l': 0.80, 'w': 1.00, 'L': 0.80}
ALPHA = {'L': 0.5}

# Paletas de vfx.js: contorno, oscuro, medio, claro, brillo. Se exportan para
# que fx.lua pinte las partículas de estela/rayo/golpe con los mismos colores.
PAL = {
    'fire':     ['#6b1200', '#b8300a', '#ff6a1f', '#ffb22e', '#fff2a0'],
    'water':    ['#0f2f78', '#1f56c4', '#3d8bff', '#8ccaff', '#eaf7ff'],
    'grass':    ['#14400f', '#24721e', '#45b23c', '#97e36c', '#eaffd0'],
    'electric': ['#6b4300', '#c48a00', '#ffd21a', '#fff36a', '#ffffff'],
    'psychic':  ['#5e0a3a', '#b0246e', '#ff4f9a', '#ff9fcf', '#ffe8f3'],
    'ice':      ['#134a60', '#2f8aa8', '#62d2ea', '#bff3ff', '#ffffff'],
    'fighting': ['#561208', '#9a2a16', '#e04a2e', '#ff9c6c', '#ffe2cc'],
    'poison':   ['#2e0a3c', '#5e1f7e', '#a043d0', '#d995f2', '#f7e2ff'],
    'ground':   ['#3a250c', '#6e4c1e', '#aa7c3c', '#dcb66c', '#f6e6b8'],
    'flying':   ['#283c66', '#5672b0', '#93b2ff', '#d2e2ff', '#ffffff'],
    'bug':      ['#2e3a06', '#5b7414', '#90b82a', '#cbe86c', '#f4ffd2'],
    'rock':     ['#2e2418', '#5a4a34', '#8e7a5a', '#c6b08a', '#f0e4c6'],
    'ghost':    ['#160e2c', '#33256a', '#5c48aa', '#9e8aea', '#e8deff'],
    'dragon':   ['#160a50', '#2e1ea0', '#5a3cff', '#a490ff', '#e8e2ff'],
    'dark':     ['#0e0a0c', '#2a2026', '#463840', '#7c6a74', '#d4c4cc'],
    'steel':    ['#232d38', '#56667a', '#8c9caf', '#cad6e2', '#ffffff'],
    'fairy':    ['#6a2050', '#b04a8a', '#ff8acb', '#ffc4e6', '#ffffff'],
    'normal':   ['#3e3834', '#7a7068', '#c4bcb0', '#ece6dc', '#ffffff'],
    'aura':     ['#0c2460', '#1c4cb0', '#3a7cff', '#90d2ff', '#ffffff'],
}

# Cómo se ve cada movimiento (MOVE de vfx.js), indexado por id.
#   proj: forma del proyectil (también novas, orbes y dash)
#   beam: forma que viaja por el rayo ('lightning' = zigzag procedural)
#   melee: extra del golpe (impact, jaws, claw, vine, feather)
#   aura / buff: partícula que acompaña · trail: estela (ember, drip, spark, bubbles, dirt, wisp)
#   pal: paleta si no es la del tipo · inward / rise: movimiento de las partículas de aura
MOVE = {
    'quick-attack':  {'proj': 'streak'},
    'ember':         {'proj': 'fire', 'trail': 'ember'},
    'heat-wave':     {'proj': 'fire', 'trail': 'ember'},
    'fire-spin':     {'proj': 'fire', 'trail': 'ember'},
    'flamethrower':  {'proj': 'fire', 'trail': 'ember', 'beam': 'fire'},
    'water-gun':     {'proj': 'drop', 'trail': 'drip'},
    'bubble':        {'proj': 'bubble'},
    'hydro-pump':    {'beam': 'drop'},
    'aqua-ring':     {'buff': 'bubble'},
    'vine-whip':     {'melee': 'vine'},
    'razor-leaf':    {'proj': 'leaf'},
    'leaf-storm':    {'proj': 'leaf'},
    'giga-drain':    {'aura': 'heart', 'inward': True},
    'thunder-shock': {'proj': 'bolt', 'trail': 'spark'},
    'discharge':     {'aura': 'bolt'},
    'thunderbolt':   {'beam': 'lightning'},
    'confusion':     {'proj': 'ring'},
    'psybeam':       {'beam': 'ring'},
    'psychic':       {'proj': 'ring'},
    'sludge':        {'proj': 'blob', 'trail': 'bubbles'},
    'poison-sting':  {'proj': 'needle'},
    'toxic':         {'aura': 'bubble', 'rise': True},
    'mud-shot':      {'proj': 'blob', 'trail': 'dirt'},
    'bulldoze':      {'aura': 'rock', 'rise': True},
    'gust':          {'proj': 'wind'},
    'wing-attack':   {'melee': 'feather'},
    'tackle':        {'melee': 'impact'},
    'body-slam':     {'melee': 'impact'},
    'hyper-voice':   {'proj': 'note'},
    'bug-bite':      {'melee': 'jaws'},
    'string-shot':   {'proj': 'web'},
    'bug-buzz':      {'aura': 'note'},
    'rock-throw':    {'proj': 'rock', 'trail': 'dirt'},
    'rock-slide':    {'proj': 'rock', 'trail': 'dirt'},
    'ice-beam':      {'beam': 'shard'},
    'powder-snow':   {'aura': 'star'},
    'karate-chop':   {'melee': 'impact'},
    'aura-sphere':   {'proj': 'ball', 'pal': 'aura', 'trail': 'spark'},
    'lick':          {'melee': 'impact'},
    'shadow-ball':   {'proj': 'shadow', 'trail': 'wisp'},
    'dragon-rage':   {'beam': 'fire'},
    'dragon-dance':  {'buff': 'arrow'},
    'fairy-wind':    {'proj': 'star'},
    'dazzling-gleam': {'aura': 'star'},
    'metal-claw':    {'melee': 'claw'},
    'flash-cannon':  {'beam': 'shard'},
    'bite':          {'melee': 'jaws'},
    'dark-pulse':    {'proj': 'crescent'},
    'night-shade':   {'aura': 'shadow', 'rise': True},
    'swords-dance':  {'buff': 'arrow', 'pal': 'fighting'},
    'agility':       {'buff': 'arrow', 'pal': 'flying'},
    'harden':        {'buff': 'arrow', 'pal': 'steel'},
    'bonemerang':    {'proj': 'crescent'},
    'psycho-cut':    {'proj': 'crescent'},
    'spikes':        {'proj': 'star'},
    'toxic-spikes':  {'proj': 'star'},
    'hail':          {'proj': 'shard'},
    'meteor-mash':   {'proj': 'rock', 'trail': 'spark'},
    'will-o-wisp':   {'proj': 'ball', 'trail': 'ember'},
    'substitute':    {'proj': 'star'},
    'aerial-ace':    {'proj': 'wind'},
    'flame-wheel':   {'proj': 'fire', 'aura': 'fire'},
    'bubble-beam':   {'proj': 'bubble'},
    'hex':           {'beam': 'shadow', 'proj': 'shadow'},
}

TYPE_SHAPE = {
    'fire': 'fire', 'water': 'drop', 'grass': 'leaf', 'electric': 'bolt', 'psychic': 'ring', 'ice': 'shard',
    'fighting': 'ball', 'poison': 'blob', 'ground': 'blob', 'flying': 'wind', 'bug': 'needle', 'rock': 'rock',
    'ghost': 'shadow', 'dragon': 'fire', 'dark': 'crescent', 'steel': 'shard', 'fairy': 'star', 'normal': 'star',
}


# ---------------- aritmética idéntica a JS ----------------

def imul(a, b):
    return ((a & 0xFFFFFFFF) * (b & 0xFFFFFFFF)) & 0xFFFFFFFF


def to_i32(v):
    """`v | 0` de JS (trunca a entero de 32 bits con signo)."""
    v = int(v) & 0xFFFFFFFF
    return v - 0x100000000 if v >= 0x80000000 else v


def H(x, y, seed=0):
    """G.U.hash de la web, bit a bit."""
    h = imul(to_i32(x), 374761393) ^ imul(to_i32(y), 668265263) ^ imul(to_i32(seed), 2246822519)
    h = imul(h ^ (h >> 13), 1274126177)
    h ^= h >> 16
    return (h & 0xFFFFFFFF) / 4294967296


def jround(v):
    """Math.round de JS: el .5 va hacia +infinito."""
    return math.floor(v + 0.5)


# ---------------- lienzo de píxeles (grid de vfx.js) ----------------

class Grid:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [[None] * w for _ in range(h)]

    def set(self, x, y, c):
        x, y = jround(x), jround(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.g[y][x]
        return None

    def fill(self, fn):
        for y in range(self.h):
            for x in range(self.w):
                c = fn(x, y)
                if c:
                    self.g[y][x] = c

    def outline(self):
        marks = []
        for y in range(self.h):
            for x in range(self.w):
                if self.g[y][x]:
                    continue
                for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    c = self.get(x + a, y + b)
                    if c and c != 'o':
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.g[y][x] = 'o'

    def line(self, x0, y0, x1, y1, c, thick=0, side=None):
        n = math.ceil(math.hypot(x1 - x0, y1 - y0) * 2) + 1
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            y = y0 + (y1 - y0) * i / n
            if thick:
                for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if not self.get(jround(x + a), jround(y + b)):
                        self.set(x + a, y + b, side or c)
            self.set(x, y, c)

    def arc(self, cx, cy, r, a0, a1, c):
        n = math.ceil(r * abs(a1 - a0) * 2) + 2
        for i in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            self.set(cx + math.cos(a) * r, cy + math.sin(a) * r, c)


# ---------------- formas (traducción literal de SHAPES) ----------------

def gen_fire(P, f):
    cx, cy = 10.5, 5
    for x in range(1, 10):
        t = (x - 1) / 8
        th = 0.5 + t * 2.6 + (H(x, f, 3) - 0.5) * 1.3
        yc = cy + math.sin(x * 1.4 + f * 2.1) * 0.8 * (1 - t)
        for y in range(P.h):
            d = abs(y - yc)
            if d > th or (t < 0.3 and H(x, y + f * 7, 5) < 0.4):
                continue
            P.set(x, y, 'l' if (d < th * 0.4 and t > 0.3) else 'm')

    def head(x, y):
        d = math.hypot(x - cx, (y - cy) * 1.1)
        return 'w' if d < 1.3 else 'l' if d < 2.4 else 'm' if d < 3.5 else None
    P.fill(head)
    P.outline()


def gen_drop(P, f):
    for x in range(2, 8):
        th = (x - 2) / 5 * 2.6
        for y in range(P.h):
            d = abs(y - 4)
            if d <= th:
                P.set(x, y, 'l' if d < th * 0.5 else 'm')

    def head(x, y):
        d = math.hypot(x - 8.5, y - 4)
        return 'l' if d < 1.6 else 'm' if d < 3.3 else None
    P.fill(head)
    P.set(9, 2, 'w'); P.set(10, 3, 'w')
    P.outline()


def gen_bubble(P, f):
    rx, ry = 4.3 + f * 0.3, 4.3 - f * 0.3

    def body(x, y):
        e = math.hypot((x - 5) / rx, (y - 5) / ry)
        return ('m' if e > 0.76 else 'L') if e <= 1 else None
    P.fill(body)
    P.set(3, 3, 'w'); P.set(4, 3, 'w'); P.set(3, 4, 'w'); P.set(7, 7, 'l')
    P.outline()


def gen_leaf(P, f):
    def body(x, y):
        dx = abs(x - 5.5) / 5.6
        dy = (y - 3) / 2.7
        return ('l' if y < 3 else 'm') if dx + dy * dy <= 1 else None
    P.fill(body)
    for x in range(2, 10):
        P.set(x, 3, 'd')
    P.set(4, 2, 'w')
    P.outline()


def gen_bolt(P, f):
    pts = [(0, 3), (4, 7), (7, 2), (10, 7), (14, 4)] if f else [(0, 6), (4, 2), (7, 7), (10, 2), (14, 5)]
    for i in range(len(pts) - 1):
        P.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 'w', 1, 'l')
    P.outline()


def gen_shard(P, f):
    P.fill(lambda x, y: ('l' if y < 3 else 'm') if abs(x - 6) / 6.2 + abs(y - 3) / 3.4 <= 1 else None)
    for x in range(6, 12):
        P.set(x, 3, 'w')
    P.set(4, 2, 'w')
    P.outline()


def gen_rock(P, f):
    r = [3.6 + H(i, f, 9) * 1.4 for i in range(7)]

    def body(x, y):
        dx, dy = x - 5.5, y - 5
        a = (math.atan2(dy, dx) + math.pi) / (2 * math.pi) * 6
        i = math.floor(a)
        t = a - i
        R = r[i] * (1 - t) + r[(i + 1) % 6] * t
        d = math.hypot(dx, dy)
        if d > R:
            return None
        lit = (-dx * 0.6 - dy * 0.8) / R
        return 'l' if lit > 0.35 else 'm' if lit > -0.3 else 'd'
    P.fill(body)
    P.set(6, 5, 'd'); P.set(7, 6, 'd'); P.set(4, 3, 'w')
    P.outline()


def gen_blob(P, f):
    def body(x, y):
        dx, dy = x - 5.5, y - 4.8
        a = math.atan2(dy, dx)
        R = 3.9 + math.sin(a * 3 + f * 2) * 0.5
        d = math.hypot(dx, dy)
        if d > R:
            return None
        lit = (-dx * 0.6 - dy * 0.8) / R
        return 'l' if lit > 0.4 else 'm' if lit > -0.35 else 'd'
    P.fill(body)
    P.set(4, 3, 'w'); P.set(3, 3, 'w')
    P.set(6, 9, 'm')
    if f:
        P.set(6, 10, 'm')
    P.outline()


def gen_needle(P, f):
    for x in range(1, 10):
        P.set(x, 2, 'm')
    for x in range(3, 9):
        P.set(x, 1, 'l')
    P.set(10, 2, 'w'); P.set(11, 2, 'w')
    P.set(1, 1, 'd'); P.set(1, 3, 'd')
    P.outline()


def gen_star(P, f):
    L = 3 if f else 4
    for i in range(-L, L + 1):
        P.set(5 + i, 5, 'm' if abs(i) == L else 'l')
        P.set(5, 5 + i, 'm' if abs(i) == L else 'l')
    D = 2 if f else 1
    for i in range(1, D + 1):
        for a, b in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            P.set(5 + a * i, 5 + b * i, 'l')
    P.set(5, 5, 'w'); P.set(4, 5, 'w'); P.set(6, 5, 'w'); P.set(5, 4, 'w'); P.set(5, 6, 'w')


def gen_streak(P, f):
    for x in range(15):
        P.set(x, 2, 'd' if x < 4 else 'm' if x < 8 else 'l' if x < 12 else 'w')
    for x in range(7, 13):
        P.set(x, 1, 'l'); P.set(x, 3, 'm')
    P.set(13, 1, 'w'); P.set(13, 3, 'w')


def gen_wind(P, f):
    P.arc(6, 5, 4.6, -0.6 + f * 0.7, 2.9 + f * 0.7, 'l')
    P.arc(6, 5, 3.6, -0.3 + f * 0.7, 2.2 + f * 0.7, 'w')
    P.arc(6, 5, 2.2, 1.8 + f, 4.6 + f, 'l')


def gen_web(P, f):
    for k in range(8):
        a = k * math.pi / 4
        P.line(5, 5, 5 + math.cos(a) * 5, 5 + math.sin(a) * 5, 'l')
    for r in (2.4, 4.4):
        for k in range(8):
            a0, a1 = k * math.pi / 4, (k + 1) * math.pi / 4
            P.line(5 + math.cos(a0) * r, 5 + math.sin(a0) * r, 5 + math.cos(a1) * r, 5 + math.sin(a1) * r, 'w')


def gen_ring(P, f):
    def body(x, y):
        d = math.hypot(x - 6, y - 6)
        if abs(d - (5 + f * 0.6)) < 0.75:
            return 'm'
        if abs(d - (3 + f * 0.5)) < 0.7:
            return 'l'
        return None
    P.fill(body)
    P.set(6, 6, 'w')


def gen_crescent(P, f):
    def body(x, y):
        a = math.hypot(x - 6.5, y - 5)
        b = math.hypot(x - 3.8, y - 5)
        if a > 4.8 or b < 4.2:
            return None
        return 'l' if b < 5.1 else 'm'
    P.fill(body)
    P.outline()


def gen_note(P, f):
    P.arc(1, 5, 2.2, -0.7, 0.7, 'w')
    P.arc(1, 5, 4.6, -0.6, 0.6, 'l')
    P.arc(1, 5, 7.2, -0.5, 0.5, 'm')


def gen_impact(P, f):
    for k in range(8):
        a = k * math.pi / 4 + (math.pi / 8 if f else 0)
        L = (3.5 if k % 2 else 6) * (1 if f else 0.75)
        P.line(7, 7, 7 + math.cos(a) * L, 7 + math.sin(a) * L, 'l')
        P.set(7 + math.cos(a) * L, 7 + math.sin(a) * L, 'm')
    P.fill(lambda x, y: 'w' if math.hypot(x - 7, y - 7) < 1.8 else None)


def gen_claw(P, f):
    for i in range(3):
        P.line(1 + i * 3.5, 11, 6 + i * 3.5, 1, 'w', 1, 'l')
    P.outline()


def gen_jaws(P, f):
    gap = 0 if f else 2
    for x in range(1, 12):
        P.set(x, 1, 'm'); P.set(x, 9, 'm')
    for t in range(4):
        x = 2 + t * 3
        P.set(x, 2, 'w'); P.set(x + 1, 2, 'w'); P.set(x, 3, 'w'); P.set(x + 1, 3, 'l')
        if not gap:
            P.set(x, 4, 'w')
        P.set(x + 1, 8, 'w'); P.set(x + 2, 8, 'w'); P.set(x + 1, 7, 'w'); P.set(x + 2, 7, 'l')
        if not gap:
            P.set(x + 1, 6, 'w')
    P.outline()


def gen_arrow(P, f):
    for y in range(4):
        for x in range(3 - y, 3 + y + 1):
            P.set(x, y, 'w' if x == 3 - y else 'l')
    for y in range(4, 9):
        for x in range(2, 5):
            P.set(x, y, 'w' if x == 2 else 'm')
    P.outline()


def gen_ball(P, f):
    def body(x, y):
        d = math.hypot(x - 5, y - 5)
        return 'w' if d < 1.5 else 'l' if d < 2.9 else 'm' if d < 4.2 + f * 0.3 else None
    P.fill(body)
    P.set(3, 3, 'w')
    P.outline()


def gen_shadow(P, f):
    def body(x, y):
        d = math.hypot(x - 6, y - 6)
        return 'l' if d < 1.6 else 'm' if d < 3 else 'd' if d < 4.4 else None
    P.fill(body)
    for k in range(6):
        a = k * 1.05 + f * 0.7
        r = 4.8 + H(k, f, 4) * 1.4
        P.set(6 + math.cos(a) * r, 6 + math.sin(a) * r, 'm')
    P.set(5, 5, 'w')
    P.outline()


HEART_ROWS = ['.ll...ll.', 'lwll.llll', 'lllllllll', 'lllllllll', '.lllllll.', '..lllll..', '...lll...', '....l....']


def gen_heart(P, f):
    for y, row in enumerate(HEART_ROWS):
        for x, c in enumerate(row):
            if c != '.':
                P.set(x, y, 'w' if c == 'w' else 'l')
    P.outline()


# nombre -> (w, h, frames, dir, spin, gen)
SHAPES = {
    'fire':     (15, 11, 3, True,  False, gen_fire),
    'drop':     (13, 9,  1, True,  False, gen_drop),
    'bubble':   (11, 11, 2, False, False, gen_bubble),
    'leaf':     (12, 7,  1, False, True,  gen_leaf),
    'bolt':     (15, 10, 2, True,  False, gen_bolt),
    'shard':    (13, 7,  1, True,  False, gen_shard),
    'rock':     (12, 11, 3, False, True,  gen_rock),
    'blob':     (12, 11, 2, False, False, gen_blob),
    'needle':   (13, 5,  1, True,  False, gen_needle),
    'star':     (11, 11, 2, False, True,  gen_star),
    'streak':   (15, 5,  1, True,  False, gen_streak),
    'wind':     (13, 11, 2, False, True,  gen_wind),
    'web':      (11, 11, 1, False, True,  gen_web),
    'ring':     (13, 13, 2, False, False, gen_ring),
    'crescent': (12, 11, 1, True,  False, gen_crescent),
    'note':     (11, 11, 1, True,  False, gen_note),
    'impact':   (15, 15, 2, False, False, gen_impact),
    'claw':     (13, 13, 1, False, False, gen_claw),
    'jaws':     (13, 11, 2, False, False, gen_jaws),
    'arrow':    (7,  9,  1, False, False, gen_arrow),
    'ball':     (11, 11, 2, False, False, gen_ball),
    'shadow':   (13, 13, 3, False, False, gen_shadow),
    'heart':    (9,  8,  1, False, False, gen_heart),
}


# ---------------- render + empaquetado ----------------

def render(name, f):
    w, h, _, _, _, gen = SHAPES[name]
    P = Grid(w, h)
    gen(P, f)
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            ch = P.g[y][x]
            if not ch:
                continue
            v = int(round(TONE[ch] * 255))
            a = int(round(ALPHA.get(ch, 1.0) * 255))
            px[x, y] = (v, v, v, a)
    return img


def pack(items):
    """Empaquetado por estantes en el lienzo potencia de 2 más pequeño.
    items: lista de (key, w, h) ya con el relleno incluido. -> (W, H, {key: (x, y)})"""
    items = sorted(items, key=lambda it: (-it[2], -it[1], it[0]))
    area = sum(w * h for _, w, h in items)
    size = 16
    while size * size < area:
        size *= 2
    while size <= MAX_TEX:
        for W, Hh in ((size, size // 2), (size // 2, size), (size, size)):
            pos, x, y, shelf = {}, 0, 0, 0
            ok = True
            for key, w, h in items:
                if x + w > W:
                    x, y, shelf = 0, y + shelf, 0
                if y + h > Hh:
                    ok = False
                    break
                pos[key] = (x, y)
                x += w
                shelf = max(shelf, h)
            if ok:
                return W, Hh, pos
        size *= 2
    raise SystemExit('el atlas de VFX no cabe en %dx%d' % (MAX_TEX, MAX_TEX))


def lua_key(k):
    if k.isidentifier() and not k.isdigit():
        return k
    return '["%s"]' % k


def lua_val(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    return '"%s"' % v


def main():
    sprites = {}
    for name in SHAPES:
        for f in range(SHAPES[name][2]):
            sprites['%s_%d' % (name, f)] = render(name, f)
    items = [(k, im.width + PAD, im.height + PAD) for k, im in sprites.items()]
    W, Hh, pos = pack(items)
    atlas = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    for k, im in sprites.items():
        atlas.paste(im, pos[k])
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    os.makedirs(os.path.dirname(OUT_LUA), exist_ok=True)
    atlas.save(OUT_PNG, optimize=True)

    L = []
    L.append('-- GENERADO por tools/gen_vfx.py a partir de js/entities/vfx.js. NO EDITAR A MANO.')
    L.append('-- Atlas: img/vfx.png (%dx%d). Formas en escala de grises para teñir con setColor.' % (W, Hh))
    L.append('--')
    L.append('-- quads[forma_f] = {x, y, w, h, ox, oy}: cuadro del fotograma f (0..frames-1) y su')
    L.append('--   centro (ox, oy) = (w/2, h/2), para love.graphics.draw(img, quad, x, y, angle, s, s, ox, oy).')
    L.append('-- shapes[forma] = {frames, dir, spin, w, h}: dir = se rota con la dirección del')
    L.append('--   movimiento (todas miran a la DERECHA); spin = gira sola (angle = t * 9).')
    L.append('--   Rotaciones a múltiplos de pi/8 como en la web. Fotograma: floor(t * 12) % frames.')
    L.append('-- tones: valor de gris de cada letra de vfx.js (o d m l w; L = l con alfa 0.5).')
    L.append('-- pal[nombre] = {contorno, oscuro, medio, claro, brillo} (hex): la paleta de vfx.js,')
    L.append('--   para que fx.lua pinte partículas de estela, rayo y golpe (G.VFX.PAL[pal][i]).')
    L.append('-- tint[nombre]: color recomendado para teñir el sprite gris de esa paleta (= pal[4], el')
    L.append('--   claro). "aura" no es un tipo: por eso se tiñe con tint[pal] y no con U.TYPE_COLOR.')
    L.append('--')
    L.append('-- RESOLUCIÓN (replica G.VFX.forMove / forType de la web):')
    L.append('--   forType(type)  -> forType[type] or forType.normal      ({proj=, pal=})')
    L.append('--   forMove(m)     -> local v = moves[m.id] or {}')
    L.append('--                     return { pal = v.pal or m.type,')
    L.append('--                              proj = v.proj or typeShape[m.type] or "ball",')
    L.append('--                              beam = v.beam, melee = v.melee, aura = v.aura, buff = v.buff,')
    L.append('--                              trail = v.trail, inward = v.inward, rise = v.rise }')
    L.append('--   (moves va por id, no por kind: así está en vfx.js. Cachear el resultado por id.)')
    L.append('-- Valores que NO son formas del atlas (comportamientos de fx.js):')
    L.append('--   beam = "lightning" (zigzag procedural); melee = "vine"/"feather" (4 hojas "leaf",')
    L.append('--   feather con pal "flying"); trail = ember|drip|spark|bubbles|dirt|wisp (partículas).')
    L.append('--   Si un movimiento no tiene proj (solo beam/melee/aura/buff) proj cae en typeShape.')
    L.append('--   dash usa vis.proj or "streak"; buff usa vis.buff or "arrow"; hazards usan forType.')
    L.append('return {')
    L.append('  image = "img/vfx.png", width = %d, height = %d,' % (W, Hh))
    L.append('  tones = { o = 0.25, d = 0.4, m = 0.55, l = 0.8, w = 1.0, L = 0.8 },')

    L.append('  quads = {')
    for k in sorted(sprites):
        im = sprites[k]
        x, y = pos[k]
        L.append('    %s = {%d, %d, %d, %d, %g, %g},' % (lua_key(k), x, y, im.width, im.height, im.width / 2, im.height / 2))
    L.append('  },')

    L.append('  shapes = {')
    for name in sorted(SHAPES):
        w, h, n, d, s, _ = SHAPES[name]
        L.append('    %s = { frames = %d, dir = %s, spin = %s, w = %d, h = %d },'
                 % (lua_key(name), n, lua_val(d), lua_val(s), w, h))
    L.append('  },')

    L.append('  pal = {')
    for name in sorted(PAL):
        L.append('    %s = { %s },' % (lua_key(name), ', '.join('"%s"' % c for c in PAL[name])))
    L.append('  },')
    L.append('  tint = {')
    for name in sorted(PAL):
        L.append('    %s = "%s",' % (lua_key(name), PAL[name][3]))
    L.append('  },')

    L.append('  typeShape = {')
    for t in sorted(TYPE_SHAPE):
        L.append('    %s = "%s",' % (lua_key(t), TYPE_SHAPE[t]))
    L.append('  },')

    L.append('  forType = {')
    for t in sorted(TYPE_SHAPE):
        L.append('    %s = { proj = "%s", pal = "%s" },' % (lua_key(t), TYPE_SHAPE[t], t if t in PAL else 'normal'))
    L.append('  },')

    L.append('  moves = {')
    for mid in sorted(MOVE):
        v = MOVE[mid]
        fields = ', '.join('%s = %s' % (k, lua_val(v[k])) for k in ('proj', 'beam', 'melee', 'aura', 'buff', 'trail', 'pal', 'inward', 'rise') if k in v)
        L.append('    %s = { %s },' % (lua_key(mid), fields))
    L.append('  },')
    L.append('}')
    with open(OUT_LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')

    print('vfx: %d formas, %d cuadros, atlas %dx%d -> %s' % (len(SHAPES), len(sprites), W, Hh, OUT_PNG))
    print('     %s' % OUT_LUA)


if __name__ == '__main__':
    main()
