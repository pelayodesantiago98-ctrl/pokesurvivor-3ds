# -*- coding: utf-8 -*-
"""gen_audio.py — pre-renderiza la música y los efectos de sonido del juego.

En la web (js/core/audio.js) todo el sonido se sintetiza en el momento con
Web Audio. La 3DS no tiene sintetizador en tiempo real, así que este script
porta ese sintetizador (instrumentos, secuenciador de js/data/music.js, mezcla,
reverberación por convolución y compresor) y escribe ficheros WAV:

    game/music/<tema>.wav   village, forest, cave, volcano, boss, rift
                            (un bucle completo de la partitura; la cola de las
                            últimas notas se pliega al principio para que
                            repita sin corte)
    game/sfx/<nombre>.wav   cada efecto de SFX; los que dependen de parámetros
                            se desglosan en variantes:
                              shot_<kind>_<0|1|2>   kind = projectile, beam,
                                                    orbit, aura, buff; 0/1/2 =
                                                    tono bajo/medio/alto (según
                                                    el tipo del ataque)
                              shot_melee, shot_nova (no dependen del tipo)
                              shot_projectile_fire / _electric (llevan un
                                                    siseo extra en la web)
                              xp_<0..24>            combo de experiencia
                              burst_<1..5>, reveal_<1..5>   rareza del gacha

Formato: 22050 Hz, mono, 16 bits. Usa numpy (comprobado: está instalado).

Uso:
    "C:\\Program Files\\Python314\\python.exe" tools\\gen_audio.py [--only music|sfx]

Mapeo tipo -> tono de `shot` (SHOT_PITCH de audio.js, en Hz):
    bajo  (0): ground 240, rock 260, dragon 300, dark 330, ghost 350, poison 400, fighting 450
    medio (1): fire 520, normal 600, grass 640, water 700, steel 750, psychic 800
    alto  (2): flying 820, ice 900, bug 980, electric 1100, fairy 1200
Las variantes se renderizan a 330 / 640 / 1000 Hz. src/audio.lua tiene la
misma tabla (SHOT_BUCKET).
"""
import math
import os
import re
import sys
import time
import wave

import numpy as np

SR = 22050                # frecuencia de muestreo de salida
NYQ = SR / 2.0
MAX_HARM = 40             # armónicos máximos de los osciladores aditivos
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_MUSIC = os.path.join(ROOT, "game", "music")
OUT_SFX = os.path.join(ROOT, "game", "sfx")

# Volúmenes de la web (settings por defecto): musicBus = 0.55*0.7, sfxBus = 0.7*2.4.
MUSIC_BUS = 0.55 * 0.7
SFX_BUS = 0.7 * 2.4
WET = 0.3                 # ganancia del retorno de reverb (va al bus de música)
OUT_GAIN = 0.9            # ganancia de salida tras el compresor
# Desviación respecto a la web: con los niveles originales la música picaba a
# ~0,35 y los efectos a ~0,08 (bajísimo para el altavoz de la 3DS). Se sube
# todo ×2 ANTES del compresor (misma ganancia para música y efectos, así se
# conserva el balance entre ellos) y se limita suavemente al final.
PRE_GAIN = 2.0
MAX_LOOP_S = 75.0         # tope de duración de un tema

rng = np.random.default_rng(20261011)


# ============================================================ piezas básicas

def osc(wave_type, freq, n):
    """Oscilador con frecuencia constante o por muestra (array de n).
    square/sawtooth son aditivos (sin aliasing) como los de Web Audio."""
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    ph = 2.0 * math.pi * np.cumsum(f) / SR
    if wave_type == "sine":
        return np.sin(ph)
    if wave_type == "triangle":
        x = (ph / (2.0 * math.pi) + 0.25) % 1.0
        return 1.0 - 4.0 * np.abs(x - 0.5)
    fmax = float(f.max())
    kmax = max(1, min(MAX_HARM, int(NYQ / max(fmax, 1.0))))
    out = np.zeros(n)
    if wave_type == "square":
        for k in range(1, kmax + 1, 2):
            out += np.sin(k * ph) / k
        return out * (4.0 / math.pi)
    if wave_type == "sawtooth":
        for k in range(1, kmax + 1):
            out += np.sin(k * ph) * ((1.0 if k % 2 == 1 else -1.0) / k)
        return out * (2.0 / math.pi)
    raise ValueError(wave_type)


def noise(n):
    return rng.uniform(-1.0, 1.0, n)


def automation(points, n):
    """Curva de automatización de Web Audio: lista de (tiempo, modo, valor) con
    modo 'set' (setValueAtTime), 'lin' (linearRamp) o 'exp' (exponentialRamp).
    Tras el último punto se mantiene el valor."""
    t = np.arange(n) / SR
    env = np.empty(n)
    env[:] = points[-1][2]
    for i in range(len(points) - 1):
        t0, _, v0 = points[i]
        t1, mode, v1 = points[i + 1]
        if t1 <= t0:
            continue
        m = (t >= t0) & (t < t1)
        u = (t[m] - t0) / (t1 - t0)
        if mode == "lin":
            env[m] = v0 + (v1 - v0) * u
        elif mode == "exp":
            v0 = max(v0, 1e-6)
            env[m] = v0 * (v1 / v0) ** u
        else:
            env[m] = v1
    env[t < points[0][0]] = points[0][2]
    return env


def exp_ramp(v0, v1, dur, n):
    """Parámetro que va exponencialmente de v0 a v1 en dur segundos y se queda."""
    t = np.arange(n) / SR
    u = np.clip(t / dur, 0.0, 1.0)
    return v0 * (v1 / v0) ** u


