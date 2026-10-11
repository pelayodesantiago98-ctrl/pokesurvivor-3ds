#!/usr/bin/env python3
"""
Iconos del menú principal (sprites de mochila de PokeAPI/sprites, como los objetos).

    python tools/gen_menu_icons.py
Salida: game/img/menu/<id>.png recortados a su caja opaca.
"""
import io
import os
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'game', 'img', 'menu')
URL = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/%s.png'
ICONS = {'play': 'poke-ball', 'stages': 'town-map', 'upgrades': 'protein', 'gacha': 'coin-case',
         'goals': 'journal', 'card': 'member-card', 'starters': 'mystery-egg'}


def pokedex_icon():
    """Pokédex clásica en pixel art (20x22): carcasa roja, lente azul, tres luces y pantalla."""
    from PIL import ImageDraw
    im = Image.new('RGBA', (20, 22), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    edge = (88, 16, 24, 255)
    d.rounded_rectangle([0, 0, 19, 21], radius=3, fill=(224, 56, 56, 255), outline=edge)
    d.rectangle([1, 1, 18, 6], fill=(240, 96, 88, 255))                 # brillo de arriba
    d.line([(1, 7), (18, 7)], fill=edge)                                # bisagra
    d.ellipse([2, 1, 8, 6], fill=(255, 255, 255, 255), outline=edge)    # lente
    d.ellipse([3, 2, 7, 5], fill=(56, 160, 248, 255))
    d.point((4, 2), fill=(200, 236, 255, 255))
    for x, c in ((11, (248, 72, 72)), (14, (248, 216, 64)), (17, (88, 208, 96))):
        d.rectangle([x - 1, 2, x, 3], fill=c + (255,))                  # luces
    d.rectangle([3, 10, 16, 17], fill=(232, 240, 232, 255), outline=edge)   # pantalla
    d.line([(5, 12), (13, 12)], fill=(120, 168, 120, 255))
    d.line([(5, 14), (11, 14)], fill=(120, 168, 120, 255))
    d.rectangle([4, 19, 7, 19], fill=(150, 30, 36, 255))                # botones
    d.rectangle([12, 19, 15, 19], fill=(150, 30, 36, 255))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    pokedex_icon().save(os.path.join(OUT, 'dex.png'), 'PNG', optimize=True)
    for key, item in ICONS.items():
        with urllib.request.urlopen(urllib.request.Request(URL % item, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30) as r:
            im = Image.open(io.BytesIO(r.read())).convert('RGBA')
        im = im.crop(im.split()[3].getbbox())
        im.save(os.path.join(OUT, key + '.png'), 'PNG', optimize=True)
        print(key, item, im.size)


if __name__ == '__main__':
    main()
