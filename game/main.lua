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
end
-- Traza a fichero (solo en modo smoke): si el proceso se cuelga, dice hasta dónde llegó.
local traceName = "smoke-trace.txt"          -- `--tag=X`: smoke-trace-X.txt (pruebas en paralelo)
for _, a in ipairs(arg or {}) do
    local tg = a:match("^%-%-tag=([%w_%-]+)$")
    if tg then traceName = "smoke-trace-" .. tg .. ".txt" end
end
local function trace(s)
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

local function isTop(screen)
    return screen ~= "bottom"
end

trace("modulos cargados")

function love.load()
    if love.graphics.setDefaultFilter then pcall(love.graphics.setDefaultFilter, "nearest", "nearest") end
    love.graphics.setBackgroundColor(0.04, 0.08, 0.19)
    Input.load()
    G.UI.load()
    trace("ui.load")
    G.Icons.load()
    trace("icons.load")
    G.Flow.boot()
    trace("boot")
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
function love.update(dt)
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
            G.Game.demo = true
            G.Input.auto = true
            G.Flow.debugStartRun()
        end
        G.Game.autoplay(dt)
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
    G.Game.frame(dt)
    G.UI.update(dt)
    Input.endFrame()
end

function love.draw(screen)
    if isTop(screen) then
        G.Game.render()
        G.TopUI.draw()
    else
        G.UI.draw()
    end
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
