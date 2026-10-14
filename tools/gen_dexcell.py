#!/usr/bin/env python3
"""
Marco de las casillas de la Pokédex, ya pintado (estilo Platino: bisel claro
arriba y oscuro abajo, esquinas redondeadas, fondo en degradado y una Poké Ball
tenue detrás del sprite). Así cada casilla es UN lg.draw en vez de varios
rectángulos redondeados (en la 3DS cada esquina redondeada son vértices en la CPU).

Uso:
  python tools/gen_dexcell.py

Salida: game/img/ui/dexcell.png (256x64) con tres variantes de 46x44 en fila:
  0 = lo tienes · 1 = no lo tienes (más apagado) · 2 = seleccionada (dorado)
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'game', 'img', 'ui', 'dexcell.png')
CW, CH = 46, 44          # celda de la rejilla (CW - 2, CH - 2 en menu.lua)
R = 4                    # radio de las esquinas


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def inside(x, y, inset=0):
    """¿Está el píxel (x, y) dentro del rectángulo redondeado (encogido `inset`)?"""
    x0, y0, x1, y1 = inset, inset, CW - 1 - inset, CH - 1 - inset
    r = max(0, R - inset)
    if x < x0 or y < y0 or x > x1 or y > y1:
        return False
    cx = x0 + r if x < x0 + r else (x1 - r if x > x1 - r else x)
    cy = y0 + r if y < y0 + r else (y1 - r if y > y1 - r else y)
    return (x - cx) ** 2 + (y - cy) ** 2 <= (r + 0.35) ** 2


# Paleta de cada variante: borde, bisel claro, bisel oscuro, fondo arriba, fondo abajo,
# Poké Ball (color, opacidad).
VARIANTS = [
    dict(edge='#0a1430', hi='#5a7cc0', lo='#0d1838', top='#2a4580', bot='#13224a', ball='#9fc0ff', ba=0.16),
    dict(edge='#080f24', hi='#2a3c68', lo='#070d20', top='#16244a', bot='#0b1430', ball='#5b77b0', ba=0.12),
    dict(edge='#ffd23f', hi='#fff3a8', lo='#b8860b', top='#4a6a2a', bot='#22361a', ball='#ffe680', ba=0.18, gold=True),
]


def ball_mask(x, y):
    """Silueta de Poké Ball (contorno, franja y botón) detrás de los pies del sprite."""
    cx, cy, r = CW / 2 - 0.5, CH / 2 + 1, 15
    d = math.hypot(x - cx, y - cy)
    if abs(d - r) < 0.7:
        return True                       # contorno
    if d < r and abs(y - cy) < 0.6 and abs(x - cx) > 4:
        return True                       # franja central
    if abs(d - 3.5) < 0.6:
        return True                       # botón
    return False


def cell(v):
    img = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    px = img.load()
    edge, hi, lo = hexc(v['edge']), hexc(v['hi']), hexc(v['lo'])
    top, bot, ball = hexc(v['top']), hexc(v['bot']), hexc(v['ball'])
    for y in range(CH):
        for x in range(CW):
            if not inside(x, y):
                continue
            if not inside(x, y, 1):
                c = edge                                  # borde exterior
            elif v.get('gold') and not inside(x, y, 2):
                c = mix(edge, lo, 0.35)                   # segundo anillo dorado
            elif not inside(x, y - 1, 1) or not inside(x - 1, y, 1) or \
                    (v.get('gold') and (not inside(x, y - 1, 2) or not inside(x - 1, y, 2))):
                c = hi                                    # bisel claro (arriba e izquierda)
            elif not inside(x, y + 1, 1) or not inside(x + 1, y, 1) or \
                    (v.get('gold') and (not inside(x, y + 1, 2) or not inside(x + 1, y, 2))):
                c = lo                                    # bisel oscuro (abajo y derecha)
            else:
                c = mix(top, bot, y / (CH - 1))           # fondo en degradado
                # Banda de brillo arriba, como los paneles de Platino.
                if y <= 4:
                    c = mix(c, hi, 0.18)
                if ball_mask(x, y):
                    c = mix(c, ball, v['ba'])
            px[x, y] = c + (255,)
    return img


def main():
    sheet = Image.new('RGBA', (256, 64), (0, 0, 0, 0))
    for i, v in enumerate(VARIANTS):
        sheet.paste(cell(v), (i * (CW + 2), 0))
    sheet.save(OUT, optimize=True)
    print('dexcell.png: %d variantes de %dx%d' % (len(VARIANTS), CW, CH))


if __name__ == '__main__':
    main()
