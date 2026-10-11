# Port de PokéSurvivor (web, JS) a Nintendo 3DS (LÖVE Potion, Lua 5.1)

Este documento es el CONTRATO entre los módulos. Quien porte un fichero JS a Lua
debe seguirlo al pie de la letra: mismos nombres de módulo (`G.World`, `G.FX`...),
mismas funciones públicas y mismos campos de las entidades, para que el resto del
código (y los otros portadores) puedan contar con ellos.

Origen: `https://github.com/JPTER78/pokesurvivor` (MIT). Copia local del repo:
`%LOCALAPPDATA%\Temp\claude\C--Users-lepay\7caef775-80b7-4d4a-9262-16318d5bee08\scratchpad\pokesurvivor-repo`.
Destino: `C:\Users\lepay\pokesurvivor-3ds\game\`.

## 1. Entorno de ejecución

- **Lua 5.1 puro** (sin LuaJIT, sin `goto`, sin `//`, sin operadores de bits, sin
  `table.unpack` → `unpack`, sin `math.tointeger`). `#t`, `ipairs`, `table.insert`,
  `table.remove`, `math.floor`, `math.huge`, `string.format` sí.
- **LÖVE 12 API** (LÖVE Potion 3.0 en consola; en PC se prueba con LÖVE 11.5 + nest,
  que simula las dos pantallas). Usar solo lo común a ambas: `love.graphics`
  (draw, rectangle, circle, ellipse, line, polygon, print/printf, setColor,
  setBlendMode "alpha"/"add", push/pop/translate/scale, newQuad, newImage,
  SpriteBatch), `love.timer.getTime()`, `love.math.random`, `love.filesystem`.
- **Sin shaders, sin canvas, sin gradientes, sin setLineDash**. Lo que en JS era
  `createRadialGradient` o `ctx.filter` se sustituye por formas simples o se omite.
- **Consola de 268 MHz y ~64 MB**: nada de crear tablas/closures/strings en bucles
  por fotograma; reutilizar tablas; borrar de listas con swap-remove (`t[i] = t[#t]; t[#t] = nil`)
  cuando el orden no importa; topes de entidades más bajos que en la web.
- Dos pantallas: **superior 400x240 = el mundo**; **inferior 320x240 táctil = la
  interfaz** (menús, HUD, cartas de nivel). Los módulos de juego NO dibujan interfaz:
  solo mundo. `love.draw(screen)` se llama una vez por pantalla; `screen == "bottom"`
  es la inferior; cualquier otro valor es la superior.

## 2. Estructura de ficheros

```
game/main.lua            arranque, bucle, callbacks, reparto por pantallas (lo hace el integrador)
game/src/util.lua        G.U (helpers)                          [hecho]
game/src/sprites.lua     G.Sprites (atlas + Animator)           [hecho]
game/src/camera.lua      G.Camera                               [hecho]
game/src/<modulo>.lua    un fichero por módulo JS, mismo nombre en minúsculas
game/data/*.lua          datos generados (pokedex, dexmeta, pkmn/<dex>.lua, tilesets, vfx)
game/img/*.png           imágenes (en consola build.ps1 las convierte a .t3x)
```

Cada módulo Lua es un fichero que **asigna su tabla en el global `G`** y no
devuelve nada (igual que el JS asigna `G.X = ...`). Se cargan con `require("src.world")`
desde `main.lua` en el orden correcto. Dentro del módulo se usan locals para todo lo
privado. Ejemplo:

```lua
-- src/hazards.lua
local U = G.U
local list = {}
G.Hazards = {}
function G.Hazards.add(h) ... end
function G.Hazards.update(dt) ... end
```

Los getters de JS (`get count() {...}`) pasan a funciones: `G.Hazards.count()`.

## 3. Helpers disponibles (G.U, src/util.lua)

