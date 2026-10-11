#!/usr/bin/env python3
"""
Arte de la tarjeta de entrenador (estilo "tarjeta clásica"): fondos dibujados aquí,
entrenadores y Pokémon con sprites oficiales de los juegos de DS/GBA.

    python tools/gen_card_art.py

  - Fondos propios (246x171): 12 colores x 3 motivos (Poké Ball, rayas de Negro/Blanco,
    puntos de DPPt), todos con la misma distribución (CARD_LAYOUT).
  - Entrenadores: sprites oficiales de 3.ª, 4.ª y 5.ª gen (80x80) de la colección de
    Pokémon Showdown (play.pokemonshowdown.com/sprites/trainers).
  - Paneles de Pokémon (50x30): sprite oficial de Negro/Blanco (PokeAPI/sprites,
    generation-v/black-white, dex 1..649) sobre fondo claro.

Salida: game/img/cards/<n>.png, game/img/trainers/<a>.png, game/img/panels/<a>.png y
game/data/cardstyle.lua. Caché de descargas en C:\\Users\\lepay\\3ds-tools\\src\\card-art.
"""
import math
import os
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, 'game')
CACHE = r'C:\Users\lepay\3ds-tools\src\card-art'
UA = {'User-Agent': 'Mozilla/5.0'}
TRAINER_URL = 'https://play.pokemonshowdown.com/sprites/trainers/%s.png'
BW_URL = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/%d.png'
TRAINER_LIST = os.path.join(HERE, 'trainers.txt')   # nombres de Showdown (3.ª-5.ª gen)

W, H = 246, 171
# Distribución común a todos los fondos (coordenadas en la tarjeta).
TEAM = [(8 + c * 55, 47 + r * 38) for r in range(2) for c in range(3)]      # paneles 50x30, separados
TRAINER = (165, 44)                                                         # 80x80
SOCKETS = [(16 + i * 28, 136) for i in range(8)]                            # huecos 20x20
NAME_PLATE = (8, 26, 132, 39)
CODE_PLATE = (136, 26, 238, 39)

COLORS = [('Rojo', '#d04040'), ('Azul', '#3a6cc8'), ('Verde', '#3c9c50'), ('Amarillo', '#e0b028'),
          ('Rosa', '#e0709c'), ('Morado', '#7c58c0'), ('Negro', '#3a3a46'), ('Plata', '#a8b0bc'),
          ('Naranja', '#e07830'), ('Cian', '#2ea4c0'), ('Marrón', '#9c6c44'), ('Dorado', '#c8a040')]
PATTERNS = [('Poké Ball', 'ball'), ('Rayas', 'stripes'), ('Puntos', 'dots')]

# Protagonistas primero (el 1 es el entrenador por defecto).
FIRST = ['lucas', 'dawn', 'ethan', 'lyra', 'hilbert', 'hilda', 'nate', 'rosa', 'brendan-gen3rs', 'may-gen3rs',
         'brendan-gen3', 'may-gen3', 'red-gen3', 'leaf-gen3', 'barry', 'cheren', 'bianca', 'n', 'cynthia']
GEN4 = set('lucas dawn barry cynthia roark gardenia maylene crasherwake fantina byron candice volkner aaron bertha '
           'flint lucian cyrus mars jupiter saturn riley palmer thorton dahlia darach argenta ethan lyra silver '
           'falkner bugsy whitney morty chuck jasmine pryce clair will karen koga lance janine blue red'.split())
GEN3_CLASSIC = set('wally steven wallace roxanne brawly wattson flannery norman winona juan sidney glacia'.split())


def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, k):
    if k >= 0:
        return tuple(int(v + (255 - v) * k) for v in c)
    return tuple(int(v * (1 + k)) for v in c)


def shade_hex(h, k):
    return '#%02x%02x%02x' % shade(rgb(h), k)


def fetch(url, path):
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
            data = r.read()
    except Exception as e:                                   # noqa: BLE001
        print('  no se pudo bajar', url, e)
        return None
    with open(path, 'wb') as f:
        f.write(data)
    return path


# ---------------- fondos ----------------

