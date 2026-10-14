-- PokéSurvivor 3DS - punto de entrada.
--
-- Reglas de pantallas (ver también docs/PORT.md y la skill 3ds-lovepotion):
--   * love.draw(screen) se llama UNA VEZ POR PANTALLA cada frame.
--   * screen == "bottom"            -> pantalla inferior (320x240, táctil): interfaz.
--   * cualquier otro valor          -> pantalla superior (400x240): el mundo.
--       "top" cuando el 3D está apagado, "left"/"right" cuando está encendido.
--   * El estado del juego se actualiza en love.update, NUNCA dentro de love.draw.

-- Prueba de humo: `love game --smoke` cierra solo tras unos frames (SMOKE_OK) o
-- imprime el error de Lua y sale con código 1. Va ANTES de nest para capturar todo.
local smokeFrames = nil
local soakSeconds = nil      -- `--soak=N`: N segundos de partida automática acelerada
local soakStage = nil        -- `--stage=N` junto a --soak: en esa fase
local startLevel = nil       -- `--level=N`: nivel inicial del jugador (prueba de evolución)
for _, a in ipairs(arg or {}) do
    if a == "--smoke" then smokeFrames = 150 end
    local n = a:match("^%-%-soak=(%d+)$")
    if n then soakSeconds = tonumber(n); smokeFrames = 1e9 end
    local st = a:match("^%-%-stage=(%d+)$")
    if st then soakStage = tonumber(st) end
    local lv = a:match("^%-%-level=(%d+)$")
    if lv then startLevel = tonumber(lv) end
end
local startTime = nil        -- `--time=N`: reloj de la run al empezar
for _, a in ipairs(arg or {}) do
    local tm = a:match("^%-%-time=(%d+)$")
    if tm then startTime = tonumber(tm) end
    if a == "--steps" then G_PRINT_STEPS = true; io.stdout:setvbuf("no") end   -- imprime los pasos G_STEP (el rastro de la 3DS)
end
-- Traza a fichero (solo en modo smoke): si el proceso se cuelga, dice hasta dónde llegó.
local traceName = "smoke-trace.txt"          -- `--tag=X`: smoke-trace-X.txt (pruebas en paralelo)
for _, a in ipairs(arg or {}) do
    local tg = a:match("^%-%-tag=([%w_%-]+)$")
    if tg then traceName = "smoke-trace-" .. tg .. ".txt" end
end
local function trace(s)
    if IS_CONSOLE_TRACE and G_STEP then G_STEP(s) end
    if not smokeFrames then return end
    local f = io.open((love.filesystem.getSourceBaseDirectory and love.filesystem.getSourceBaseDirectory() or ".") .. "/build/" .. traceName, "a")
    if f then f:write(os.date("%H:%M:%S ") .. tostring(s) .. "\n") f:close() end
end
if smokeFrames then
    io.stdout:setvbuf("no")
    trace("inicio")
    function love.errorhandler(msg)
        print("SMOKE_ERROR: " .. tostring(msg))
        print(debug.traceback())
        trace("ERROR " .. tostring(msg) .. "\n" .. debug.traceback())
        os.exit(1)
    end
end
G_TRACE = trace

-- En la 3DS un error de Lua puede cerrar la aplicación y volver al HOME sin mostrar
-- nada. Por eso, en consola, cada error (con su traza, la versión de Lua y los
-- últimos pasos anotados con G_STEP) se escribe en sdmc:/pokesurvivor-error.txt.
local IS_CONSOLE = love._potion_version ~= nil
    or (love.system and love.system.getOS and love.system.getOS() == "Horizon")