```lua
G.LIFT = 18
U.clamp(v,a,b)  U.lerp(a,b,t)  U.rand(a,b)  U.randInt(a,b)  U.pick(arr)  U.pickN(arr,n)
U.dist(ax,ay,bx,by)  U.dist2(...)  U.norm(x,y) -> nx, ny (DOS valores, no tabla)
U.damp(a,b,rate,dt)  U.hash(x,y,seed) -> [0,1)  U.mmss(s)
U.hypot(x,y)  U.sign(x)  U.round(x)
U.TYPE_COLOR[type] -> string "#rrggbb"   U.TYPE_NAME[type] -> "Fuego"
U.rgb("#rrggbb") -> r,g,b en 0..1 (cacheado; usar siempre esto, nunca parsear a mano)
U.setColor(hex, alpha)  -- love.graphics.setColor con un hex y alfa opcional
U.hexMix(h1, h2, t) -> hex
U.shuffle(arr)  U.removeSwap(arr, i)  U.indexOf(arr, v)  U.remove(arr, v)
U.now() -> segundos (love.timer.getTime())
U.contains(arr, v)  -- arr.includes
U.keys(t)  U.values(t)  U.count(t)
```

`Set` de JS → tabla `{[id]=true}`; `Map` → tabla normal; `arr.filter/map/some/find`
→ bucles explícitos (sin closures en código por fotograma).

## 4. Cámara (G.Camera, src/camera.lua)

Las **unidades de mundo son las mismas que en la web** (todas las velocidades,
radios y alcances del JS se copian tal cual). La pantalla superior muestra
**800x480 unidades** (`G.Camera.w = 800, G.Camera.h = 480`) con `G.Camera.scale = 0.5`:
un píxel de arte (PX = 2 unidades) = 1 píxel de pantalla.

```lua
G.Camera.x, .y, .w, .h, .scale, .shake
G.Camera.follow(tx, ty, dt)   G.Camera.kick(amount)
G.Camera.left()  G.Camera.top()  G.Camera.sees(x, y, pad)  G.Camera.outerRadius()
G.Camera.apply()   -- love.graphics.push + scale + translate (el integrador lo llama)
G.Camera.unapply() -- pop
```

## 5. Sprites (G.Sprites, src/sprites.lua)

Misma API que `js/core/sprites.js` salvo lo indicado:

```lua
G.Sprites.PX = 2
G.Sprites.meta(dex)          -> {s=shadow, hv=flota, sh=tiene shiny, iw, iay, full} o nil
G.Sprites.hovers(dex)  G.Sprites.hasShiny(dex)
G.Sprites.animMeta(dex, anim) -> {w,h,n,d={...},ax,ay} (o nil)
G.Sprites.animName(dex, anim) -> nombre real (con respaldo Idle/Walk)
G.Sprites.bodyRadius(dex, scale)  G.Sprites.bodyHeight(dex, scale)
G.Sprites.drawShadow(dex, x, y, scale)
G.Sprites.dirFromAngle(a) -> 0..7
G.Sprites.preload(dexes, full)   -- carga ya las hojas (full = con animaciones de ataque)
G.Sprites.gc(keepDexes)          -- descarga las hojas que no estén en keepDexes
G.Sprites.Animator.new(dex, scale, shiny) -> anim
anim.dir (0..7)   anim:loop(name, speed)   anim:play(name, {speed=, hold=})
anim:busy()  anim:progress()  anim:update(dt)  anim:draw(x, y, {flash=, alpha=, color=})
anim:restart(name)  -- equivale a _start(name, false)
```

Solo hay 5 filas de dirección en el atlas (Down, DownRight, Right, UpRight, Up); las
tres izquierdas se dibujan volteadas. Los enemigos solo tienen Idle y Walk (`full=false`):
`play("Attack")` etc. recae en Idle sin error. El compañero del jugador se carga con
`full=true` si existe su atlas completo.

## 6. Dibujo: equivalencias JS → Lua