def card_background(base, pattern):
    B = rgb(base)
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    edge = shade(B, -0.6)
    # Cuerpo con degradado vertical (más claro arriba)
    body = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    for y in range(H):
        k = 0.28 - 0.4 * y / H
        bd.line([(0, y), (W, y)], fill=shade(B, k) + (255,))
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=9, fill=255)
    # Motivo de fondo (suave)
    pat = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pat)
    light = (255, 255, 255, 46)
    if pattern == 'ball':
        cx, cy, r = 196, 92, 74
        pd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=light, width=12)
        pd.rectangle([cx - r, cy - 6, cx + r, cy + 6], fill=light)
        pd.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=(0, 0, 0, 0), outline=light, width=10)
    elif pattern == 'stripes':
        for x0 in range(-H, W + H, 18):
            pd.polygon([(x0, H), (x0 + 8, H), (x0 + 8 + H, 0), (x0 + H, 0)], fill=(255, 255, 255, 30))
    else:
        for y in range(4, H, 8):
            for x in range(4 + (y // 8 % 2) * 4, W, 8):
                pd.rectangle([x, y, x + 1, y + 1], fill=(255, 255, 255, 40))
    body = Image.alpha_composite(body, pat)
    img.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=9, outline=edge + (255,), width=2)
    d.rounded_rectangle([2, 2, W - 3, H - 3], radius=8, outline=shade(B, 0.45) + (255,), width=1)
    # Franja de título con el corte en diagonal (estilo Negro/Blanco)
    band = shade(B, -0.42)
    d.polygon([(4, 5), (156, 5), (146, 21), (4, 21)], fill=band + (255,))
    d.line([(4, 22), (145, 22)], fill=shade(B, 0.5) + (255,))
    d.polygon([(160, 5), (241, 5), (241, 9), (157, 9)], fill=band + (255,))
    # Placas de nombre (clara) y número (oscura)
    d.rounded_rectangle(NAME_PLATE, radius=3, fill=(248, 248, 240, 235), outline=edge + (255,))
    d.rounded_rectangle(CODE_PLATE, radius=3, fill=shade(B, -0.5) + (255,), outline=edge + (255,))
    # Huecos del equipo (marco oscuro; dentro va el panel del Pokémon)
    for x, y in TEAM:
        # Hueco con marco de 1 px y sombra; entre hueco y hueco quedan 3 px libres.
        d.rectangle([x, y + 1, x + 51, y + 32], fill=shade(B, -0.5) + (150,))
        d.rectangle([x - 1, y - 1, x + 50, y + 30], fill=edge + (255,))
        d.rectangle([x, y, x + 49, y + 29], fill=(240, 244, 248, 255))
    # Zona del entrenador: foco en el suelo
    tx, ty = TRAINER
    d.ellipse([tx + 10, ty + 66, tx + 70, ty + 82], fill=shade(B, -0.3) + (140,))
    # Fila de medallas: banda oscura con 8 huecos redondos
    d.rounded_rectangle([8, 131, W - 9, 161], radius=6, fill=shade(B, -0.45) + (255,), outline=edge + (255,))
    for x, y in SOCKETS:
        d.ellipse([x, y, x + 19, y + 19], fill=shade(B, -0.65) + (255,))
        d.arc([x, y, x + 19, y + 19], 200, 340, fill=shade(B, -0.2) + (255,))
    return img


# ---------------- tarjetas al estilo de los juegos (3.ª, 4.ª y 5.ª gen) ----------------
# Mismas posiciones para las tres: datos a la izquierda (etiqueta + valor a la derecha),
# número de ID arriba a la derecha, entrenador a la derecha y fila de medallas abajo.
G_ROWS = [('NOMBRE', 'name', 30), ('DINERO', 'money', 48), ('POKEDEX', 'dex', 66),
          ('TIEMPO', 'time', 84), ('FASES', 'stages', 102)]
G_TRAINER = (158, 30)
G_ID = (160, 10)
RANKS = [('Azul', '#4c7cc4'), ('Bronce', '#b07444'), ('Cobre', '#c05c3c'), ('Plata', '#9ca4b4'), ('Oro', '#d0aa30')]


def game_card(gen, base):
    B = rgb(base)
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=8 if gen != 3 else 5, fill=255)
    body = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    edge = shade(B, -0.6)
    if gen == 3:
        # RSE: cuerpo liso del color del rango, cabecera más clara, borde grueso.
        d.rectangle([0, 0, W, H], fill=B + (255,))
        d.rectangle([0, 0, W, 22], fill=shade(B, 0.35) + (255,))
        d.line([(0, 22), (W, 22)], fill=shade(B, -0.35) + (255,), width=2)
        for i, (_, _, y) in enumerate(G_ROWS):
            d.rectangle([8, y - 3, 152, y + 11], fill=shade(B, 0.55 if i % 2 == 0 else 0.45) + (255,))
        d.rectangle([156, 26, W - 8, 114], fill=shade(B, 0.6) + (255,), outline=shade(B, -0.35) + (255,), width=2)
    elif gen == 4:
        # DPPt/HGSS: cara clara con rayas finas, barra de título oscura, filas con líneas.
        face = shade(B, 0.72)
        d.rectangle([0, 0, W, H], fill=face + (255,))
        for x0 in range(-H, W + H, 6):
            d.line([(x0, H), (x0 + H, 0)], fill=shade(B, 0.62) + (255,))
        d.rectangle([0, 0, W, 21], fill=shade(B, -0.25) + (255,))
        d.rectangle([0, 21, W, 23], fill=shade(B, -0.5) + (255,))
        for _, _, y in G_ROWS:
            d.line([(10, y + 12), (152, y + 12)], fill=shade(B, -0.2) + (255,))
        d.ellipse([G_TRAINER[0] + 8, G_TRAINER[1] + 66, G_TRAINER[0] + 72, G_TRAINER[1] + 82], fill=shade(B, 0.3) + (255,))
    else:
        # Negro/Blanco: fondo oscuro del color, pestaña de título redondeada y etiquetas de color.
        d.rectangle([0, 0, W, H], fill=shade(B, -0.45) + (255,))
        for y in range(0, H, 4):
            d.line([(0, y), (W, y)], fill=shade(B, -0.38) + (255,))
        d.rounded_rectangle([6, 4, 150, 20], radius=8, fill=shade(B, 0.15) + (255,), outline=shade(B, 0.5) + (255,))
        for _, _, y in G_ROWS:
            d.rounded_rectangle([8, y - 3, 152, y + 11], radius=6, fill=shade(B, -0.62) + (255,))
            d.rounded_rectangle([8, y - 3, 62, y + 11], radius=6, fill=shade(B, 0.1) + (255,))
        d.rounded_rectangle([156, 26, W - 8, 114], radius=8, fill=shade(B, -0.25) + (255,), outline=shade(B, 0.3) + (255,))
    img.paste(body, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=8 if gen != 3 else 5, outline=edge + (255,), width=2)
    # Fila de medallas (las Poké Balls del juego)
    strip = shade(B, -0.4) if gen != 4 else shade(B, -0.1)
    d.rounded_rectangle([8, 131, W - 9, 161], radius=6, fill=strip + (255,), outline=edge + (255,))
    for x, y in SOCKETS:
        d.ellipse([x, y, x + 19, y + 19], fill=shade(B, -0.62) + (255,))
    return img