local steps = {}
-- En consola cada paso se escribe YA en sdmc:/pokesurvivor-trace.txt (abrir, escribir,
-- cerrar): si el cierre no es un error de Lua (no hay manejador que valga), la
-- última línea del fichero dice qué se estaba haciendo.
local traceFile = "sdmc:/pokesurvivor-trace.txt"
function G_STEP(s)
    steps[#steps + 1] = tostring(s)
    if #steps > 40 then table.remove(steps, 1) end
    if G_PRINT_STEPS then print("PASO " .. tostring(s)) end
    if IS_CONSOLE_TRACE then
        local f = io.open(traceFile, "a")
        if f then f:write(string.format("%.2f [lua %dKB] %s\n", love.timer and love.timer.getTime() or 0, collectgarbage("count"), tostring(s))); f:close() end
    end
end
local function writeConsoleError(msg, tb)
    local f = io.open("sdmc:/pokesurvivor-error.txt", "a")
    if not f then return end
    f:write("==== " .. os.date("%Y-%m-%d %H:%M:%S") .. " · " .. tostring(_VERSION)
        .. (jit and (" · " .. tostring(jit.version)) or "")
        .. " · LÖVE Potion " .. tostring(love._potion_version) .. "\n")
    f:write("ERROR: " .. tostring(msg) .. "\n" .. tostring(tb) .. "\n")
    f:write("Últimos pasos:\n  " .. table.concat(steps, "\n  ") .. "\n\n")
    f:close()
end
IS_CONSOLE_TRACE = IS_CONSOLE and not smokeFrames
if IS_CONSOLE_TRACE then
    local f = io.open(traceFile, "w")
    if f then
        f:write("==== arranque " .. os.date("%Y-%m-%d %H:%M:%S") .. " · " .. tostring(_VERSION)
            .. (jit and (" · " .. tostring(jit.version)) or "") .. " · LÖVE Potion " .. tostring(love._potion_version) .. "\n")
        f:close()
    end
end
if IS_CONSOLE and not smokeFrames then
    local defaultHandler = love.errorhandler or love.errhand
    function love.errorhandler(msg)
        pcall(writeConsoleError, msg, debug.traceback("", 2))
        if defaultHandler then return defaultHandler(msg) end
    end
end

-- Formas seguras. En el PC, LÖVE corrige solo las formas imposibles; en la 3DS
-- (LÖVE Potion / citro2d) un rectángulo con esquinas más grandes que la mitad de su
-- lado, o una forma de tamaño cero o negativo, puede colgar la consola. Se recortan
-- las esquinas y no se dibuja nada de tamaño <= 0.
--
-- Presupuesto de vértices. LÖVE Potion 3.0 (renderer_ext.cpp) mete todo lo de un
-- fotograma —las dos pantallas— en UN búfer de 6 * 0x1000 = 24.576 vértices y lo
-- copia con memcpy SIN comprobar el límite: si un fotograma se pasa, pisa otra
-- memoria y la consola cae más tarde en cualquier sitio (data abort). Se lleva la
-- cuenta (imagen 4, letra 6, rectángulo 4, redondeado/círculo según sus puntos,
-- como en graphics.tcc) y, cerca del tope, se deja de dibujar en ese fotograma.
-- G_VERTS se pone a 0 en love.update (una vez por fotograma).
VERT_LIMIT = 22000
G_VERTS, G_VERTS_MAX, G_VERTS_SKIPPED = 0, 0, 0
do
    local lg = love.graphics
    local rect, circ, ell, arc = lg.rectangle, lg.circle, lg.ellipse, lg.arc
    local draw, print_, printf, poly, line = lg.draw, lg.print, lg.printf, lg.polygon, lg.line
    local min, max, sqrt, floor = math.min, math.max, math.sqrt, math.floor
    -- Suma n vértices; false si ya no caben (y entonces no se dibuja).
    local function spend(n)
        local v = G_VERTS + n
        if v > VERT_LIMIT then G_VERTS_SKIPPED = G_VERTS_SKIPPED + 1; return false end
        G_VERTS = v
        if v > G_VERTS_MAX then G_VERTS_MAX = v end
        return true
    end
    G_VERT_SPEND = spend
    local function ellPts(rx, ry) return max(sqrt((rx + ry) / 2 * 20), 8) end
    lg.rectangle = function(mode, x, y, w, h, rx, ry, seg)
        G_DRAWN = (G_DRAWN or 0) + 1
        if not w or not h or w <= 0 or h <= 0 or w ~= w or h ~= h then return end
        local line_ = mode == "line"
        if rx then
            local m = min(w, h) / 2
            rx = min(rx, m)
            ry = min(ry or rx, m)
            if rx >= 1 and ry >= 1 then
                local pc = (max(floor(ellPts(rx, ry) / 4), 1) + 2) * 4 + 1
                if not spend(line_ and pc * 6 or pc) then return end
                return rect(mode, x, y, w, h, rx, ry, seg)
            end
        end
        if not spend(line_ and 30 or 4) then return end
        return rect(mode, x, y, w, h)
    end
    lg.circle = function(mode, x, y, r, seg)
        if not r or r <= 0 or r ~= r then return end
        local pc = (seg or ellPts(r, r)) + 2
        if not spend(mode == "line" and pc * 6 or pc) then return end
        return circ(mode, x, y, r, seg)
    end
    lg.ellipse = function(mode, x, y, rx, ry, seg)
        if not rx or not ry or rx <= 0 or ry <= 0 or rx ~= rx or ry ~= ry then return end
        local pc = (seg or ellPts(rx, ry)) + 2
        if not spend(mode == "line" and pc * 6 or pc) then return end
        return ell(mode, x, y, rx, ry, seg)
    end
    lg.arc = function(mode, a, b, c, d, e, f, g)
        -- arc(mode, [arctype,] x, y, radius, angle1, angle2, segments)
        local r = type(a) == "string" and d or c
        if not r or r <= 0 or r ~= r then return end
        local pc = ellPts(r, r) + 3
        if not spend(mode == "line" and pc * 6 or pc) then return end
        return arc(mode, a, b, c, d, e, f, g)
    end
    lg.draw = function(obj, ...)
        if not spend(4) then return end
        return draw(obj, ...)
    end
    local function textVerts(s)
        if type(s) == "string" then return #s * 6 end
        if type(s) == "table" then
            local n = 0
            for i = 2, #s, 2 do if type(s[i]) == "string" then n = n + #s[i] end end
            return n * 6
        end
        return #tostring(s) * 6
    end
    lg.print = function(s, ...)
        if not spend(textVerts(s)) then return end
        return print_(s, ...)
    end
    lg.printf = function(s, ...)
        if not spend(textVerts(s)) then return end
        return printf(s, ...)
    end
    lg.polygon = function(mode, ...)
        local n = select("#", ...)
        if n == 1 then n = #(...) end
        if not spend(mode == "line" and n * 6 or n / 2 + 1) then return end
        return poly(mode, ...)
    end
    lg.line = function(...)
        local n = select("#", ...)
        if n == 1 then n = #(...) end
        if not spend(n * 6) then return end
        return line(...)
    end
end

-- nest: en PC simula las dos pantallas de la 3DS. En consola no hace nada.
local nestScale = 2
for _, a in ipairs(arg or {}) do
    if a == "--scale1" then nestScale = 1 end
end
local ok, nest = pcall(require, "nest")
if ok and nest and nest.init then
    nest.init({ console = "3ds", scale = nestScale })
elseif not ok then
    print("nest no disponible: " .. tostring(nest))
end

G = {}

-- Orden de carga: cimientos, datos, mundo, entidades, sistemas, interfaz.
require("src.util")
require("src.audio")
require("src.icons")
require("src.camera")
require("src.sprites")
require("src.input")
require("src.dex")
require("src.types")
require("src.items")
require("src.upgrades")
require("src.starters")
require("src.moves")
require("src.enemies")
require("src.missions")
require("src.achievements")
require("src.json")
require("src.db")
G.Tiles = require("data.tiles")
require("src.world")
require("src.pathing")
require("src.vfx")
require("src.fx")
require("src.projectile")
require("src.pickup")
require("src.hazards")
require("src.player")
require("src.enemy")
require("src.combat")
require("src.spawner")
require("src.levelup")
require("src.weather")
require("src.interact")
require("src.rift")
require("src.judgment")
require("src.events")
require("src.gacha")
require("src.progress")
require("src.evolution")
require("src.stages")
require("src.difficulty")
require("src.burst")
require("src.game")
require("src.ui.ui")
require("src.ui.pixelfont")
require("src.ui.top")
require("src.ui.run")
require("src.ui.test")
require("src.ui.menu")

local Input = G.Input

G_FIRSTDRAW = {}
local function isTop(screen)
    return screen ~= "bottom"
end

trace("modulos cargados")

function love.load()
    if love.graphics.setDefaultFilter then pcall(love.graphics.setDefaultFilter, "nearest", "nearest") end
    trace("love.load")
    love.graphics.setBackgroundColor(0.04, 0.08, 0.19)
    Input.load()
    trace("input.load")
    G.UI.load()
    trace("ui.load")
    G.Icons.load()
    trace("icons.load")
    G.Flow.boot()
    trace("boot")
    if G_BAKE_BG then
        G_BAKING = true
        local cv = love.graphics.newCanvas(G.UI.W, G.UI.H)
        love.graphics.setCanvas(cv)
        love.graphics.clear(0, 0, 0, 0)
        G.RunUI.platinumBackground(0)
        love.graphics.setCanvas()
        love.filesystem.createDirectory("img/ui")
        cv:newImageData():encode("png", "img/ui/platbg.png")
        print("BAKE_OK " .. love.filesystem.getSaveDirectory() .. "/img/ui/platbg.png")
        love.event.quit()
        G_BAKING = false
        return
    end
    if G.Audio.preload then pcall(G.Audio.preload) end
    -- `love game --run`: empieza una partida directamente (capturas y depuración).
    -- `love game --ui=<pantalla>`: abre esa pantalla de la interfaz (menu, dex, gacha, test...).
    for _, a in ipairs(arg or {}) do
        if a == "--run" then G.Flow.debugStartRun() end
        local st = a:match("^%-%-stage=(%d+)$")
        if st and not soakSeconds then G.Flow.debugStartRun(tonumber(st)) end
        if startLevel and not soakSeconds then G.Game.debugSetLevel(startLevel) end
        if startTime and not soakSeconds then G.Game.debugTime(startTime) end
        if a == "--levelup" then G.Game.debugLevelUp() end
        if a == "--die" then G.Game.debugDie() end
        if a == "--killbosses" then G.Game.autoKillBosses = true end
        -- `--liqtest`: ¿quién puede pisar agua (bosque) y lava (volcán)?
        if a == "--liqtest" then
            G.Flow.debugStartRun()
            local W = G.World
            for _, b in ipairs({ 0, 2 }) do
                W.setBiome(b, true)
                local lx, ly
                for r = 4, 120 do
                    for k = 0, 63 do
                        local x, y = math.cos(k / 64 * 6.2832) * r * 32, math.sin(k / 64 * 6.2832) * r * 32
                        x, y = math.floor(x / 32) * 32 + 16, math.floor(y / 32) * 32 + 16
                        if W.isLiquid(x, y) and W.isLiquid(x + 32, y) and W.isLiquid(x - 32, y)
                           and W.isLiquid(x, y + 32) and W.isLiquid(x, y - 32) then lx, ly = x, y break end
                    end
                    if lx then break end
                end
                for _, tl in ipairs({ { "fire" }, { "electric" }, { "normal", "flying" }, { "fire", "flying" } }) do
                    local ty = table.concat(tl, "/")
                    local e = { x = lx, y = ly, r = 10, types = tl }
                    W.collide(e)
                    local moved = math.abs(e.x - lx) + math.abs(e.y - ly) > 0.5
                    print(string.format("LIQTEST %s %s: %s", W.biomeName(), ty, moved and "BLOQUEADO" or "PASA"))
                end
            end
            love.event.quit()
        end
        if a == "--treetest" then
            G.Flow.debugStartRun()
            for b = 0, 20 do
                G.World.setBiome(b, true)
                print("TREETEST " .. b .. " " .. G.World.biomeName() .. ": " .. G.World.debugTreeTest(12))
            end
            love.event.quit()
        end
        -- `--inwater`: pone al jugador en medio del agua más cercana (ver reflejos).
        if a == "--inwater" and G.Game.player() then
            local pl, W = G.Game.player(), G.World
            for r = 4, 80 do
                local done = false
                for k = 0, 63 do
                    local ang = k / 64 * 6.2832
                    local x, y = math.cos(ang) * r * 32, math.sin(ang) * r * 32
                    if W.isLiquid(x, y) and W.isLiquid(x + 40, y) and W.isLiquid(x - 40, y) and W.isLiquid(x, y + 48) then
                        pl.x, pl.y = x, y; done = true
                        G.Camera.x, G.Camera.y = x, y     -- (puede estar en pausa por las cartas)
                        break
                    end
                end
                if done then break end
            end
        end
        -- `--moves=id,id`: añade esos movimientos (para ver la botonera con nombres largos).
        local mv = a:match("^%-%-moves=(.+)$")
        if mv and G.Game.player() then
            for id in mv:gmatch("[^,]+") do G.Game.player():addMove(id) end
        end
        if a == "--shiny" then G.Spawner.debugForceShiny(6) end
        -- `--card=fondo,entrenador`: elige estilo de la tarjeta (ids de data/cardstyle.lua).
        local cb, ct = a:match("^%-%-card=(%d+),(%d+)$")
        if cb then
            local s = G.DB.save
            s.profile = s.profile or { favs = {}, title = "" }
            s.profile.cardBg, s.profile.trainer = tonumber(cb), tonumber(ct)
            s.profile.favs = { 1, 4, 7, 133, 143 }
        end
        -- `--medals=N`: da las N primeras medallas (para ver las Poké Balls de la tarjeta).
        local nm = tonumber(a:match("^%-%-medals=(%d+)$") or "")
        if nm then
            local s = G.DB.save
            s.ach = s.ach or {}
            for i, ad in ipairs(G.AchDefs.LIST) do if i <= nm then s.ach[ad.id] = s.ach[ad.id] or 1 end end
        end
        local name = a:match("^%-%-ui=(%w+)$")
        if name then
            local s = G.DB.save
            if not s.partner then s.partner = 25; G.DB.grant(25, "debug") end
            if name == "test" then G.TestUI.start() else G.UI.show(name) end
        end
    end
end

local soakStarted = false
local demo = false

-- `--tour`: recorre solo todas las pantallas (para enseñarlas o revisarlas) y guarda
-- una captura de cada una en la carpeta de guardado (tour_NN_nombre.png).
local tour = nil
for _, a in ipairs(arg or {}) do
    if a == "--tour" then
        local UI = function(n) return function() G.UI.show(n) end end
        tour = { i = 0, t = 0, steps = {
            { "titulo", 3, UI("title") },
            { "menu", 4, UI("menu") },
            { "pokedex", 4, UI("dex") },
            { "tarjeta", 4, UI("card") },
            { "mejoras", 4, UI("upgrades") },
            { "gacha", 4, UI("gacha") },
            { "misiones", 4, UI("goals") },
            { "fases", 4, UI("stages") },
            { "inicial", 4, UI("starters") },
            { "partida", 7, function() G.UI.show("menu"); G.Flow.debugStartRun() end },
            { "subida_nivel", 4, function() G.Game.debugLevelUp() end },
            { "pausa", 4, function()
                if G.UI.current() == "cards" then G.UI.pressButton("a") end
                G.Game.togglePause() end },
            { "derrota", 5, function() G.Game.togglePause(); G.Game.debugDie() end },
            { "menu_final", 4, function() G.Flow.goMenu() end },
        } }
    end
end
-- `--newgame`: lo que hace un jugador nuevo: cuestionario (primera respuesta de
-- cada pregunta), "¡Vamos juntos!", menú y Jugar. Para cazar fallos con partida vacía.
for _, a in ipairs(arg or {}) do
    if a == "--newgame" then
        local P = function(b) return function() G.UI.pressButton(b) end end
        local steps = { { "test", 2, function() G.UI.show("test") end } }
        for q = 1, #(G.PERSONALITY_TEST or {}) do
            steps[#steps + 1] = { "pregunta" .. q, 0.4, function() G.UI.pressButton("dpdown"); G.UI.pressButton("a") end }
        end
        steps[#steps + 1] = { "resultado", 2, P("a") }
        steps[#steps + 1] = { "menu", 2, function() end }
        steps[#steps + 1] = { "jugar", 12, P("a") }
        steps[#steps + 1] = { "fin", 1, function() print("NEWGAME_OK estado=" .. tostring(G.Game.state())); love.event.quit() end }
        tour = { i = 0, t = 0, steps = steps }
    end
end
local function tourUpdate(dt)
    tour.t = tour.t - dt
    if tour.shotIn and tour.t <= tour.shotIn then
        tour.shotIn = nil
        local st = tour.steps[tour.i]
        love.graphics.captureScreenshot(string.format("tour_%02d_%s.png", tour.i, st[1]))
    end
    if tour.t > 0 then return end
    tour.i = tour.i + 1
    local st = tour.steps[tour.i]
    if not st then print("TOUR_OK"); tour = nil; return end
    print("TOUR " .. tour.i .. " " .. st[1])
    local ok, err = pcall(st[3])
    if not ok then print("TOUR_ERROR " .. st[1] .. ": " .. tostring(err)) end
    tour.t = st[2]
    tour.shotIn = st[2] - 1.6            -- captura a los 1,6 s de entrar
end
local shotAt, shotT = nil, 0     -- `--shot=N`: guarda shot.png en la carpeta de guardado a los N s y sale
for _, a in ipairs(arg or {}) do
    if a == "--demo" then demo = true end
    local s = a:match("^%-%-shot=(%d+)$")
    if s then shotAt = tonumber(s) end
end
local vertLogT = 0
-- Tiempos medidos en la consola (ms acumulados en la ventana de 10 s).
PERF = { upd = 0, top = 0, bot = 0, n = 0, worst = 0 }
function love.update(dt)
    G_VERTS = 0
    PERF.n = PERF.n + 1
    if dt > PERF.worst then PERF.worst = dt end
    -- Cada 10 s, al rastro: pico de vértices por fotograma, si se saltó dibujo y los FPS.
    vertLogT = vertLogT + dt
    if vertLogT >= 10 then
        vertLogT = 0
        if G_STEP then
            local n = math.max(1, PERF.n)
            local pl = G.Game.player and G.Game.player()
            G_STEP(string.format("rendimiento: %d fps | logica %.1f ms, arriba %.1f ms, abajo %.1f ms, peor fotograma %.0f ms | pico %d vertices, saltados %d | enemigos %d | hojas %d | pantalla %s",
                love.timer.getFPS(), PERF.upd * 1000 / n, PERF.top * 1000 / n, PERF.bot * 1000 / n, PERF.worst * 1000,
                G_VERTS_MAX, G_VERTS_SKIPPED, (pl and G.EnemyMgr.count()) or 0, G.Sprites.loadedCount(),
                tostring(G.UI.current and G.UI.current())))
            PERF.upd, PERF.top, PERF.bot, PERF.n, PERF.worst = 0, 0, 0, 0, 0
        end
        if G_COUNTDRAW then print("VERTICES pico=" .. G_VERTS_MAX .. " saltados=" .. G_VERTS_SKIPPED) end
        G_VERTS_MAX, G_VERTS_SKIPPED = 0, 0
    end
    if shotAt then
        shotT = shotT + dt
        if shotT >= shotAt and shotAt > 0 then
            shotAt = -1
            love.graphics.captureScreenshot("shot.png")
        elseif shotAt == -1 and shotT >= 0 then
            shotAt = -2; shotT = -0.5
        elseif shotAt == -2 and shotT >= 0 then
            love.event.quit()
        end
    end
    if tour then tourUpdate(dt) end
    if demo then
        -- Modo demostración: juega solo a velocidad normal; al caer, vuelve a empezar.
        if G.Game.state() == "ui" or G.Game.state() == "over" then
            if G.Game.state() == "over" then G.Flow.goMenu() end
            G.Game.demo = not G_PROF       -- perfilando: invulnerable, para medir siempre la partida
            G.Input.auto = true
            G.Flow.debugStartRun()
            if startLevel then G.Game.debugSetLevel(startLevel) end
        end
        G.Game.autoplay(dt)
    end
    if G_PROF and G.Game.state() == "playing" then
        if not G_PROF.on then
            G_PROF.on = true; G_PROF.t = 0
            G_PROF.install()
        end
        G_PROF.t = G_PROF.t + dt
        G_PROF.cnt["love.update"] = (G_PROF.cnt["love.update"] or 0) + 1
        if G_PROF.t > (G_PROF.secs or 60) then
            local ne = #G.EnemyMgr.all()
            print("enemigos al final: " .. ne .. "  fps medio PC sin JIT: " .. string.format("%.1f", G_PROF.cnt["love.update"] / G_PROF.t))
            G_PROF.report()
            love.event.quit()
            G_PROF.secs = 1e9
        end
    end
    if soakSeconds then
        -- Prueba de resistencia: 8 pasos de simulación por fotograma, jugador automático.
        local S = G_SOAK
        if not soakStarted then
            soakStarted = true; G.Input.auto = true
            S = { sim = 0, runs = 0, deaths = 0, wins = 0, maxStep = 0, stuck = 0, lastT = -1, uiT = 0, memMax = 0 }
            G_SOAK = S
            for _, a in ipairs(arg or {}) do
                if a == "--mortal" then S.mortal = true end
                if a == "--killbosses" then S.kill = true end
                local df = a:match("^%-%-difficulty=(%a+)$")
                if df then G.DB.save.difficulty = df end
                local pd = tonumber(a:match("^%-%-partner=(%d+)$") or "")
                if pd then G.DB.save.partner = pd; G.DB.grant(pd, "debug") end
            end
            S.start = function()
                S.runs = S.runs + 1
                G.Game.demo = S.mortal or false               -- mortal: sin invulnerabilidad
                G.Flow.debugStartRun(soakStage)
                if startLevel then G.Game.debugSetLevel(startLevel) end
                if startTime then G.Game.debugTime(startTime) end
                G.Game.autoKillBosses = S.kill or false
            end
            S.start()
        end
        for i = 1, 8 do
            local c0 = os.clock()
            G.Game.frame(1 / 30)
            G.UI.update(1 / 30)
            G.Game.autoplay(1 / 30)
            Input.endFrame()
            local ms = (os.clock() - c0) * 1000
            if ms > S.maxStep then S.maxStep = ms; S.maxAt = G.Game.time() end
            S.sim = S.sim + 1 / 30
        end
        local t = G.Game.time()
        local st = G.Game.state()
        -- Atascos: el reloj de la partida no avanza estando en juego, o una pantalla
        -- (cartas, pausa...) que no se cierra.
        if st == "playing" then
            if t <= S.lastT then S.stuck = S.stuck + 8 / 30 else S.stuck = 0 end
            S.uiT = 0
        else
            S.uiT = S.uiT + 8 / 30
        end
        S.lastT = t
        S.memMax = math.max(S.memMax, collectgarbage("count"))
        if S.stuck > 20 or S.uiT > 60 then
            print(string.format("SOAK_STUCK t=%.1f estado=%s ui=%s parado=%.0fs", t, tostring(st), tostring(G.UI.current()), math.max(S.stuck, S.uiT)))
            trace("ATASCO estado=" .. tostring(st) .. " ui=" .. tostring(G.UI.current()))
            os.exit(2)
        end
        if math.floor(S.sim) % 30 == 0 and math.floor(S.sim) ~= (G_SOAK_LAST or -1) then
            G_SOAK_LAST = math.floor(S.sim)
            trace(string.format("soak sim=%d run=%d t=%d nivel=" .. (G.Game.player() and G.Game.player().level or 0) .. " estado=%s enemigos=%d fx=%d proy=%d hojas=%d mem=%dKB", S.sim, S.runs, t, tostring(st),
                G.EnemyMgr.count(), G.FX.count and G.FX.count() or -1, G.Projectiles.count(), G.Sprites.loadedCount(), collectgarbage("count")))
        end
        if st == "over" then
            -- Fin de partida: en modo mortal se cuenta y se empieza otra (vuelta al menú).
            if G.Stages.cleared() then S.wins = S.wins + 1 else S.deaths = S.deaths + 1 end
            if S.deaths <= 3 and S.lastHurt then print(string.format("MUERTE run=%d t=%.0f %s", S.runs, t, S.lastHurt)) end
            if S.mortal and S.sim < soakSeconds then
                G.Flow.goMenu()
                S.lastT = -1
                S.start()
                return
            end
        end
        if S.sim >= soakSeconds or st == "over" then
            local plv = G.Game.player()
            print(string.format("SOAK_OK sim=%d t=%d runs=%d muertes=%d superadas=%d estado=%s nivel=%s forma=%s derrotados=%s paso_max=%.1fms(t=%d) mem=%dKB mem_max=%dKB",
                S.sim, t, S.runs, S.deaths, S.wins, tostring(st), plv and plv.level or "?", plv and (plv.form or 1) or "?", plv and plv.kills or "?",
                S.maxStep, S.maxAt or 0, collectgarbage("count"), S.memMax))
            print("SMOKE_OK")
            love.event.quit()
        end
        return
    end
    if smokeFrames then
        if smokeFrames % 30 == 0 then trace("update " .. smokeFrames .. " estado=" .. tostring(G.Game.state())) end
        smokeFrames = smokeFrames - 1
        if smokeFrames == 120 then G.Flow.debugStartRun() end
        if smokeFrames <= 0 then
            print("SMOKE_OK")
            love.event.quit()
        end
    end
    dt = math.min(1 / 30, dt)
    local tu = love.timer.getTime()
    G.Game.frame(dt)
    G.UI.update(dt)
    PERF.upd = PERF.upd + love.timer.getTime() - tu
    Input.endFrame()
end

function love.draw(screen)
    -- Sin 3D estereoscópico: el ojo derecho no se dibuja (sería el mismo dibujo otra
    -- vez, el doble de trabajo y de vértices). love.graphics.set3D(false) cerraba la
    -- consola al arrancar, por eso se hace así.
    if screen == "right" then return end
    if G_STEP and not G_FIRSTDRAW[screen] then G_FIRSTDRAW[screen] = true; G_STEP("primer dibujo " .. tostring(screen)) end
    G_DRAWN = 0
    local td = love.timer.getTime()
    local t0 = G_PROF and G_PROF.on and love.timer.getTime()
    if isTop(screen) then
        G.Game.render()
        G.TopUI.draw()
    else
        G.UI.draw()
    end
    if isTop(screen) then PERF.top = PERF.top + love.timer.getTime() - td
    else PERF.bot = PERF.bot + love.timer.getTime() - td end
    if t0 then
        local k = isTop(screen) and "DIBUJO pantalla arriba" or "DIBUJO pantalla abajo"
        G_PROF.acc[k] = (G_PROF.acc[k] or 0) + love.timer.getTime() - t0
        G_PROF.cnt[k] = (G_PROF.cnt[k] or 0) + 1
    end
    if G_COUNTDRAW then
        local k = (isTop(screen) and "arriba " or "abajo ") .. tostring(G.UI.current and G.UI.current() or "?")
        if G_DRAWN > (G_COUNTDRAW[k] or 0) then
            G_COUNTDRAW[k] = G_DRAWN
            print("FORMAS " .. k .. " = " .. G_DRAWN)
        end
        local kp = "p" .. k
        local used = G_VERTS - (G_VPREV or 0)
        G_VPREV = isTop(screen) and G_VERTS or 0
        if used > (G_COUNTDRAW[kp] or 0) then
            G_COUNTDRAW[kp] = used
            print("VPANTALLA " .. k .. " = " .. used)
        end
        local kv = "v" .. tostring(G.UI.current and G.UI.current())
        if not isTop(screen) and G_VERTS > (G_COUNTDRAW[kv] or 0) then
            G_COUNTDRAW[kv] = G_VERTS
            print("VFOTOGRAMA " .. kv:sub(2) .. " = " .. G_VERTS)
        end
        local kc = "c" .. k
        if (G_CHARS or 0) > (G_COUNTDRAW[kc] or 0) then
            G_COUNTDRAW[kc] = G_CHARS
            print("LETRAS " .. k .. " = " .. G_CHARS)
        end
    end
    G_CHARS = 0
end

-- Botones de la consola llegan como gamepad; en PC nest los emula con el teclado.
function love.gamepadpressed(_, button)
    Input.gamepadPressed(button)
    G.UI.pressButton(button)
end

function love.gamepadreleased(_, button)
    Input.gamepadReleased(button)
end

function love.gamepadaxis(_, axis, value)
    Input.gamepadAxis(axis, value)
end

-- Táctil: solo tiene sentido en la pantalla inferior.
function love.touchpressed(id, x, y)
    G.UI.touch(x, y)
end

function love.touchmoved(id, x, y)
    G.UI.touchMoved(x, y)
end

function love.touchreleased(id, x, y)
    G.UI.touchReleased(x, y)
end

function love.mousepressed(x, y, button, istouch)
    if istouch or G.U.CONSOLE then return end
    -- En PC nest convierte el clic en la pantalla inferior en toque.
    love.touchpressed(0, x, y)
end

function love.mousemoved(x, y, dx, dy, istouch)
    if istouch or G.U.CONSOLE then return end
    if love.mouse.isDown(1) then love.touchmoved(0, x, y) end
end

function love.mousereleased(x, y, button, istouch)
    if istouch or G.U.CONSOLE then return end
    love.touchreleased(0, x, y)
end

-- Teclado en PC sin nest (atajos de depuración).
function love.keypressed(key)
    if G.U.CONSOLE then return end
    if key == "f1" then G.Flow.debugStartRun() end
end

-- En consola: cada callback va protegido; si falla, el error se escribe en la SD
-- (sdmc:/pokesurvivor-error.txt) antes de seguir su curso. `--wrap` lo activa en PC.
local forceWrap = false
for _, a in ipairs(arg or {}) do
    if a == "--wrap" then forceWrap = true end
    if a == "--prof" then
        -- Perfil a lo 3DS: sin JIT (la consola interpreta Lua 5.1) y con el tiempo
        -- (inclusivo) de cada función pública de cada módulo de G. Se imprime al salir.
        if jit then jit.off() end
        local getTime = love.timer.getTime
        local acc, cnt, vacc = {}, {}, {}
        G_PROF = { acc = acc, cnt = cnt, vacc = vacc }
        for _, b in ipairs(arg) do
            local s = b:match("^%-%-profsecs=(%d+)$")
            if s then G_PROF.secs = tonumber(s) end
        end
        local function wrapTable(name, t, seen)
            if type(t) ~= "table" or seen[t] then return end
            seen[t] = true
            for k, f in pairs(t) do
                if type(f) == "function" and type(k) == "string" then
                    local key = name .. "." .. k
                    t[k] = function(...)
                        local t0, v0 = getTime(), G_VERTS
                        local r1, r2, r3, r4 = f(...)
                        if G_VERTS > v0 then vacc[key] = (vacc[key] or 0) + G_VERTS - v0 end
                        acc[key] = (acc[key] or 0) + getTime() - t0
                        cnt[key] = (cnt[key] or 0) + 1
                        return r1, r2, r3, r4
                    end
                end
            end
        end
        G_PROF.install = function()
            local seen = {}
            for name, t in pairs(G) do
                if type(t) == "table" and name ~= "U" and name ~= "JSON" then wrapTable(name, t, seen) end
            end
            for _, fn in ipairs({ "draw", "print", "printf", "rectangle", "circle", "polygon", "line", "setColor", "setFont" }) do
                local f = love.graphics[fn]
                local key = "lg." .. fn
                love.graphics[fn] = function(...)
                    local t0 = getTime()
                    f(...)
                    acc[key] = (acc[key] or 0) + getTime() - t0
                    cnt[key] = (cnt[key] or 0) + 1
                end
            end
        end
        G_PROF.report = function()
            local keys = {}
            for k in pairs(acc) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return acc[a] > acc[b] end)
            local frames = cnt["love.update"] or 1
            print(string.format("PERFIL (%d fotogramas, ms por fotograma, inclusivo):", frames))
            for i = 1, math.min(60, #keys) do
                local k = keys[i]
                print(string.format("  %8.3f ms  %8.1f llamadas/f  %s", acc[k] * 1000 / frames, cnt[k] / frames, k))
            end
            local vk = {}
            for k in pairs(vacc) do vk[#vk + 1] = k end
            table.sort(vk, function(a, b) return vacc[a] > vacc[b] end)
            print("VERTICES por fotograma (inclusivo):")
            for i = 1, math.min(30, #vk) do print(string.format("  %8.0f  %s", vacc[vk[i]] / frames, vk[i])) end
        end
    end
    if a == "--bakebg" then
        -- Hornea el fondo de Platino (pantalla de abajo) en img/ui/platbg.png de la
        -- carpeta de guardado; luego se copia a game/img/ui/.
        G_BAKE_BG = true
    end
    if a == "--countdraw" then
        G_COUNTDRAW = {}
        for _, fn in ipairs({ "draw", "print", "printf", "circle", "polygon", "line" }) do
            local f = love.graphics[fn]
            love.graphics[fn] = function(...) G_DRAWN = (G_DRAWN or 0) + 1; return f(...) end
        end
        for _, fn in ipairs({ "print", "printf" }) do
            local f = love.graphics[fn]
            love.graphics[fn] = function(s, ...)
                G_CHARS = (G_CHARS or 0) + (type(s) == "string" and #s or 0)
                return f(s, ...)
            end
        end
    end
end
if (IS_CONSOLE or forceWrap) and not smokeFrames then
    for _, name in ipairs({ "update", "draw", "touchpressed", "touchmoved", "touchreleased", "gamepadpressed", "gamepadreleased", "gamepadaxis" }) do
        local fn = love[name]
        if fn then
            love[name] = function(...)
                -- Lua 5.1 (la de la 3DS): xpcall NO pasa argumentos a la función (LuaJIT
                -- del PC sí), así que van en un cierre.
                local args, n = { ... }, select("#", ...)
                local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end,
                                       function(e) return { e = e, tb = debug.traceback("", 2) } end)
                if not ok then
                    pcall(writeConsoleError, err.e, err.tb)
                    error(err.e, 0)
                end
            end
        end
    end
end