| JS (Canvas) | Lua |
|---|---|
| `ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x,y,r,0,6.28); ctx.fill()` | `U.setColor(col); love.graphics.circle("fill", x, y, r)` |
| `ctx.ellipse(x,y,rx,ry,...)` fill/stroke | `love.graphics.ellipse("fill"/"line", x, y, rx, ry)` |
| `ctx.fillRect(x,y,w,h)` | `love.graphics.rectangle("fill", x, y, w, h)` |
| `ctx.globalAlpha = a` | pasar `a` como alfa en `U.setColor(col, a)` |
| `ctx.lineWidth = n` | `love.graphics.setLineWidth(n)` |
| `ctx.save()/restore()` | no hace falta si se restaura color/alfa/blend al salir |
| `ctx.setLineDash` | omitir (línea normal) |
| `ctx.drawImage(img, sx,sy,sw,sh, dx,dy,dw,dh)` | `love.graphics.draw(img, quad, dx, dy, 0, dw/sw, dh/sh)` |
| `ctx.translate/rotate` | `love.graphics.push(); translate; rotate; ...; pop()` |
| `ctx.font = ...; fillText` | `love.graphics.print(text, x, y)` (fuente por defecto) |
| `performance.now()/1000` | `U.now()` |
| `Math.random()` | `love.math.random()` |
| `Math.hypot` | `U.hypot` |
| `arr.length` | `#arr` |

Siempre terminar un bloque de dibujo con `love.graphics.setColor(1,1,1,1)` y, si se
cambió, `setBlendMode("alpha")` / `setLineWidth(1)`.

Las coordenadas de mundo se usan tal cual dentro de `G.Camera.apply()`.

## 7. Módulos que NO existen en la consola (y qué hacer)

- `G.Coop.*`, `G.Social`, `G.Ranking`, `G.Net`, `G.Guard`, `G.Settings`: **no se
  portan**. Quitar todas las ramas de cooperativo. `G.Settings.get('calm')` → `false`.
- `G.Audio.sfx(name, opts)` y `G.Audio.music(name)`: existen como stubs en
  `src/audio.lua` (no-op de momento). Llamarlas igual que en el JS.
- `G.Icons.draw(name, x, y, size)`: existe en `src/icons.lua` (de momento dibuja un
  cuadrado del color del tipo/nombre). Llamarla igual.
- `G.UI`, `G.RunUI`, `G.HUD`, `G.MenuUI`, DOM, `document`, `G.Touch`: no existen. La
  interfaz la hace el integrador en la pantalla inferior (`src/ui/*.lua`). Los módulos
  de juego exponen DATOS (p. ej. `G.Spawner.banner()`), nunca dibujan interfaz.
- `G.Game`: lo hace el integrador. Los módulos pueden usar `G.Game.player()`,
  `G.Game.time()`, `G.Game.levelXp()`, `G.Game.offerItem(id)`, `G.Game.onShinyCaught(e)`,
  `G.Game.onRescue(dex, name)`, `G.Game.flash(col, dur)`, `G.Game.state()`.
- `G.DB`: partida guardada, en `src/db.lua` (ver §9). `G.DB.save` es la tabla de la
  partida, `G.DB.commit()` la escribe a disco.

## 8. Datos (game/data/*.lua)

- `G.DEX` (array de Pokémon, mismos campos que pokedex.js: dex, name, types, hp, spd,
  atk, rarity, bst, starter, gen, leg) y `G.DEX_BY[dex]`.
- `G.STARTERS`, `G.STARTER_BY`, `G.startMoveOf(dex)`, `G.TRAIT_TEXT`, `G.PERSONALITY_TEST`,
  `G.personalityResult(scores)`.
- `G.Moves`, `G.Types`, `G.Items`, `G.Upgrades`, `G.Enemies`, `G.MissionDefs`, `G.AchDefs`:
  misma API que sus `.js`. Las funciones `on/off/apply/value/text/match` de los datos
  se portan como funciones Lua dentro de las tablas.
