-- vfx.lua — sprites pixel art de los ataques (port de js/entities/vfx.js).
--
-- En la web las formas (llama, gota, burbuja, hoja, rayo...) se generaban por
-- código en un canvas. En la 3DS vienen de un atlas en escala de grises
-- (img/vfx.png + data/vfx.lua, generados por tools/gen_vfx.py) que se TIÑE con
-- el color del tipo: una misma burbuja sale azul de agua o morada de veneno.
--
--   G.VFX.draw(shape, pal, x, y, { angle, scale, frame, alpha })
--   G.VFX.forMove(m)  -> cómo se ve ese movimiento (proyectil, rayo, golpe...)
--   G.VFX.forType(t)  -> forma por defecto de un tipo (disparos enemigos)
--
-- Contrato de data/vfx.lua (PORT.md §13):
--   quads  = { ["<forma>_<f>"] = {x, y, w, h, ox, oy} }   (ox,oy = recorte dentro de la caja w×h)
--   shapes = { [forma] = { frames=n, dir=bool, spin=bool, w=, h= } }
--   forType / forMoveKind (opcionales): si vienen, se mezclan con las tablas de aquí.
-- Si el atlas no existe, se dibuja un círculo del color del tipo del tamaño de la forma.
local U = G.U
local V = {}
G.VFX = V

local lg = love.graphics
local floor, sin, cos, max, pi = math.floor, math.sin, math.cos, math.max, math.pi
local PX = G.Sprites and G.Sprites.PX or 2
V.PX = PX

-- Paletas por tipo: contorno, oscuro, medio, claro, brillo (índices 1..5).
-- Las usa G.FX para estelas, rayos y golpes; el atlas se tiñe con U.TYPE_COLOR.
V.PAL = {
    fire     = { '#6b1200', '#b8300a', '#ff6a1f', '#ffb22e', '#fff2a0' },
    water    = { '#0f2f78', '#1f56c4', '#3d8bff', '#8ccaff', '#eaf7ff' },
    grass    = { '#14400f', '#24721e', '#45b23c', '#97e36c', '#eaffd0' },
    electric = { '#6b4300', '#c48a00', '#ffd21a', '#fff36a', '#ffffff' },
    psychic  = { '#5e0a3a', '#b0246e', '#ff4f9a', '#ff9fcf', '#ffe8f3' },
    ice      = { '#134a60', '#2f8aa8', '#62d2ea', '#bff3ff', '#ffffff' },
    fighting = { '#561208', '#9a2a16', '#e04a2e', '#ff9c6c', '#ffe2cc' },
    poison   = { '#2e0a3c', '#5e1f7e', '#a043d0', '#d995f2', '#f7e2ff' },
    ground   = { '#3a250c', '#6e4c1e', '#aa7c3c', '#dcb66c', '#f6e6b8' },
    flying   = { '#283c66', '#5672b0', '#93b2ff', '#d2e2ff', '#ffffff' },
    bug      = { '#2e3a06', '#5b7414', '#90b82a', '#cbe86c', '#f4ffd2' },
    rock     = { '#2e2418', '#5a4a34', '#8e7a5a', '#c6b08a', '#f0e4c6' },
    ghost    = { '#160e2c', '#33256a', '#5c48aa', '#9e8aea', '#e8deff' },
    dragon   = { '#160a50', '#2e1ea0', '#5a3cff', '#a490ff', '#e8e2ff' },
    dark     = { '#0e0a0c', '#2a2026', '#463840', '#7c6a74', '#d4c4cc' },
    steel    = { '#232d38', '#56667a', '#8c9caf', '#cad6e2', '#ffffff' },
    fairy    = { '#6a2050', '#b04a8a', '#ff8acb', '#ffc4e6', '#ffffff' },
    normal   = { '#3e3834', '#7a7068', '#c4bcb0', '#ece6dc', '#ffffff' },
    aura     = { '#0c2460', '#1c4cb0', '#3a7cff', '#90d2ff', '#ffffff' },
}
local PAL = V.PAL

