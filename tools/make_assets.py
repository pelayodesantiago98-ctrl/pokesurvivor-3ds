"""Genera los assets de empaquetado si no existen:
  assets/icon.png    48x48  (icono del menú HOME / SMDH)
  assets/banner.png  256x128 (banner del CIA)
  assets/banner.wav  sonido corto del banner
Sin dependencias externas (PNG escrito a mano con zlib)."""
import os
import struct
import sys
import wave
import zlib
import math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")


def write_png(path, width, height, pixel):
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filtro None
        for x in range(width):
            r, g, b, a = pixel(x, y)
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def icon_pixel(x, y):
    # Pokébola simplificada: círculo rojo/blanco con franja negra.
    cx, cy, r = 23.5, 23.5, 22
    d = math.hypot(x - cx, y - cy)
    if d > r:
        return (0, 0, 0, 0)
    if d > r - 2:
        return (20, 20, 20, 255)
    if abs(y - cy) < 2.5:
        return (20, 20, 20, 255)
    if d < 6:
        return (20, 20, 20, 255) if d > 4 else (245, 245, 245, 255)
    if y < cy:
        return (220, 50, 50, 255)
    return (245, 245, 245, 255)


def banner_pixel(x, y):
    # Degradado oscuro con una pokébola grande a la izquierda.
    base = (int(20 + 40 * y / 128), int(30 + 30 * y / 128), int(50 + 60 * y / 128), 255)
    cx, cy, r = 64, 64, 48
    d = math.hypot(x - cx, y - cy)
    if d <= r:
        if d > r - 3 or abs(y - cy) < 4:
            return (20, 20, 20, 255)
        if d < 12:
            return (20, 20, 20, 255) if d > 8 else (245, 245, 245, 255)
        return (220, 50, 50, 255) if y < cy else (245, 245, 245, 255)
    return base


def write_wav(path):
    rate = 32000
    frames = bytearray()
    for i in range(int(rate * 0.6)):
        t = i / rate
        env = max(0.0, 1.0 - t / 0.6)
        v = 0.4 * env * (math.sin(2 * math.pi * 660 * t) + 0.5 * math.sin(2 * math.pi * 990 * t))
        frames += struct.pack("<h", int(v * 32767))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


def main():
    os.makedirs(ASSETS, exist_ok=True)
    icon = os.path.join(ASSETS, "icon.png")
    banner = os.path.join(ASSETS, "banner.png")
    sound = os.path.join(ASSETS, "banner.wav")
    if not os.path.exists(icon):
        write_png(icon, 48, 48, icon_pixel)
        print("creado", icon)
    if not os.path.exists(banner):
        write_png(banner, 256, 128, banner_pixel)
        print("creado", banner)
    if not os.path.exists(sound):
        write_wav(sound)
        print("creado", sound)
    return 0


if __name__ == "__main__":
    sys.exit(main())