def gain_env(n, a, peak, dur, rel, sus=0.7):
    """Port de gainEnv(): ataque lineal, caída exponencial al sustain
    (setTargetAtTime) y liberación exponencial a partir de dur."""
    t = np.arange(n) / SR
    tau1 = max(0.02, dur * 0.4)
    tau2 = rel / 3.0
    env = np.empty(n)
    d = max(dur, a)
    m1 = t < a
    env[m1] = 0.0001 + (peak - 0.0001) * t[m1] / a
    m2 = (t >= a) & (t < d)
    env[m2] = peak * sus + (peak - peak * sus) * np.exp(-(t[m2] - a) / tau1)
    vd = peak * sus + (peak - peak * sus) * math.exp(-(d - a) / tau1)
    m3 = t >= d
    env[m3] = 0.0001 + (vd - 0.0001) * np.exp(-(t[m3] - d) / tau2)
    return env


def biquad_coefs(kind, f, q):
    """Coeficientes de BiquadFilterNode (lowpass/highpass: Q en dB)."""
    f = min(max(f, 10.0), NYQ * 0.995)
    w = 2.0 * math.pi * f / SR
    c, s = math.cos(w), math.sin(w)
    if kind in ("lowpass", "highpass"):
        alpha = s / (2.0 * 10.0 ** (q / 20.0))
    else:
        alpha = s / (2.0 * q)
    if kind == "lowpass":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == "highpass":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    elif kind == "bandpass":
        b0, b1, b2 = alpha, 0.0, -alpha
    else:
        raise ValueError(kind)
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0


