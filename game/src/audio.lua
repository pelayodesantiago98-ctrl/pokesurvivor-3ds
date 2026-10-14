-- audio.lua — música y efectos (port de js/core/audio.js).
--
-- En la web el sonido se sintetizaba en el momento con Web Audio. En la 3DS no hay
-- sintetizador en tiempo real: tools/gen_audio.py pre-renderiza todo a WAV
-- (22050 Hz, mono, 16 bits) en game/music/<tema>.wav y game/sfx/<nombre>.wav.
--
--   G.Audio.music("village" | "forest" | "cave" | "volcano" | "boss" | "rift" | nil)
--       cambia de tema con fundido cruzado (0,7 s de salida, 0,8 s de entrada).
--   G.Audio.sfx("coin")                       efecto (con separación mínima y tope de voces)
--   G.Audio.sfx("shot", {kind=, type=})       elige la variante pre-renderizada
--   G.Audio.sfx("burst"/"reveal", {rarity=})  variante por rareza
--   G.Audio.update(dt)                        avanza los fundidos y recicla voces
--   G.Audio.setMuted(m) / isMuted() / current() / setVolume("music"|"sfx", v) / preload()
--
-- Todo lo que toca love.audio va en pcall: un fichero ausente o un fallo del
-- hardware nunca deben romper el juego. Los WAV se cargan igual en PC y en consola.
local A = {}
G.Audio = A

local MAX_VOICES = 12          -- efectos sonando a la vez (la web permitía 24)
local POOL = 3                 -- clones por efecto para solapar repeticiones
local DEFAULT_GAP = 0.04       -- separación mínima entre repeticiones (s)
-- En la 3DS, LÖVE Potion suelta los canales que acaban desde otro hilo, sin proteger
-- bien play/stop/clone del mismo sonido: con cientos de golpes por minuto la consola
-- se acababa cerrando (confirmado: sin efectos no se cerraba). Allí, una sola copia de
-- cada efecto, nunca se corta uno que está sonando (si ya suena, el nuevo se salta) y
-- menos a la vez.
local SAFE = love._potion_version ~= nil
    or (love.system and love.system.getOS and love.system.getOS() == "Horizon")
if SAFE then MAX_VOICES, POOL, DEFAULT_GAP = 6, 1, 0.08 end
local FADE_IN, FADE_OUT = 0.8, 0.7
-- Separaciones concretas de la web (ms -> s). "break" es palabra clave en Lua.
local MIN_GAP = { hit = 0.045, faint = 0.06, xp = 0.035, coin = 0.05, grass = 0.07,
                  shot = 0.07, hover = 0.04, ["break"] = 0.06 }

local hasAudio = love.audio ~= nil and love.timer ~= nil
local settings = { music = 1.0, sfx = 1.0, muted = false }

-- ---------------------------------------------------------------- nombres de fichero

-- Tono de `shot` según el tipo (SHOT_PITCH de audio.js agrupado en 3 cubos):
--   0 bajo  (< 500 Hz):   ground rock dragon dark ghost poison fighting
--   1 medio (500-800 Hz): fire normal grass water steel psychic   (y tipo desconocido)
--   2 alto  (> 800 Hz):   flying ice bug electric fairy
local SHOT_BUCKET = {
    ground = 0, rock = 0, dragon = 0, dark = 0, ghost = 0, poison = 0, fighting = 0,
    fire = 1, normal = 1, grass = 1, water = 1, steel = 1, psychic = 1,
    flying = 2, ice = 2, bug = 2, electric = 2, fairy = 2,
}
-- Ficheros precalculados (nada de concatenar cadenas por disparo).
local SHOT_FILES = {}          -- kind -> { [0]=, [1]=, [2]= }
for _, kind in ipairs({ "projectile", "beam", "orbit", "aura", "buff" }) do
    SHOT_FILES[kind] = { [0] = "shot_" .. kind .. "_0", [1] = "shot_" .. kind .. "_1", [2] = "shot_" .. kind .. "_2" }
end
local SHOT_SINGLE = { melee = "shot_melee", nova = "shot_nova" }
-- En la web el proyectil de fuego/eléctrico lleva un siseo extra: variante propia.
local SHOT_SPECIAL = { fire = "shot_projectile_fire", electric = "shot_projectile_electric" }
local SHOT_KEY = {}            -- clave de separación mínima: "shot" .. kind
local XP_FILES, BURST_FILES, REVEAL_FILES = {}, {}, {}
for i = 0, 24 do XP_FILES[i] = "xp_" .. i end
for r = 1, 5 do BURST_FILES[r] = "burst_" .. r; REVEAL_FILES[r] = "reveal_" .. r end

