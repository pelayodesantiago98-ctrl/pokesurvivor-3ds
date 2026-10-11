# Estado del port (actualizado 2026-10-12, madrugada)

**Repositorio:** privado en GitHub, `pelayodesantiago98-ctrl/pokesurvivor-3ds`. En este
PC no hay `gh` con sesión: se sube a través del VPS (remoto `vps` =
`(servidor) que tiene `gh` y su `origin` en
GitHub). Flujo: `git push vps main` y luego en el VPS `cd /root/proyectos/pokesurvivor-3ds
&& git push origin main`. git portable: `C:\Users\lepay\3ds-tools\git\cmd\git.exe`.
`build/` y `dist/` no se suben (regenerables).

**NOVEDAD 4 (sesión del 2026-10-11/12, todo probado en PC con capturas, smoke y soak):**
- Mapa: gráficos del tileset HGSS de SirMaio (`tools/gen_hgss.py`): suelo, hierba (con
  animación al pisarla), flores, árboles, rocas y arbolito de Corte. Colocación estilo
  Vampire Survivors (`pieceAt` en world.lua): piezas al azar con distancia mínima, sin
  filas/columnas; rendijas < 72 entre árboles se rellenan; nada pisa los interactivos.
  Hierba y flores en montones variados.
- Colisión de árboles con caja de tronco + hojas (la sombra se pisa); `--treetest`.
- Agua = agua poco profunda de Negro/Blanco con reflejos y bordes redondeados; lava =
  mar de DPPt teñido y animado (4 fotogramas), sólida. Fuego cruza lava y no agua; el
  resto al revés; Volador cruza ambas (`W.liquidSolidFor`); `--liqtest`, `--inwater`.
- HUD de combate estilo Platino (etiqueta HP verde fija, barra que cambia de color);
  botones de movimiento con fuente pixelada a tamaño 1.5 fijo (parte en 2 líneas o con
  guion silábico); `--moves=id,id`.
- Menús táctiles estilo DS (botón genérico `UI.button` con contorno, brillo y cursor de
  esquinas rojo; fondo de rayas); menú principal estilo HGSS/BW con iconos de objeto
  (`tools/gen_menu_icons.py`, Pokédex dibujada) y la ficha del compañero arriba.
- Tarjeta de entrenador: 36 fondos propios + 15 al estilo de las tarjetas de 3.ª/4.ª/5.ª
  gen (`tools/gen_card_art.py`), 311 entrenadores oficiales (Showdown, lista en
  `tools/trainers.txt`), paneles con sprites de Negro/Blanco (1-649), 8 Poké Balls de
  colores como medallas (una cada 16 de las 127, `tools/gen_badges.py`); sólo salen los
  Pokémon que tienes. `--card=fondo,entrenador`, `--medals=N` (no se guardan).
- NO se usa nada de Pokécharms (sus normas lo prohíben); se retiró.

**Pendiente para la siguiente sesión:**
- Reconstruir el CIA (`tools\build.ps1 -Target cia`), subirlo por FTP (192.168.1.34:5000,
  /CIAS/) y probar en la consola: rendimiento de la lava animada, memoria de la tarjeta.
- Las demás pantallas (gacha, misiones, mejoras, fases) conservan su distribución
  antigua con los botones nuevos: pasarlas al estilo DS si el usuario lo pide.
- El número de la tarjeta sale "ID 59067" (la fuente pixelada no tiene "º").

# Estado anterior (2026-10-11 por la noche)

**NOVEDAD 3 (mecánicas de giovanneluna/poke-survivors, MIT, copia del código en
`C:\Users\lepay\3ds-tools\src\poke-survivors`):**
- Evolución del compañero en partida (`src/evolution.lua`, cadenas de PokeAPI en
  `data/evolutions.lua` vía `tools/gen_evolutions.py`): nivel 16 → 1ª evolución, 36 → 2ª;
  cambia sprite, stats y tipos; solo dura la run.
- Modo Fases (`src/stages.lua`, `data/stages.lua` vía `tools/gen_stages.py`): 8 fases
  de 10 min con 20 oleadas fijas y 3-4 jefes; derrotar al jefe final supera la fase y
  desbloquea la siguiente (`save.stages`). Pantalla "stages" y botón Fases en el menú.
  El spawner usa `G.Stages` cuando hay fase activa.
- Evolución de movimientos con objeto: `G.Moves.evoInfo(m, statsTaken, pl)` también
  está lista si el Pokémon ha evolucionado (forma ≥ 2) y lleva un objeto.
- Tarjeta de entrenador (pantalla "card"): nombre, título, dinero, Pokédex, shinies,
  tiempo jugado (`stats.playTime`), fases superadas, 3 favoritos y 8 medallas (logros).
- Argumentos de depuración nuevos: `--stage=N --level=N --time=N --killbosses`.
- Audio hecho (lote F): `tools/gen_audio.py` (numpy) → `game/music/*.wav` (6 temas,
  6,8 MB) y `game/sfx/*.wav` (82); `src/audio.lua` con pools y fundidos.
- PENDIENTE: construir el CIA (la última construcción la mató el sistema por falta
  de memoria; relanzar solo cuando el usuario lo pida), subirlo y probar en la 3DS.
  El usuario quiere después trabajar en el "menú táctil" (interfaz de la pantalla inferior).

**NOVEDAD 2:** shinies hechos (`pack_sprites.py` genera `<dex>_s.png` Idle+Walk para 958
Pokémon; `sprites.lua` elige el atlas shiny; la Pokédex permite elegir el compañero
shiny; `--shiny` fuerza shinies salvajes). Prueba de resistencia (`soak-test.ps1`)
OK 7 minutos de juego sin errores. Audio en curso por un agente (lote F:
`tools/gen_audio.py` → `game/music/*.wav`, `game/sfx/*.wav`, `src/audio.lua`).

**NOVEDAD:** `combat.lua`, `spawner.lua` y `levelup.lua` ya están escritos y el juego
entero ARRANCA EN PC: `tools\smoke-test.ps1` da SMOKE_OK, y con `tools\pc-shot.ps1`
(captura la ventana de nest; argumentos del juego `--run`, `--levelup`, `--die`,
`--ui=menu|dex|gacha|upgrades|goals|test|starters`, `--scale1`) se han verificado
visualmente título, menú, Pokédex con ficha arriba, test, partida con HUD, cartas de
nivel, resumen de caída, gacha y mejoras. Arreglos hechos al integrar: conf.lua
declara 11.5 en PC (LÖVE 11.5 bloquea con un cuadro "Compatibility Warning" si pone
12.0); la consola real se detecta con `G.U.CONSOLE` (`love._potion_version`), porque
nest también define `love._console` en PC. `dist\PokeSurvivor.cia` (67 MB) generado
con todo; PENDIENTE subirlo por FTP (ftpd cerrado al cerrar la sesión) y probarlo
en la 3DS: rendimiento y memoria son la incógnita. Las secciones de abajo describen
la situación anterior a esto.

# Estado del port (2026-10-11, al cerrar la sesión)

Objetivo: portar pokesurvivor.com (código MIT, github JPTER78/pokesurvivor) a 3DS con
LÖVE Potion. Contrato entre módulos: `docs/PORT.md`. Lo que había antes (survivor
mínimo) se sustituyó por completo.

## Hecho

| Parte | Ficheros | Estado |
|---|---|---|
| Cimientos | `src/util.lua`, `src/sprites.lua`, `src/camera.lua`, `src/input.lua`, `src/audio.lua` (stub), `src/icons.lua` | hecho, sintaxis OK |
| Flujo e interfaz | `main.lua`, `conf.lua`, `src/game.lua`, `src/ui/{ui,top,run,test,menu}.lua` | hecho, sintaxis OK, SIN probar en ejecución |
| Datos (lote A) | `src/{dex,types,items,upgrades,starters,moves,enemies,missions,achievements}.lua`, `data/pokedex.lua`, `tools/gen_pokedex.py` | hecho y probado por el agente (ver notas abajo) |
| Arte (lotes B1/B2) | `tools/gen_tiles.py` → `img/tiles/0-20.png` + `data/tiles.lua`; `tools/gen_vfx.py` → `img/vfx.png` + `data/vfx.lua`; `tools/gen_icons.py` → `img/icons.png` + `data/icons.lua` | hecho |
| Sprites | `tools/pack_sprites.py` → `img/pkmn/<dex>.png`, `<dex>_f.png`, `data/pkmn/<dex>.lua`, `data/dexmeta.lua` (966 Pokémon) | hecho |
| Mundo (lote C) | `src/world.lua`, `src/pathing.lua` | escritos; sintaxis OK; el agente se cortó antes de probar e informar |
| Efectos (lote D1) | `src/{vfx,fx,projectile,pickup,hazards}.lua` | escritos; sintaxis OK; el agente se cortó antes de probar e informar |
| Entidades (lote D2) | `src/player.lua`, `src/enemy.lua` | escritos; sintaxis OK. **FALTAN `src/combat.lua`, `src/spawner.lua`, `src/levelup.lua`** (el agente se cortó) |
| Sistemas (lote E) | `src/{json,db,weather,interact,rift,events,gacha,progress}.lua` | escritos; sintaxis OK; el agente se cortó antes de probar e informar |
| Build | `tools/build.ps1` con caché t3x incremental (`build/t3x-cache`, 1952 ficheros ya convertidos); `tools/luacheck.ps1` | hecho; `dist/PokeSurvivor.cia` de 66 MB generado (con el Lua sin integrar) |

## Siguiente sesión, en este orden

1. Escribir `src/combat.lua`, `src/spawner.lua`, `src/levelup.lua` portando
   `js/systems/{combat,spawner,levelup}.js` (ver PORT.md §11 y el brief del lote D2:
   CAP = 40, sin cooperativo, campos/minas/meteoros/torretas iguales al JS,
   `G.Sprites.preload/gc` desde el spawner). El código JS del repo (sin sprites) está
   copiado en `C:\Users\lepay\3ds-tools\src\pokesurvivor-web`; si hiciera falta algo
   más, clonar de nuevo (`git clone --filter=blob:none https://github.com/JPTER78/pokesurvivor`).
2. Revisar que los módulos de los lotes C, D1, D2 y E cumplen el contrato (sus informes
   se perdieron): leer la cabecera de cada fichero y comprobar las llamadas cruzadas
   (`G.Rift.inArena()` como función, `G.Events.golden` campo, `pl:atk()` métodos,
   `G.Weather.current()` función, `G.Rift.arrow()`, `G.Enemies.tierAt` 1-based...).
3. `tools\smoke-test.ps1` (arranca una run automáticamente con `--smoke`; en PC también
   con F1) y arreglar errores en cascada. Luego `tools\run-pc.ps1` y jugar.
4. `tools\build.ps1 -Target cia`, subir por FTP a `/CIAS/` (ftpd en la 3DS,
   192.168.1.34:5000) e instalar con FBI. Vigilar memoria en consola (atlas RGBA8).
5. Pendiente de diseño: sonido (stubs en `src/audio.lua`; la web sintetiza música desde
   partituras en `js/data/music.js`: se podrían renderizar a ogg con Python), shinies
   (no hay atlas shiny; `sh` indica si existe), ajustes, README final.

## Notas del lote A (informe del agente)

- Orden de carga: util → sprites → dex → types → items → upgrades → moves → starters →
  enemies → missions → achievements (ya está así en `main.lua`).
- `G.Enemies.tierAt(t)` devuelve índice **1-based**; `cast = 5`; `bagAt(t)` cachea por
  segundo (no modificar la tabla devuelta).
- `G.Moves.instance` copia campo a campo; `ups[N]` es la mejora N→N+1; `evolved=false`,
  `castAt=0` desde el principio; `baseName` solo tras `evolve()`.
- `G.personalityResult` desempata con `G.TRAIT_ORDER`.
- `U.hash` no es el de la web: las personalidades por hash (beamer/zoner/...) no
  coinciden Pokémon a Pokémon con la web, pero sí la distribución.
- Claves de `owned/shiny` aceptadas como número o texto.

## Notas de los lotes B1/B2

- Tiles: 21 atlas 256x256; cuadros `floor_0..5` (usar `G.Tiles.floorVariant(U.hash(tx,ty,14))`),
  `dirt_m`/`wall_m` (m = 1N+2E+4S+8O), `liquid_m` (47 canónicas via `G.Tiles.liquidKey`),
  `wallshadow`, `prop_<tipo>_<var>`. Paletas 1-based (`grass[3]` = JS `grass[2]`).
- VFX: `data/vfx.lua` con `quads` (ox,oy centro), `shapes`, `pal`, `tint`, `typeShape`,
  `forType`, `moves` (por id). Iconos: 87 nombres (medallas son `medal1..3`/`medalOff`).

## Decisiones

- Cámara 800x480 unidades a escala 0.5 (1 px de arte = 1 px de pantalla); unidades de
  mundo idénticas a la web.
- Enemigos solo con Idle+Walk (atlas `<dex>.png`); compañero con las 7 animaciones
  (`<dex>_f.png`). 5 direcciones en atlas, las izquierdas volteadas.
- Fuente: Pixelify Sans en PC; en consola la del sistema (mkbcfnt no la convierte).
- Sin cooperativo, ranking, cuentas ni nube.
