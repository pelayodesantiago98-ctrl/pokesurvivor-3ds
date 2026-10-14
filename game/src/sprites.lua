-- sprites.lua — sprites estilo Mundo Misterioso desde atlas (port de js/core/sprites.js).
--
-- Atlas generados por tools/pack_sprites.py: un PNG por Pokémon con 5 filas de
-- dirección (0 Down · 1 DownRight · 2 Right · 3 UpRight · 4 Up); las direcciones
-- 5..7 (UpLeft, Left, DownLeft) se dibujan volteando las filas 3, 2 y 1.
-- Geometría en data/pkmn/<dex>.lua (se carga bajo demanda) e índice en data/dexmeta.lua.
--
-- (x, y) de una entidad son sus PIES: cada animación trae su ancla (ax, ay).
local U = G.U
local S = {}
G.Sprites = S

S.PX = 2                                    -- unidades de mundo por píxel de arte

local DEXMETA = require("data.dexmeta")
local datas = {}                            -- dex -> tabla de data/pkmn/<dex>.lua
local sheets = {}                           -- "dex" / "dex_f" -> { img, anims, w, h }
local lg = love.graphics

-- Fila del atlas y volteo para cada dirección 0..7.
local ROW = { [0] = 0, 1, 2, 3, 4, 3, 2, 1 }
local FLIP = { [0] = false, false, false, false, false, true, true, true }

function S.meta(dex) return DEXMETA[dex] end
function S.hovers(dex) local m = DEXMETA[dex] return m ~= nil and m.hv end
function S.hasShiny(dex) local m = DEXMETA[dex] return m ~= nil and m.sh end
function S.hasFull(dex) local m = DEXMETA[dex] return m ~= nil and m.full end

local function data(dex)
    local d = datas[dex]
    if d then return d end
    if not DEXMETA[dex] then return nil end
    local chunk = love.filesystem.load("data/pkmn/" .. dex .. ".lua")
    if not chunk then return nil end
    d = chunk()
    datas[dex] = d
    return d
end

-- Conjunto de animaciones a usar: shiny (Idle+Walk, si existe), full (las 7) o enemy.
local function setFor(d, full, shiny)
    if shiny and d.shiny then return d.shiny end
    if full and d.full then return d.full end
    return d.enemy
end

-- Hoja (atlas) de un Pokémon: "<dex>", "<dex>_f" o "<dex>_s".
local function sheetKey(dex, full, shiny)
    if shiny then return dex .. "_s" end
    if full then return dex .. "_f" end
    return tostring(dex)
end

-- Límite de hojas cargadas a la vez. En la 3DS la memoria de texturas es poca: los
-- menús (Pokédex, fases...) cargaban cientos de hojas sin soltarlas; al llenarse,
-- newImage fallaba en cada fotograma (2 fps) y la siguiente textura que no se
-- comprobaba (efectos de un cofre...) cerraba la consola. Se sueltan las que llevan
-- más tiempo sin dibujarse (nunca las del último medio segundo).
local MAX_SHEETS = 40
local nSheets = 0
local failed = {}                            -- key -> hora del último fallo (no reintentar cada fotograma)
local getTime = love.timer.getTime

local function release(key, sh)
    sh.dead = true                           -- (los animadores que la guardan la vuelven a pedir)
    if sh.img.release then pcall(sh.img.release, sh.img) end
    sheets[key] = nil
    nSheets = nSheets - 1
end

