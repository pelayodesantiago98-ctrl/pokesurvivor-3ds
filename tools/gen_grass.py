#!/usr/bin/env python3
"""
Hierba alta al estilo de la 4.ª generación (Diamante/Perla/Platino), dibujada a mano
en código: casilla de 16x16 con matas en forma de V (base oscura, puntas claras).

Fotogramas (fila única de 16x16 en game/img/grass4.png):
  0       capa trasera quieta (casilla entera, va debajo de los Pokémon)
  1..3    capa trasera agitándose al pisarla
  4       capa delantera quieta (sólo las puntas de abajo: tapa los pies)
  5..7    capa delantera agitándose
"""
import os

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')
T = 16

DARK = (24, 72, 40, 255)        # sombra entre matas
BASE = (40, 112, 48, 255)       # cuerpo de la mata
MID = (64, 152, 56, 255)        # hoja
LIGHT = (112, 200, 80, 255)     # punta iluminada
EDGE = (16, 48, 24, 255)        # contorno

# Una mata: V doble de hojas. Coordenadas relativas a su pie (x, y = base).
TUFT = [
    # (dx, dy, color) de abajo arriba
    (0, 0, BASE), (1, 0, BASE), (2, 0, BASE), (3, 0, BASE), (4, 0, BASE), (5, 0, BASE),
    (0, -1, BASE), (1, -1, MID), (2, -1, BASE), (3, -1, BASE), (4, -1, MID), (5, -1, BASE),
    (0, -2, MID), (1, -2, MID), (2, -2, BASE), (3, -2, BASE), (4, -2, MID), (5, -2, MID),
    (-1, -3, MID), (0, -3, LIGHT), (2, -3, MID), (3, -3, MID), (5, -3, LIGHT), (6, -3, MID),
    (-1, -4, LIGHT), (2, -4, LIGHT), (3, -4, LIGHT), (6, -4, LIGHT),
    (-2, -5, LIGHT), (2, -5, LIGHT), (7, -5, LIGHT),
]