def biquad(x, kind, f, q):
    """Filtro de coeficientes constantes. Solo procesa hasta la última muestra
    no nula (+ un margen para la cola)."""
    nz = np.flatnonzero(x)
    if len(nz) == 0:
        return np.zeros_like(x)
    end = min(len(x), int(nz[-1]) + 1 + SR // 8)
    b0, b1, b2, a1, a2 = biquad_coefs(kind, f, q)
    src = x[:end].tolist()
    y = [0.0] * end
    x1 = x2 = y1 = y2 = 0.0
    for i in range(end):
        xi = src[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = xi; y2 = y1; y1 = yi
        y[i] = yi
    out = np.zeros_like(x)
    out[:end] = y
    return out


def biquad_var(x, kind, freqs, q, block=16):
    """Filtro con frecuencia de corte variable (array por muestra); los
    coeficientes se recalculan cada `block` muestras."""
    n = len(x)
    src = x.tolist()
    fl = np.asarray(freqs, dtype=np.float64)
    y = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for start in range(0, n, block):
        b0, b1, b2, a1, a2 = biquad_coefs(kind, float(fl[start]), q)
        for i in range(start, min(n, start + block)):
            xi = src[i]
            yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            y[i] = yi
    return np.array(y)


# ------------------------------------------------------------ reverb

def make_ir():
    """Respuesta al impulso de audio.js (ruido que se apaga en 1,8 s) con la
    normalización de ConvolverNode, ajustada para que la cola suene igual de
    fuerte que en un navegador a 48 kHz."""
    n = int(SR * 1.8)
    g = 1.0 - np.arange(n) / n
    ir = rng.uniform(-1.0, 1.0, n) * g * g * np.sqrt(g)
    power = math.sqrt(float(np.mean(ir * ir)))
    scale = (0.00125 / power) * (44100.0 / 48000.0) * math.sqrt(48000.0 / SR)
    return ir * scale


IR = make_ir()


def convolve(x, ir):
    nz = np.flatnonzero(x)
    if len(nz) == 0:
        return np.zeros_like(x)
    n = len(x) + len(ir) - 1
    size = 1
    while size < n:
        size *= 2
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return y


# ------------------------------------------------------------ compresor

def make_compressor(threshold_db=-14.0, knee_db=30.0, ratio=4.0):
    """Curva estática del DynamicsCompressorNode de Blink (rodilla exponencial)
    con su ganancia de compensación (makeup ^ 0.6)."""
    T = 10.0 ** (threshold_db / 20.0)
    K = 10.0 ** ((threshold_db + knee_db) / 20.0)

    def knee(x, k):
        return T + (1.0 - math.exp(-k * (x - T))) / k

    def slope(k):
        x1 = K * 1.001
        y0, y1 = knee(K, k), knee(x1, k)
        return (math.log10(y1) - math.log10(y0)) / (math.log10(x1) - math.log10(K))

    lo, hi = 0.001, 10.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if slope(mid) > 1.0 / ratio:
            lo = mid
        else:
            hi = mid
    k = (lo + hi) / 2
    yk = knee(K, k)

    def curve(x):
        x = np.asarray(x, dtype=np.float64)
        out = x.copy()
        m = (x >= T) & (x < K)
        out[m] = T + (1.0 - np.exp(-k * (x[m] - T))) / k
        m = x >= K
        out[m] = yk * (x[m] / K) ** (1.0 / ratio)
        return out

    makeup = (1.0 / float(curve(np.array([1.0]))[0])) ** 0.6
    return curve, makeup


COMP_CURVE, COMP_MAKEUP = make_compressor()


def compress(x, attack=0.003, release=0.25):
    """Seguidor de envolvente + curva estática; devuelve la señal comprimida."""
    n = len(x)
    ca = math.exp(-1.0 / (SR * attack))
    cr = math.exp(-1.0 / (SR * release))
    src = np.abs(x).tolist()
    env = [0.0] * n
    e = 0.0
    for i in range(n):
        a = src[i]
        if a > e:
            e = a + (e - a) * ca
        else:
            e = a + (e - a) * cr
        env[i] = e
    env = np.array(env)
    safe = np.maximum(env, 1e-6)
    gain = COMP_CURVE(safe) / safe
    return x * gain * COMP_MAKEUP


def soft_clip(x, knee=0.8):
    """Limitador suave: identidad hasta `knee`, tanh por encima (máximo 1.0)."""
    a = np.abs(x)
    over = a > knee
    out = x.copy()
    out[over] = np.sign(x[over]) * (knee + (1.0 - knee) * np.tanh((a[over] - knee) / (1.0 - knee)))
    return out


def master(x):
    """Cadena final: pre-ganancia, compresor, ganancia de salida y limitador."""
    return soft_clip(compress(x * PRE_GAIN) * OUT_GAIN)


# ============================================================ instrumentos

# Filtro fijo de cada instrumento (el mismo para todas sus notas, así que se
# aplica una sola vez a la suma: es lineal).
INST_FILTER = {
    "flute": ("lowpass", 3600, 0.5),
    "bass": ("lowpass", 900, 0.7),
    "pad": ("lowpass", 1100, 0.6),
    "lead": ("lowpass", 2600, 1.0),
    "snare": ("highpass", 1300, 0.7),
    "hat": ("highpass", 7500, 0.7),
    "shaker": ("bandpass", 5200, 1.2),
}


class Track:
    """Buses de una pieza: `bus` (directo), uno por instrumento con filtro
    (pre-filtro) y `wet` (envío a la reverb)."""

    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.bus = np.zeros(self.n)
        self.wet = np.zeros(self.n)
        self.pre = {}

    def add(self, which, t, sig):
        if which == "bus":
            buf = self.bus
        elif which == "wet":
            buf = self.wet
        else:
            buf = self.pre.get(which)
            if buf is None:
                buf = self.pre[which] = np.zeros(self.n)
        s = int(round(t * SR))
        e = min(self.n, s + len(sig))
        if e > s:
            buf[s:e] += sig[:e - s]

    def mix(self):
        """Suma los buses (filtrando los de instrumento) y añade la reverb."""
        dry = self.bus.copy()
        for inst, buf in self.pre.items():
            kind, f, q = INST_FILTER[inst]
            dry += biquad(buf, kind, f, q)
        wet = convolve(self.wet, IR) * WET
        return dry, wet


def i_flute(tr, t, f, d, v):
    n = int((d + 0.3) * SR)
    tt = np.arange(n) / SR
    env = gain_env(n, 0.045, 0.2 * v, d, 0.14, 0.82)
    depth = f * 0.007 * np.clip(tt / min(0.35, d), 0.0, 1.0)
    lfo = np.sin(2.0 * math.pi * 5.3 * tt) * depth
    sig = osc("triangle", f + lfo, n) + 0.18 * osc("sine", 2 * f + lfo, n)
    nn = int(0.09 * SR)
    ng = automation([(0, "set", 0.25), (0.08, "exp", 0.001)], nn)
    sig[:nn] += biquad(noise(nn) * ng, "bandpass", f * 2.2, 2.0)
    sig *= env
    tr.add("flute", t, sig)
    tr.add("wet", t, 0.35 * sig)


def i_bell(tr, t, f, d, v):
    n = int(1.0 * SR)
    env = automation([(0, "set", 0.0001), (0.004, "lin", 0.22 * v), (min(d, 0.45) + 0.45, "exp", 0.0008)], n)
    sig = osc("sine", f, n) * env
    n2 = int(0.12 * SR)
    g2 = automation([(0, "set", 0.35), (0.09, "exp", 0.001)], n2)
    sig[:n2] += osc("sine", 4 * f, n2) * g2 * env[:n2]
    tr.add("bus", t, sig)
    tr.add("wet", t, 0.3 * sig)


def i_pluck(tr, t, f, d, v):
    n = int(0.7 * SR)
    env = automation([(0, "set", 0.0001), (0.005, "lin", 0.11 * v), (min(d, 0.35) + 0.25, "exp", 0.0008)], n)
    fc = exp_ramp(3200.0, max(300.0, f * 1.8), 0.22, n)
    sig = biquad_var(osc("sawtooth", f, n), "lowpass", fc, 2.0) * env
    tr.add("bus", t, sig)
    tr.add("wet", t, 0.2 * sig)


def i_bass(tr, t, f, d, v):
    n = int((d + 0.2) * SR)
    env = gain_env(n, 0.008, 0.34 * v, d * 0.9, 0.08, 0.65)
    sig = (osc("triangle", f, n) + 0.25 * osc("square", f, n)) * env
    tr.add("bass", t, sig)


def i_pad(tr, t, f, d, v):
    n = int((d + 1.0) * SR)
    env = gain_env(n, 0.35, 0.05 * v, d, 0.7, 0.9)
    sig = (osc("sawtooth", f * 1.004, n) + osc("sawtooth", f * 0.996, n)) * env
    tr.add("pad", t, sig)
    tr.add("wet", t, 0.5 * sig)


def i_lead(tr, t, f, d, v):
    n = int((d + 0.2) * SR)
    tt = np.arange(n) / SR
    env = gain_env(n, 0.01, 0.075 * v, d, 0.08, 0.75)
    depth = f * 0.008 * np.clip(tt / 0.2, 0.0, 1.0)
    lfo = np.sin(2.0 * math.pi * 6.0 * tt) * depth
    sig = (osc("square", f + lfo, n) + osc("square", f * 1.006 + lfo, n)) * env
    tr.add("lead", t, sig)
    tr.add("wet", t, 0.2 * sig)


def i_kick(tr, t, v):
    n = int(0.25 * SR)
    env = automation([(0, "set", 0.55 * v), (0.22, "exp", 0.001)], n)
    fr = exp_ramp(150.0, 42.0, 0.13, n)
    tr.add("bus", t, osc("sine", fr, n) * env)


def i_snare(tr, t, v):
    n = int(0.15 * SR)
    env = automation([(0, "set", 0.22 * v), (0.13, "exp", 0.001)], n)
    sig = noise(n) * env
    tr.add("snare", t, sig)
    tr.add("wet", t, 0.15 * sig)
    n2 = int(0.1 * SR)
    env2 = automation([(0, "set", 0.12 * v), (0.08, "exp", 0.001)], n2)
    tr.add("bus", t, osc("triangle", 190.0, n2) * env2)


def i_hat(tr, t, v):
    n = int(0.05 * SR)
    env = automation([(0, "set", 0.08 * v), (0.045, "exp", 0.001)], n)
    tr.add("hat", t, noise(n) * env)


def i_shaker(tr, t, v):
    n = int(0.08 * SR)
    env = automation([(0, "set", 0.0001), (0.012, "lin", 0.07 * v), (0.07, "exp", 0.001)], n)
    tr.add("shaker", t, noise(n) * env)


INST = {"flute": i_flute, "bell": i_bell, "pluck": i_pluck, "bass": i_bass, "pad": i_pad, "lead": i_lead}
DRUMS = {"kick": i_kick, "snare": i_snare, "hat": i_hat, "shaker": i_shaker}


# ============================================================ partituras (music.js)

MUSIC = {
    "village": {
        "bpm": 100, "swing": 0.18,
        "chords": ["F", "C/E", "Dm", "Bb", "F", "C", "Bb", "C",
                   "Bb", "C", "Am", "Dm", "Gm", "C", "F", "F"],
        "melody": [{"inst": "flute", "vel": 1, "bars": [
            "A4:4 C5:2 A4:2 G4:4 F4:4", "G4:6 A4:2 C5:4 -:4", "D5:4 C5:2 A4:2 F4:4 A4:4", "G4:12 -:4",
            "A4:4 C5:2 F5:2 E5:4 D5:4", "C5:6 A4:2 G4:4 E4:4", "F4:4 G4:2 A4:2 D5:4 C5:4", "C5:12 -:4",
            "D5:2 D5:2 F5:4 D5:4 Bb4:4", "C5:2 C5:2 E5:4 G5:4 E5:4", "A5:6 G5:2 E5:4 C5:4", "D5:8 C5:4 A4:4",
            "Bb4:4 D5:4 G5:4 F5:2 D5:2", "E5:4 G5:2 E5:2 C5:4 Bb4:4", "A4:4 C5:4 F5:6 E5:2", "F5:12 -:4"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "useBass": True, "vel": 0.9, "pattern": "R--F--O-R--F--T-"},
            {"inst": "bell", "octave": 4, "vel": 0.5, "pattern": "0.1.2.1.3.2.1.2."},
            {"inst": "pad", "octave": 3, "vel": 0.9, "pattern": "C---------------"},
        ],
        "drums": {"kick": "x.......x.......", "snare": "....o.......o...", "shaker": "o.x.o.x.o.x.o.x."},
    },
    "forest": {
        "bpm": 122,
        "chords": ["Dm", "C", "Bb", "A", "Dm", "C", "Bb", "A",
                   "Bb", "C", "Dm", "Dm", "Bb", "C", "A", "A"],
        "melody": [{"inst": "flute", "vel": 1, "bars": [
            "D5:3 E5:1 F5:4 A5:4 G5:2 F5:2", "E5:6 D5:2 C5:4 E5:4", "F5:4 D5:4 Bb4:4 D5:4", "C#5:8 E5:4 A4:4",
            "D5:2 F5:2 A5:4 D6:4 C6:2 A5:2", "G5:4 E5:4 C5:4 E5:4", "F5:3 G5:1 F5:4 D5:4 Bb4:4", "A4:4 C#5:4 E5:4 A5:4",
            "D5:8 F5:8", "E5:8 G5:8", "A5:12 F5:4", "D5:16",
            "F5:4 E5:4 D5:4 C5:4", "E5:4 D5:4 C5:4 G4:4", "A4:8 C#5:8", "E5:16"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "vel": 0.9, "pattern": "R.R.R.R.F.F.O.F."},
            {"inst": "pluck", "octave": 4, "vel": 0.6, "pattern": "0.2.1.2.3.2.1.2."},
            {"inst": "pad", "octave": 3, "vel": 0.6, "pattern": "C-------C-------"},
        ],
        "drums": {"kick": "X.....x.X.......", "snare": "....X.......X...", "hat": "x.o.x.o.x.o.x.o."},
    },
    "cave": {
        "bpm": 92, "swing": 0.1,
        "chords": ["Am", "F", "G", "Em", "Am", "F", "Dm", "E",
                   "F", "G", "Em", "Am", "Dm", "Em", "F", "E"],
        "melody": [{"inst": "flute", "vel": 0.85, "bars": [
            "E5:6 A5:2 G5:4 E5:4", "F5:8 C5:4 A4:4", "D5:6 G5:2 F5:4 D5:4", "E5:12 -:4",
            "C6:4 B5:2 A5:2 E5:4 C5:4", "A5:6 G5:2 F5:4 C5:4", "D5:4 F5:4 A5:4 G5:2 F5:2", "E5:4 G#5:4 B5:8",
            "A5:4 C6:4 A5:4 F5:4", "B5:4 D6:4 B5:4 G5:4", "G5:6 E5:2 B4:8", "C5:4 E5:4 A5:8",
            "F5:4 A5:4 D6:4 C6:4", "B5:6 G5:2 E5:8", "A5:4 G5:4 F5:4 E5:4", "E5:8 -:8"]}],
        "parts": [
            {"inst": "bell", "octave": 4, "vel": 0.5, "pattern": "0.2.4.2.3.2.4.2."},
            {"inst": "bass", "octave": 2, "vel": 0.8, "pattern": "R-------F-------"},
            {"inst": "pad", "octave": 3, "vel": 1, "pattern": "C---------------"},
        ],
        "drums": {"kick": "o.......o.......", "hat": "..o...o...o...o."},
    },
    "volcano": {
        "bpm": 132,
        "chords": ["Em", "F", "Em", "D", "Em", "F", "G", "F"],
        "melody": [{"inst": "lead", "vel": 0.9, "bars": [
            "E5:2 -:2 E5:2 F5:2 G5:4 F5:2 E5:2", "F5:2 -:2 F5:2 G5:2 A5:4 G5:2 F5:2",
            "G5:4 B5:4 A5:2 G5:2 F5:2 E5:2", "D5:8 F#5:4 A5:4",
            "B5:4 A5:2 G5:2 E5:4 G5:4", "C6:4 B5:2 A5:2 F5:4 A5:4",
            "B5:2 D6:2 B5:2 G5:2 D5:4 G5:4", "A5:4 G5:4 F5:4 E5:4"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "vel": 1, "pattern": "R.R.R.R.R.R.F.O."},
            {"inst": "pluck", "octave": 3, "vel": 0.5, "pattern": "0.0.1.0.2.0.1.0."},
            {"inst": "pad", "octave": 3, "vel": 0.5, "pattern": "C-------C-------"},
        ],
        "drums": {"kick": "X..x..X.X..x..X.", "snare": "....X.......X..x", "hat": "xoxoxoxoxoxoxoxo"},
    },
    "boss": {
        "bpm": 150,
        "chords": ["Em", "C", "D", "B", "Em", "C", "D", "B"],
        "melody": [{"inst": "lead", "vel": 1, "bars": [
            "E5:2 E5:2 G5:2 E5:2 B5:4 A5:2 G5:2", "E5:2 E5:2 G5:2 E5:2 C6:4 B5:2 A5:2",
            "F#5:4 A5:4 D6:4 C6:2 B5:2", "D#5:8 F#5:4 B5:4",
            "G5:2 F#5:2 E5:2 F#5:2 G5:4 B5:4", "A5:2 G5:2 E5:2 G5:2 A5:4 C6:4",
            "B5:4 A5:4 F#5:4 D5:4", "D#5:4 F#5:4 A5:4 B5:4"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "vel": 1, "pattern": "R.RR.RR.R.RR.RF."},
            {"inst": "pluck", "octave": 4, "vel": 0.5, "pattern": "0.1.2.1.0.1.2.3."},
        ],
        "drums": {"kick": "X.x.X.x.X.x.X.x.", "snare": "....X.......X.X.", "hat": "oooooooooooooooo"},
    },
    "rift": {
        "bpm": 164,
        "chords": ["Am", "F", "G", "E", "Am", "F", "Dm", "E",
                   "F", "G", "Am", "Am", "Dm", "E", "Am", "E"],
        "melody": [{"inst": "lead", "vel": 1, "bars": [
            "A5:2 C6:2 E6:4 D6:2 C6:2 B5:4", "A5:2 F5:2 A5:4 C6:4 F6:4",
            "G5:2 B5:2 D6:4 C6:2 B5:2 G5:4", "G#5:8 B5:4 E6:4",
            "A5:2 A5:2 C6:2 A5:2 E6:4 D6:2 C6:2", "F6:4 E6:2 D6:2 C6:4 A5:4",
            "D6:4 C6:2 A5:2 F5:4 A5:4", "G#5:4 B5:4 D6:4 E6:4",
            "F6:2 E6:2 C6:4 A5:4 C6:4", "G6:2 F6:2 D6:4 B5:4 D6:4",
            "E6:4 C6:2 A5:2 E6:4 A6:4", "A6:12 -:4",
            "F6:4 D6:2 A5:2 F6:4 E6:2 D6:2", "E6:2 G#6:2 B6:4 G#6:4 E6:4",
            "A6:4 E6:2 C6:2 A5:4 C6:4", "B5:4 G#5:4 E5:4 -:4"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "vel": 1, "pattern": "R.RRR.RRF.FFO.OF"},
            {"inst": "pluck", "octave": 4, "vel": 0.5, "pattern": "0.2.3.2.1.2.3.4."},
            {"inst": "pad", "octave": 3, "vel": 0.55, "pattern": "C-------C-------"},
        ],
        "drums": {"kick": "X.x.X.x.X.x.X.xx", "snare": "....X.......X..X", "hat": "xoxoxoxoxoxoxoxo"},
    },
    # La Sentencia de Arceus (minuto 30). Solemne y sin salida: Re menor con un
    # Mi bemol (frigio) que oscurece, campanas graves en cada compás y la
    # melodía subiendo hasta el final.
    "judgment": {
        "bpm": 140,
        "chords": ["Dm", "Bb", "Gm", "A", "Dm", "Eb", "C", "A",
                   "Bb", "C", "Dm", "Dm", "Gm", "A", "Dm", "A"],
        "melody": [{"inst": "lead", "vel": 1, "bars": [
            "D5:4 F5:4 A5:6 G5:2", "F5:4 D5:4 Bb4:8",
            "G5:4 Bb5:4 D6:4 C6:2 Bb5:2", "A5:8 C#6:4 E6:4",
            "D6:6 C6:2 A5:4 F5:4", "G5:4 Eb5:4 G5:4 Bb5:4",
            "C6:4 E5:2 G5:2 C6:4 E6:4", "C#6:12 -:4",
            "D6:2 D6:2 F6:4 D6:4 Bb5:4", "C6:2 C6:2 E6:4 C6:4 G5:4",
            "A5:4 D6:4 F6:4 E6:2 D6:2", "D6:12 -:4",
            "Bb5:4 D6:4 G6:4 F6:2 D6:2", "E6:4 C#6:4 A5:4 E6:4",
            "F6:4 E6:2 D6:2 A5:4 F5:4", "E5:4 A5:4 C#6:4 E6:4"]}],
        "parts": [
            {"inst": "bass", "octave": 2, "vel": 1, "pattern": "R.RRR.RRR.RRF.OF"},
            {"inst": "bell", "octave": 4, "vel": 0.6, "pattern": "0.......2......."},
            {"inst": "pad", "octave": 3, "vel": 0.8, "pattern": "C---------------"},
        ],
        "drums": {"kick": "X..xX..xX..xX.xx", "snare": "....X.......X..X", "hat": "x.x.x.x.x.x.x.x."},
    },
}


# ============================================================ secuenciador

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi_freq(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def midi_of(name):
    m = re.match(r"^([A-G])(#|b)?(-?\d)$", name)
    if not m:
        return None
    acc = 1 if m.group(2) == "#" else -1 if m.group(2) == "b" else 0
    return 12 * (int(m.group(3)) + 1) + NOTE[m.group(1)] + acc


def parse_chord(c):
    m = re.match(r"^([A-G])(#|b)?(m?)(?:/([A-G])(#|b)?)?$", c)

    def pc(letter, a):
        return (NOTE[letter] + (1 if a == "#" else -1 if a == "b" else 0) + 12) % 12

    root = pc(m.group(1), m.group(2))
    return {"root": root, "minor": m.group(3) == "m", "bass": pc(m.group(4), m.group(5)) if m.group(4) else root}


def compile_song(song):
    """Port de compile(): lista de eventos por semicorchea."""
    bars = song.get("bars") or len(song["chords"])
    steps = bars * 16
    ev = [[] for _ in range(steps)]

    for tr in song.get("melody", []):
        for bi, bar in enumerate(tr["bars"]):
            s = 0
            for tok in bar.strip().split():
                parts = tok.split(":")
                n = parts[0]
                L = int(parts[1]) if len(parts) > 1 and parts[1] else 1
                if n != "-":
                    midi = midi_of(n) + tr.get("shift", 0)
                    ev[(bi * 16 + s) % steps].append({"inst": tr["inst"], "f": midi_freq(midi), "len": L, "v": tr.get("vel", 1)})
                s += L

    chords = [parse_chord(c) for c in song["chords"]]

    def chord_tone(ch, i, base):
        third = 3 if ch["minor"] else 4
        ivs = [0, third, 7, 12, 12 + third, 19]
        iv = ivs[i] if 0 <= i < len(ivs) else 0
        return base + ch["root"] + iv

    for b in range(bars):
        ch = chords[b % len(chords)]
        for tr in song.get("parts", []):
            pat = tr["pattern"]
            base = 12 * (tr["octave"] + 1)
            for s in range(16):
                c = pat[s] if s < len(pat) else None
                if not c or c in ".-":
                    continue
                ln = 1
                while s + ln < 16 and pat[s + ln] == "-":
                    ln += 1
                if c == "R":
                    midi = base + (ch["bass"] if tr.get("useBass") else ch["root"])
                elif c == "F":
                    midi = base + ch["root"] + 7
                elif c == "O":
                    midi = base + ch["root"] + 12
                elif c == "T":
                    midi = base + ch["root"] + (3 if ch["minor"] else 4)
                elif c == "C":
                    for i in range(3):
                        ev[b * 16 + s].append({"inst": tr["inst"], "f": midi_freq(chord_tone(ch, i, base)), "len": ln, "v": tr.get("vel", 1)})
                    continue
                else:
                    midi = chord_tone(ch, int(c), base)
                ev[b * 16 + s].append({"inst": tr["inst"], "f": midi_freq(midi), "len": ln, "v": tr.get("vel", 1)})
        for inst, pat in song.get("drums", {}).items():
            for s in range(16):
                c = pat[s] if s < len(pat) else None
                if c and c != ".":
                    ev[b * 16 + s].append({"inst": inst, "drum": True, "v": 1 if c == "X" else 0.75 if c == "x" else 0.45})
    return {"steps": steps, "ev": ev, "bpm": song["bpm"], "swing": song.get("swing", 0)}


def render_song(name, song):
    comp = compile_song(song)
    sd = 60.0 / comp["bpm"] / 4.0
    steps = comp["steps"]
    loop_s = steps * sd
    if loop_s > MAX_LOOP_S:
        # Recorta a compases enteros que quepan en el tope.
        bars = int(MAX_LOOP_S / (16 * sd))
        steps = bars * 16
        loop_s = steps * sd
    tail_s = 3.5                           # cola máxima (reverb 1,8 s + liberación)
    tr = Track(loop_s + tail_s)
    for i in range(steps):
        t = i * sd + (comp["swing"] * sd if i % 4 == 2 else 0.0)
        for e in comp["ev"][i]:
            if e.get("drum"):
                DRUMS[e["inst"]](tr, t, e["v"])
            else:
                INST[e["inst"]](tr, t, e["f"], e["len"] * sd, e["v"])
    dry, wet = tr.mix()
    mix = (dry + wet) * MUSIC_BUS
    n_loop = int(round(loop_s * SR))
    out = mix[:n_loop].copy()
    tail = mix[n_loop:]
    out[:len(tail)] += tail                # pliega la cola al principio: bucle sin corte
    return master(out)


# ============================================================ efectos de sonido

SHOT_PITCH = {
    "fire": 520, "water": 700, "electric": 1100, "psychic": 800, "grass": 640, "ice": 900, "poison": 400,
    "ghost": 350, "dragon": 300, "fairy": 1200, "normal": 600, "fighting": 450, "rock": 260, "ground": 240,
    "steel": 750, "bug": 980, "dark": 330, "flying": 820,
}
SHOT_BUCKET_FREQ = {0: 330.0, 1: 640.0, 2: 1000.0}


def shot_bucket(ptype):
    f = SHOT_PITCH.get(ptype, 600)
    return 0 if f < 500 else 1 if f <= 800 else 2


class Sfx:
    """Contexto de un efecto: equivalente a sfxBus. Los instrumentos (bell, pad,
    kick) que la web toca sobre sfxBus también envían a la reverb."""

    def __init__(self, seconds=6.0):
        self.tr = Track(seconds)

    def tone(self, wave_type, f0, f1, dur, vol, at=0.0):
        n = int((dur + 0.05) * SR)
        env = automation([(0, "set", 0.0001), (0.006, "lin", vol), (dur, "exp", 0.0005)], n)
        fr = exp_ramp(f0, f1, dur, n) if (f1 and f1 != f0) else f0
        self.tr.add("bus", at, osc(wave_type, fr, n) * env)

    def hiss(self, dur, vol, kind, f0, f1=None, at=0.0, q=1.0):
        n = int((dur + 0.05) * SR)
        env = automation([(0, "set", vol), (dur, "exp", 0.0005)], n)
        src = noise(n)
        if f1:
            sig = biquad_var(src, kind, exp_ramp(f0, f1, dur, n), q)
        else:
            sig = biquad(src, kind, f0, q)
        self.tr.add("bus", at, sig * env)

    def arp(self, wave_type, freqs, gap, dur, vol):
        for i, f in enumerate(freqs):
            self.tone(wave_type, f, f, dur, vol, i * gap)

    def inst(self, fn, at, *args):
        fn(self.tr, at, *args)

    def render(self):
        dry, wet = self.tr.mix()
        mix = master(dry * SFX_BUS + wet * MUSIC_BUS)
        # Recorta el silencio final (umbral -60 dB) dejando 30 ms.
        nz = np.flatnonzero(np.abs(mix) > 0.001)
        end = (int(nz[-1]) + int(0.03 * SR)) if len(nz) else int(0.05 * SR)
        return mix[:min(len(mix), end)]


def sfx_shot(s, kind, f, ptype=None):
    if kind == "melee":
        s.hiss(0.12, 0.13, "bandpass", 600, 2800, 0, 1.4)
    elif kind == "beam":
        s.tone("sawtooth", f * 0.6, f * 0.35, 0.3, 0.05)
        s.hiss(0.25, 0.04, "bandpass", f * 2, f, 0, 3)
    elif kind == "nova":
        s.hiss(0.2, 0.1, "lowpass", 2400, 300)
        s.tone("sine", 140, 60, 0.16, 0.12)
    elif kind == "aura":
        s.tone("sine", f * 0.5, f * 0.55, 0.25, 0.04)
        s.tone("sine", f * 0.75, f * 0.8, 0.25, 0.03)
    elif kind == "buff":
        s.arp("sine", [f, f * 1.25, f * 1.5], 0.05, 0.12, 0.05)
    elif kind == "orbit":
        s.tone("triangle", f, f * 1.5, 0.15, 0.04)
    else:
        s.tone("triangle", f * 1.5, f * 0.5, 0.09, 0.05)
        if ptype in ("fire", "electric"):
            s.hiss(0.06, 0.03, "highpass", 3000)


def sfx_shiny(s):
    for i, f in enumerate([2093, 2637, 3136, 2349, 3520, 4186]):
        s.inst(i_bell, i * 0.07, f, 0.3, 0.8)


def sfx_break(s):
    s.hiss(0.16, 0.12, "lowpass", 1100, 200)
    s.tone("triangle", 140, 60, 0.12, 0.08)


def sfx_coin(s):
    s.tone("square", 1320, 1320, 0.05, 0.035)
    s.tone("square", 1760, 1760, 0.14, 0.035, 0.05)


def sfx_burst(s, r):
    s.hiss(0.5, 0.14, "bandpass", 400, 4000, 0, 0.8)
    chord = [[523, 659, 784], [587, 740, 880], [659, 831, 988], [698, 880, 1047], [784, 988, 1175, 1568]][r - 1]
    for f in chord:
        s.tone("triangle", f, f, 0.6 + r * 0.15, 0.04)


def sfx_reveal(s, r):
    s.inst(i_bell, 0, [523, 659, 784, 988, 1319][r - 1], 0.3, 0.8)


def sfx_boss(s):
    for f in (82, 123, 165):
        s.tone("sawtooth", f, f * 0.98, 1.3, 0.05)
    s.inst(i_kick, 0, 1)


def sfx_rift(s):
    for i, f in enumerate([196, 233, 277, 330]):
        s.inst(i_pad, i * 0.08, f, 1.4, 1.2)
    s.hiss(0.9, 0.08, "bandpass", 900, 300)


def sfx_biome(s):
    for f in (392, 494, 587, 784):
        s.inst(i_pad, 0, f, 1.2, 1.4)


def sfx_xp(s, combo):
    s.tone("sine", 880 * 2 ** (combo / 12.0), 0, 0.06, 0.035)


# ---- La Sentencia de Arceus (src/judgment.lua) ----
def sfx_quake(s):
    s.hiss(2.4, 0.18, "lowpass", 320, 50)
    s.tone("sine", 52, 30, 2.2, 0.22)


def sfx_toll(s):
    for i, f in enumerate([110, 165, 220, 330]):
        s.inst(i_bell, 0, f, 1.4, 1.5 - i * 0.3)
    s.inst(i_pad, 0, 55, 2.4, 2.6)
    s.inst(i_pad, 0, 82.4, 2.4, 2)
    s.tone("sine", 55, 52, 2.4, 0.16)


def sfx_descend(s):
    s.hiss(2.4, 0.07, "bandpass", 300, 3200, 0, 0.7)
    for i, f in enumerate([262, 330, 392, 523, 659]):
        s.inst(i_pad, i * 0.3, f, 2.2, 1.6)


def sfx_land(s):
    s.hiss(1.6, 0.32, "lowpass", 2400, 50)
    s.tone("sine", 95, 26, 1.4, 0.36)
    s.inst(i_kick, 0, 1.6)
    s.inst(i_kick, 0.12, 1.1)
    s.arp("square", [523, 659, 784, 1047, 1319], 0.07, 0.6, 0.045)


def sfx_judge(s):
    s.tone("sine", 1760, 700, 0.45, 0.04)
    s.hiss(0.35, 0.07, "highpass", 1800, 6000)
    s.tone("triangle", 120, 50, 0.3, 0.1)


SFX = {
    "hover": lambda s: s.tone("square", 1400, 1400, 0.025, 0.025),
    "click": lambda s: s.tone("square", 660, 990, 0.05, 0.06),
    "back": lambda s: s.tone("square", 880, 520, 0.07, 0.05),
    "confirm": lambda s: s.arp("triangle", [784, 988, 1319], 0.05, 0.12, 0.09),
    "select": lambda s: s.tone("square", 990, 1180, 0.04, 0.045),
    "error": lambda s: s.arp("square", [330, 262], 0.08, 0.09, 0.05),
    "hit": lambda s: s.tone("triangle", 230, 90, 0.045, 0.045),
    "faint": lambda s: s.tone("sine", 720, 240, 0.08, 0.04),
    "bossDown": lambda s: (s.hiss(0.7, 0.18, "lowpass", 1500, 100), s.arp("triangle", [262, 330, 392, 523], 0.09, 0.4, 0.08)),
    "coin": sfx_coin,
    "heal": lambda s: s.arp("triangle", [523, 659, 784, 1047], 0.06, 0.18, 0.06),
    "levelup": lambda s: (s.arp("square", [523, 659, 784, 1047], 0.07, 0.14, 0.05), s.arp("triangle", [1047, 1319, 1568], 0.07, 0.3, 0.05)),
    "hurt": lambda s: (s.tone("square", 150, 70, 0.14, 0.06), s.hiss(0.1, 0.06, "lowpass", 900)),
    "boss": sfx_boss,
    "surge": lambda s: s.hiss(0.7, 0.12, "lowpass", 500, 120),
    "shiny": sfx_shiny,
    "shinyGet": lambda s: (sfx_shiny(s), s.arp("square", [784, 988, 1175, 1568], 0.1, 0.35, 0.05)),
    "break": sfx_break,
    "chest": lambda s: (sfx_break(s), s.arp("square", [1047, 1319, 1568, 2093], 0.06, 0.12, 0.04)),
    "grass": lambda s: s.hiss(0.06, 0.03, "highpass", 2600),
    "ball": lambda s: (s.tone("triangle", 220, 70, 0.12, 0.12), s.hiss(0.08, 0.06, "lowpass", 800)),
    "shake": lambda s: s.tone("square", 420, 380, 0.04, 0.05),
    "rift": sfx_rift,
    "legend": lambda s: (s.arp("square", [523, 659, 784, 1047, 1319, 1568], 0.08, 0.3, 0.05), sfx_shiny(s)),
    "gameover": lambda s: s.arp("triangle", [523, 440, 349, 262], 0.2, 0.35, 0.08),
    "biome": sfx_biome,
    "quake": sfx_quake,
    "toll": sfx_toll,
    "descend": sfx_descend,
    "land": sfx_land,
    "judge": sfx_judge,
    "pause": lambda s: s.arp("square", [784, 523], 0.06, 0.07, 0.04),
    "buy": lambda s: (sfx_coin(s), s.arp("triangle", [659, 784, 1047], 0.05, 0.12, 0.06)),
}


def all_sfx_jobs():
    """Lista de (nombre de fichero, función que rellena el Sfx)."""
    jobs = [(name, fn) for name, fn in SFX.items()]
    for kind in ("projectile", "beam", "orbit", "aura", "buff"):
        for b, f in SHOT_BUCKET_FREQ.items():
            jobs.append(("shot_%s_%d" % (kind, b), (lambda k, ff: lambda s: sfx_shot(s, k, ff))(kind, f)))
    jobs.append(("shot_melee", lambda s: sfx_shot(s, "melee", 600)))
    jobs.append(("shot_nova", lambda s: sfx_shot(s, "nova", 600)))
    jobs.append(("shot_projectile_fire", lambda s: sfx_shot(s, "projectile", SHOT_PITCH["fire"], "fire")))
    jobs.append(("shot_projectile_electric", lambda s: sfx_shot(s, "projectile", SHOT_PITCH["electric"], "electric")))
    for combo in range(25):
        jobs.append(("xp_%d" % combo, (lambda c: lambda s: sfx_xp(s, c))(combo)))
    for r in range(1, 6):
        jobs.append(("burst_%d" % r, (lambda rr: lambda s: sfx_burst(s, rr))(r)))
        jobs.append(("reveal_%d" % r, (lambda rr: lambda s: sfx_reveal(s, rr))(r)))
    return jobs


# ============================================================ salida

def write_wav(path, data):
    clipped = np.clip(data, -1.0, 1.0)
    pcm = (clipped * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return os.path.getsize(path), float(np.max(np.abs(clipped))), float(np.sqrt(np.mean(clipped * clipped)))


def main():
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
    # --names a,b,c: sólo esos temas/efectos (los demás ficheros no se tocan).
    names = None
    if "--names" in sys.argv:
        names = set(sys.argv[sys.argv.index("--names") + 1].split(","))
    t0 = time.time()
    total = 0
    if only in (None, "music"):
        os.makedirs(OUT_MUSIC, exist_ok=True)
        for name, song in MUSIC.items():
            if names is not None and name not in names:
                continue
            t1 = time.time()
            data = render_song(name, song)
            path = os.path.join(OUT_MUSIC, name + ".wav")
            size, peak, rms = write_wav(path, data)
            total += size
            print("music/%-8s %6.1f s  %7d KB  pico %.3f  rms %.3f  (%.1f s)" % (
                name + ".wav", len(data) / SR, size // 1024, peak, rms, time.time() - t1))
    if only in (None, "sfx"):
        os.makedirs(OUT_SFX, exist_ok=True)
        for name, fn in all_sfx_jobs():
            if names is not None and name not in names:
                continue
            s = Sfx()
            fn(s)
            data = s.render()
            path = os.path.join(OUT_SFX, name + ".wav")
            size, peak, rms = write_wav(path, data)
            total += size
            print("sfx/%-26s %5.2f s  %5d KB  pico %.3f" % (name + ".wav", len(data) / SR, size // 1024, peak))
    print("total %.1f MB en %.0f s" % (total / 1048576.0, time.time() - t0))


if __name__ == "__main__":
    main()
