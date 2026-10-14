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
        local quads, ox, oy = {}, {}, {}
        local n = a.n
        for row = 0, a.rows - 1 do
            for i = 0, n - 1 do
                local idx = row * n + i
                local k = idx * 6
                quads[idx + 1] = lg.newQuad(a.q[k + 1], a.q[k + 2], a.q[k + 3], a.q[k + 4], set.w, set.h)
                ox[idx + 1] = a.q[k + 5]
                oy[idx + 1] = a.q[k + 6]
            end
        end
        anims[name] = { w = a.w, h = a.h, n = n, rows = a.rows, ax = a.ax, ay = a.ay, d = a.d,
                        quads = quads, ox = ox, oy = oy }
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

-- Sombra elíptica bajo los pies, tamaño según el ShadowSize de PMD.
local SHADOW_R = { [0] = 5, 8, 12 }
function S.drawShadow(dex, x, y, scale)
    local m = DEXMETA[dex]
    local s = m and m.s or 1
    local rx = SHADOW_R[U.clamp(s, 0, 2)] * S.PX * (scale or 1)
    lg.setColor(0, 0, 0, 0.34)
    lg.ellipse("fill", x, y, rx, rx * 0.42)
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
    local m = S.animMeta(self.dex, self.cur, self.full, self.shiny)
    if not m or self.done then return end
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
    local sh = loadSheet(self.dex, self.full, self.shiny)
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
    sh.used = U.now()
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
    local _, _, qw = quad:getViewport()
    local px, py
    if FLIP[dir] then
        px = U.snap(x - (qw - ax) * k) + qw * k
    else
        px = U.snap(x - ax * k)
    end
    py = U.snap(y - ay * k)
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
    local _, _, qw = a.quads[idx]:getViewport()
    local flip = FLIP[dir or 0]
    local px = flip and (U.round(x - (qw - ax) * k) + qw * k) or U.round(x - ax * k)
    lg.draw(sh.img, a.quads[idx], px, U.round(y - ay * k), 0, flip and -k or k, k)
    return true
end