local function shotKey(kind)
    local k = SHOT_KEY[kind]
    if not k then k = "shot" .. tostring(kind); SHOT_KEY[kind] = k end
    return k
end

local function shotFile(opts)
    local kind = opts and opts.kind or "projectile"
    local typ = opts and opts.type
    local single = SHOT_SINGLE[kind]
    if single then return single end
    local files = SHOT_FILES[kind] or SHOT_FILES.projectile
    if files == SHOT_FILES.projectile and SHOT_SPECIAL[typ] then return SHOT_SPECIAL[typ] end
    return files[SHOT_BUCKET[typ] or 1]
end

local function rarityFile(files, opts)
    local r = opts and tonumber(opts.rarity) or 1
    if r < 1 then r = 1 elseif r > 5 then r = 5 end
    return files[math.floor(r)]
end

-- ---------------------------------------------------------------- efectos

local pools = {}               -- fichero -> { src1, src2, src3, n=, next= } | false (no carga)
local voices = {}              -- fuentes sonando (se podan en update)
local last = {}                -- clave -> instante de la última reproducción
local xpCombo, xpT = 0, -1

local function getPool(file)
    local p = pools[file]
    if p ~= nil then return p end
    if G_MARKF then G_MARKF("SFX:" .. tostring(file)) end
    local ok, src = pcall(love.audio.newSource, "sfx/" .. file .. ".wav", "static")
    if not ok or not src then
        pools[file] = false
        return false
    end
    p = { src, n = 1, next = 1 }
    pools[file] = p
    return p
end