- `G.Sprites` carga sus propios datos (`data/dexmeta.lua`, `data/pkmn/<dex>.lua`).

## 9. Partida guardada (G.DB)

Tabla `G.DB.save` con los campos de `newSave()` de db.js (sin nube): `coins`, `owned`
(`[dex]={at=,from=}`), `shiny`, `partner`, `partnerShiny`, `starter`, `personality`,
`upgrades` (`[dex] = {hp=n,...}`), `pity`, `tickets={t1=,t10=}`, `ach`, `missions`,
`profile`, `stats={runs,bestTime,bestLevel,totalKills,pulls,coinsEarned,shinies,
bossesTotal,riftWins,evolutions,missionsDone}`, `legends`, `arenas`, `itemsFound`,
`evoMoves`. API: `G.DB.load()`, `G.DB.newSave()`, `G.DB.commit()`, `G.DB.owns(dex)`,
`G.DB.grant(dex, from)`, `G.DB.ownsShiny(dex)`, `G.DB.grantShiny(dex, from) -> isNew`,
`G.DB.upgradesOf(dex)`. Se guarda como JSON con `src/json.lua` (encode/decode).

## 10. Rendimiento: topes para la 3DS

| Cosa | Web | 3DS |
|---|---|---|
| Enemigos a la vez (`G.Spawner.CAP`) | 64 | 40 |
| Elenco por tramo (`cast`) | 7 | 5 |
| Pickups (`MAX`) | 420 | 160 |
| Partículas FX | sin tope | 150 |
| Números de daño | 70 | 24 |
| Cadáveres | 120 | 30 |
| Chunks de datos en caché | 400 | 120 |

Los cálculos por fotograma deben ser O(entidades), con rejilla espacial como en la web.

## 11. Entidades: campos obligatorios

**Jugador** (`G.Player.new(mon, perks, shiny)`): `x, y, r, bodyH, dex, mon, anim, hp,
maxHp, dead, invuln, flash, aim, moveAngle, walking, target, atkMul, spdMul, cdMul,
dmgReduce, regenFlat, magnet, xpMul, coinMul, level, xp, xpNext, kills, bosses, coins,
t1, t10, dmgDealt, moves, slots, active, maxMoves, bonds, buffs, item, statsTaken,
power, slowT, inLiquid`. Métodos: `atk(), spd(), reduction(), regen()` (son FUNCIONES
en Lua, no getters), `addMove, hasMove, setActive, cycle, bondOptions, fuse,
activeGroup, activeMove, cast, hurt, heal, addMaxHp, gainXp, hasItem, equip, onDealt,
addPower, addBuff, update(dt), revive, draw()`. `cy()` devuelve `y`.

**Enemigo** (`G.Enemy.new(def, x, y, sc, boss)`): `id, def, dex, name, x, y, boss,
scale, anim, r, bodyH, maxHp, hp, spd, dmg, xp, behavior, types, atkType, flying,
flash, slow, burn, poison, kx, ky, touchCd, dead, fade, phase, shiny, shield,
minions, jump, legend, golden`. Métodos: `makeShiny, makeGolden, hurt(amount, color,
dirX, dirY, knock, eff), applySlow, applyBurn, applyPoison, die, update(dt, pl),
strike(pl), draw(), cy()`. Gestor `G.EnemyMgr`: `clear, all, add, get, stash,
restore, update(dt, pl), drawables(cam), queryCircle(x,y,r), rebuildGrid, bossAlive,
shinies, count()`.

**Proyectil** (`G.Projectiles.spawn(o)`): campos como en projectile.js; `hits` y
`phits` son tablas `{[id]=true}`; `hitLog` tabla `[id]=tiempo`.

## 12. Nombres de ficheros Lua y quién los hace

