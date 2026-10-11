#!/usr/bin/env python3
"""
Extrae del tileset HGSS de SirMaio (versión RMXP de jls-dchrn/HGSS_pokemon_tileset,
escalada x2) el suelo, la hierba, las flores y los árboles, a su tamaño original.

    python tools/gen_hgss.py [png]

Salida en build/hgss/: ground_N.png, grass.png, flowers.png y tree_NN.png (+ montage.png
para revisar). Los recortes que se usan en el juego los empaqueta gen_deco/gen_grass.
"""
import os
import sys
from collections import Counter, deque

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\lepay\3ds-tools\src\hgss-tileset\Buildings\Fused_with_basics\outside_with_bured_tower.png'
OUT = os.path.join(os.path.dirname(HERE), 'build', 'hgss')


def half(img):
    """El tileset está escalado x2 por vecino más cercano: se toma 1 de cada 2 píxeles."""
    w, h = img.size
    return img.resize((w // 2, h // 2), Image.NEAREST)


def is_magenta(c):
    return c[3] == 0 or (c[0] > 200 and c[1] < 60 and c[2] > 200)


def main():
    os.makedirs(OUT, exist_ok=True)
    full = Image.open(SRC).convert('RGBA')
    im = half(full)
    px = im.load()
    W, H = im.size
    # Suelo: la primera fila del tileset (casillas 1..5 de 16x16), sin el cuadro negro.
    grounds = []
    for i in range(1, 6):
        t = im.crop((i * 16, 0, i * 16 + 16, 16))
        t.save(os.path.join(OUT, 'ground_%d.png' % i))
        grounds.append(t)
    # Colores de suelo (los más frecuentes en esas casillas): se borran de los objetos.
    cnt = Counter()
    for t in grounds:
        cnt.update(t.getdata())
    ground_cols = set(c for c, n in cnt.most_common(6))

    def keyed(box):
        t = im.crop(box).copy()
        tp = t.load()
        for y in range(t.size[1]):
            for x in range(t.size[0]):
                c = tp[x, y]
                if is_magenta(c) or c in ground_cols:
                    tp[x, y] = (0, 0, 0, 0)
        return t

    BASE = (112, 200, 160, 255)    # color liso del suelo: lo único que se borra de hierba y flores

    def keyed_base(box):
        t = im.crop(box).copy()
        tp = t.load()
        for y in range(t.size[1]):
            for x in range(t.size[0]):
                if is_magenta(tp[x, y]) or tp[x, y] == BASE:
                    tp[x, y] = (0, 0, 0, 0)
        return t

    keyed_base((96, 0, 112, 16)).save(os.path.join(OUT, 'grass.png'))
    keyed_base((112, 48, 128, 64)).save(os.path.join(OUT, 'flowers.png'))

    # Árboles recortados a mano (coordenadas a tamaño original); se quita magenta, suelo
    # y la casilla de "vacío" (X roja sobre blanco) y se recorta a la caja opaca.
    MANUAL = {
        'pine': (64, 832, 96, 880),
        'round_a': (0, 976, 48, 1024), 'round_b': (48, 976, 96, 1024),
        'autumn': (48, 1056, 96, 1120),
    }
    tdir = os.path.join(OUT, 'trees')
    os.makedirs(tdir, exist_ok=True)
    picks = []
    for name, box in MANUAL.items():
        t = keyed(box)
        tp = t.load()
        for y in range(t.size[1]):
            for x in range(t.size[0]):
                c = tp[x, y]
                if c[3] and ((c[0] > 240 and c[1] > 240 and c[2] > 240) or (c[0] > 200 and c[1] < 60 and c[2] < 60)):
                    tp[x, y] = (0, 0, 0, 0)
        bb = t.split()[3].getbbox()
        if bb:
            t = t.crop(bb)
        if name.startswith('round'):
            # Las esquinas de arriba traen trozos del árbol vecino: fuera del círculo de la copa.
            tp = t.load()
            w, h = t.size
            cx, cy, r = (w - 1) / 2.0, w / 2.0, w / 2.0 + 0.5
            for y in range(int(cy)):
                for x in range(w):
                    if (x - cx) ** 2 + (y - cy) ** 2 > r * r:
                        tp[x, y] = (0, 0, 0, 0)
            bb = t.split()[3].getbbox()
            t = t.crop(bb)
        t.save(os.path.join(tdir, name + '.png'))
        picks.append((name, t))
    # Rocas y arbolito de Corte (para rocas rompibles y matas), quitando el fondo
    # blanco y las X rojas. El arbolito pierde la fila del tiesto de abajo.
    odir = os.path.join(OUT, 'objects')
    os.makedirs(odir, exist_ok=True)
    OBJ = {'rock_pile': (4, 2244, 28, 2264), 'rock_big': (36, 2244, 60, 2266),
           'rock_smash': (0, 1886, 16, 1904), 'rock_strength': (16, 1886, 32, 1904),
           'bush_cut': (48, 1886, 66, 1904)}
    for name, box in OBJ.items():
        t = im.crop(box).copy()
        tp = t.load()
        for y in range(t.size[1]):
            for x in range(t.size[0]):
                r, g, b, a = tp[x, y]
                if a == 0 or (r > 240 and g > 240 and b > 240) or is_magenta(tp[x, y]) or (r > 200 and g < 60 and b < 60):
                    tp[x, y] = (0, 0, 0, 0)
        t = t.crop(t.split()[3].getbbox())
        t.save(os.path.join(odir, name + '.png'))
    cw = max(t.size[0] for _, t in picks) + 6
    ch = max(t.size[1] for _, t in picks) + 6
    mont = Image.new('RGBA', (cw * len(picks), ch), (90, 200, 150, 255))
    for k, (name, t) in enumerate(picks):
        mont.paste(t, (k * cw + 3, 3), t)
    mont.resize((mont.size[0] * 4, mont.size[1] * 4), Image.NEAREST).save(os.path.join(OUT, 'picks.png'))
    print('elegidos:', ', '.join('%s %dx%d' % (n, t.size[0], t.size[1]) for n, t in picks))

    # Árboles: componentes conexas de la zona de árboles una vez quitados magenta y suelo.
    y0, y1 = 832, 1280
    mask = [[False] * W for _ in range(y1 - y0)]
    for y in range(y0, y1):
        for x in range(W):
            c = px[x, y]
            mask[y - y0][x] = not (is_magenta(c) or c in ground_cols)
    seen = [[False] * W for _ in range(y1 - y0)]
    comps = []
    for y in range(y1 - y0):
        for x in range(W):
            if mask[y][x] and not seen[y][x]:
                q = deque([(x, y)]); seen[y][x] = True
                xs, ys, n = [x, x], [y, y], 0
                while q:
                    cx, cy = q.popleft(); n += 1
                    xs[0] = min(xs[0], cx); xs[1] = max(xs[1], cx)
                    ys[0] = min(ys[0], cy); ys[1] = max(ys[1], cy)
                    for ax, ay in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + ax, cy + ay
                        if 0 <= nx < W and 0 <= ny < y1 - y0 and mask[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True; q.append((nx, ny))
                w, h = xs[1] - xs[0] + 1, ys[1] - ys[0] + 1
                if w >= 14 and h >= 18 and n > 150:
                    comps.append((xs[0], ys[0] + y0, w, h))
    comps.sort(key=lambda b: (b[1], b[0]))
    trees = []
    for i, (x, y, w, h) in enumerate(comps):
        t = keyed((x, y, x + w, y + h))
        t.save(os.path.join(OUT, 'tree_%02d.png' % i))
        trees.append((i, t))
    # Hoja de revisión
    cw = max(t.size[0] for _, t in trees) + 4 if trees else 40
    ch = max(t.size[1] for _, t in trees) + 12 if trees else 40
    mont = Image.new('RGBA', (cw * 8, ch * ((len(trees) + 7) // 8 + 1)), (90, 200, 150, 255))
    for k, (i, t) in enumerate(trees):
        mont.paste(t, ((k % 8) * cw + 2, (k // 8) * ch + 2), t)
    mont = mont.resize((mont.size[0] * 3, mont.size[1] * 3), Image.NEAREST)
    mont.save(os.path.join(OUT, 'montage.png'))
    print('suelo: %d, árboles: %d (%s)' % (len(grounds), len(trees), ', '.join('%d:%dx%d' % (i, t.size[0], t.size[1]) for i, t in trees)))


if __name__ == '__main__':
    main()
