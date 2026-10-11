-- db.lua — partida guardada (port de la parte LOCAL de js/core/db.js).
-- Sin cuentas ni nube: una única partida en `save.json` (carpeta de guardado de
-- LÖVE: identidad "pokesurvivor3ds"). Todo el acceso a datos persistentes pasa
-- por aquí; el resto del juego usa G.DB.save y G.DB.commit().
--
--   G.DB.load()                lee save.json (o crea una partida nueva) → G.DB.save
--   G.DB.newSave()             partida en blanco (mismos campos que db.js)
--   G.DB.commit() -> ok        escribe save.json
--   G.DB.owns(dex) / grant(dex, from) / ownsShiny(dex) / grantShiny(dex, from) -> isNew
--   G.DB.upgradesOf(dex)       mejoras de ese Pokémon { id -> nivel } (tabla viva)
--   G.DB.buyUpgrade(dex, id)   -> ok (cobra, sube un nivel y guarda)
--   G.DB.grantStarter(dex)     el inicial del test: lo da, lo hace compañero y guarda
--   G.DB.setPartner(dex, shiny)
--
-- Fechas (`created`, `updated`, `owned[dex].at`, `legends[dex]`...) en SEGUNDOS
-- (os.time()), no en milisegundos como en la web.
local DB = {}
G.DB = DB

local FILE = "save.json"
DB.FILE = FILE
DB.VERSION = 3
DB.START_COINS = 500
DB.save = nil

local function now() return os.time() end

function DB.newSave(name)
    return {
        v = DB.VERSION,
        name = name or "Entrenador",
        created = now(),
        updated = now(),            -- última modificación
        coins = DB.START_COINS,
        owned = {},                 -- dex -> { at, from = 'starter'|'gacha'|'wild'|'rescue' }
        shiny = {},                 -- dex -> { at, from }: variantes shiny conseguidas
        partner = nil,              -- dex del Pokémon con el que juegas
        partnerShiny = false,       -- jugar con su versión shiny (si la tienes)
        starter = nil,              -- dex que te tocó en el test
        personality = nil,          -- { trait, scores }
        upgrades = {},              -- (antiguo) mejoras de la cuenta; ahora van por Pokémon
        pupg = {},                  -- dex -> { id -> nivel }: mejoras de cada Pokémon
        pupgDone = true,
        tickets = { t1 = 0, t10 = 0 },  -- tickets del gacha (x1 y x10)
        pity = {},                  -- generación del banner -> tiradas sin ★5
        legends = {},               -- dex -> fecha: legendarios vencidos en grietas
        arenas = {},                -- tipo -> fecha: arenas de grieta ganadas
        itemsFound = {},            -- id -> fecha: objetos equipables encontrados
        evoMoves = {},              -- id -> fecha: movimientos evolucionados alguna vez
        ach = {},                   -- id -> fecha: logros conseguidos
        missions = {},              -- misiones del día / semana (src/progress.lua)
        profile = { favs = {}, title = "" },   -- perfil: 3 favoritos y título
        stats = { runs = 0, bestTime = 0, bestLevel = 0, totalKills = 0, pulls = 0, coinsEarned = 0,
                  shinies = 0, bossesTotal = 0, riftWins = 0, evolutions = 0, missionsDone = 0,
                  groupRuns = 0, bestGroupTime = 0 }
    }
end

-- Rellena campos que falten en partidas de versiones anteriores.
local function migrate(s)
    local base = DB.newSave(s.name)
    for k, v in pairs(base) do if s[k] == nil then s[k] = v end end
    if type(s.stats) ~= "table" then s.stats = base.stats end
    for k, v in pairs(base.stats) do if s.stats[k] == nil then s.stats[k] = v end end
    -- v1 -> v2: había un único banner (Kanto) con el pity como número.
    if type(s.pity) == "number" then s.pity = { [1] = s.pity } end
    -- v2 -> v3: las mejoras eran de la cuenta; pasan al compañero de entonces.
    if not s.pupgDone then
        if s.partner and type(s.upgrades) == "table" then
            local any = false
            for _, v in pairs(s.upgrades) do if type(v) == "number" and v > 0 then any = true end end
            if any then
                local c = {}
                for k, v in pairs(s.upgrades) do c[k] = v end
                s.pupg[s.partner] = c
            end
        end
        s.pupgDone = true
    end
    if type(s.tickets) ~= "table" then s.tickets = { t1 = 0, t10 = 0 } end
    s.tickets.t1 = s.tickets.t1 or 0
    s.tickets.t10 = s.tickets.t10 or 0
    s.v = DB.VERSION
    return s
