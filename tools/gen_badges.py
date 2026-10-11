#!/usr/bin/env python3
"""
Las 8 "medallas" de la tarjeta de entrenador: Poké Balls de distintos colores
(sprites de mochila de PokeAPI/sprites, como los demás objetos). La i-ésima se
desbloquea al tener ceil(i * total / 8) medallas (logros) del juego.

    python tools/gen_badges.py
Salida: game/img/badges/<1..8>.png (recortadas a su caja opaca).
"""
import io
import os
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), 'game', 'img', 'badges')
URL = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/%s.png'
BALLS = ['poke-ball', 'great-ball', 'ultra-ball', 'safari-ball', 'dive-ball', 'luxury-ball', 'premier-ball', 'master-ball']


def main():
    os.makedirs(OUT, exist_ok=True)
    for i, name in enumerate(BALLS, 1):
        with urllib.request.urlopen(urllib.request.Request(URL % name, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30) as r:
            im = Image.open(io.BytesIO(r.read())).convert('RGBA')
        im = im.crop(im.split()[3].getbbox())
        im.save(os.path.join(OUT, '%d.png' % i), 'PNG', optimize=True)
        print(i, name, im.size)


if __name__ == '__main__':
    main()