-- Geometría de cada forma (la misma que en vfx.js): sirve de respaldo si no
-- hay atlas y para isDir/spins/frames. data/vfx.lua puede sobrescribirla.
local SHAPES = {
    fire     = { w = 15, h = 11, frames = 3, dir = true },
    drop     = { w = 13, h = 9,  frames = 1, dir = true },
    bubble   = { w = 11, h = 11, frames = 2 },
    leaf     = { w = 12, h = 7,  frames = 1, spin = true },
    bolt     = { w = 15, h = 10, frames = 2, dir = true },
    shard    = { w = 13, h = 7,  frames = 1, dir = true },
    rock     = { w = 12, h = 11, frames = 3, spin = true },
    blob     = { w = 12, h = 11, frames = 2 },
    needle   = { w = 13, h = 5,  frames = 1, dir = true },
    star     = { w = 11, h = 11, frames = 2, spin = true },
    streak   = { w = 15, h = 5,  frames = 1, dir = true },
    wind     = { w = 13, h = 11, frames = 2, spin = true },
    web      = { w = 11, h = 11, frames = 1, spin = true },
    ring     = { w = 13, h = 13, frames = 2 },
    crescent = { w = 12, h = 11, frames = 1, dir = true },
    note     = { w = 11, h = 11, frames = 1, dir = true },
    impact   = { w = 15, h = 15, frames = 2 },
    claw     = { w = 13, h = 13, frames = 1 },
    jaws     = { w = 13, h = 11, frames = 2 },
    arrow    = { w = 7,  h = 9,  frames = 1 },
    ball     = { w = 11, h = 11, frames = 2 },
    shadow   = { w = 13, h = 13, frames = 3 },
    heart    = { w = 9,  h = 8,  frames = 1 },
}
V.SHAPES = SHAPES

-- ---------------- atlas ----------------

local img = nil                 -- imagen del atlas (nil si no existe)
local frames = {}               -- forma -> { [f] = { quad, ox, oy } } (f desde 0)
local frameCount = {}           -- forma -> nº de cuadros en el atlas
local tried = false

-- Carga img/vfx.png + data/vfx.lua. Devuelve true si hay atlas.
function V.load()
    tried = true
    local ok, d = pcall(require, "data.vfx")
    if not ok or type(d) ~= "table" or not d.quads then return false end
    local ok2, im = pcall(lg.newImage, U.img("img/vfx"))
    if not ok2 or not im then return false end
    if im.setFilter then pcall(im.setFilter, im, "nearest", "nearest") end
    local iw, ih = im:getWidth(), im:getHeight()
    for name, q in pairs(d.quads) do
        local shape, f = name:match("^(.-)_(%d+)$")
        if shape then f = tonumber(f) else shape, f = name, 0 end
        local list = frames[shape]
        if not list then list = {}; frames[shape] = list; frameCount[shape] = 0 end
        list[f] = { quad = lg.newQuad(q[1], q[2], q[3], q[4], iw, ih), ox = q[5] or 0, oy = q[6] or 0 }
        if f + 1 > frameCount[shape] then frameCount[shape] = f + 1 end
    end
    if d.shapes then
        for name, s in pairs(d.shapes) do
            local m = SHAPES[name]
            if not m then m = {}; SHAPES[name] = m end
            if s.w then m.w = s.w end
            if s.h then m.h = s.h end
            if s.frames then m.frames = s.frames end
            if s.dir ~= nil then m.dir = s.dir end
            if s.spin ~= nil then m.spin = s.spin end
        end
    end
    -- Tablas opcionales del generador: completan (sin pisar) las de aquí.
    if d.forType then
        for t, shape in pairs(d.forType) do if not V.TYPE_SHAPE[t] then V.TYPE_SHAPE[t] = shape end end
    end
    if d.forMoveKind then
        for id, v in pairs(d.forMoveKind) do if not V.MOVE[id] then V.MOVE[id] = v end end
    end
    img = im
    return true
