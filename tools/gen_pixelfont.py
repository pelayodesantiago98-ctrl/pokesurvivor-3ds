# gen_pixelfont.py — atlas de la fuente pixelada (game/img/pixelfont.png +
# game/data/pixelfont.lua) a partir de los glifos de game/src/ui/pixelfont.lua.
# Antes cada píxel de cada letra era un rectángulo: el cuestionario pasaba de 14.000
# por fotograma y la 3DS se cerraba. Con el atlas cada letra es una sola imagen, y la
# sombra y el contorno van ya hechos (2 dibujos por letra en vez de 4 o 9).
#   Para cada escala (1, 1.5 -> "15", 2) y cada glifo:
#     b  la letra            (en su sitio)
#     s  su sombra           (la letra desplazada +1,0 / 0,+1 / +1,+1 píxel de pantalla)
#     o  su contorno         (desplazada en las 8 direcciones; empieza en -1,-1)
import re, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, "game", "src", "ui", "pixelfont.lua"), encoding="utf-8").read()
block = src[src.index("local GLYPHS = {"):src.index("\n}\n", src.index("local GLYPHS = {"))]
glyphs = {}
for m in re.finditer(r'^\s*(?:(\w)|\["(.+?)"\])\s*=\s*\{([^}]*)\}', block, re.M):
    key = m.group(1) or m.group(2)
    rows = re.findall(r'"([.#]+)"', m.group(3))
    assert len(rows) == 7, key
    glyphs[key] = rows

MID_ROWS = [2, 1, 1, 2, 1, 1, 2]
def mid_cols(w):
    mid = w // 2 + 1
    return [2 if (c == 1 or c == w or c == mid) else 1 for c in range(1, w + 1)]

def mask(rows, scale):
    """Conjunto de píxeles de pantalla encendidos de la letra a esa escala."""
    w = len(rows[0])
    if scale == "15":
        cw, rh = mid_cols(w), MID_ROWS
    else:
        s = int(scale)
        cw, rh = [s] * w, [s] * 7
    on = set()
    yy = 0
    for r in range(7):
        xx = 0
        for c in range(w):
            if rows[r][c] == "#":
                for dy in range(rh[r]):
                    for dx in range(cw[c]):
                        on.add((xx + dx, yy + dy))
            xx += cw[c]
        yy += rh[r]
    return on, sum(cw), sum(rh)

def image(px, w, h, ox=0, oy=0):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for (x, y) in px:
        im.putpixel((x + ox, y + oy), (255, 255, 255, 255))
    return im

pieces = []
for key in sorted(glyphs):
    for scale in ("1", "15", "2"):
        on, w, h = mask(glyphs[key], scale)
        pieces.append((scale + "b", key, image(on, w, h)))
        sh = set()
        for dx, dy in ((1, 0), (0, 1), (1, 1)):
            sh |= {(x + dx, y + dy) for (x, y) in on}
        pieces.append((scale + "s", key, image(sh, w + 1, h + 1)))
        ol = set()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx or dy:
                    ol |= {(x + dx, y + dy) for (x, y) in on}
        pieces.append((scale + "o", key, image(ol, w + 2, h + 2, 1, 1)))

AW = 512
x, y, rowh, place = 1, 1, 0, []
for kind, key, im in pieces:
    if x + im.width + 1 > AW:
        x, y, rowh = 1, y + rowh + 1, 0
    place.append((kind, key, x, y, im))
    x += im.width + 1
    rowh = max(rowh, im.height)
H = 1
while H < y + rowh + 1:
    H *= 2
assert H <= 1024, H
atlas = Image.new("RGBA", (AW, H), (0, 0, 0, 0))
for kind, key, px, py, im in place:
    atlas.paste(im, (px, py))
atlas.save(os.path.join(ROOT, "game", "img", "pixelfont.png"))

def lstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'
kinds = []
for k, *_ in place:
    if k not in kinds:
        kinds.append(k)
out = ["-- Generado por tools/gen_pixelfont.py: no editar a mano.",
       "-- [escala .. capa][glifo] = { x, y, w, h }; escala 1/15/2, capa b (letra), s (sombra), o (contorno).",
       "return { w = %d, h = %d," % (AW, H)]
for kind in kinds:
    out.append('  ["%s"] = {' % kind)
    for k, key, px, py, im in place:
        if k == kind:
            out.append("    [%s] = { %d, %d, %d, %d }," % (lstr(key), px, py, im.width, im.height))
    out.append("  },")
out.append("}")
open(os.path.join(ROOT, "game", "data", "pixelfont.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("glifos:", len(glyphs), "atlas:", AW, "x", H)

# ---- Estilos ya coloreados (game/img/pixelfont_st.png + game/data/pixelfont_st.lua) ----
# Para el HUD de la partida: cada letra ya lleva su color y su sombra (un solo dibujo
# por letra, y todas las de un texto en un SpriteBatch, que en la 3DS no se puede
# teñir). Mismo tamaño de caja que la capa "s" (w+1, h+1); la letra en (0, 0).
#   nombre: (escala, color, sombra) — los mismos de los estilos de src/ui/run.lua
STYLES = {
    "box":   ("2",  "#383838", "#b8b8b0"),
    "stats": ("1",  "#e8e4ff", "#3a3458"),
    "name":  ("15", "#403f30", "#fbf6f0"),
    "burst": ("1",  "#ffffff", "#2a2440"),
}
def rgba(h):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), 255)
spieces = []
for st in sorted(STYLES):
    scale, col, shcol = STYLES[st]
    for key in sorted(glyphs):
        on, w, h = mask(glyphs[key], scale)
        im = Image.new("RGBA", (w + 1, h + 1), (0, 0, 0, 0))
        for dx, dy in ((1, 0), (0, 1), (1, 1)):
            for (x0, y0) in on:
                im.putpixel((x0 + dx, y0 + dy), rgba(shcol))
        for (x0, y0) in on:
            im.putpixel((x0, y0), rgba(col))
        spieces.append((st, key, im))
x, y, rowh, splace = 1, 1, 0, []
for st, key, im in spieces:
    if x + im.width + 1 > AW:
        x, y, rowh = 1, y + rowh + 1, 0
    splace.append((st, key, x, y, im))
    x += im.width + 1
    rowh = max(rowh, im.height)
SH = 1
while SH < y + rowh + 1:
    SH *= 2
assert SH <= 1024, SH
satlas = Image.new("RGBA", (AW, SH), (0, 0, 0, 0))
for st, key, px, py, im in splace:
    satlas.paste(im, (px, py))
satlas.save(os.path.join(ROOT, "game", "img", "pixelfont_st.png"))
out = ["-- Generado por tools/gen_pixelfont.py: no editar a mano.",
       "-- [estilo][glifo] = { x, y, w, h }: letra con su color y su sombra ya pintados.",
       "return { w = %d, h = %d," % (AW, SH)]
for st in sorted(STYLES):
    out.append('  ["%s"] = {' % st)
    for s2, key, px, py, im in splace:
        if s2 == st:
            out.append("    [%s] = { %d, %d, %d, %d }," % (lstr(key), px, py, im.width, im.height))
    out.append("  },")
out.append("}")
open(os.path.join(ROOT, "game", "data", "pixelfont_st.lua"), "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
print("estilos:", len(STYLES), "atlas:", AW, "x", SH)