-- Reproduce un fichero sobre un clon libre del pool (o roba el más antiguo).
local function play(file, vol)
    local p = getPool(file)
    if not p then return end
    local s
    for i = 1, p.n do
        if not p[i]:isPlaying() then s = p[i]; break end
    end
    if not s and p.n < POOL then
        local ok, c = pcall(p[1].clone, p[1])
        if ok and c then p.n = p.n + 1; p[p.n] = c; s = c end
    end
    if not s then
        if SAFE then return end              -- (no cortar uno que suena: ver SAFE)
        s = p[p.next]
        p.next = p.next % p.n + 1
        s:stop()
    end
    s:setVolume(vol)
    s:play()
    voices[#voices + 1] = s
end

local function pruneVoices()
    for i = #voices, 1, -1 do
        if not voices[i]:isPlaying() then
            voices[i] = voices[#voices]
            voices[#voices] = nil
        end
    end
end

-- Efecto: sfx("hit"), sfx("shot", {kind="beam", type="fire"}), sfx("burst", {rarity=3}) ...
function A.sfx(name, opts)
    if not hasAudio or not name or settings.muted or settings.sfx <= 0 then return end
    if G_FLAGS and G_FLAGS.nosfx then return end
    local key = name
    if name == "shot" and opts then key = shotKey(opts.kind) end
    local now = love.timer.getTime()
    if now - (last[key] or 0) < (MIN_GAP[name] or DEFAULT_GAP) then return end
    if #voices >= MAX_VOICES then return end
    last[key] = now
    local file = name
    if name == "shot" then
        file = shotFile(opts)
    elseif name == "xp" then
        -- Cada xp seguido sube un semitono (hasta 24), como en la web.
        if now - xpT < 0.45 then xpCombo = math.min(xpCombo + 1, 24) else xpCombo = 0 end
        xpT = now
        file = XP_FILES[xpCombo]
    elseif name == "burst" then
        file = rarityFile(BURST_FILES, opts)
    elseif name == "reveal" then
        file = rarityFile(REVEAL_FILES, opts)
    end
    pcall(play, file, settings.sfx)
end

-- Precarga de todos los efectos (evita tirones la primera vez que suenan). Son ~80
-- WAV: cargarlos de golpe retrasaba en la 3DS la primera imagen del juego. Se ponen
-- en cola (los de los menús primero) y A.update carga uno por fotograma fuera de la
-- partida; jugando, uno cada PRELOAD_GAP s. Lo que suene antes se carga al momento.
local PRELOAD = {
    "hover", "click", "back", "confirm", "select", "error", "hit", "faint", "bossDown", "coin",
    "heal", "levelup", "hurt", "boss", "surge", "shiny", "shinyGet", "break", "chest", "grass",
    "ball", "shake", "rift", "legend", "gameover", "biome", "pause", "buy", "shot_melee", "shot_nova",
    "shot_projectile_fire", "shot_projectile_electric",
}
local PRELOAD_GAP = 0.5
local queue, qHead, qWait = {}, 1, 0
function A.preload()
    if not hasAudio then return end
    local function add(f) queue[#queue + 1] = f end
    for _, f in ipairs(PRELOAD) do add(f) end
    for _, kind in ipairs({ "projectile", "beam", "orbit", "aura", "buff" }) do
        for b = 0, 2 do add(SHOT_FILES[kind][b]) end
    end
    for i = 0, 24 do add(XP_FILES[i]) end
    for r = 1, 5 do add(BURST_FILES[r]); add(REVEAL_FILES[r]) end
end
local function preloadStep(dt)
    if qHead > #queue then return end
    -- Jugando no se carga nada: en la 3DS cada WAV es un tirón. Lo que falte lo
    -- carga A.finishPreload al empezar la partida.
    if G.Game and G.Game.state and G.Game.state() ~= "ui" then return end
    -- Salta los que ya estén cargados (sonaron antes de llegar a ellos).
    while qHead <= #queue and pools[queue[qHead]] ~= nil do qHead = qHead + 1 end
    if qHead > #queue then return end
    local f = queue[qHead]
    qHead = qHead + 1
    getPool(f)
end

-- ---------------------------------------------------------------- música

local wanted = nil             -- tema pedido (lo que devuelve current())
local cur = nil                -- { name=, src=, vol= } tema sonando o entrando
local fading = {}              -- temas saliendo
local musicSrc = {}            -- nombre -> Source (en bucle); false si no cargó.
                               -- Se cachean: Horizon no deja abrir dos veces un fichero.
local dirty = false            -- hay que reaplicar volúmenes

local function musicGain()
    if settings.muted then return 0 end
    return settings.music
end

local function loadMusic(name)
    local ok, src = pcall(love.audio.newSource, "music/" .. name .. ".wav", "stream")
    if not ok or not src then return false end
    pcall(src.setLooping, src, true)
    return src
end

local function startMusic(name)
    if G_MARKF then G_MARKF("MUS:" .. tostring(name)) end
    local src = musicSrc[name]
    if src == nil then
        src = loadMusic(name)
        musicSrc[name] = src
    end
    if not src then return end
    cur = { name = name, src = src, vol = 0 }
    pcall(src.setVolume, src, 0)
    pcall(src.play, src)
end

-- Al empezar una partida (ya es un momento de carga): los efectos que falten y la
-- música de jefe, para que nada se cargue a mitad de partida.
function A.finishPreload()
    if not hasAudio then return end
    while qHead <= #queue do
        local f = queue[qHead]
        qHead = qHead + 1
        if pools[f] == nil then pcall(getPool, f) end
    end
    if musicSrc.boss == nil then
        local ok, src = pcall(loadMusic, "boss")
        musicSrc.boss = ok and src or false
    end
end

-- Música: music("village" | "forest" | "cave" | "volcano" | "boss" | "rift" | nil)
function A.music(name)
    if wanted == name then return end
    wanted = name
    if not hasAudio then return end
    if cur then fading[#fading + 1] = cur; cur = nil end
    if not name then return end
    -- Si el tema pedido aún se estaba apagando, se recupera sin reiniciarlo.
    for i = #fading, 1, -1 do
        if fading[i].name == name then
            cur = table.remove(fading, i)
            return
        end
    end
    pcall(startMusic, name)
end

local function updateMusic(dt)
    if cur then
        if cur.vol < 1 then
            cur.vol = cur.vol + dt / FADE_IN
            if cur.vol > 1 then cur.vol = 1 end
            cur.src:setVolume(cur.vol * musicGain())
        elseif dirty then
            cur.src:setVolume(musicGain())
        end
    end
    for i = #fading, 1, -1 do
        local f = fading[i]
        f.vol = f.vol - dt / FADE_OUT
        if f.vol <= 0 then
            f.src:stop()
            fading[i] = fading[#fading]
            fading[#fading] = nil
        else
            f.src:setVolume(f.vol * musicGain())
        end
    end
    dirty = false
end

function A.update(dt)
    if not hasAudio then return end
    pcall(updateMusic, dt)
    pcall(pruneVoices)
    if qHead <= #queue then pcall(preloadStep, dt) end
end

-- ---------------------------------------------------------------- ajustes

function A.current() return wanted end
function A.track() return cur and cur.name or nil end
function A.setMuted(m) settings.muted = m and true or false; dirty = true end
function A.isMuted() return settings.muted end
function A.toggleMute() A.setMuted(not settings.muted); return settings.muted end
function A.setVolume(which, v)
    if which ~= "music" and which ~= "sfx" then return end
    v = tonumber(v) or 0
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    settings[which] = v
    dirty = true
end
function A.settings() return settings end
