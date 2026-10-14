#!/usr/bin/env python3
"""
Hojas de miniaturas de la Pokédex: el fotograma quieto de cada Pokémon (Idle,
dirección abajo, fotograma 0 del atlas de enemigo: lo mismo que dibuja
G.Sprites.drawStill) recortado de img/pkmn/<dex>.png y colocado en pocas hojas
por generación.

Por qué: en la Pokédex cada casilla cargaba la hoja ENTERA del Pokémon (128-512 KB
de texturas, ~40 ms en la 3DS) para dibujar un solo fotograma; al pasar de página
salían tirones de 0,2-0,5 s. Con esto una generación son 1-2 texturas.

Uso:
  python tools/gen_thumbs.py

Salida (en game/):
  img/thumbs/g<gen>_<k>.png   hojas de hasta 512x512 (alto recortado a potencia de dos)
  data/thumbs.lua             hojas, generación de cada hoja y, por dex, su cuadro y ancla
"""
import os
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')
SIZE = 512          # lado máximo de una hoja
PAD = 1             # separación entre miniaturas (que no se cuelen texels vecinos)

RX_DEX = re.compile(r'\{dex=(\d+),.*?gen=(\d+)')
RX_ATLAS = re.compile(r'enemy=\{ atlas="([^"]+)"')
RX_ANIM = re.compile(r'(Idle|Walk)=\{w=\d+,h=\d+,n=\d+,rows=\d+,ax=([-\d.]+),ay=([-\d.]+),'
                     r'd=\{[^}]*\},q=\{(-?\d+),(-?\d+),(-?\d+),(-?\d+),(-?\d+),(-?\d+)')


def pokedex():
    """[(dex, gen)] en el orden de data/pokedex.lua."""
    out = []
    with open(os.path.join(GAME, 'data', 'pokedex.lua'), encoding='utf-8') as f:
        for line in f:
            m = RX_DEX.search(line)
            if m:
                out.append((int(m.group(1)), int(m.group(2))))
    return out


def still(dex):
    """(imagen recortada, ax, ay) del fotograma quieto, o None si no hay atlas."""
    path = os.path.join(GAME, 'data', 'pkmn', '%d.lua' % dex)
    if not os.path.exists(path):
        return None
    with open(path, encoding='utf-8') as f:
        txt = f.read()
    i = txt.find('enemy={')
    if i < 0:
        return None
    end = txt.find('\n }}', i)
    block = txt[i:end if end > 0 else len(txt)]
    m = RX_ATLAS.search(block)
    if not m:
        return None
    anims = {a.group(1): a for a in RX_ANIM.finditer(block)}
    a = anims.get('Idle') or anims.get('Walk')       # como drawStill: Idle o, si no, Walk
    if not a:
        return None
    png = os.path.join(GAME, m.group(1).replace('/', os.sep) + '.png')
    if not os.path.exists(png):
        return None
    ax, ay = float(a.group(2)), float(a.group(3))
    qx, qy, qw, qh, ox, oy = (int(a.group(k)) for k in range(4, 10))
    img = Image.open(png).convert('RGBA').crop((qx, qy, qx + qw, qy + qh))
    # Ancla ya corregida por el recorte (la misma cuenta que drawStill: a.ax - a.ox).
    return img, ax - ox, ay - oy


def pack(items):
    """Estantes en hojas de SIZE x SIZE. items: [(dex, img, ax, ay)] ->
    [[(dex, img, ax, ay, x, y)]] (una lista por hoja)."""
    items = sorted(items, key=lambda t: (-t[1].height, t[0]))
    sheets, cur = [], []
    x = y = shelf = 0
    for it in items:
        w, h = it[1].width, it[1].height
        if x + w > SIZE:
            x, y, shelf = 0, y + shelf + PAD, 0
        if y + h > SIZE:
            sheets.append(cur)
            cur, x, y, shelf = [], 0, 0, 0
        cur.append(it + (x, y))
        x += w + PAD
        shelf = max(shelf, h)
    if cur:
        sheets.append(cur)
    return sheets


def pow2(n):
    p = 8
    while p < n:
        p *= 2
    return p


def main():
    outdir = os.path.join(GAME, 'img', 'thumbs')
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.endswith('.png'):
            os.remove(os.path.join(outdir, f))
    bygen, missing = {}, []
    for dex, gen in pokedex():
        s = still(dex)
        if s is None:
            missing.append(dex)
            continue
        bygen.setdefault(gen, []).append((dex,) + s)
    sheet_lines, dex_lines = [], []
    total = 0
    for gen in sorted(bygen):
        for k, sheet in enumerate(pack(bygen[gen]), 1):
            h = pow2(max(it[5] + it[1].height for it in sheet))
            atlas = Image.new('RGBA', (SIZE, h), (0, 0, 0, 0))
            for dex, img, ax, ay, x, y in sheet:
                atlas.paste(img, (x, y))
                dex_lines.append('M[%d]={%d,%d,%d,%d,%d,%g,%g}' % (
                    dex, len(sheet_lines) + 1, x, y, img.width, img.height, ax, ay))
            name = 'g%d_%d' % (gen, k)
            atlas.save(os.path.join(outdir, name + '.png'), optimize=True)
            sheet_lines.append('{path="img/thumbs/%s",gen=%d,w=%d,h=%d},' % (name, gen, SIZE, h))
            total += SIZE * h * 4
            print('%s: %d miniaturas, %dx%d' % (name, len(sheet), SIZE, h))
    with open(os.path.join(GAME, 'data', 'thumbs.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERADO por tools/gen_thumbs.py: miniaturas de la Pokédex (fotograma quieto de cada dex).\n')
        f.write('-- sheets[i] = hoja · M[dex] = { hoja, x, y, w, h, ax, ay } (ancla ya corregida por el recorte)\n')
        f.write('local M = {}\nM.sheets = {\n' + '\n'.join(sheet_lines) + '\n}\n')
        f.write('\n'.join(dex_lines) + '\nreturn M\n')
    print('%d hojas, %.1f MB de texturas en total; sin miniatura: %s'
          % (len(sheet_lines), total / 1048576.0, missing or 'ninguno'))


if __name__ == '__main__':
    main()