-- Suelta las hojas sin usar desde hace `age` s, de la más vieja a la más nueva, hasta
-- dejar `target` (o todas las que se pueda si target es 0).
local function evict(target, age)
    local now, list = getTime(), {}
    for key, sh in pairs(sheets) do
        if now - sh.used > age then list[#list + 1] = key end
    end
    table.sort(list, function(a, b) return sheets[a].used < sheets[b].used end)
    for i = 1, #list do
        if nSheets <= target then break end
        release(list[i], sheets[list[i]])
    end
end

local function loadSheet(dex, full, shiny)
    local d = data(dex)
    if not d then return nil end
    if shiny and not d.shiny then shiny = false end
    if full and not d.full then full = false end
    local key = sheetKey(dex, full, shiny)
    local sh = sheets[key]
    if sh then sh.used = getTime() return sh end
    local set = setFor(d, full, shiny)
    if not set then return nil end
    if failed[key] and getTime() - failed[key] < 3 then return nil end
    if nSheets >= MAX_SHEETS then evict(MAX_SHEETS - 8, 0.5) end
    if G_PRINT_STEPS and G_STEP then G_STEP("hoja de sprites " .. tostring(set.atlas)) end
    local ok, img = pcall(lg.newImage, U.img(set.atlas))
    if not ok or not img then
        -- Sin memoria: suelta todo lo que no se esté dibujando y prueba otra vez.
        evict(0, 0.5)
        ok, img = pcall(lg.newImage, U.img(set.atlas))
    end
    if not ok or not img then
        failed[key] = getTime()
        if G_STEP then G_STEP("FALLO al cargar " .. tostring(set.atlas) .. " (" .. nSheets .. " hojas cargadas)") end
        print("[Sprites] no se pudo cargar " .. set.atlas .. ": " .. tostring(img))
        return nil
    end
    failed[key] = nil
    if img.setFilter then pcall(img.setFilter, img, "nearest", "nearest") end
    -- Cuadros por animación (fila-mayor). Cada fotograma está recortado a su
    -- caja opaca: ox/oy corrigen el ancla.
    local anims = {}
    for name, a in pairs(set.anims) do
        local quads, ox, oy, qw = {}, {}, {}, {}
        local n = a.n
        for row = 0, a.rows - 1 do
            for i = 0, n - 1 do
                local idx = row * n + i
                local k = idx * 6
                quads[idx + 1] = lg.newQuad(a.q[k + 1], a.q[k + 2], a.q[k + 3], a.q[k + 4], set.w, set.h)
                qw[idx + 1] = a.q[k + 3]
                ox[idx + 1] = a.q[k + 5]
                oy[idx + 1] = a.q[k + 6]
            end
        end
        anims[name] = { w = a.w, h = a.h, n = n, rows = a.rows, ax = a.ax, ay = a.ay, d = a.d,
                        quads = quads, ox = ox, oy = oy, qw = qw }
    end
    sh = { img = img, anims = anims, full = full and d.full ~= nil, used = getTime() }
    sheets[key] = sh
    nSheets = nSheets + 1
    return sh
end

-- Geometría de una animación (sin cargar la imagen) del set que toque.
local function animDef(dex, anim, full, shiny)
    local d = data(dex)
    if not d then return nil end
    local set = setFor(d, full, shiny)
    if set and set.anims[anim] then return set.anims[anim] end
    return nil
end

-- Nombre real de la animación disponible (respaldo Idle/Walk).
function S.animName(dex, anim, full, shiny)
    if animDef(dex, anim, full, shiny) then return anim end
    if animDef(dex, "Idle", full, shiny) then return "Idle" end
    return "Walk"
end

function S.animMeta(dex, anim, full, shiny)
    local name = S.animName(dex, anim, full, shiny)
    return animDef(dex, name, full, shiny)
end

-- Carga ya las hojas (para que no se cargue en mitad de un fotograma).
function S.preload(dexes, full, shiny)
    for i = 1, #dexes do loadSheet(dexes[i], full, shiny) end
end

-- Igual, pero poco a poco: una hoja por fotograma (S.step). En la 3DS cada hoja
-- tarda ~40 ms en cargarse; cargar las de todo el minuto siguiente de golpe daba
-- tirones de medio segundo en mitad de la partida.
-- Cola en listas paralelas (sin una tabla por entrada) y sin repetidos: cada 10 s
-- el spawner vuelve a pedir lo del minuto siguiente y antes se encolaba otra vez
-- todo lo que aún no había dado tiempo a cargar.
local qDex, qFull, qShiny, qHead, qTail = {}, {}, {}, 1, 0
local queued = {}                            -- clave de hoja -> true si está en la cola
function S.preloadSoon(dexes, full, shiny)
    for i = 1, #dexes do
        local d = dexes[i]
        local key = sheetKey(d, full, shiny)
        if not sheets[key] and not queued[key] then
            queued[key] = true
            qTail = qTail + 1
            qDex[qTail], qFull[qTail], qShiny[qTail] = d, full or false, shiny or false
        end
    end
end
-- Carga como mucho UNA hoja por fotograma; las que ya estaban cargadas (o no
-- existen) se saltan sin gastar el fotograma.
function S.step()
    while qHead <= qTail do
        local d, full, shiny = qDex[qHead], qFull[qHead], qShiny[qHead]
        qDex[qHead], qFull[qHead], qShiny[qHead] = nil, nil, nil
        qHead = qHead + 1
        queued[sheetKey(d, full, shiny)] = nil
        local dd = data(d)
        if dd then
            -- (Sin atlas completo o shiny se usa el normal: la clave que se cargaría.)
            if full and not dd.full then full = false end
            if shiny and not dd.shiny then shiny = false end
            if not sheets[sheetKey(d, full, shiny)] then
                loadSheet(d, full, shiny)
                break
            end
        end
    end
    if qHead > qTail then qHead, qTail = 1, 0 end
end
function S.clearQueue()
    for i = qHead, qTail do qDex[i], qFull[i], qShiny[i] = nil, nil, nil end
    qHead, qTail = 1, 0
    for k in pairs(queued) do queued[k] = nil end
end

-- Descarga las hojas que no estén en keep ({dex=true} o lista). Las "full" se
-- conservan solo si keep las marca con true en keepFull. Las shiny se tratan
-- como las normales (siguen a keep).
function S.gc(keep, keepFull)
    local set = {}
    if keep then
        -- ¿Lista de dex ({25, 4}) o conjunto ({[25]=true})? Se mira el valor, no `#keep`:
        -- un conjunto con los dex 1 y 2 (Bulbasaur/Ivysaur) tiene `#keep > 0` y antes se
        -- tomaba por lista (cierre por índice nil y se soltaban hojas que hacían falta).
        local isList = false
        for _, v in pairs(keep) do isList = type(v) == "number"; break end
        if isList then for _, d in pairs(keep) do set[d] = true end
        else set = keep end
    end
    for key, sh in pairs(sheets) do
        local dex = tonumber(key:match("^(%d+)"))
        local isFull = key:sub(-2) == "_f"
        local wanted = isFull and (keepFull and keepFull[dex]) or (not isFull and set[dex])
        if not wanted then release(key, sh) end
    end
end

function S.loadedCount() return nSheets end

-- Ángulo de pantalla (atan2(dy,dx)) -> fila de dirección 0..7.
function S.dirFromAngle(a)
    local d = U.round((math.pi / 2 - a) / (math.pi / 4)) % 8
    return (d + 8) % 8
end

-- Radio de colisión aproximado a partir del tamaño del sprite.
function S.bodyRadius(dex, scale)
    local m = DEXMETA[dex]
    local w = m and m.iw or 32
    return U.clamp(w * 0.22, 5, 26) * S.PX * (scale or 1)
end

-- Alto visual aproximado (barras de vida y números de daño).
function S.bodyHeight(dex, scale)
    local m = DEXMETA[dex]
    return (m and m.iay or 24) * S.PX * (scale or 1)
end

-- Elipses rellenas con una textura (img/ellipse.png, elipse blanca de 128×64 sin
-- suavizar) en vez de lg.ellipse: en la 3DS una elipse son ~20-30 vértices que se
-- calculan uno a uno en la CPU, y la textura es un solo cuadro (4). Se ve igual:
-- el borde es tan duro como el del polígono. Con el color que esté puesto.
local ellImg, ellFailed = nil, false
local function ellipseImg()
    if ellImg or ellFailed then return ellImg end
    local ok, img = pcall(lg.newImage, U.img("img/ellipse"))
    if ok and img then
        if img.setFilter then pcall(img.setFilter, img, "nearest", "nearest") end
        ellImg = img
    else
        ellFailed = true
    end
    return ellImg
end
S.ellipseImg = ellipseImg

local ELL_W, ELL_H = 128, 64
function S.ellipse(x, y, rx, ry)
    if rx <= 0 or ry <= 0 then return end
    local img = ellImg or ellipseImg()
    if img then
        lg.draw(img, x - rx, y - ry, 0, rx * 2 / ELL_W, ry * 2 / ELL_H)
    else
        lg.ellipse("fill", x, y, rx, ry)
    end
end

-- Contorno de elipse con los tramos justos: LÖVE Potion calcula los tramos con el
-- radio en unidades de MUNDO (sqrt(r·20)), pero la cámara dibuja a escala 0,5 y
-- con la mitad (π·sqrt(r en píxeles)) el error queda por debajo de medio píxel.
-- Cada tramo de una línea son 6 vértices: así cuesta la mitad.
local sqrt, floor = math.sqrt, math.floor
function S.ellipseLine(x, y, rx, ry)
    local n = floor(3.2 * sqrt((rx + ry) * 0.25)) -- (rx+ry)/2 · escala 0,5
    if n < 8 then n = 8 end
    lg.ellipse("line", x, y, rx, ry, n)
end

-- Sombra elíptica bajo los pies, tamaño según el ShadowSize de PMD.
local SHADOW_R = { [0] = 5, 8, 12 }
-- Radio horizontal de la sombra (el vertical es 0,42 de éste).
function S.shadowRadius(dex, scale)
    local m = DEXMETA[dex]
    local s = m and m.s or 1
    if s < 0 then s = 0 elseif s > 2 then s = 2 end
    return SHADOW_R[s] * S.PX * (scale or 1)
end
function S.drawShadow(dex, x, y, scale)
    local rx = S.shadowRadius(dex, scale)
    lg.setColor(0, 0, 0, 0.34)
    S.ellipse(x, y, rx, rx * 0.42)
    lg.setColor(1, 1, 1, 1)
end

-- ---------------- Animator ----------------

local Animator = {}
Animator.__index = Animator
S.Animator = Animator

--  loop(anim)        animación de fondo (Idle / Walk); no reinicia si ya suena
--  play(anim, opts)  animación de una vez (Attack, Shoot, Hurt...) que tapa a la de fondo
-- @param full  usar el atlas completo (compañero del jugador) si existe
function Animator.new(dex, scale, shiny, full)
    local self = setmetatable({}, Animator)
    self.dex = dex
    self.scale = scale or 1
    self.shiny = shiny and S.hasShiny(dex) or false
    self.full = full and S.hasFull(dex) or false
    self.base = "Idle"
    self.cur = "Idle"
    self.frame = 0
    self.t = 0                 -- tiempo dentro del fotograma, en 1/60 s
    self.speed = 1
    self.once = false
    self.hold = false
    self.done = false
    self.dir = 0
    return self
end

function Animator:loop(anim, speed)
    self.base = anim
    if not self.once and self.cur ~= anim then self:_start(anim, false) end
    if not self.once then self.speed = speed or 1 end
end

function Animator:play(anim, opts)
    self:_start(anim, true)
    self.speed = (opts and opts.speed) or 1
    self.hold = opts and opts.hold or false
end

function Animator:restart(anim) self:_start(anim, false) end

function Animator:busy() return self.once and not self.done end

function Animator:progress()
    local m = S.animMeta(self.dex, self.cur, self.full, self.shiny)
    if not m then return 1 end
    local total, before = 0, 0
    for i = 1, m.n do
        if i - 1 < self.frame then before = before + m.d[i] end
        total = total + m.d[i]
    end
    if total == 0 then return 1 end
    return (before + self.t) / total
end

function Animator:_start(anim, once)
    self.cur = S.animName(self.dex, anim, self.full, self.shiny)
    self.frame = 0; self.t = 0
    self.once = once; self.done = false
end

function Animator:update(dt)
    if self.done then return end
    -- Geometría de la animación actual, guardada mientras no cambie (antes se buscaba
    -- cada fotograma, hasta 4 consultas por Pokémon).
    local m = self._meta
    if self._mcur ~= self.cur then
        m = S.animMeta(self.dex, self.cur, self.full, self.shiny)
        self._meta, self._mcur = m, self.cur
    end
    if not m then return end
    self.t = self.t + dt * 60 * self.speed
    local d = m.d
    while self.t >= d[self.frame + 1] do
        self.t = self.t - d[self.frame + 1]
        self.frame = self.frame + 1
        if self.frame >= m.n then
            if self.once then
                if self.hold then self.frame = m.n - 1; self.done = true; return end
                self:_start(self.base, false)
                self.speed = 1
                return
            end
            self.frame = 0
        end
    end
end

-- Dibuja con los pies en (x, y). opts: { flash, alpha, color }
function Animator:draw(x, y, opts)
    -- La hoja se guarda en el animador mientras siga cargada (sin buscarla por su
    -- clave de texto en cada dibujo).
    local sh = self._sh
    if sh and not sh.dead then
        sh.used = getTime()
    else
        sh = loadSheet(self.dex, self.full, self.shiny)
        self._sh = sh
    end
    local k = S.PX * self.scale
    local alpha = (opts and opts.alpha) or 1
    if alpha <= 0 then return end
    local a = sh and sh.anims[self.cur]
    local frame = self.frame
    if sh and not a then
        -- Esta animación no está en la hoja cargada: Idle/Walk de respaldo.
        a = sh.anims.Idle or sh.anims.Walk
        frame = 0
    end
    if not sh or not a then
        -- Respaldo: bolita, por si falta el fichero.
        U.setColor((opts and opts.color) or "#6b7a94", alpha)
        lg.circle("fill", x, y - 12 * k, 8 * k)
        lg.setColor(1, 1, 1, 1)
        return
    end
    local dir = self.dir
    local row = ROW[dir] or 0
    if row > a.rows - 1 then row = a.rows - 1 end
    local n = a.n
    if frame > n - 1 then frame = n - 1 end
    local idx = row * n + frame + 1
    local quad = a.quads[idx]
    local ax, ay = a.ax - a.ox[idx], a.ay - a.oy[idx]
    -- Las anclas de SpriteCollab son medias (15,5): se redondea la esquina del
    -- dibujo a píxel entero para que no se cuelen texels de los fotogramas vecinos.
    local qw = a.qw[idx]
    -- (Como U.snap, con la escala de la cámara leída una vez.)
    local cam = G.Camera
    local u = 1 / ((cam and cam.scale) or 0.5)
    local px, py
    if FLIP[dir] then
        px = floor((x - (qw - ax) * k) / u + 0.5) * u + qw * k
    else
        px = floor((x - ax * k) / u + 0.5) * u
    end
    py = floor((y - ay * k) / u + 0.5) * u
    local sx = FLIP[dir] and -k or k
    if opts and opts.reflect then
        -- Reflejo en el agua (Negro/Blanco): volteado en vertical desde los pies.
        lg.setColor(0.85, 0.95, 1, alpha * 0.42)
        lg.draw(sh.img, quad, px, U.snap(y + ay * k), 0, sx, -k)
        lg.setColor(1, 1, 1, 1)
        return
    end
    lg.setColor(1, 1, 1, alpha)
    lg.draw(sh.img, quad, px, py, 0, sx, k)
    if opts and opts.flash then
        -- Destello: la misma imagen sumada encima (sin shaders no hay silueta blanca).
        lg.setBlendMode("add")
        lg.setColor(1, 1, 1, (opts.softFlash and 0.5 or 0.9) * alpha)
        lg.draw(sh.img, quad, px, py, 0, sx, k)
        lg.setBlendMode("alpha")
    end
    lg.setColor(1, 1, 1, 1)
end

-- Dibuja un fotograma suelto (menús, colección): animación Idle, dirección 0.
function S.drawStill(dex, x, y, scale, anim, frame, dir, shiny)
    local sh = loadSheet(dex, false, shiny)
    if not sh then return false end
    local a = sh.anims[anim or "Idle"] or sh.anims.Idle or sh.anims.Walk
    if not a then return false end
    local k = S.PX * (scale or 1)
    local row = ROW[dir or 0] or 0
    if row > a.rows - 1 then row = a.rows - 1 end
    local f = math.min(frame or 0, a.n - 1)
    local idx = row * a.n + f + 1
    local ax, ay = a.ax - a.ox[idx], a.ay - a.oy[idx]
    local qw = a.qw[idx]
    local flip = FLIP[dir or 0]
    local px = flip and (U.round(x - (qw - ax) * k) + qw * k) or U.round(x - ax * k)
    lg.draw(sh.img, a.quads[idx], px, U.round(y - ay * k), 0, flip and -k or k, k)
    return true
end