| JS | Lua | Lote |
|---|---|---|
| data/pokedex.js, sprites-meta.js | data/pokedex.lua, data/dexmeta.lua, data/pkmn/*.lua | generados (hecho por tools/) |
| data/starters.js, moves.js, types.js, items.js, upgrades.js, enemies.js, missions.js, achievements.js | src/starters.lua, src/moves.lua, src/types.lua, src/items.lua, src/upgrades.lua, src/enemies.lua, src/missions.lua, src/achievements.lua | A |
| world/tiles.js (pintado) + vfx.js (formas) + icons.js | tools/gen_tiles.py, tools/gen_vfx.py, tools/gen_icons.py → img/tiles/<bioma>.png + data/tiles.lua, img/vfx.png + data/vfx.lua, img/icons.png + data/icons.lua | B |
| world/world.js, systems/pathing.js | src/world.lua, src/pathing.lua | C |
| entities/fx.js, vfx.js (dibujo), projectile.js, pickup.js, systems/hazards.js | src/fx.lua, src/vfx.lua, src/projectile.lua, src/pickup.lua, src/hazards.lua | D1 |
| entities/player.js, enemy.js, systems/combat.js, spawner.js, levelup.js | src/player.lua, src/enemy.lua, src/combat.lua, src/spawner.lua, src/levelup.lua | D2 |
| systems/weather.js, interact.js, rift.js, events.js, gacha.js, progress.js, core/db.js | src/weather.lua, src/interact.lua, src/rift.lua, src/events.lua, src/gacha.lua, src/progress.lua, src/db.lua, src/json.lua | E |
| game.js, ui/* | main.lua, src/game.lua, src/ui/*.lua | integrador |

## 13. Contrato de los atlas generados por B

**Tiles** (`img/tiles/<bi>.png`, `bi` = índice de bioma 0..20 como en tiles.js) y
`data/tiles.lua` que devuelve `{ T = 16, quads = { [bi] = { nombre = {x, y, w, h}, ... } } }`:

- `floor_0 .. floor_5`: suelo (6 variantes), 16x16.
- `dirt_<m>` m = 0..15: tierra con autotile de 4 vecinos (bit 1 = N, 2 = E, 4 = S, 8 = O
  indica que el vecino TAMBIÉN es tierra), 16x16, con transparencia en los bordes.
- `wall_<m>` m = 0..15: pared, mismo convenio de bits (vecino también pared). La cara
  frontal (6 px) va dentro del tile como en tiles.js.
- `liquid_<m>` m = 0..255: líquido con 8 vecinos (bits 1 N, 2 NE, 4 E, 8 SE, 16 S,
  32 SO, 64 O, 128 NO; vecino también líquido). Solo se generan las 47 combinaciones
  canónicas: una diagonal cuenta solo si sus dos ortogonales están; `data/tiles.lua`
  trae `liquidKey(m) -> m canónico`.
- Props: `prop_<tipo>_<variante>` con tipos tree, rock(0,1), chest, grass(0,1),
  altar(0..7), spring(0,1), bigchest, trap(0..2), rift(0..3). Anclaje: centro
  inferior (el integrador dibuja con `ox = w/2, oy = h`).

**VFX** (`img/vfx.png`, `data/vfx.lua`): cada forma de vfx.js en escala de grises
(4 tonos) para teñirla con `U.setColor(U.TYPE_COLOR[type])`; `{ quads = { nombre_f = {x,y,w,h} } }`
con fotogramas `_0, _1...` cuando los haya, y una tabla `shapes = { nombre = {frames=n, dir=bool, spin=bool} }`.

**Iconos** (`img/icons.png`, `data/icons.lua`): `{ quads = { nombre = {x,y,w,h} } }`
con los iconos de icons.js a 12 px (los `move:<id>` se componen con `type_<t>` + `fam_<kind>`).

## 14. Pruebas

`tools\smoke-test.ps1` arranca el juego en PC 90 fotogramas y falla si hay error de
Lua. Cada lote debe dejar su módulo cargable con `require` sin error y sin usar
variables globales que no sean `G` y `love`.