end

-- Lee la partida del disco (o crea una nueva si no hay o está corrupta).
function DB.load()
    local s = nil
    local ok, text = pcall(love.filesystem.read, FILE)
    if ok and type(text) == "string" and #text > 0 then
        local ok2, data = pcall(G.JSON.decode, text)
        if ok2 and type(data) == "table" then s = data
        else print("[DB] save.json ilegible, se empieza de cero: " .. tostring(data)) end
    end
    DB.save = s and migrate(s) or DB.newSave()
    DB.fresh = (s == nil)          -- true si no había partida guardada
    return DB.save
end

-- Guarda la partida actual en save.json.
function DB.commit()
    local s = DB.save
    if not s then return false end
    s.updated = now()
    local ok, text = pcall(G.JSON.encode, s)
    if not ok then print("[DB] no se pudo codificar la partida: " .. tostring(text)) return false end
    local ok2, err = love.filesystem.write(FILE, text)
    if not ok2 then print("[DB] no se pudo escribir " .. FILE .. ": " .. tostring(err)) return false end
    return true
end

-- Borra la partida y empieza de cero (para el menú de opciones).
function DB.reset()
    DB.save = DB.newSave()
    DB.fresh = true
    return DB.commit()
end

-- ---------------- helpers de partida ----------------

function DB.owns(dex)
    local s = DB.save
    return s ~= nil and s.owned[dex] ~= nil
end

function DB.grant(dex, from)
    local s = DB.save
    if not s then return end
    if not s.owned[dex] then s.owned[dex] = { at = now(), from = from } end
end

function DB.ownsShiny(dex)
    local s = DB.save
    return s ~= nil and s.shiny ~= nil and s.shiny[dex] ~= nil
end

-- Da la versión shiny (y la normal, si no la tenía). Devuelve true si es nueva.
function DB.grantShiny(dex, from)
    local s = DB.save
    if not s then return false end
    DB.grant(dex, from)
    if s.shiny[dex] then return false end
    s.shiny[dex] = { at = now(), from = from }
    return true
end

-- Mejoras compradas para un Pokémon: { id -> nivel } (la tabla viva del guardado).
function DB.upgradesOf(dex)
    local s = DB.save
    if not s then return {} end
    s.pupg = s.pupg or {}
    local u = s.pupg[dex]
    if not u then u = {}; s.pupg[dex] = u end
    return u
end

-- Compra un nivel de la mejora `id` para `dex` (ver data/upgrades: G.Upgrades.BY y cost).
-- Devuelve true si se ha comprado (y guarda); false si está al máximo o no llegan las monedas.
function DB.buyUpgrade(dex, id)
    local s = DB.save
    local u = G.Upgrades and G.Upgrades.BY[id]
    if not s or not u then return false end
    local levels = DB.upgradesOf(dex)
    local lvl = levels[id] or 0
    if lvl >= u.max then return false end
    local cost = G.Upgrades.cost(id, lvl)
    if s.coins < cost then return false end
    s.coins = s.coins - cost
    levels[id] = lvl + 1
    DB.commit()
    return true
end

-- Elige compañero (y si se juega con su shiny, solo si lo tienes).
function DB.setPartner(dex, shiny)
    local s = DB.save
    if not s or not s.owned[dex] then return false end
    s.partner = dex
    s.partnerShiny = (shiny and DB.ownsShiny(dex)) or false
    DB.commit()
    return true
end

-- El inicial que te ha tocado en el test: lo da, lo hace compañero y guarda.
-- `personality` = { trait, scores } opcional.
function DB.grantStarter(dex, personality)
    local s = DB.save
    if not s then return false end
    s.starter = dex
    s.partner = dex
    s.partnerShiny = false
    if personality then s.personality = personality end
    DB.grant(dex, "starter")
    DB.commit()
    return true
end