def draw_tuft(img, bx, by, sway):
    px = img.load()
    for dx, dy, c in TUFT:
        # Las puntas (dy <= -3) se inclinan según `sway`.
        lean = sway if dy <= -3 else (sway // 2 if dy == -2 else 0)
        x, y = bx + dx + lean, by + dy
        if 0 <= x < T and 0 <= y < T:
            px[x, y] = c


def outline(img):
    px = img.load()
    marks = []
    for y in range(T):
        for x in range(T):
            if px[x, y][3]:
                continue
            for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + ax, y + ay
                if 0 <= xx < T and 0 <= yy < T and px[xx, yy][3] and px[xx, yy] != EDGE:
                    marks.append((x, y))
                    break
    for x, y in marks:
        px[x, y] = EDGE


# Mata pequeña de la hierba alta de DPPt (3 de ancho, 4 de alto, el pie en (0, 0)).
SMALL_TUFT = [
    (0, -3, LIGHT),
    (-1, -2, LIGHT), (0, -2, MID), (1, -2, LIGHT),
    (-1, -1, MID), (0, -1, MID), (1, -1, MID),
    (-1, 0, MID), (0, 0, BASE), (1, 0, MID),
]


def put_tuft(px, bx, by, sway, rows=None):
    for dx, dy, c in SMALL_TUFT:
        lean = sway if dy <= -2 else 0
        x, y = (bx + dx + lean) % T, by + dy          # en horizontal se repite: casilla continua
        if 0 <= y < T and (rows is None or y in rows):
            px[x, y] = c


# Dos filas de matas al tresbolillo (como el tile del juego); se repite sin costuras.
ROW1 = [(1, 7), (5, 7), (9, 7), (13, 7)]
ROW2 = [(3, 15), (7, 15), (11, 15), (15, 15)]


def back_frame(sway):
    """Capa trasera: casilla entera opaca de hierba alta (base oscura + 2 filas de matas)."""
    img = Image.new('RGBA', (T, T), DARK)
    px = img.load()
    for y in range(T):
        for x in range(T):
            if (x * 3 + y * 5) % 11 == 0:
                px[x, y] = BASE
    for bx, by in ROW1:
        put_tuft(px, bx, by, sway)
    for bx, by in ROW2:
        put_tuft(px, bx, by, -sway)
    # Las puntas de la fila de abajo de la casilla de arriba asoman por la parte de arriba.
    for bx, by in ROW2:
        put_tuft(px, bx, by - T, -sway)
    return img


def front_frame(sway):
    """Capa delantera: sólo la fila de matas de abajo (tapa los pies del Pokémon)."""
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    px = img.load()
    for bx, by in ROW2:
        put_tuft(px, bx, by, -sway)
    for x in range(T):
        if px[x, T - 1][3] == 0:
            px[x, T - 1] = DARK
    return img


def short_frame(sway, cut=False):
    """Hierba normal: una mata corta suelta (2 matitas) sobre transparente."""
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    px = img.load()
    for bx, by, s in ((5, 13, sway), (9, 14, -sway)):
        for dx, dy, c in SMALL_TUFT:
            lean = s if dy <= -2 else 0
            if cut and dy <= -2:
                continue
            x, y = bx + dx + lean, by + dy
            if 0 <= x < T and 0 <= y < T:
                px[x, y] = c
    return img


FLOWER_COLS = [((248, 88, 88, 255), (248, 200, 200, 255)), ((248, 208, 64, 255), (248, 240, 168, 255))]


def flower_frame(col, sway):
    """Flor de 4 pétalos sobre un tallito, meciéndose."""
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    px = img.load()
    petal, light = col
    cx, cy = 7 + sway, 8
    for x, y in ((cx, cy - 1), (cx - 1, cy), (cx + 1, cy), (cx, cy + 1)):
        px[x, y] = petal
    px[cx, cy - 1] = light
    px[cx, cy] = (248, 232, 112, 255)
    for y in range(cy + 2, cy + 6):
        px[7, y] = MID
    px[6, cy + 4] = LIGHT; px[8, cy + 5] = LIGHT
    return img


# ---------- hierba de la 4.ª gen (captura del usuario): mata de hojas en estrella ----------
# Paleta muestreada de la captura: suelo menta, sombra menta oscura y 4 verdes.
G_SHADOW = (24, 162, 89, 255)     # #18a259
G_DARK = (31, 128, 31, 255)       # #1f801f
G_MID = (40, 159, 8, 255)         # #289f08
G_MID2 = (58, 168, 26, 255)       # #3aa81a
G_LIGHT = (88, 191, 55, 255)      # #58bf37
G_EDGE = (22, 100, 30, 255)


def rosette(shake):
    """Mata de 5 hojas puntiagudas que salen del centro (arriba, y dos a cada lado),
    con luz arriba a la izquierda y sombra menta debajo. `shake` mueve las puntas."""
    import math
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    px = img.load()
    # Sombra en el suelo
    for y in range(T):
        for x in range(T):
            if ((x - 7.5) / 7.5) ** 2 + ((y - 11.5) / 4.2) ** 2 <= 1:
                px[x, y] = G_SHADOW
    cx, cy = 7.5, 9.0
    leaves = [(-90, 7.0), (-35, 7.5), (-145, 7.5), (20, 6.5), (160, 6.5)]
    for ang, length in leaves:
        a = math.radians(ang + shake * (6 if ang < 0 else -4))
        ux, uy = math.cos(a), math.sin(a)
        for y in range(T):
            for x in range(T):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                t = dx * ux + dy * uy                      # a lo largo de la hoja
                if t < 0 or t > length:
                    continue
                w = 2.6 * math.sin(math.pi * min(1.0, t / length)) + 0.4   # hoja puntiaguda
                d = abs(-dx * uy + dy * ux)                # distancia al nervio
                if d > w:
                    continue
                lit = -ux * 0.5 - uy * 0.85                # hojas hacia arriba, más claras
                side = (-dx * uy + dy * ux)                # lado izquierdo/derecho del nervio
                if d > w - 0.8:
                    c = G_EDGE
                elif d < 0.6 and t > 1.5:
                    c = G_DARK                             # nervio central
                elif lit > 0.4:
                    c = G_LIGHT if side < 0 else G_MID2
                elif lit > -0.2:
                    c = G_MID2 if side < 0 else G_MID
                else:
                    c = G_MID if side < 0 else G_DARK
                px[x, y] = c
    return img


# Flores de la 4.ª gen (captura del usuario): grupo de dos flores redondas.
F_STEM = (35, 193, 91, 255)       # #23c15b
FLOWERS = {
    'yellow': ((225, 219, 99, 255), (248, 240, 168, 255), (184, 168, 64, 255)),
    'purple': ((164, 155, 192, 255), (208, 200, 232, 255), (129, 128, 161, 255)),
}


def flower_cluster(col, sway):
    img = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    px = img.load()
    base, light, dark = col
    for fx, fy in ((4 + sway, 5), (10 - sway, 9)):
        # tallo
        for y in range(fy + 3, min(T, fy + 7)):
            px[fx, y] = F_STEM
        px[fx - 1, fy + 5] = F_STEM; px[fx + 1, fy + 6] = F_STEM
        # corola redonda 5x4 con luz arriba y sombra abajo
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                if abs(dx) + abs(dy) > 3:
                    continue
                x, y = fx + dx, fy + dy
                if 0 <= x < T and 0 <= y < T:
                    px[x, y] = light if dy < 0 and dx <= 0 else (dark if dy == 2 or dx == 2 else base)
        px[fx, fy] = dark                               # centro
    return img


HGSS = os.path.join(os.path.dirname(HERE), 'build', 'hgss')


def shear(img, top_dx, rows):
    """Desplaza en horizontal las `rows` filas de arriba de lo opaco (las puntas de las
    hojas) `top_dx` píxeles, menos cuanto más abajo: la mata se agita sin despegarse del pie."""
    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    src = img.load()
    dst = out.load()
    bb = img.split()[3].getbbox() or (0, 0, T, T)
    y0 = bb[1]
    for y in range(T):
        k = y - y0
        dx = int(round(top_dx * (rows - k) / float(rows))) if 0 <= k < rows else 0
        for x in range(T):
            c = src[x, y]
            if c[3] and 0 <= x + dx < T:
                dst[x + dx, y] = c
    return out


def recolor(img, cmap):
    out = img.copy()
    px = out.load()
    for y in range(T):
        for x in range(T):
            c = px[x, y][:3]
            if c in cmap:
                px[x, y] = cmap[c] + (255,)
    return out


def hgss_frames():
    """Hierba y flores reales de HGSS (tileset de SirMaio) si gen_hgss.py ya se ha ejecutado."""
    gp, fp = os.path.join(HGSS, 'grass.png'), os.path.join(HGSS, 'flowers.png')
    if not (os.path.exists(gp) and os.path.exists(fp)):
        return None
    g = Image.open(gp).convert('RGBA')
    # Quieta (con un leve vaivén) y dos de agitarse al pisarla, como en el juego.
    short = [g, shear(g, 1, 6), shear(g, -2, 9), shear(g, 2, 9)]
    f = Image.open(fp).convert('RGBA')
    # Sólo los pétalos: fuera el tramado de sombra y las medias flores de los bordes
    # (el tile está pensado para repetirse). Debajo, una sombra lisa de un píxel.
    fpx = f.load()
    SHADE = {(56, 168, 128), (64, 176, 136), (136, 216, 184)}
    for y in range(T):
        for x in range(T):
            c = fpx[x, y]
            if c[3] and (c[:3] in SHADE or x < 4 or y < 2 or x > T - 3 or y > T - 3):
                fpx[x, y] = (0, 0, 0, 0)
    sh = []
    for y in range(T - 1):
        for x in range(T):
            if fpx[x, y][3] and not fpx[x, y + 1][3]:
                sh.append((x, y + 1))
    for x, y in sh:
        fpx[x, y] = (56, 168, 128, 255)
    # Flores naranjas/blancas de HGSS teñidas a las amarillas y moradas de Platino.
    yellow = recolor(f, {(224, 168, 120): (232, 208, 72), (208, 224, 184): (248, 240, 168)})
    purple = recolor(f, {(224, 168, 120): (152, 128, 200), (208, 224, 184): (208, 200, 232),
                         (216, 224, 240): (232, 224, 248)})
    flower = [yellow, ImageChops.offset(yellow, 1, 0), purple, ImageChops.offset(purple, -1, 0)]
    return short, flower


def main():
    sways = [0, 2, -2, 1]
    frames = [back_frame(s) for s in sways] + [front_frame(s) for s in sways]
    real = hgss_frames()
    if real:
        frames += real[0] + real[1]
    else:
        # Hierba normal de 4.ª gen (mata en estrella): 2 de mecerse + 2 de agitarse al pisarla
        frames += [rosette(0), rosette(0.5), rosette(1.5), rosette(-1.5)]
        # Flores: amarillas y moradas, 2 fotogramas cada una
        frames += [flower_cluster(FLOWERS['yellow'], 0), flower_cluster(FLOWERS['yellow'], 1),
                   flower_cluster(FLOWERS['purple'], 0), flower_cluster(FLOWERS['purple'], -1)]
    atlas = Image.new('RGBA', (T * len(frames) + len(frames) + 1, T + 2), (0, 0, 0, 0))
    lines = ['-- GENERADO por tools/gen_grass.py: hierba alta estilo 4.ª gen.',
             '-- back[1..4] = quieta + 3 de agitación; front[1..4] igual para la capa que tapa los pies.',
             'return { w = %d, h = %d, back = {' % (atlas.width, atlas.height)]
    quads = []
    for i, fr in enumerate(frames):
        x = 1 + i * (T + 1)
        atlas.paste(fr, (x, 1))
        quads.append('{%d,1,%d,%d}' % (x, T, T))
    lines.append('  ' + ', '.join(quads[:4]) + ' },')
    lines.append('  front = { ' + ', '.join(quads[4:8]) + ' },')
    lines.append('  short = { ' + ', '.join(quads[8:12]) + ' },')
    lines.append('  flower = { ' + ', '.join(quads[12:16]) + ' } }')
    atlas.save(os.path.join(GAME, 'img', 'grass4.png'), 'PNG', optimize=True)
    with open(os.path.join(GAME, 'data', 'grass4.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    big = atlas.resize((atlas.width * 6, atlas.height * 6), Image.NEAREST)
    big.save(os.path.join(os.path.dirname(HERE), 'build', 'grass4-preview.png'))
    print('hierba: %d fotogramas' % len(frames))


if __name__ == '__main__':
    main()