end

function V.hasAtlas() return img ~= nil end

-- Color con el que se tiñe una paleta: el del tipo, o el tono medio de PAL.
local function tint(pal)
    local c = U.TYPE_COLOR[pal]
    if c then return c end
    local p = PAL[pal]
    if p then return p[3] end
    return U.TYPE_COLOR.normal
end

local STEP = pi / 8

-- Dibuja centrado en (x, y). opts: angle, scale (1 = píxel de juego), frame, alpha.
function V.draw(shape, pal, x, y, o)
    if not tried then V.load() end
    local meta = SHAPES[shape]
    if not meta then shape = 'ball'; meta = SHAPES.ball end
    local scale, alpha, a, fr = 1, 1, 0, 0
    if o then
        scale = o.scale or 1
        alpha = o.alpha or 1
        a = o.angle or 0
        fr = o.frame or 0
    end
    if alpha <= 0 then return end
    local k = PX * scale
    if a ~= 0 then a = floor(a / STEP + 0.5) * STEP end       -- 16 direcciones: menos parpadeo
    local rx, ry = U.snap(x), U.snap(y)
    local list = img and frames[shape]
    if list then
        local n = frameCount[shape]
        local f = list[floor(fr) % n] or list[0]
        if f then
            U.setColor(tint(pal), alpha)
            lg.draw(img, f.quad, rx, ry, a, k, k, meta.w / 2 - f.ox, meta.h / 2 - f.oy)
            lg.setColor(1, 1, 1, 1)
            return
        end
    end
    -- Respaldo sin atlas: círculo del color del tipo, del tamaño de la forma.
    U.setColor(tint(pal), alpha)
    lg.circle("fill", rx, ry, max(meta.w, meta.h) * 0.3 * k)
    lg.setColor(1, 1, 1, 1)
end

function V.isDir(shape) local s = SHAPES[shape] return s ~= nil and s.dir == true end
function V.spins(shape) local s = SHAPES[shape] return s ~= nil and s.spin == true end
function V.frames(shape) local s = SHAPES[shape] return (s and s.frames) or 1 end

-- ---------------- cómo se ve cada movimiento ----------------
--   proj: forma del proyectil (también novas y orbes)
--   beam: forma que viaja por el rayo ('lightning' = zigzag)
--   melee: extra del golpe (impact, jaws, claw, vine, feather)
--   aura / buff: partícula que acompaña
--   pal: paleta si no es la del tipo · trail: partículas de estela

