# check_lua51.py — compila (sin ejecutar) todos los .lua del juego con Lua 5.1, la
# versión que usa LÖVE Potion en la 3DS. En el PC el juego corre en LuaJIT, que
# acepta cosas que Lua 5.1 no (goto, etiquetas ::x::...), y esos fallos sólo salían
# en la consola. Uso: python tools/check_lua51.py   (sale con 1 si hay errores)
import os, sys
import lupa.lua51 as lupa

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game")
lua = lupa.LuaRuntime()
compile_ = lua.eval("function(src, name) local f, err = loadstring(src, name) return err end")
bad = 0
total = 0
for dirpath, _, files in os.walk(ROOT):
    if os.sep + "nest" in dirpath:
        continue
    for f in files:
        if not f.endswith(".lua"):
            continue
        path = os.path.join(dirpath, f)
        rel = os.path.relpath(path, ROOT)
        src = open(path, "rb").read()
        total += 1
        err = compile_(src, "@" + rel)
        if err:
            bad += 1
            print("ERROR", err)
print("Lua 5.1: %d ficheros, %d con errores" % (total, bad))
sys.exit(1 if bad else 0)
