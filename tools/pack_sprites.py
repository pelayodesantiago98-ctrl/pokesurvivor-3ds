#!/usr/bin/env python3
"""
Reempaqueta los sprites de SpriteCollab (procesados por el repo de PokéSurvivor)
en un atlas por Pokémon para la 3DS, y genera los datos Lua.

Por qué: LÖVE Potion en 3DS solo acepta texturas RGBA8 (4 bytes/píxel) de hasta
1024x1024, y la consola tiene ~64 MB. Las hojas originales (8 filas de dirección,
una por animación) desperdician mucho. Aquí:
  - solo se guardan 5 direcciones (Down, DownRight, Right, UpRight, Up); las tres
    izquierdas se dibujan volteadas en el juego;
  - todas las animaciones elegidas van en UN atlas potencia de dos lo más pequeño
    posible (empaquetado por estantes);
  - dos atlas por Pokémon: <dex>.png (Idle + Walk: enemigos) y <dex>_f.png (las 7
    animaciones: compañero del jugador), este último solo para los dex de --full.

Uso:
  python tools/pack_sprites.py <repo> [--full 1,4,7,...] [--only 1-151] [--full-all]

Salida (en game/):
  img/pkmn/<dex>.png, img/pkmn/<dex>_f.png
  data/pkmn/<dex>.lua    geometría + cuadros (uno por dex, se carga bajo demanda)
  data/dexmeta.lua       índice pequeño para todos: s, hv, sh, iw, iay, full
"""
import json
import os
import re
import sys

from PIL import Image

ROWS = 5
ENEMY_ANIMS = ['Idle', 'Walk']
FULL_ANIMS = ['Idle', 'Walk', 'Attack', 'Shoot', 'Charge', 'Hurt', 'Faint']
MAX_TEX = 1024

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')


def parse_meta(path):
    """sprites-meta.js -> {dex: meta}"""
    out = {}
    rx = re.compile(r'^\s*(\d+):\s*(\{.*\}),?\s*$')
    with open(path, encoding='utf-8') as f:
        for line in f:
            m = rx.match(line)
            if m:
                out[int(m.group(1))] = json.loads(m.group(2))
    return out


def crop_frames(sheet, a):
    """Lista de (row, i, imagen recortada, ox, oy) para las 5 filas. Cada
    fotograma se recorta a su caja opaca; (ox, oy) es dónde empieza esa caja
    dentro del fotograma original (para corregir el ancla al dibujar)."""
    w, h, n = a['w'], a['h'], a['n']
    rows = min(ROWS, a['r'])
    frames = []
    for row in range(rows):
        for i in range(n):
            box = (i * w, row * h, (i + 1) * w, (row + 1) * h)
            img = sheet.crop(box)
            bb = img.split()[3].getbbox()
            if not bb:
                bb = (0, 0, 1, 1)
            frames.append((row, i, img.crop(bb), bb[0], bb[1]))
    return frames, rows