V.MOVE = {
    ['quick-attack']   = { proj = 'streak' },
    ['ember']          = { proj = 'fire', trail = 'ember' },
    ['heat-wave']      = { proj = 'fire', trail = 'ember' },
    ['fire-spin']      = { proj = 'fire', trail = 'ember' },
    ['flamethrower']   = { proj = 'fire', trail = 'ember', beam = 'fire' },
    ['water-gun']      = { proj = 'drop', trail = 'drip' },
    ['bubble']         = { proj = 'bubble' },
    ['hydro-pump']     = { beam = 'drop' },
    ['aqua-ring']      = { buff = 'bubble' },
    ['vine-whip']      = { melee = 'vine' },
    ['razor-leaf']     = { proj = 'leaf' },
    ['leaf-storm']     = { proj = 'leaf' },
    ['giga-drain']     = { aura = 'heart', inward = true },
    ['thunder-shock']  = { proj = 'bolt', trail = 'spark' },
    ['discharge']      = { aura = 'bolt' },
    ['thunderbolt']    = { beam = 'lightning' },
    ['confusion']      = { proj = 'ring' },
    ['psybeam']        = { beam = 'ring' },
    ['psychic']        = { proj = 'ring' },
    ['sludge']         = { proj = 'blob', trail = 'bubbles' },
    ['poison-sting']   = { proj = 'needle' },
    ['toxic']          = { aura = 'bubble', rise = true },
    ['mud-shot']       = { proj = 'blob', trail = 'dirt' },
    ['bulldoze']       = { aura = 'rock', rise = true },
    ['gust']           = { proj = 'wind' },
    ['wing-attack']    = { melee = 'feather' },
    ['tackle']         = { melee = 'impact' },
    ['body-slam']      = { melee = 'impact' },
    ['hyper-voice']    = { proj = 'note' },
    ['bug-bite']       = { melee = 'jaws' },
    ['string-shot']    = { proj = 'web' },
    ['bug-buzz']       = { aura = 'note' },
    ['rock-throw']     = { proj = 'rock', trail = 'dirt' },
    ['rock-slide']     = { proj = 'rock', trail = 'dirt' },
    ['ice-beam']       = { beam = 'shard' },
    ['powder-snow']    = { aura = 'star' },
    ['karate-chop']    = { melee = 'impact' },
    ['aura-sphere']    = { proj = 'ball', pal = 'aura', trail = 'spark' },
    ['lick']           = { melee = 'impact' },
    ['shadow-ball']    = { proj = 'shadow', trail = 'wisp' },
    ['dragon-rage']    = { beam = 'fire' },
    ['dragon-dance']   = { buff = 'arrow' },
    ['fairy-wind']     = { proj = 'star' },
    ['dazzling-gleam'] = { aura = 'star' },
    ['metal-claw']     = { melee = 'claw' },
    ['flash-cannon']   = { beam = 'shard' },
    ['bite']           = { melee = 'jaws' },
    ['dark-pulse']     = { proj = 'crescent' },
    ['night-shade']    = { aura = 'shadow', rise = true },
    ['swords-dance']   = { buff = 'arrow', pal = 'fighting' },
    ['agility']        = { buff = 'arrow', pal = 'flying' },
    ['harden']         = { buff = 'arrow', pal = 'steel' },
    ['bonemerang']     = { proj = 'crescent' },
    ['psycho-cut']     = { proj = 'crescent' },
    ['spikes']         = { proj = 'star' },
    ['toxic-spikes']   = { proj = 'star' },
    ['hail']           = { proj = 'shard' },
    ['meteor-mash']    = { proj = 'rock', trail = 'spark' },
    ['will-o-wisp']    = { proj = 'ball', trail = 'ember' },
    ['substitute']     = { proj = 'star' },
    ['aerial-ace']     = { proj = 'wind' },
    ['flame-wheel']    = { proj = 'fire', aura = 'fire' },
    ['bubble-beam']    = { proj = 'bubble' },
    ['hex']            = { beam = 'shadow', proj = 'shadow' },
}

V.TYPE_SHAPE = {
    fire = 'fire', water = 'drop', grass = 'leaf', electric = 'bolt', psychic = 'ring', ice = 'shard',
    fighting = 'ball', poison = 'blob', ground = 'blob', flying = 'wind', bug = 'needle', rock = 'rock',
    ghost = 'shadow', dragon = 'fire', dark = 'crescent', steel = 'shard', fairy = 'star', normal = 'star',
}

-- Las tablas devueltas se cachean por id de movimiento / tipo (no se crean por
-- llamada): quien las reciba NO debe modificarlas.
local moveCache, typeCache = {}, {}

-- Aspecto de un movimiento: { pal, proj, beam?, melee?, aura?, buff?, trail?, inward?, rise? }
function V.forMove(m)
    local key = m.id or m.type
    local r = moveCache[key]
    if r then return r end
    local v = V.MOVE[m.id]
    r = { pal = m.type, proj = V.TYPE_SHAPE[m.type] or 'ball' }
    if v then
        for k, val in pairs(v) do r[k] = val end
        r.pal = v.pal or m.type
    end
    moveCache[key] = r
    return r
end

-- Forma por defecto de un tipo (disparos enemigos): { proj, pal }
function V.forType(t)
    local r = typeCache[t]
    if r then return r end
    r = { proj = V.TYPE_SHAPE[t] or 'ball', pal = PAL[t] and t or 'normal' }
    typeCache[t] = r
    return r
end