# ---------------- paneles de Pokémon ----------------

def make_panel(sprite):
    panel = Image.new('RGBA', (50, 30), (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    for y in range(30):
        pd.line([(0, y), (49, y)], fill=shade((248, 250, 252), -0.12 * y / 30) + (255,))
    sp = sprite.crop(sprite.split()[3].getbbox())
    w, h = sp.size
    # Centrado; si es alto, se ve la parte de arriba (cabeza) como en las tarjetas clásicas.
    x = (50 - w) // 2
    y = (30 - h) // 2 if h <= 28 else 1
    panel.alpha_composite(sp, (max(-200, x), y)) if x >= 0 else panel.paste(sp, (x, y), sp)
    return panel


def pack(items, cw, ch, cols, rows, outdir):
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        os.remove(os.path.join(outdir, f))
    per = cols * rows
    where = {}
    for a in range((len(items) + per - 1) // per):
        atlas = Image.new('RGBA', (cols * cw, rows * ch), (0, 0, 0, 0))
        for k, (key, im) in enumerate(items[a * per:(a + 1) * per]):
            x, y = (k % cols) * cw, (k // cols) * ch
            atlas.paste(im, (x, y))
            where[key] = (a, x, y)
        atlas.save(os.path.join(outdir, '%d.png' % a), 'PNG', optimize=True)
    return where


def main():
    out = ['-- GENERADO por tools/gen_card_art.py: arte de la tarjeta de entrenador.',
           '-- cards: fondos propios (246x171) con sus posiciones; trainers: sprites oficiales',
           '-- (3.ª-5.ª gen, colección de Pokémon Showdown); panels[dex] = {atlas, x, y}: sprite',
           '-- oficial de Negro/Blanco en un panel de 50x30.',
           'local M = { cards = {}, trainers = {}, panels = {} }']

    # Fondos
    cdir = os.path.join(GAME, 'img', 'cards')
    os.makedirs(cdir, exist_ok=True)
    for f in os.listdir(cdir):
        os.remove(os.path.join(cdir, f))
    pk = ','.join('{%d,%d}' % p for p in TEAM)
    bd = ','.join('{%d,%d}' % (x + 2, y + 2) for x, y in SOCKETS)
    n = 0
    for pname, pat in PATTERNS:
        for cname, col in COLORS:
            n += 1
            card_background(col, pat).save(os.path.join(cdir, '%d.png' % n), 'PNG', optimize=True)
            dark = sum(rgb(col)) < 300
            out.append('M.cards[#M.cards + 1] = { id = %d, cat = "%s · %s", name = {%d,%d}, code = {%d,%d}, '
                       'trainer = {%d,%d}, nameColor = "#303030", codeColor = "#ffffff", titleColor = "%s", '
                       'pokemon = {%s}, badges = {%s} }'
                       % (n, cname, pname, NAME_PLATE[0] + 5, NAME_PLATE[1] + 6, CODE_PLATE[0] + 5, CODE_PLATE[1] + 6,
                          TRAINER[0], TRAINER[1], '#ffffff' if dark or True else '#303030', pk, bd))
    # Tarjetas al estilo de los juegos
    rows = ','.join('{"%s","%s",%d}' % r for r in G_ROWS)
    for gen, gname in ((3, 'Tarjeta 3.ª gen'), (4, 'Tarjeta 4.ª gen'), (5, 'Tarjeta 5.ª gen')):
        for rname, col in RANKS:
            n += 1
            game_card(gen, col).save(os.path.join(cdir, '%d.png' % n), 'PNG', optimize=True)
            # Texto: oscuro sobre las claras (3.ª y 4.ª), claro sobre la oscura (5.ª).
            ink = '#ffffff' if gen == 5 else '#303030'
            lab = '#ffffff' if gen == 5 else shade_hex(col, -0.45)
            out.append('M.cards[#M.cards + 1] = { id = %d, layout = "game", gen = %d, cat = "%s · %s", '
                       'title = {12,9}, titleColor = "%s", code = {%d,%d}, codeColor = "%s", trainer = {%d,%d}, '
                       'rows = {%s}, labelX = 14, valueX = 148, labelColor = "%s", valueColor = "%s", badges = {%s} }'
                       % (n, gen, gname, rname, '#303030' if gen == 3 else '#ffffff', G_ID[0], G_ID[1],
                          '#303030' if gen == 3 else '#ffffff', G_TRAINER[0], G_TRAINER[1], rows,
                          lab, ink, bd))
    print('fondos:', n)

    # Entrenadores
    names = [l.strip() for l in open(TRAINER_LIST, encoding='utf-8') if l.strip()]
    names = [x for x in names if not (x in GEN3_CLASSIC)]
    order = [x for x in FIRST if x in names] + sorted(x for x in names if x not in FIRST)
    with ThreadPoolExecutor(12) as ex:
        paths = list(ex.map(lambda nm: fetch(TRAINER_URL % nm, os.path.join(CACHE, 'trainers', nm + '.png')), order))
    items, meta = [], []
    for nm, p in zip(order, paths):
        if not p:
            continue
        im = Image.open(p).convert('RGBA')
        if im.size != (80, 80):
            continue
        g = 'Gen 3' if '-gen3' in nm else ('Gen 5' if '-gen5' in nm else ('Gen 4' if '-gen4' in nm or nm in GEN4 else 'Gen 5'))
        items.append((nm, im))
        meta.append((nm, g))
    where = pack(items, 80, 80, 6, 6, os.path.join(GAME, 'img', 'trainers'))
    for i, (nm, g) in enumerate(meta, 1):
        a, x, y = where[nm]
        out.append('M.trainers[#M.trainers + 1] = { id = %d, name = "%s", cat = "%s", atlas = %d, x = %d, y = %d }' % (i, nm, g, a, x, y))
    print('entrenadores:', len(meta))

    # Paneles (Negro/Blanco)
    dexes = list(range(1, 650))
    with ThreadPoolExecutor(12) as ex:
        paths = list(ex.map(lambda d: fetch(BW_URL % d, os.path.join(CACHE, 'bw', '%d.png' % d)), dexes))
    items = []
    for d, p in zip(dexes, paths):
        if p:
            items.append((d, make_panel(Image.open(p).convert('RGBA'))))
    where = pack(items, 50, 30, 10, 17, os.path.join(GAME, 'img', 'panels'))
    for d, _ in items:
        a, x, y = where[d]
        out.append('M.panels[%d] = {%d,%d,%d}' % (d, a, x, y))
    print('paneles:', len(items))

    out.append('return M')
    with open(os.path.join(GAME, 'data', 'cardstyle.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
