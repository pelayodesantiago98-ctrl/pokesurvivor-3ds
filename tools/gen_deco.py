#!/usr/bin/env python3
"""
Empaqueta la decoración de ruta de Poké World Survivors (giovanneluna/poke-survivors,
MIT: public/assets/tiles/route/objects) en un atlas para la 3DS.

    python tools/gen_deco.py [ruta_al_repo]

Salida: game/img/deco.png y game/data/deco.lua con, por objeto:
  { name, x, y, w, h, cat }   cat = tree | bush | small | rock
Cada objeto se recorta a su caja opaca y se separa 1 px de los demás.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\lepay\3ds-tools\src\poke-survivors'
SRC = os.path.join(REPO, 'public', 'assets', 'tiles', 'route', 'objects')
GAME = os.path.join(os.path.dirname(HERE), 'game')

# Qué se usa y en qué categoría (el autumn y el cactus se dejan para variedad rara).
CATS = {
    'trees': 'tree',
    'vegetation': None,       # por nombre, abajo
    'rocks': 'rock',
}
VEG = {
    'bush-green': 'bush', 'bush-light': 'bush', 'bush-large': 'bush', 'bush-leafy': 'bush',
    'hedge-point-dark': 'bush', 'hedge-point-green': 'bush', 'hedge-point-light': 'bush', 'hedge-point-vdark': 'bush',
    'pine-small-a': 'bush', 'pine-small-b': 'bush',
    'bush-cone': 'small', 'fern': 'small', 'palm-small': 'small', 'stump': 'small',
    'hedge-large-green': 'big', 'hedge-large-light': 'big',
    'cactus': 'rare',
}
SKIP = {'coral', 'catalog', 'stump', 'cactus',
        'fern', 'palm-small', 'bush-cone'}   # vienen cortados por abajo en el original
# Familias que al completarse con su reflejo dejan una muesca oscura en la copa.
SKIP_PREFIX = ('tree-autumn', 'tree-tall')


def cut_ratio(im, side):
    """Fracción de píxeles opacos en una columna/fila del borde (1 = cortado de lleno)."""
    a = im.split()[3]
    w, h = im.size
    if side in ('left', 'right'):
        x = 0 if side == 'left' else w - 1
        vals = [a.getpixel((x, y)) > 40 for y in range(h)]
    else:
        y = 0 if side == 'top' else h - 1
        vals = [a.getpixel((x, y)) > 40 for x in range(w)]
    return sum(vals) / float(len(vals))


def complete(im):
    """Los objetos de la hoja original vienen partidos por la mitad vertical: se
    completan con su reflejo. Devuelve None si están cortados arriba (no se puede)."""
    from PIL import ImageOps
    r, l, t = cut_ratio(im, 'right'), cut_ratio(im, 'left'), cut_ratio(im, 'top')
    if t > 0.45:
        return None
    w, h = im.size
    if r > 0.35 and r >= l:
        out = Image.new('RGBA', (w * 2, h), (0, 0, 0, 0))
        out.paste(im, (0, 0))
        out.paste(ImageOps.mirror(im), (w, 0))
        return out
    if l > 0.35:
        out = Image.new('RGBA', (w * 2, h), (0, 0, 0, 0))
        out.paste(ImageOps.mirror(im), (0, 0))
        out.paste(im, (w, 0))
        return out
    return im


TRUNK = {(64, 56, 48), (96, 64, 72), (112, 96, 96), (128, 104, 80)}


def tree_body(im):
    """Caja sólida del árbol en píxeles del sprite (x0, y0, x1, y1): hojas + tronco,
    sin la sombra del suelo (que se puede pisar). Hasta la última fila con tronco."""
    w, h = im.size
    px = im.load()
    foot = None
    for y in range(h - 1, -1, -1):
        if any(px[x, y][3] and px[x, y][:3] in TRUNK for x in range(w)):
            foot = y + 1
            break
    if foot is None:
        return None
    xs = [x for y in range(foot) for x in range(w) if px[x, y][3]]
    ys = [y for y in range(foot) for x in range(w) if px[x, y][3]]
    # Un poco de holgura: los bordes de las hojas no frenan.
    return (min(xs) + 2, min(ys) + 3, max(xs) - 1, foot)


def main():
    items = []
    # Árboles: los de HeartGold/SoulSilver (tileset de SirMaio) que saca tools/gen_hgss.py.
    hdir = os.path.join(os.path.dirname(HERE), 'build', 'hgss', 'trees')
    for fn in sorted(os.listdir(hdir)):
        if fn.endswith('.png'):
            items.append(('hgss-' + fn[:-4], 'tree', Image.open(os.path.join(hdir, fn)).convert('RGBA')))
    # Rocas (rompibles) y arbolito de Corte (mata) de HGSS.
    odir = os.path.join(os.path.dirname(HERE), 'build', 'hgss', 'objects')
    for fn in sorted(os.listdir(odir)):
        if fn.endswith('.png'):
            n = fn[:-4]
            items.append(('hgss-' + n, 'rock' if n.startswith('rock') else 'bush',
                          Image.open(os.path.join(odir, fn)).convert('RGBA')))
    # (La vegetación de poke-survivors ya no se usa: no pegaba con el estilo HGSS.)
    for sub in ():
        d = os.path.join(SRC, sub)
        for fn in sorted(os.listdir(d)):
            if not fn.endswith('.png'):
                continue
            name = fn[:-4]
            if name in SKIP or name.startswith(SKIP_PREFIX):
                continue
            cat = CATS[sub] or VEG.get(name)
            if not cat:
                continue
            im = Image.open(os.path.join(d, fn)).convert('RGBA')
            bb = im.split()[3].getbbox()
            if not bb:
                continue
            fixed = complete(im.crop(bb))
            if fixed is None:
                print('  descartado (cortado arriba):', name)
                continue
            if fixed.width > 48 or fixed.height > 72:
                print('  descartado (demasiado grande):', name)
                continue
            items.append((name, cat, fixed))
    # Estantes en un lienzo de 256 de ancho.
    items.sort(key=lambda it: -it[2].height)
    W, x, y, shelf = 256, 1, 1, 0
    pos = []
    for name, cat, im in items:
        if x + im.width + 1 > W:
            x, y, shelf = 1, y + shelf + 1, 0
        pos.append((name, cat, im, x, y))
        x += im.width + 1
        shelf = max(shelf, im.height)
    H = 1
    while H < y + shelf + 1:
        H *= 2
    atlas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for name, cat, im, px, py in pos:
        atlas.paste(im, (px, py))
    atlas.save(os.path.join(GAME, 'img', 'deco.png'), 'PNG', optimize=True)
    lines = ['-- GENERADO por tools/gen_deco.py: árboles HGSS (tileset de SirMaio) y matas/rocas',
             '-- de ruta de giovanneluna/poke-survivors (MIT).',
             '-- cat: tree (sólido) · bush · big · small · rock · rare. x, y, w, h en el atlas img/deco.png.',
             'return { w = %d, h = %d, list = {' % (W, H)]
    for name, cat, im, px, py in sorted(pos, key=lambda p: (p[1], p[0])):
        body = ''
        if cat == 'tree':
            b = tree_body(im)
            if b:
                body = ', body = { %d, %d, %d, %d }' % b
        lines.append('  { name = "%s", cat = "%s", x = %d, y = %d, w = %d, h = %d%s },' % (name, cat, px, py, im.width, im.height, body))
    lines.append('} }')
    with open(os.path.join(GAME, 'data', 'deco.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('%d objetos en un atlas de %dx%d' % (len(pos), W, H))


if __name__ == '__main__':
    main()