def pack(items):
    """Empaquetado por estantes en el lienzo potencia de 2 más pequeño.
    items: lista de (key, w, h). Devuelve (W, H, {key: (x, y)}) o None."""
    items = sorted(items, key=lambda it: (-it[2], -it[1]))
    area = sum(w * h for _, w, h in items)
    size = 32
    while size * size < area:
        size *= 2
    while size <= MAX_TEX:
        # Primero los rectángulos (la mitad de memoria), luego el cuadrado.
        for W, H in ((size, size // 2), (size // 2, size), (size, size)):
            if W < 8 or H < 8 or W * H < area:
                continue
            pos = try_pack(items, W, H)
            if pos:
                return W, H, pos
        size *= 2
    return None


def try_pack(items, W, H):
    pos = {}
    x = y = 0
    shelf_h = 0
    for key, w, h in items:
        if w > W:
            return None
        if x + w > W:
            x = 0
            y += shelf_h
            shelf_h = 0
        if y + h > H:
            return None
        pos[key] = (x, y)
        x += w
        shelf_h = max(shelf_h, h)
    return pos


def build_atlas(dex, meta, src_dir, anims):
    """Devuelve (imagen, datos_lua) o None si falta algo esencial."""
    items = []
    frames = {}
    info = {}
    for name in anims:
        a = meta['a'].get(name)
        path = os.path.join(src_dir, name + '.png')
        if not a or not os.path.exists(path):
            continue
        sheet = Image.open(path).convert('RGBA')
        fr, rows = crop_frames(sheet, a)
        info[name] = {'w': a['w'], 'h': a['h'], 'n': a['n'], 'd': a['d'], 'ax': a['ax'], 'ay': a['ay'], 'rows': rows}
        for row, i, img, ox, oy in fr:
            key = (name, row, i)
            frames[key] = (img, ox, oy)
            items.append((key, img.width, img.height))
    if 'Idle' not in info and 'Walk' not in info:
        return None
    packed = pack(items)
    if not packed:
        return None
    W, H, pos = packed
    atlas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for key, (img, ox, oy) in frames.items():
        atlas.paste(img, pos[key])
    # Cuadros por animación, orden fila-mayor, 6 números por fotograma:
    # x, y, w, h del recorte en el atlas y ox, oy del recorte dentro del fotograma.
    for name, a in info.items():
        q = []
        for row in range(a['rows']):
            for i in range(a['n']):
                x, y = pos[(name, row, i)]
                img, ox, oy = frames[(name, row, i)]
                q.extend((x, y, img.width, img.height, ox, oy))
        a['q'] = q
    return atlas, info, (W, H)


def lua_anim(name, a):
    d = ','.join(str(v) for v in a['d'])
    q = ','.join(str(v) for v in a['q'])
    return ('  %s={w=%d,h=%d,n=%d,rows=%d,ax=%s,ay=%s,d={%s},q={%s}},\n'
            % (name, a['w'], a['h'], a['n'], a['rows'], a['ax'], a['ay'], d, q))


def save_png(img, path):
    # Paleta exacta si cabe: mismo dibujo, mucho menos peso en disco.
    cols = img.getcolors(256)
    if cols is None:
        img.save(path, 'PNG', optimize=True)
        return
    img.save(path, 'PNG', optimize=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    repo = sys.argv[1]
    full = set()
    only = None
    full_all = False
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == '--full':
            full = set(int(v) for v in args[i + 1].split(','))
            i += 2
        elif args[i] == '--only':
            lo, hi = args[i + 1].split('-')
            only = (int(lo), int(hi))
            i += 2
        elif args[i] == '--full-all':
            full_all = True
            i += 1
        else:
            i += 1

    metas = parse_meta(os.path.join(repo, 'js', 'data', 'sprites-meta.js'))
    out_img = os.path.join(GAME, 'img', 'pkmn')
    out_data = os.path.join(GAME, 'data', 'pkmn')
    os.makedirs(out_img, exist_ok=True)
    os.makedirs(out_data, exist_ok=True)

    index = {}
    sizes = {'e': {}, 'f': {}, 's': {}}
    done = 0
    for dex in sorted(metas):
        if only and not (only[0] <= dex <= only[1]):
            continue
        meta = metas[dex]
        src = os.path.join(repo, 'assets', 'pokemon', str(dex))
        if not os.path.isdir(src):
            continue
        res = build_atlas(dex, meta, src, ENEMY_ANIMS)
        if not res:
            print('  ! sin Idle/Walk:', dex)
            continue
        atlas, info, (W, H) = res
        save_png(atlas, os.path.join(out_img, '%d.png' % dex))
        sizes['e'][(W, H)] = sizes['e'].get((W, H), 0) + 1

        has_full = False
        finfo = None
        if full_all or dex in full:
            resf = build_atlas(dex, meta, src, FULL_ANIMS)
            if resf:
                fatlas, finfo, (FW, FH) = resf
                save_png(fatlas, os.path.join(out_img, '%d_f.png' % dex))
                sizes['f'][(FW, FH)] = sizes['f'].get((FW, FH), 0) + 1
                has_full = True

        # Shiny (Idle + Walk) desde assets/pokemon/<dex>/s/, con su geometría propia si
        # difiere (meta['sa']) y las animaciones que le falten (meta['sm']) omitidas.
        has_shiny = False
        sinfo = None
        sdir = os.path.join(src, 's')
        if meta.get('sh') and os.path.isdir(sdir):
            smeta = {'a': dict(meta['a'])}
            for k, v in (meta.get('sa') or {}).items():
                smeta['a'][k] = v
            for k in (meta.get('sm') or []):
                smeta['a'].pop(k, None)
            ress = build_atlas(dex, smeta, sdir, ENEMY_ANIMS)
            if ress:
                satlas, sinfo, (SW, SH) = ress
                save_png(satlas, os.path.join(out_img, '%d_s.png' % dex))
                sizes['s'][(SW, SH)] = sizes['s'].get((SW, SH), 0) + 1
                has_shiny = True

        idle = info.get('Idle') or info.get('Walk')
        with open(os.path.join(out_data, '%d.lua' % dex), 'w', encoding='utf-8', newline='\n') as f:
            f.write('-- GENERADO por tools/pack_sprites.py. dex %d\n' % dex)
            f.write('return {\n s=%d, hv=%s, sh=%s,\n' % (meta.get('s', 1), 'true' if meta.get('hv') else 'false',
                                                         'true' if meta.get('sh') else 'false'))
            f.write(' enemy={ atlas="img/pkmn/%d", w=%d, h=%d, anims={\n' % (dex, W, H))
            for name, a in info.items():
                f.write(lua_anim(name, a))
            f.write(' }},\n')
            if has_full:
                f.write(' full={ atlas="img/pkmn/%d_f", w=%d, h=%d, anims={\n' % (dex, FW, FH))
                for name, a in finfo.items():
                    f.write(lua_anim(name, a))
                f.write(' }},\n')
            if has_shiny:
                f.write(' shiny={ atlas="img/pkmn/%d_s", w=%d, h=%d, anims={\n' % (dex, SW, SH))
                for name, a in sinfo.items():
                    f.write(lua_anim(name, a))
                f.write(' }},\n')
            f.write('}\n')
        index[dex] = (meta.get('s', 1), 1 if meta.get('hv') else 0, 1 if has_shiny else 0,
                      idle['w'], idle['ay'], 1 if has_full else 0)
        done += 1
        if done % 100 == 0:
            print('  %d...' % done, flush=True)

    with open(os.path.join(GAME, 'data', 'dexmeta.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('-- GENERADO por tools/pack_sprites.py: índice de sprites por dex.\n')
        f.write('-- s = ShadowSize · hv = flota · sh = hay atlas shiny (<dex>_s) · iw/iay = ancho y ancla Y de Idle · full = atlas completo\n')
        f.write('local M = {}\n')
        for dex in sorted(index):
            s, hv, sh, iw, iay, fu = index[dex]
            f.write('M[%d]={s=%d,hv=%s,sh=%s,iw=%d,iay=%s,full=%s}\n'
                    % (dex, s, 'true' if hv else 'false', 'true' if sh else 'false', iw, iay, 'true' if fu else 'false'))
        f.write('return M\n')

    print('%d Pokémon empaquetados' % done)
    for kind, label in (('e', 'enemigo (Idle+Walk)'), ('f', 'completo'), ('s', 'shiny (Idle+Walk)')):
        if sizes[kind]:
            print(' atlas %s:' % label)
            for (W, H), n in sorted(sizes[kind].items()):
                print('   %4dx%-4d  %d  (%d KB RGBA8 en memoria)' % (W, H, n, W * H * 4 // 1024))


if __name__ == '__main__':
    main()
