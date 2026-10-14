-- world.lua — arena abierta infinita con obstáculos (port de js/world/world.js).
--
-- Terreno por tile, determinista (ruido de valor con semilla):
--   floor   suelo (con manchas de tierra)
--   wall    formaciones rocosas: bloquean a quien camina y a los proyectiles
--   liquid  agua (ralentiza) o lava en el volcán (quema)
--
-- Objetos del escenario (props), dibujados ordenados por Y con las entidades:
--   tree, rock, chest, grass, altar, spring, bigchest, trap
--   (la lógica de los interactivos está en src/interact.lua)
--
-- Grieta: setArena() convierte una zona lejana del mapa en una arena redonda
-- cerrada por paredes, donde se lucha contra un legendario (src/rift.lua).
--
-- Coordenadas: (x, y) de una entidad = sus PIES, en el plano del suelo.
-- Los chunks se separan en DATOS (baratos, siempre) y BATCH (un SpriteBatch
-- del tileset del bioma, sólo para los visibles).
--
-- Diferencias con la web (ver docs/PORT.md §13):
--   * El suelo se dibuja con un tileset por bioma (img/tiles/<bi>.png +
--     data/tiles.lua, generados por tools/gen_tiles.py), no se pinta en código.
--   * La "tierra" es un booleano por tile (autotile de 4 vecinos).
--   * No hay fundido de bioma: el cambio es directo.
--   * Sin cooperativo.
--
-- Este fichero también define G.Tiles (sólo DATOS de tiles.js: biomas, temas
-- de arena, índices), que usan rift.lua y weather.lua.
local U = G.U
local lg = love.graphics
local floor, abs, min, max, sin, huge = math.floor, math.abs, math.min, math.max, math.sin, math.huge
local sqrt = math.sqrt
local random = love.math.random
local H = U.hash

-- =====================================================================
-- G.Tiles: datos de biomas (de js/world/tiles.js)
-- =====================================================================
local Tiles = {}
G.Tiles = Tiles

Tiles.T = 16                                 -- píxeles de arte por tile

-- Índices 0..2: biomas normales (se turnan en una run). A partir de ARENA,
-- las arenas de la grieta (una por tipo, en el orden de ARENA_TYPES).
local BIOMES = {
    [0] = { name = 'Bosque Umbrío', liquid = 'water',
            floor = { '#3e7a39', '#44813d', '#397134' }, dirt = { '#7d6742', '#735e3b', '#86704a' },
            speck = '#2f5f2b', light = '#5f9d50', flowers = { '#f4d65c', '#f39ac0', '#eef2ff' },
            wallTop = { '#5d6e49', '#677a50', '#566544' }, wallLight = '#88a06e', wallEdge = '#26301f',
            wallFace = { '#3e4934', '#363f2d' }, wallFaceDark = '#232a1d',
            liq = '#3b7fc6', liqDeep = '#2c64a6', foam = '#b3defa', shore = '#2b5b2a',
            prop = 'tree', leaf = { '#235a2b', '#2f7535', '#45943f', '#64b252' }, trunk = { '#5b3b22', '#7a5130' },
            rock = { '#5e6670', '#7f8893', '#a1aab4' }, grass = { '#2f6b2c', '#4c9a3f', '#7cc45a' } },
    [1] = { name = 'Cueva Cristal', liquid = 'water',
            floor = { '#4d5778', '#535e81', '#47506f' }, dirt = { '#3c4462', '#424a69', '#37405b' },
            speck = '#3b4363', light = '#6a78a4', flowers = { '#8fe3ff', '#c9a6ff', '#7ef0d0' },
            wallTop = { '#5f5089', '#695996', '#56497d' }, wallLight = '#a08ddc', wallEdge = '#1f1934',
            wallFace = { '#3f3463', '#382e59' }, wallFaceDark = '#221c3a',
            liq = '#2a9cab', liqDeep = '#1d7c8a', foam = '#aaf4f7', shore = '#33405e',
            prop = 'crystal', leaf = { '#5ad1e8', '#8fe7f5', '#c8f7ff', '#ffffff' }, trunk = { '#3a4a78', '#4e64a0' },
            rock = { '#555d79', '#737c9c', '#959fc0' }, grass = { '#3d5c8a', '#5a86c0', '#8ab8ee' } },
    [2] = { name = 'Monte Ascuas', liquid = 'lava',
            floor = { '#5b4537', '#644c3c', '#533f32' }, dirt = { '#403530', '#473b34', '#392f2b' },
            speck = '#47362b', light = '#806452', flowers = { '#ff8d3d', '#ffc45e', '#e06a4a' },
            wallTop = { '#3c3634', '#443d3a', '#35302e' }, wallLight = '#625752', wallEdge = '#141110',
            wallFace = { '#2b2624', '#25201f' }, wallFaceDark = '#151211',
            liq = '#e45a1f', liqDeep = '#b9401a', foam = '#ffd46a', shore = '#3a2a22',
            prop = 'dead', leaf = { '#4a3a30', '#5e4a3c', '#6f5a49', '#806a58' }, trunk = { '#3a2e27', '#52423a' },
            rock = { '#4e4642', '#6a605b', '#877c76' }, grass = { '#6b4a2a', '#94693a', '#c4914e' } },
}
Tiles.BIOMES = BIOMES
local NORMAL = 3                             -- biomas que se van turnando en una run
local ARENA = 3                              -- a partir de aquí, las arenas de la grieta
Tiles.NORMAL, Tiles.ARENA = NORMAL, ARENA

-- Cada tipo tiene su arena: paleta, terreno y clima.
--   liquid   charcos: water (frena) · swamp (frena más) · lava (quema) ·
--            poison (envenena) · spark (descarga) · ice (resbala)
--   pools    cuánto terreno es charco (0 = ninguno)
--   pillars  probabilidad de una columna 2×2 (cobertura) por bloque
--   props    densidad de árboles / rocas / hierba
--   weather  clima que trae (ver src/weather.lua) o nil
local ARENA_THEMES = {
    normal   = { name = 'Pradera Eterna', floor = '#6f8a4f', wall = '#8a7f6a', liquid = 'water', liq = '#4f8fd0', prop = 'tree',
                 leaf = '#5aa04a', trunk = '#6b4a2a', flowers = { '#f4d65c', '#ffffff', '#f39ac0' }, grass = '#5a9a40', rock = '#8a8a8a',
                 pools = 0, pillars = 0.035, props = { tree = 0.025, grass = 0.05 }, weather = nil },
    fire     = { name = 'Monte Ascuas', floor = '#5b3a2e', wall = '#3a2826', liquid = 'lava', liq = '#e45a1f', foam = '#ffd46a', prop = 'dead',
                 leaf = '#5e4a3c', trunk = '#3a2e27', flowers = { '#ff8d3d', '#ffc45e', '#e06a4a' }, grass = '#94693a', rock = '#6a605b',
                 pools = 0.31, pillars = 0.03, props = { tree = 0.01 }, weather = 'sun' },
    water    = { name = 'Gruta Marina', floor = '#3c6a80', wall = '#2a4660', liquid = 'water', liq = '#2f86d6', foam = '#bfeaff', prop = 'crystal',
                 leaf = '#5fd0e8', trunk = '#2a4a78', flowers = { '#ff9ec4', '#7ef0d0', '#ffffff' }, grass = '#3f8a9a', rock = '#5d7a90',
                 pools = 0.33, pillars = 0.02, props = { tree = 0.015 }, weather = 'rain' },
    grass    = { name = 'Selva Esmeralda', floor = '#3a7a32', wall = '#4a6a36', liquid = 'swamp', liq = '#4f6b2a', foam = '#9ac25a', prop = 'tree',
                 leaf = '#3f9a3a', trunk = '#5b3b22', flowers = { '#f4d65c', '#ff8ad8', '#ffffff' }, grass = '#4caa3f', rock = '#6a7a5a',
                 pools = 0.22, pillars = 0, props = { tree = 0.05, grass = 0.12 }, weather = nil },
    electric = { name = 'Central Voltio', floor = '#4a4840', wall = '#3a3a48', liquid = 'spark', liq = '#e8c020', foam = '#fff6c0', prop = 'crystal',
                 leaf = '#ffd23f', trunk = '#5a5030', flowers = { '#ffe14d', '#ffffff', '#7fd0ff' }, grass = '#8a8a40', rock = '#70707a',
                 pools = 0.28, pillars = 0.04, props = { tree = 0.01 }, weather = 'rain' },
    ice      = { name = 'Glaciar Eterno', floor = '#b8cfe0', wall = '#7f9fc0', liquid = 'ice', liq = '#9fd8f0', foam = '#ffffff', prop = 'crystal',
                 leaf = '#bfe8ff', trunk = '#6f8fb0', flowers = { '#ffffff', '#9fe0ff', '#d8f1ff' }, grass = '#9fc0d8', rock = '#8fa8c0',
                 pools = 0.36, pillars = 0.02, props = { tree = 0.02 }, weather = 'snow' },
    fighting = { name = 'Dojo Ancestral', floor = '#8a6a46', wall = '#5e4232', liquid = 'water', liq = '#4f8fd0', prop = 'tree',
                 leaf = '#4f8a3a', trunk = '#5b3b22', flowers = { '#ff5f6d', '#f4d65c', '#ffffff' }, grass = '#6a8a40', rock = '#8a7a6a',
                 pools = 0, pillars = 0.075, props = { tree = 0.008 }, weather = nil },
    poison   = { name = 'Ciénaga Tóxica', floor = '#46384f', wall = '#33263f', liquid = 'poison', liq = '#9a4fc0', foam = '#e0a6ff', prop = 'dead',
                 leaf = '#5a4a6a', trunk = '#3a2f45', flowers = { '#c86bdc', '#8bd94a', '#e0a6ff' }, grass = '#6a5a8a', rock = '#5a4f6a',
                 pools = 0.31, pillars = 0.015, props = { tree = 0.02 }, weather = nil },
    ground   = { name = 'Desierto Rojo', floor = '#b08a52', wall = '#8a5e34', liquid = 'swamp', liq = '#9a7a48', foam = '#d6b98a', prop = 'dead',
                 leaf = '#8a6a40', trunk = '#6a4a2a', flowers = { '#e06a4a', '#f4d65c', '#ffffff' }, grass = '#b0904a', rock = '#9a7a5a',
                 pools = 0.25, pillars = 0.04, props = { tree = 0.01, rock = 0.015 }, weather = 'sand' },
    flying   = { name = 'Pico Celeste', floor = '#9fb8d8', wall = '#dfe8f4', liquid = 'water', liq = '#7fb8ff', prop = 'tree',
                 leaf = '#e8f2ff', trunk = '#9aa8c0', flowers = { '#ffffff', '#ffe14d', '#bfe0ff' }, grass = '#b8d0e8', rock = '#c0ccdc',
                 pools = 0, pillars = 0.02, props = { tree = 0.025 }, weather = nil },
    psychic  = { name = 'Templo Mental', floor = '#5e4470', wall = '#3e2a55', liquid = 'water', liq = '#8a5ad0', prop = 'crystal',
                 leaf = '#ff8ad8', trunk = '#5a3a7a', flowers = { '#ff8ad8', '#c9a6ff', '#ffffff' }, grass = '#8a5a9a', rock = '#7a6a8a',
                 pools = 0, pillars = 0.045, props = { tree = 0.02 }, weather = nil },
    bug      = { name = 'Bosque Colmena', floor = '#5a6a2a', wall = '#5e4a26', liquid = 'swamp', liq = '#6a7a2a', foam = '#c4d65a', prop = 'tree',
                 leaf = '#8aaa30', trunk = '#5b3b22', flowers = { '#f4d65c', '#ffffff', '#c4d65a' }, grass = '#8aaa30', rock = '#7a7a5a',
                 pools = 0.2, pillars = 0, props = { tree = 0.04, grass = 0.12 }, weather = nil },
    rock     = { name = 'Cantera Antigua', floor = '#7a6a58', wall = '#55473a', liquid = 'water', liq = '#4f8fd0', prop = 'dead',
                 leaf = '#6a5a4a', trunk = '#4a3e32', flowers = { '#c9b28a', '#ffffff', '#a89070' }, grass = '#8a7a5a', rock = '#8a7a6a',
                 pools = 0, pillars = 0.08, props = { rock = 0.03 }, weather = 'sand' },
    ghost    = { name = 'Cementerio Sombrío', floor = '#383447', wall = '#24202e', liquid = 'water', liq = '#3a3a6a', prop = 'dead',
                 leaf = '#4a4060', trunk = '#2e2838', flowers = { '#9a8ad0', '#5fe0c0', '#c9cfdc' }, grass = '#4a4a60', rock = '#5a5670',
                 pools = 0, pillars = 0.03, props = { tree = 0.03 }, weather = 'fog' },
    dragon   = { name = 'Santuario Dragón', floor = '#363a5e', wall = '#24264a', liquid = 'lava', liq = '#7b5cff', foam = '#c9a6ff', prop = 'crystal',
                 leaf = '#7b5cff', trunk = '#2a2a5a', flowers = { '#7b5cff', '#ffd23f', '#ffffff' }, grass = '#4a4a8a', rock = '#5a5a8a',
                 pools = 0.22, pillars = 0.04, props = { tree = 0.015 }, weather = nil },
    dark     = { name = 'Callejón Oscuro', floor = '#2c282e', wall = '#1c181f', liquid = 'water', liq = '#2a2a3a', prop = 'dead',
                 leaf = '#3a3040', trunk = '#241e28', flowers = { '#ff5f6d', '#6b5c52', '#9a8a9a' }, grass = '#3a343a', rock = '#4a444a',
                 pools = 0, pillars = 0.05, props = { tree = 0.02 }, weather = nil },
    steel    = { name = 'Fortaleza de Acero', floor = '#6d7888', wall = '#465060', liquid = 'water', liq = '#4f8fd0', prop = 'crystal',
                 leaf = '#c9d2de', trunk = '#5d6773', flowers = { '#c9d2de', '#ffd23f', '#ffffff' }, grass = '#8a96a6', rock = '#9aa6b5',
                 pools = 0, pillars = 0.08, props = { tree = 0.01 }, weather = nil },
    fairy    = { name = 'Bosque Encantado', floor = '#4f7f5a', wall = '#7a5a8a', liquid = 'water', liq = '#8fd8ff', foam = '#ffe0f4', prop = 'tree',
                 leaf = '#e08ad0', trunk = '#6b4a5a', flowers = { '#ff8ad8', '#ffffff', '#c9a6ff' }, grass = '#c48ad8', rock = '#9a8aa8',
                 pools = 0.16, pillars = 0, props = { tree = 0.05, grass = 0.1 }, weather = nil },
}
Tiles.ARENA_THEMES = ARENA_THEMES
-- Mismo orden que Object.keys(ARENA_THEMES) en el JS: fija el índice de bioma.
local ARENA_TYPES = { 'normal', 'fire', 'water', 'grass', 'electric', 'ice', 'fighting', 'poison', 'ground',
                      'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy' }
Tiles.ARENA_TYPES = ARENA_TYPES

-- Paleta completa de bioma a partir de los pocos colores de una arena.
local function arenaBiome(th)
    local shade = U.shade
    local f, w, L = th.floor, th.wall, th.liq
    return {
        name = 'Grieta · ' .. th.name, liquid = th.liquid,
        floor = { f, shade(f, 0.05), shade(f, -0.06) }, dirt = { shade(f, -0.16), shade(f, -0.12), shade(f, -0.2) },
        speck = shade(f, -0.25), light = shade(f, 0.22), flowers = th.flowers,
        wallTop = { w, shade(w, 0.07), shade(w, -0.07) }, wallLight = shade(w, 0.32), wallEdge = shade(w, -0.7),
        wallFace = { shade(w, -0.3), shade(w, -0.38) }, wallFaceDark = shade(w, -0.55),
        liq = L, liqDeep = shade(L, -0.22), foam = th.foam or shade(L, 0.55), shore = shade(f, -0.32),
        prop = th.prop, leaf = { shade(th.leaf, -0.35), shade(th.leaf, -0.15), th.leaf, shade(th.leaf, 0.3) },
        trunk = { shade(th.trunk, -0.2), th.trunk },
        rock = { shade(th.rock, -0.2), th.rock, shade(th.rock, 0.22) },
        grass = { shade(th.grass, -0.28), th.grass, shade(th.grass, 0.28) },
    }
end
for i = 1, #ARENA_TYPES do BIOMES[ARENA + i - 1] = arenaBiome(ARENA_THEMES[ARENA_TYPES[i]]) end

-- La arena de Arceus al minuto 30 (src/judgment.lua): ceniza, ruinas y árboles
-- muertos, con un claro donde aterriza (clear). No es de ninguna grieta: va
-- aparte (bioma JUDGMENT, img/tiles/21.png) y no entra en ARENA_TYPES ni en el
-- ciclo de biomas de la run.
ARENA_THEMES.judgment = { name = 'Ruinas del Juicio', floor = '#4a4240', wall = '#2e2829', liquid = 'lava', liq = '#e8a82a',
                          foam = '#fff1b8', prop = 'dead', leaf = '#3e3633', trunk = '#2a2321',
                          flowers = { '#8a7f76', '#e8a82a', '#5a514c' }, grass = '#5e544c', rock = '#6a625c',
                          pools = 0, pillars = 0.03, props = { tree = 0.012, rock = 0.02 }, weather = nil, clear = 4.5 }
local JUDGMENT = ARENA + #ARENA_TYPES
Tiles.JUDGMENT = JUDGMENT
BIOMES[JUDGMENT] = arenaBiome(ARENA_THEMES.judgment)
BIOMES[JUDGMENT].name = ARENA_THEMES.judgment.name

-- Índice de bioma de la arena de un tipo.
function Tiles.arenaBiome(typ)
    if typ == 'judgment' then return JUDGMENT end
    local i = U.indexOf(ARENA_TYPES, typ)
    return ARENA + ((i or 1) - 1)
end

-- =====================================================================
-- G.World
-- =====================================================================
local W = {}
G.World = W

local T = Tiles.T                            -- px de arte por tile (16)
local N = 16                                 -- tiles por chunk
local SC = G.Sprites.PX                      -- escala arte -> mundo (2)
local TS = T * SC                            -- tamaño de tile en mundo (32)
local CW = N * TS                            -- tamaño de chunk en mundo (512)
W.TS, W.CW = TS, CW
local FLOOR, WALL, LIQUID = 0, 1, 2
local KIND = { [0] = 'floor', 'wall', 'liquid' }

local seed, biome = 1, 0
local arena = nil                            -- { tx, ty, r, type, th } en tiles
local data = {}                              -- clave numérica -> datos del chunk
local dataOrder = {}                         -- claves en orden de creación (se desaloja la más vieja)
local MAX_DATA = 120
local broken = {}                            -- props destruidos: clave de tile -> true
local nextPropId = 1
local propsVer = 0                           -- sube al cambiar los objetos a la vista (chunk nuevo, bioma...)
local candL, candR, candT, candB = 0, -1, 0, -1   -- rectángulo de candidatos visibles (W.visibleSplit)

-- Claves numéricas (nada de concatenar strings por fotograma).
local function ckey(cx, cy) return cx * 100003 + cy end
local function tkey(tx, ty) return tx * 1000003 + ty end

-- ---------------- ruido ----------------

-- Hash de cada esquina de la rejilla del ruido, por semilla: una casilla y sus
-- vecinas comparten esquinas, y al generar un trozo se consultan desordenadas
-- (candidatas de los vecinos, bosquecillo, hierba...), así que guardar sólo la
-- última celda fallaba casi siempre (~5000 hashes por trozo). Mismo resultado,
-- ~4 veces menos hashes. Se vacía al pasar de LAT_MAX esquinas (memoria).
local latC, latN = {}, 0
local LAT_MAX = 20000                        -- (~900 esquinas por trozo nuevo)
-- Ruido de valor (vnoise): interpolación suave entre los hashes de las 4 esquinas
-- de la celda. fbm son dos octavas:
--   vnoise(x, y, s) * 0.65 + vnoise(x * 2.13 + 17, y * 2.13 - 9, s + 1) * 0.35
-- con vnoise escrita aquí dentro dos veces (en Lua 5.1 interpretado cada llamada
-- cuesta, y esto se llama ~1500 veces por trozo). Mismas operaciones, mismo resultado.
local function fbm(x, y, s)
    local xi, yi = floor(x), floor(y)
    local xf, yf = x - xi, y - yi
    local u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    local L = latC[s]
    if not L then L = {}; latC[s] = L end
    local k = xi * 1000003 + yi
    local a, b, c, d = L[k], L[k + 1000003], L[k + 1], L[k + 1000004]
    if not a then a = H(xi, yi, s); L[k] = a; latN = latN + 1 end
    if not b then b = H(xi + 1, yi, s); L[k + 1000003] = b; latN = latN + 1 end
    if not c then c = H(xi, yi + 1, s); L[k + 1] = c; latN = latN + 1 end
    if not d then d = H(xi + 1, yi + 1, s); L[k + 1000004] = d; latN = latN + 1 end
    local n1 = (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    -- Segunda octava.
    x, y, s = x * 2.13 + 17, y * 2.13 - 9, s + 1
    xi, yi = floor(x), floor(y)
    xf, yf = x - xi, y - yi
    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    L = latC[s]
    if not L then L = {}; latC[s] = L end
    k = xi * 1000003 + yi
    a, b, c, d = L[k], L[k + 1000003], L[k + 1], L[k + 1000004]
    if not a then a = H(xi, yi, s); L[k] = a; latN = latN + 1 end
    if not b then b = H(xi + 1, yi, s); L[k + 1000003] = b; latN = latN + 1 end
    if not c then c = H(xi, yi + 1, s); L[k + 1] = c; latN = latN + 1 end
    if not d then d = H(xi + 1, yi + 1, s); L[k + 1000004] = d; latN = latN + 1 end
    if latN > LAT_MAX then latC, latN = {}, 0 end
    return n1 * 0.65 + ((a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v) * 0.35
end

-- ---------------- terreno "puro" (sin caché) ----------------

local function arenaDist(tx, ty)
    if not arena then return huge end
    return U.hypot(tx - arena.tx, ty - arena.ty)
end
local function arenaOuter() if arena then return arena.r + 7 end return 0 end

-- Pasillo libre de la arena: donde apareces (sur) y el legendario (norte).
-- Con `clear` en el tema, además un claro donde aterriza Arceus (5 al norte).
local function arenaSafe(tx, ty)
    local lx, ly = tx - arena.tx, ty - arena.ty
    return (abs(lx) <= 2 and ly >= -6 and ly <= 5) or U.hypot(lx, ly) < 2.5
        or ((arena.th.clear or 0) > 0 and U.hypot(lx, ly + 5) < arena.th.clear)
end

local function terrainRaw(tx, ty)
    if arena then
        local ad = arenaDist(tx, ty)
        if ad < arenaOuter() then
            if ad >= arena.r then return WALL end
            if arenaSafe(tx, ty) then return FLOOR end
            local th = arena.th
            -- Columnas de 2×2 (cobertura) y charcos según el tipo de la arena.
            if th.pillars and th.pillars > 0 and ad < arena.r - 2
               and H(floor(tx / 2), floor(ty / 2), seed + 31 + arena.tx) < th.pillars then return WALL end
            if th.pools and th.pools > 0 and ad < arena.r - 1.5
               and fbm(tx / 3.2, ty / 3.2, seed + 37 + arena.tx) < th.pools then return LIQUID end
            return FLOOR
        end
    end
    local d2 = tx * tx + ty * ty
    if d2 < 81 then return FLOOR end                        -- claro inicial (a menos de 9)
    local ramp = (sqrt(d2) - 9) / 8                         -- aparición suave (0..1)
    if ramp > 1 then ramp = 1 end
    if fbm(tx / 13, ty / 13, seed + 101) < 0.04 + 0.23 * ramp then return LIQUID end
    -- (Sin formaciones rocosas en el mapa normal: quedaban como bloques planos.
    -- Los árboles hacen de obstáculo. Las arenas de las grietas sí tienen muro.)
    return FLOOR
end

-- Caché del terreno puro por casilla: al generar un trozo, cada casilla se
-- consultaba ~20 veces (huecos libres alrededor de árboles, matas, interactivos)
-- y cada consulta son 8 hashes de ruido. Se vacía con la de piezas (nueva semilla,
-- arena) y al pasar de un tope de memoria (todo es recalculable).
local terrCache, terrN = {}, 0
local specCache = {}                         -- casillas sin interactivo (specialRaw): true
local specBlk = {}                           -- interactivos por bloque de 8x8 (ver nearSpecial)
local function terrainC(tx, ty)
    local k = tx * 1000003 + ty
    local t = terrCache[k]
    if t then return t end
    t = terrainRaw(tx, ty)
    terrN = terrN + 1
    if terrN > 60000 then terrCache = {}; specCache = {}; specBlk = {}; terrN = 1 end
    terrCache[k] = t
    return t
end

-- Mancha de tierra: booleano por tile (en la web era un campo por píxel).
local function dirtRaw(tx, ty)
    return fbm(tx / 6, ty / 6, seed + 303) > 0.64
end

-- ---------------- props ----------------

local PROP = {
    tree     = { solid = true,  hp = huge, r = 20 },     -- la base de la copa, no sólo el tronco
    rock     = { solid = true,  hp = 34,   r = 12 },
    chest    = { solid = true,  hp = 22,   r = 12 },
    grass    = { solid = false, hp = 1,    r = 14 },
    altar    = { solid = true,  hp = huge, r = 9 },
    spring   = { solid = false, hp = huge, r = 22, flat = true },
    bigchest = { solid = true,  hp = huge, r = 14 },
    trap     = { solid = false, hp = huge, r = 9, flat = true },
    -- Decoración de ruta (giovanneluna/poke-survivors): kind = 1 arbusto (bloquea),
    -- 2 helecho (no bloquea), 3 seto grande (bloquea).
    deco     = { solid = false, hp = huge, r = 8 },
    -- Hierba normal (mata corta) y flores de 4.ª gen: sólo adorno animado.
    tuft     = { solid = false, hp = huge, r = 10 },
    flower   = { solid = false, hp = huge, r = 6 },
}

local SPECIAL = { altar = true, spring = true, bigchest = true, trap = true }

local function makeProp(typ, tx, ty, kind)
    local d = PROP[typ]
    local p = {
        id = nextPropId, type = typ, tx = tx, ty = ty, kind = kind or 0,
        x = tx * TS + TS / 2, y = ty * TS + TS - 4,
        r = d.r, hp = d.hp, maxHp = d.hp, solid = d.solid, flat = d.flat == true,
        destructible = d.hp ~= huge, flash = 0,
        wiggle = H(tx, ty, 9) * 6.28,
        used = false, charge = 1, open = 0,              -- altar / manantial / cofre con candado
    }
    nextPropId = nextPropId + 1
    return p
end

-- ---------------- colocación (estilo Vampire Survivors) ----------------
-- Mucho campo abierto para esquivar, bosquecillos dispersos y árboles sueltos.
-- Los árboles y matas ("piezas") van en casillas al azar, sin filas ni columnas:
-- cada casilla candidata tiene una prioridad aleatoria y sólo se queda si ninguna
-- candidata a 2 casillas o menos tiene más prioridad. Así dos piezas quedan
-- siempre a 3 casillas o más (96 unidades, el ancho del árbol más grande) y los
-- sprites no se pisan. Todo es determinista (se consulta desde casillas vecinas).

local candCache, pieceCache = {}, {}
local cacheN = 0
local function clearPieceCache()
    candCache, pieceCache, cacheN = {}, {}, 0
    terrCache, terrN, specCache, specBlk = {}, 0, {}, {}
end

-- (En estos bucles se mira la caché directamente y sólo se llama a la función si
-- falta: en Lua 5.1 interpretado cada llamada cuesta más que la consulta.)
local function openAt(tx, ty)
    for b = -1, 1 do
        local y = ty + b
        for a = -1, 1 do
            local t = terrCache[(tx + a) * 1000003 + y] or terrainC(tx + a, y)
            if t ~= FLOOR then return false end
        end
    end
    return true
end

-- Interactivos (altar, manantial, cofre grande, trampa): raros, lejos del inicio.
local function specialRaw(tx, ty)
    local k = tx * 1000003 + ty
    if specCache[k] then return nil end
    local hs = H(tx, ty, seed + 909)
    if hs >= 0.0032 then specCache[k] = true return nil end
    if U.hypot(tx, ty) <= 12 or arenaDist(tx, ty) < arenaOuter() + 2
       or terrainC(tx, ty) ~= FLOOR or not openAt(tx, ty) then
        specCache[k] = true                     -- (también es puro: se vacía con la arena)
        return nil
    end
    local typ = hs < 0.0004 and 'altar' or hs < 0.0008 and 'spring' or hs < 0.0011 and 'bigchest' or 'trap'
    return typ, floor(H(tx, ty, seed + 910) * (typ == 'altar' and 4 or 3))
end

-- Interactivos por bloques de 8x8 casillas: lista { tx, ty, tx, ty... } o false
-- (casi siempre). Así "¿hay uno cerca?" mira 1-4 bloques en vez de 8-48 casillas.
local function specBlock(bx, by)
    local k = bx * 100003 + by
    local l = specBlk[k]
    if l ~= nil then return l end
    l = false
    for j = by * 8, by * 8 + 7 do
        for i = bx * 8, bx * 8 + 7 do
            if not specCache[i * 1000003 + j] and specialRaw(i, j) then
                if not l then l = {} end
                local n = #l
                l[n + 1] = i; l[n + 2] = j
            end
        end
    end
    specBlk[k] = l
    return l
end

-- ¿Hay un interactivo a `d` casillas o menos (sin contar la propia)?
local function nearSpecial(tx, ty, d)
    for by = floor((ty - d) / 8), floor((ty + d) / 8) do
        for bx = floor((tx - d) / 8), floor((tx + d) / 8) do
            local l = specBlk[bx * 100003 + by]
            if l == nil then l = specBlock(bx, by) end
            if l then
                for i = 1, #l, 2 do
                    local sx, sy = l[i], l[i + 1]
                    if (sx ~= tx or sy ~= ty) and abs(sx - tx) <= d and abs(sy - ty) <= d then return true end
                end
            end
        end
    end
    return false
end

-- Bosquecillo: ruido ancho; en él hay muchos más árboles.
local function groveAt(tx, ty) return fbm(tx / 9, ty / 9, seed + 505) end

-- Candidata a pieza en (tx, ty): { typ, kind, pri } o false.
local function candRaw(tx, ty)
    local k = tkey(tx, ty)
    local c = candCache[k]
    if c ~= nil then return c end
    -- Tope de memoria: al explorar mucho se vacía (todo es recalculable).
    cacheN = cacheN + 1
    if cacheN > 40000 then clearPieceCache(); cacheN = 1 end
    c = false
    if tx * tx + ty * ty >= 49 and openAt(tx, ty) then        -- (a 7 casillas o más del centro; openAt mira la propia)
        local typ, kind = nil, 0
        local h = H(tx, ty, seed + 404)
        local ad = arenaDist(tx, ty)
        if ad < arenaOuter() + 2 then
            -- Arenas de la grieta: árboles de su tipo, también al azar y separados.
            if arena and ad < arena.r - 1.2 and not arenaSafe(tx, ty)
               and H(tx, ty, seed + 777) < (arena.th.props.tree or 0) * 6 then typ = 'tree' end
        elseif h < 0.36 then                               -- (si no, no hay pieza en ningún caso)
            local gv = groveAt(tx, ty)
            if gv > 0.62 then                              -- bosquecillo
                if h < 0.30 then typ = 'tree' elseif h < 0.36 then typ, kind = 'deco', 1 end
            elseif gv > 0.55 then                          -- borde del bosquecillo
                if h < 0.07 then typ = 'tree' elseif h < 0.12 then typ, kind = 'deco', 1 end
            else                                           -- campo abierto
                if h < 0.010 then typ = 'tree' elseif h < 0.022 then typ, kind = 'deco', 1 end
            end
        end
        -- Nada que tape a un interactivo (su sombra los pisaba).
        if typ and not nearSpecial(tx, ty, 3) then
            c = { typ = typ, kind = kind, pri = H(tx, ty, seed + 4545) }
        end
    end
    candCache[k] = c
    return c
end

-- ¿Gana la candidata de (tx, ty) a todas las de 2 casillas a la redonda?
local function winsAt(tx, ty, c)
    local pri = c.pri
    for b = -2, 2 do
        local y = ty + b
        for a = -2, 2 do
            if a ~= 0 or b ~= 0 then
                local o = candCache[(tx + a) * 1000003 + y]
                if o == nil then o = candRaw(tx + a, y) end
                if o and o.pri > pri then return false end
            end
        end
    end
    return true
end

-- Pieza definitiva en (tx, ty): { typ, kind } o false. Las matas no se ponen
-- pegadas a un árbol (a 4 casillas o menos).
local function pieceAt(tx, ty)
    local k = tkey(tx, ty)
    local r = pieceCache[k]
    if r ~= nil then return r end
    r = false
    local c = candRaw(tx, ty)
    if c and winsAt(tx, ty, c) then
        r = c
        if c.typ == 'deco' then
            for b = -4, 4 do
                for a = -4, 4 do
                    local o = (a ~= 0 or b ~= 0) and candRaw(tx + a, ty + b)
                    if o and o.typ == 'tree' and winsAt(tx + a, ty + b, o) then r = false end
                end
            end
        end
    end
    pieceCache[k] = r
    return r
end

-- ¿Hay una pieza en esta casilla o pegada a ella?
local function nearPiece(tx, ty)
    for b = -1, 1 do
        local y = ty + b
        for a = -1, 1 do
            if a ~= 0 or b ~= 0 then
                local r = pieceCache[(tx + a) * 1000003 + y]
                if r == nil then r = pieceAt(tx + a, y) end
                if r then return true end
            end
        end
    end
    return false
end

-- Objetos de las casillas i0..i1 de la fila j del chunk (se genera a trozos de
-- fila: ver genStep). Lo caro (ruido, hashes, "¿hay suelo alrededor?") se calcula
-- sólo cuando decide algo, en el mismo orden de prioridades de siempre.
local function placePropsRow(c, j, i0, i1)
    local terr, props, propAt = c.terr, c.props, c.propAt
    do
        for i = i0, i1 do
            local lidx = j * N + i + 1
            if terr[lidx] == FLOOR then
                local tx, ty = c.cx * N + i, c.cy * N + j
                -- (A 7 casillas o más del centro: hypot >= 7 sin raíz.)
                if tx * tx + ty * ty >= 49 and not broken[tx * 1000003 + ty] then
                    local typ, kind = nil, 0
                    local ad = arenaDist(tx, ty)
                    local piece = pieceAt(tx, ty)
                    if piece then
                        typ, kind = piece.typ, piece.kind
                    elseif nearPiece(tx, ty) then
                        typ = nil                         -- nada pegado a un árbol o mata
                    elseif ad < arenaOuter() + 2 then
                        -- Dentro de la arena: la decoración de su tipo (y nada en el pasillo).
                        if arena and ad < arena.r - 1.2 and not arenaSafe(tx, ty) then
                            local pr = arena.th.props
                            local hh = H(tx, ty, seed + 777)
                            local ptree, prock, pgrass = pr.tree or 0, pr.rock or 0, pr.grass or 0
                            -- (Las rocas necesitan suelo alrededor: no se pegan a paredes / agua.)
                            if hh >= ptree and hh < ptree + prock and openAt(tx, ty) then typ = 'rock'
                            elseif hh > 1 - pgrass then typ = 'grass' end
                        end
                    else
                        local sp, sk = nil, 0
                        if not specCache[tx * 1000003 + ty] then sp, sk = specialRaw(tx, ty) end
                        if sp then
                            typ, kind = sp, sk
                        elseif nearSpecial(tx, ty, 1) then
                            typ = nil                     -- alrededor de un interactivo, despejado
                        else
                            local h = H(tx, ty, seed + 404)
                            -- Rocas y cofres: necesitan suelo alrededor (no pegarse a paredes / agua).
                            local open = h > 0.985 and openAt(tx, ty)
                            if open and h > 0.992 then typ = 'rock'
                            elseif open and h <= 0.992 and H(tx, ty, seed + 606) < 0.07 then typ = 'chest'
                            elseif groveAt(tx, ty) <= 0.62 then
                                -- (En el bosquecillo, nada de esto.)
                                -- Hierba en montones variados: grandes (ruido ancho), pequeños de
                                -- 2-5 matas (ruido fino) y matas sueltas.
                                if fbm(tx / 6, ty / 6, seed + 707) > 0.68 then typ = 'grass'
                                elseif fbm(tx / 1.6, ty / 1.6, seed + 717) > 0.74 then typ = 'grass'
                                -- Flores también en grupos (cada grupo de un color).
                                elseif fbm(tx / 2.2, ty / 2.2, seed + 737) > 0.75 then
                                    typ = 'flower'; kind = H(floor(tx / 5), floor(ty / 5), seed + 738) > 0.5 and 1 or 0
                                else
                                    local hd = H(tx, ty, seed + 1212)
                                    if hd < 0.07 then typ = 'tuft'
                                    elseif hd > 0.993 then typ = 'flower'; kind = hd > 0.9965 and 1 or 0 end
                                end
                            end
                        end
                    end

                    if typ then
                        local p = makeProp(typ, tx, ty, kind)
                        props[#props + 1] = p
                        if p.solid then propAt[lidx] = p end
                        if typ == 'tree' then c.trees[#c.trees + 1] = p end
                        if typ == 'grass' or typ == 'tuft' then c.grassAt[lidx] = p end   -- (W.rustle)
                    end
                end
            end
        end
    end
end

-- ---------------- datos de chunk ----------------

local dropBatch                              -- (definida más abajo, en dibujo)

-- Un chunk se genera por pasos: N filas de terreno y luego las de objetos (los
-- objetos miran el terreno de las casillas vecinas). Generar uno entero son
-- ~70 ms en la consola (eran ~95 antes de las cachés de ruido): W.update adelanta los de alrededor de la cámara paso a
-- paso, con el tiempo que le sobra al fotograma (prefetch), y así al llegar ya están.
--
-- Nadie más genera trozos enteros de golpe, salvo los de la ZONA DURA (los que se
-- ven: hay que dibujarlos y ahí está el jugador; si el prefetch va bien ya están
-- hechos) y en las cargas. Las consultas "de fondo" (colisión de un enemigo lejano, la
-- rejilla de colisión, los candidatos a dibujar, los interactivos cercanos...)
-- usan chunkSoft: si el trozo no está, no lo generan:
--   * el terreno y la tierra son funciones puras (terrainC, dirtRaw): sale igual;
--   * los objetos no están: "nada sólido, ningún objeto". Lo que se guarda en
--     caché con esa falta (rejilla de colisión, forma de los árboles) se marca
--     como parcial y se rehace al terminarse el trozo que faltaba (commitChunk).
local pending = {}                           -- clave -> chunk a medio generar (aún no está en `data`)
local nPending = 0
local prefetchDone = false                   -- todo lo de alrededor de la cámara ya está
local softMiss = false                       -- una consulta blanda se ha topado con un trozo sin hacer
-- Zona dura, en trozos (la pone W.update donde mire la cámara: ver setHard).
local hardX0, hardX1, hardY0, hardY1 = 0, -1, 0, -1
local function newChunk(cx, cy, k)
    return { cx = cx, cy = cy, key = k, terr = {}, dirt = {}, props = {}, propAt = {}, liquids = {}, trees = {},
             grassAt = {}, step = 0 }
end

-- Un paso de la generación; devuelve true al acabar. Pasos: N filas de terreno
-- (baratas) y luego 4·N cuartos de fila de objetos (lo caro: ~1/70 del trozo cada
-- uno, ~1 ms en la consola; así el prefetch puede pararse a tiempo sin pasarse
-- de su tope).
local PROP_W = 4                             -- casillas de objetos por paso
local GEN_STEPS = N + N * N / PROP_W
local function genStep(c)
    local s = c.step
    if s < N then
        local j = s
        local terr, dirt, liquids = c.terr, c.dirt, c.liquids
        local nl = #liquids
        local cx, cy = c.cx, c.cy
        for i = 0, N - 1 do
            local tx, ty = cx * N + i, cy * N + j
            local t = terrCache[tx * 1000003 + ty] or terrainC(tx, ty)
            local idx = j * N + i + 1
            terr[idx] = t
            dirt[idx] = dirtRaw(tx, ty)
            if t == LIQUID then liquids[nl + 1] = tx; liquids[nl + 2] = ty; nl = nl + 2 end
        end
    else
        local h = (s - N) * PROP_W                  -- primera casilla del paso (0..N·N-1)
        local i0 = h % N
        placePropsRow(c, floor(h / N), i0, i0 + PROP_W - 1)
    end
    c.step = s + 1
    return c.step >= GEN_STEPS
end

-- Trozos que no se desalojan (alrededor de la cámara: los va a pedir enseguida).
local keepX0, keepX1, keepY0, keepY1 = 0, -1, 0, -1

-- Mete un chunk terminado en `data` (desalojando el más viejo si hace falta).
local function commitChunk(c)
    if G_MARKF then G_MARKF("CHUNK") end
    c.step = nil
    if pending[c.key] then pending[c.key] = nil; nPending = nPending - 1 end
    if #dataOrder >= MAX_DATA then
        if G_MARKF then G_MARKF("DROPCHUNK") end
        -- El más viejo que no esté alrededor de la cámara.
        local vi = 1
        for i = 1, #dataOrder do
            local o = data[dataOrder[i]]
            if o.cx < keepX0 or o.cx > keepX1 or o.cy < keepY0 or o.cy > keepY1 then vi = i break end
        end
        local old = table.remove(dataOrder, vi)
        data[old] = nil
        dropBatch(old)
        prefetchDone = false
    end
    data[c.key] = c
    dataOrder[#dataOrder + 1] = c.key
    -- Lo que se calculó sin este trozo (parcial) se rehace: la rejilla de colisión
    -- de los trozos a 2 o menos (mira árboles de sus vecinos, cuyas formas miran
    -- 5 casillas más allá) y las formas de los árboles de los de al lado.
    for b = -2, 2 do
        for a = -2, 2 do
            local o = data[(c.cx + a) * 100003 + c.cy + b]
            if o then
                if o.colPart then o.colBiome = nil end
                if o.treePart and a >= -1 and a <= 1 and b >= -1 and b <= 1 then
                    o.treePart = nil
                    local trees = o.trees
                    for i = 1, #trees do
                        if trees[i].shapePart then trees[i].shapeBiome = nil end
                    end
                end
            end
        end
    end
    -- Sólo cambia lo visible si el chunk cae en el rectángulo de candidatos.
    local x0, y0 = c.cx * CW, c.cy * CW
    if x0 < candR and x0 + CW > candL and y0 < candB and y0 + CW > candT then propsVer = propsVer + 1 end
end

-- Trozo entero YA (lo termina en el acto si falta). Sólo para lo que de verdad
-- lo necesita: dibujar la vista, la zona dura, momentos de carga, depuración.
local function chunkData(cx, cy)
    local k = cx * 100003 + cy
    local c = data[k]
    if c then return c end
    c = pending[k] or newChunk(cx, cy, k)    -- (commitChunk lo quita de pending)
    if G_MARKF then G_MARKF("GOLPE") end     -- (en el rastro: "GOLPE CHUNK" = generado de golpe)
    while not genStep(c) do end
    commitChunk(c)
    return c
end

-- Trozo para una consulta de fondo: nil si aún no está (y no se genera), salvo
-- en la zona dura. Quien guarde algo calculado con un nil debe mirar softMiss.
local function chunkSoft(cx, cy)
    local c = data[cx * 100003 + cy]
    if c then return c end
    if cx >= hardX0 and cx <= hardX1 and cy >= hardY0 and cy <= hardY1 then return chunkData(cx, cy) end
    softMiss = true
    return nil
end

-- Adelanta la generación de los chunks alrededor de la cámara (x, y) hasta gastar
-- `budget` segundos (o `urgent` si lo que falta está a punto de verse). Va primero
-- lo que antes vaya a entrar en la vista: lo que ya se ve (zona dura), luego lo que
-- está en la dirección en que se mueve la cámara (vx, vy) y lo más cercano: así va
-- por delante del jugador. Devuelve el tiempo gastado.
local prefetch
do
local KEEP_R = 640                            -- alrededor de la cámara y del punto adelantado
local LOOK, LOOK_MAX = 1.2, 700               -- adelanto: segundos de movimiento (tope en unidades)
local WALK = 150                              -- velocidad supuesta para "lo cercano" (unidades/s)
local URGENT_T = 1.2                          -- "a punto de verse": en menos de esto (s)
local scX0, scX1, scY0, scY1 = 0, -1, 0, -1   -- rectángulo (en trozos) del último barrido completo
local stepEst = 0.0003                        -- lo que tarda un paso de genStep (s), estimado
local getTime = love.timer.getTime

-- El trozo que toca: el que falte que antes vaya a verse (o nil si no falta
-- ninguno), y en cuántos segundos. Para cada uno: lo que tardaría en entrar en la
-- vista (vl, vr, vt, vb) con la velocidad de la cámara, o yendo hacia él a WALK si
-- es menos. Uno a medio hacer cuenta como antes (no se deja a medias sin motivo).
local function pick(x0, x1, y0, y1, vl, vr, vt, vb, vx, vy)
    local best, bs, bx, by = nil, huge, 0, 0
    for cy = y0, y1 do
        local t, b = cy * CW, cy * CW + CW
        local gy = max(0, t - vb, vt - b)                -- hueco vertical con la vista
        local ty = 0
        if gy > 0 then
            if t >= vb then ty = vy > 1 and gy / vy or huge else ty = vy < -1 and gy / -vy or huge end
        end
        for cx = x0, x1 do
            local k = cx * 100003 + cy
            if not data[k] then
                local l, r = cx * CW, cx * CW + CW
                local gx = max(0, l - vr, vl - r)
                local tx = 0
                if gx > 0 then
                    if l >= vr then tx = vx > 1 and gx / vx or huge else tx = vx < -1 and gx / -vx or huge end
                end
                local s = sqrt(gx * gx + gy * gy) / WALK
                local sv = max(tx, ty)
                if sv < s then s = sv end
                if pending[k] then s = s * 0.7 end
                if s < bs then bs = s; best = k; bx, by = cx, cy end
            end
        end
    end
    return best, bx, by, bs
end

prefetch = function(x, y, vx, vy, hw, hh, budget, urgent)
    if G_FLAGS and G_FLAGS.noprefetch then return 0 end
    -- Punto adelantado.
    local ax, ay = vx * LOOK, vy * LOOK
    local al = ax * ax + ay * ay
    if al > LOOK_MAX * LOOK_MAX then local k = LOOK_MAX / sqrt(al); ax, ay = ax * k, ay * k end
    local px, py = x + ax, y + ay
    local x0, x1 = floor((min(x, px) - KEEP_R) / CW), floor((max(x, px) + KEEP_R) / CW)
    local y0, y1 = floor((min(y, py) - KEEP_R) / CW), floor((max(y, py) + KEEP_R) / CW)
    keepX0, keepX1, keepY0, keepY1 = x0 - 1, x1 + 1, y0 - 1, y1 + 1
    if prefetchDone and x0 == scX0 and x1 == scX1 and y0 == scY0 and y1 == scY1 then return 0 end
    -- Los que se quedaron a medias y ya no hacen falta, fuera (memoria).
    if nPending > 3 then
        for k, c in next, pending do
            if c.cx < x0 or c.cx > x1 or c.cy < y0 or c.cy > y1 then pending[k] = nil; nPending = nPending - 1 end
        end
    end
    local t0 = getTime()
    local now = t0
    local cur = nil
    while true do
        if not cur then
            local k, bx, by, s = pick(x0, x1, y0, y1, x - hw, x + hw, y - hh, y + hh, vx, vy)
            if not k then
                prefetchDone, scX0, scX1, scY0, scY1 = true, x0, x1, y0, y1
                break
            end
            prefetchDone = false
            cur = pending[k]
            if not cur then
                cur = newChunk(bx, by, k)
                pending[k] = cur; nPending = nPending + 1
            end
            -- ¿A punto de verse? Entonces se le da más tiempo (mejor un fotograma algo
            -- largo que generarlo de golpe cuando entre en la vista).
            if s < URGENT_T and urgent > budget then
                budget = urgent
            end
        end
        if genStep(cur) then
            commitChunk(cur)
            cur = nil
        end
        local t = getTime()
        local st = t - now
        now = t
        -- Media móvil de lo que tarda un paso: si el siguiente no cabe, se para.
        -- (Alguno tarda bastante más: una casilla con muchas candidatas alrededor.)
        stepEst = stepEst + (st - stepEst) * 0.25
        if now - t0 + stepEst > budget then break end
    end
    return now - t0
end

end -- (prefetch)

-- El terreno y la tierra de una casilla: del trozo si está; si no, se calculan
-- (son funciones puras: sale lo mismo) sin generar el trozo.
local function terrainAt(tx, ty)
    local cx, cy = floor(tx / N), floor(ty / N)
    local c = data[cx * 100003 + cy]
    if c then return c.terr[(ty - cy * N) * N + (tx - cx * N) + 1] end
    return terrCache[tx * 1000003 + ty] or terrainC(tx, ty)
end

local function dirtAt(tx, ty)
    local cx, cy = floor(tx / N), floor(ty / N)
    local c = data[cx * 100003 + cy]
    if c then return c.dirt[(ty - cy * N) * N + (tx - cx * N) + 1] end
    return dirtRaw(tx, ty)
end

-- Objeto sólido de una casilla (consulta blanda: nil si su trozo aún no está).
local function propAtTile(tx, ty)
    local cx, cy = floor(tx / N), floor(ty / N)
    local c = data[cx * 100003 + cy] or chunkSoft(cx, cy)
    if not c then return nil end
    return c.propAt[(ty - cy * N) * N + (tx - cx * N) + 1]
end

-- ---------------- consultas ----------------

local function tileOf(v) return floor(v / TS) end

function W.kindAt(x, y) return KIND[terrainAt(tileOf(x), tileOf(y))] end
function W.isWall(x, y) return terrainAt(tileOf(x), tileOf(y)) == WALL end
function W.isLiquid(x, y) return terrainAt(tileOf(x), tileOf(y)) == LIQUID end
-- ¿Puede esta entidad pisar el líquido del bioma? La lava sólo la cruzan los de
-- tipo Fuego; el agua (poco profunda) la cruzan todos menos los de tipo Fuego.
-- Los de tipo Volador cruzan las dos (un Charizard, Fuego/Volador, también el agua).
-- Los demás líquidos (veneno, descarga) se pisan, con su efecto.
function W.liquidSolidFor(e)
    local liq = BIOMES[biome].liquid
    if liq ~= 'lava' and liq ~= 'water' then return false end
    local types = e and (e.types or (e.mon and e.mon.types))
    local fire = false
    if types then
        for i = 1, #types do
            if types[i] == 'flying' then return false end       -- vuela por encima de todo
            if types[i] == 'fire' then fire = true end
        end
    end
    if liq == 'lava' then return not fire end
    return fire
end

-- ¿El líquido de este bioma refleja (agua)? La lava y el veneno, no.
function W.reflects() return BIOMES[biome].liquid == 'water' end
function W.liquidKind() return BIOMES[biome].liquid end

-- Efecto del charco actual sobre un Pokémon de estos tipos:
--   { slow, dmg, flat, every, color, slide }  (dmg en % de vida máxima)
-- Los de su tipo no sufren el suyo (Fuego en lava, Veneno en veneno...).
local LIQ = {
    water  = { slow = 0.6, immune = { 'water' } },        -- los de tipo agua nadan sin frenarse
    swamp  = { slow = 0.45, immune = { 'water' } },
    lava   = { dmg = 0.06, flat = 5, every = 0.5, color = '#ff8a3d', immune = { 'fire' } },
    poison = { dmg = 0.035, flat = 3, every = 0.5, color = '#c86bdc', immune = { 'poison', 'steel' } },
    spark  = { dmg = 0.045, flat = 4, every = 0.7, color = '#ffe14d', immune = { 'electric', 'ground' } },
    ice    = { slide = true, immune = { 'ice' } },
}
local NO_EFFECT = {}                         -- tabla vacía compartida (no se modifica)
function W.liquidEffect(types)
    local e = LIQ[BIOMES[biome].liquid] or LIQ.water
    -- Los de tipo Volador van por encima: ningún líquido les afecta.
    if types then
        for i = 1, #types do if types[i] == 'flying' then return NO_EFFECT end end
    end
    if e.immune and types then
        local im = e.immune
        for i = 1, #types do
            for j = 1, #im do if types[i] == im[j] then return NO_EFFECT end end
        end
    end
    return e
end

-- ¿Se puede pasar por esta casilla andando? (pathing.lua)
function W.walkable(tx, ty)
    local t = terrainAt(tx, ty)
    if t == WALL then return false end
    if t == LIQUID then
        local e = LIQ[BIOMES[biome].liquid]
        if e and e.dmg then return false end                -- lava, veneno, descarga
    end
    local p = propAtTile(tx, ty)
    return not (p and p.solid)
end

-- ¿Hay sitio para que algo de radio r esté aquí?
function W.isFree(x, y, r, allowLiquid)
    r = r or 12
    -- allowLiquid puede ser la entidad: entonces depende de si ella puede pisarlo.
    if type(allowLiquid) == 'table' then allowLiquid = not W.liquidSolidFor(allowLiquid)
    elseif BIOMES[biome].liquid == 'lava' then allowLiquid = false end   -- la lava no se pisa
    local t0x, t1x, t0y, t1y = tileOf(x - r), tileOf(x + r), tileOf(y - r), tileOf(y + r)
    for ty = t0y, t1y do
        for tx = t0x, t1x do
            local t = terrainAt(tx, ty)
            if t == WALL or (not allowLiquid and t == LIQUID) then return false end
            local p = propAtTile(tx, ty)
            if p and U.dist2(x, y, p.x, p.y) < (r + p.r) * (r + p.r) then return false end
        end
    end
    return true
end

local function clearList(t) for i = #t, 1, -1 do t[i] = nil end end
local NO_PROPS = {}                          -- (lista vacía compartida: trozo aún sin generar)
local flashing = {}                          -- objetos con destello (p.flash > 0), ver W.update

-- Objetos destructibles (incluida la hierba) que tocan un círculo.
-- La tabla devuelta se REUTILIZA en la siguiente llamada (o pasa la tuya en `out`).
local circleOut = {}
function W.propsInCircle(x, y, r, out)
    out = out or circleOut
    clearList(out)
    local c0x, c1x = floor((x - r) / CW), floor((x + r) / CW)
    local c0y, c1y = floor((y - r) / CW), floor((y + r) / CW)
    for cy = c0y, c1y do
        for cx = c0x, c1x do
            local c = chunkSoft(cx, cy)
            local props = c and c.props or NO_PROPS
            for i = 1, #props do
                local p = props[i]
                if p.destructible and p.hp > 0 then
                    local rr = r + p.r
                    if U.dist2(x, y, p.x, p.y) <= rr * rr then out[#out + 1] = p end
                end
            end
        end
    end
    return out
end

-- Objetos interactivos (altares, manantiales, cofres con candado, trampas) cerca.
-- La tabla devuelta se REUTILIZA en la siguiente llamada (o pasa la tuya en `out`).
local specialOut = {}
function W.specialsNear(x, y, r, out)
    out = out or specialOut
    clearList(out)
    local c0x, c1x = floor((x - r) / CW), floor((x + r) / CW)
    local c0y, c1y = floor((y - r) / CW), floor((y + r) / CW)
    for cy = c0y, c1y do
        for cx = c0x, c1x do
            -- (Sólo lo ya generado, ni siquiera la zona dura: con radio 720 llega fuera
            -- de la vista, y lo que aún no está no puede tener nada activo.)
            local c = data[cx * 100003 + cy]
            local props = c and c.props or NO_PROPS
            for i = 1, #props do
                local p = props[i]
                if SPECIAL[p.type] then
                    local rr = r + p.r
                    if U.dist2(x, y, p.x, p.y) <= rr * rr then out[#out + 1] = p end
                end
            end
        end
    end
    return out
end

-- Roca o cofre más cercano (para apuntar cuando no hay enemigos).
local nearestOut = {}
function W.nearestBreakable(x, y, r)
    local best, bd = nil, r * r
    local list = W.propsInCircle(x, y, r, nearestOut)
    for i = 1, #list do
        local p = list[i]
        if p.solid then
            local d = U.dist2(x, y, p.x, p.y)
            if d < bd then bd = d; best = p end
        end
    end
    return best
end

-- Empuja el círculo (x, y, r) fuera de la caja; devuelve la nueva posición o nil.
local function pushOutBox(x, y, r, bx0, by0, bx1, by1)
    local qx, qy = U.clamp(x, bx0, bx1), U.clamp(y, by0, by1)
    local dx, dy = x - qx, y - qy
    local d2 = dx * dx + dy * dy
    if d2 >= r * r then return nil end
    if d2 > 1e-6 then
        local d = sqrt(d2)
        return x + dx / d * (r - d), y + dy / d * (r - d)
    end
    local l, rr, u, b = x - bx0, bx1 - x, y - by0, by1 - y
    local m = min(l, rr, u, b)
    if m == l then return bx0 - r, y
    elseif m == rr then return bx1 + r, y
    elseif m == u then return x, by0 - r end
    return x, by1 + r
end

-- Caja sólida de un árbol de ruta (tronco + hojas, sin la sombra), en coordenadas
-- de mundo, según el sprite que le toca. nil si el árbol no tiene sprite de ruta.
-- Biomas de hoja verde donde se usan los árboles y matas de ruta.
local DECO_BIOME = { [0] = true }
do
    local types = ARENA_TYPES
    local base = ARENA
    for i, t in ipairs(types) do
        if t == 'normal' or t == 'grass' or t == 'bug' or t == 'fighting' then DECO_BIOME[base + i - 1] = true end
    end
end

local DECO_TREES = nil
-- Árboles del tileset (biomas sin decoración de ruta): sprite 30x40 / 26x40 / 28x40
-- anclado por abajo; caja de tronco + hojas en píxeles de arte (x0, y0, x1, y1).
local TILE_TREE = { tree = { 30, 40, 2, 3, 28, 39 }, crystal = { 26, 40, 3, 4, 23, 39 },
                    dead = { 28, 40, 5, 5, 23, 39 } }
local function treeBox(p)
    if p.type ~= 'tree' then return nil end
    if p.boxBiome == biome then return p.box end
    if not DECO_BIOME[biome] then
        local B = BIOMES[biome]
        local s = B and TILE_TREE[B.prop or 'tree'] or TILE_TREE.tree
        local x0, y0 = p.x - s[1] * SC / 2, p.y + 2 - s[2] * SC
        p.boxBiome = biome
        p.box = { x0 + s[3] * SC, y0 + s[4] * SC, x0 + s[5] * SC, y0 + s[6] * SC }
        return p.box
    end
    if DECO_TREES == nil then
        DECO_TREES = false
        local ok, d = pcall(require, 'data.deco')
        if ok and d then
            local l = {}
            for _, o in ipairs(d.list) do if o.cat == 'tree' then l[#l + 1] = o end end
            if #l > 0 then DECO_TREES = l end
        end
    end
    p.boxBiome, p.box = biome, nil
    if not DECO_TREES then return nil end
    local o = DECO_TREES[floor(H(p.tx, p.ty, 4242) * #DECO_TREES) + 1]
    if not o.body then return nil end
    local x0 = p.x - o.w * SC / 2
    local y0 = p.y + 2 - o.h * SC
    p.box = { x0 + o.body[1] * SC, y0 + o.body[2] * SC, x0 + o.body[3] * SC, y0 + o.body[4] * SC }
    return p.box
end
W.treeBox = treeBox

-- Paso mínimo entre árboles: una rendija más estrecha se rellena (no hay pasos
-- falsos que casi dejan pasar); a partir de aquí se pasa con holgura incluso con
-- un Pokémon grande.
local MIN_GAP = 72

-- Cajas sólidas de un árbol: la suya y los puentes hacia los árboles vecinos con
-- los que deja una rendija < MIN_GAP. Devuelve (lista, caja que lo abarca todo).
-- Si algún trozo vecino aún no está, la forma queda PARCIAL (sin los puentes hacia
-- sus árboles): p.shapePart, y su trozo treePart; commitChunk la tira al terminar
-- el vecino. Mientras, quien la use se entera por softMiss.
local function treeShape(p)
    if p.shapeBiome == biome then
        if p.shapePart then softMiss = true end
        return p.shape, p.shapeExt
    end
    p.shapeBiome, p.shape, p.shapeExt, p.shapePart = biome, nil, nil, nil
    local pb = treeBox(p)
    if not pb then return nil end
    local outer = softMiss
    softMiss = false
    local list = { pb }
    local ext = { pb[1], pb[2], pb[3], pb[4] }
    for b = -5, 5 do
        for a = -5, 5 do
            local q = (a ~= 0 or b ~= 0) and propAtTile(p.tx + a, p.ty + b)
            local qb = q and q.solid and treeBox(q)
            if qb then
                local gx = max(qb[1] - pb[3], pb[1] - qb[3])     -- hueco horizontal (<0: se solapan)
                local gy = max(qb[2] - pb[4], pb[2] - qb[4])     -- hueco vertical
                local narrow = (gx > 0 and gy <= 0 and gx < MIN_GAP) or (gy > 0 and gx <= 0 and gy < MIN_GAP)
                    or (gx > 0 and gy > 0 and gx * gx + gy * gy < MIN_GAP * MIN_GAP)
                if narrow then
                    -- Rectángulo entre las dos cajas (en el eje que se solapan, la parte común).
                    local x0 = gx > 0 and min(pb[3], qb[3]) or max(pb[1], qb[1])
                    local x1 = gx > 0 and max(pb[1], qb[1]) or min(pb[3], qb[3])
                    local y0 = gy > 0 and min(pb[4], qb[4]) or max(pb[2], qb[2])
                    local y1 = gy > 0 and max(pb[2], qb[2]) or min(pb[4], qb[4])
                    if x1 > x0 and y1 > y0 then
                        list[#list + 1] = { x0, y0, x1, y1 }
                        ext[1], ext[2] = min(ext[1], x0), min(ext[2], y0)
                        ext[3], ext[4] = max(ext[3], x1), max(ext[4], y1)
                    end
                end
            end
        end
    end
    p.shape, p.shapeExt = list, ext
    if softMiss then
        p.shapePart = true
        local o = data[ckey(floor(p.tx / N), floor(p.ty / N))]
        if o then o.treePart = true end
    end
    softMiss = outer or softMiss
    return list, ext
end

-- Y con la que se ordena un objeto al dibujar: los árboles, por el pie del tronco
-- (quien pisa la sombra de delante queda por delante del árbol).
function W.propSortY(p)
    local b = treeBox(p)
    if b then return b[4] end
    return p.y
end

-- Salida rápida de W.collide en campo abierto: cada chunk tiene una rejilla de
-- celdas de COLC x COLC unidades marcadas si algo sólido (pared, objeto sólido,
-- caja o puente de árbol) o líquido queda a menos de COL_M de la celda. Si el
-- centro de la entidad cae en una celda sin marcar, no puede tocar nada (para
-- radios <= COL_MAXR: el margen cubre radio + radio del objeto, que es <= 22).
-- Lo roto no se desmarca (sólo sería más lento, no distinto). Las cajas de los
-- árboles dependen del bioma: la rejilla se rehace al cambiarlo.
do
local COLC = 128
local COLN = CW / COLC                       -- celdas por lado de chunk (4)
local COL_MAXR = 48
local COL_M = COL_MAXR + 24
local function colMark(grid, c, x0, y0, x1, y1)
    local ox, oy = c.cx * CW, c.cy * CW
    local i0, i1 = floor((x0 - COL_M - ox) / COLC), floor((x1 + COL_M - ox) / COLC)
    local j0, j1 = floor((y0 - COL_M - oy) / COLC), floor((y1 + COL_M - oy) / COLC)
    if i0 < 0 then i0 = 0 end
    if j0 < 0 then j0 = 0 end
    if i1 > COLN - 1 then i1 = COLN - 1 end
    if j1 > COLN - 1 then j1 = COLN - 1 end
    for j = j0, j1 do
        for i = i0, i1 do grid[j * COLN + i + 1] = true end
    end
end
-- Con algún vecino sin generar (consulta blanda: no se generan aquí; antes un
-- enemigo lejano que chocaba generaba vecinos en cascada), la rejilla queda
-- PARCIAL (c.colPart: sin sus objetos) y commitChunk la tira al terminar el vecino.
-- El terreno sí sale entero (terrainAt no necesita el trozo).
local function colGrid(c)
    if c.colBiome == biome then return c end
    softMiss = false
    local solid, liq = {}, {}
    -- Paredes y líquido del chunk y de una franja de los vecinos (lo que queda a
    -- menos de COL_M del borde).
    local B = floor(COL_M / TS) + 1
    local terr = c.terr
    local bx0, by0 = c.cx * N, c.cy * N
    for ty = by0 - B, by0 + N - 1 + B do
        local inY = ty >= by0 and ty < by0 + N
        for tx = bx0 - B, bx0 + N - 1 + B do
            local t
            if inY and tx >= bx0 and tx < bx0 + N then t = terr[(ty - by0) * N + (tx - bx0) + 1]
            else t = terrainAt(tx, ty) end
            if t ~= FLOOR then
                local x0, y0 = tx * TS, ty * TS
                colMark(t == WALL and solid or liq, c, x0, y0, x0 + TS, y0 + TS)
            end
        end
    end
    -- Objetos sólidos y árboles (con sus puentes) de éste y de los vecinos, que
    -- pueden asomar a éste (las copas, sobre todo).
    for b = -1, 1 do
        for a = -1, 1 do
            local o = chunkSoft(c.cx + a, c.cy + b)
            local props = o and o.props or NO_PROPS
            for k = 1, #props do
                local p = props[k]
                if p.solid then
                    local boxes, ext = nil, nil
                    if p.type == 'tree' then boxes, ext = treeShape(p) end
                    if boxes then
                        colMark(solid, c, ext[1], ext[2], ext[3], ext[4])
                    else
                        -- Redondo (rocas, cofres... y árboles sin caja).
                        colMark(solid, c, p.x - p.r, p.y - p.r, p.x + p.r, p.y + p.r)
                    end
                end
            end
        end
    end
    c.colSolid, c.colLiq, c.colBiome = solid, liq, biome
    c.colPart = softMiss or nil
    softMiss = false
    return c
end

-- Empuja un círculo fuera de paredes y objetos sólidos (deslizando).
-- Devuelve true si ha chocado con algo.
function W.collide(e)
    local r = e.r
    local hit = false
    if r <= COL_MAXR then
        local x, y = e.x, e.y
        local cx, cy = floor(x / CW), floor(y / CW)
        -- (Consultas blandas: un enemigo lejano en un trozo sin generar choca sólo
        -- con el terreno hasta que el prefetch lo haga. El jugador está en la zona dura.)
        local c = data[cx * 100003 + cy] or chunkSoft(cx, cy)
        if c then
            if c.colBiome ~= biome then colGrid(c) end
            local cell = floor((y - cy * CW) / COLC) * COLN + floor((x - cx * CW) / COLC) + 1
            if not c.colSolid[cell] and not (c.colLiq[cell] and W.liquidSolidFor(e)) then return false end
        end
    end
    -- La lava (mar de lava) no se pisa salvo los de tipo Fuego, y éstos no pisan
    -- el agua: para quien no puede, el líquido cuenta como pared.
    local lavaSolid = W.liquidSolidFor(e)
    for pass = 1, 2 do
        -- La 2.ª pasada sólo sirve si la 1.ª ha movido algo (si no, daría lo mismo).
        if pass == 2 and not hit then break end
        -- +1 casilla alrededor (y más hacia abajo y a los lados: la copa de un árbol
        -- ocupa varias casillas por encima y a los lados de su pie).
        local t0x, t1x, t0y, t1y = tileOf(e.x - r) - 1, tileOf(e.x + r) + 1, tileOf(e.y - r) - 1, tileOf(e.y + r) + 1
        -- Árboles: su caja (tronco + hojas) y los puentes que tapan rendijas estrechas.
        -- Se buscan en las listas de árboles de los chunks cercanos.
        local qx0, qx1, qy0, qy1 = e.x - r - 160, e.x + r + 160, e.y - r - 160, e.y + r + 200
        for cy = floor(qy0 / (N * TS)), floor(qy1 / (N * TS)) do
            for cx = floor(qx0 / (N * TS)), floor(qx1 / (N * TS)) do
                local c = data[cx * 100003 + cy] or chunkSoft(cx, cy)
                local trees = c and c.trees or NO_PROPS
                for k = 1, #trees do
                    local tp = trees[k]
                    local boxes, ext
                    if tp.shapeBiome == biome and not tp.shapePart then boxes, ext = tp.shape, tp.shapeExt
                    else boxes, ext = treeShape(tp) end
                    if boxes and e.x + r > ext[1] and e.x - r < ext[3] and e.y + r > ext[2] and e.y - r < ext[4] then
                        for b = 1, #boxes do
                            local bx = boxes[b]
                            local nx, ny = pushOutBox(e.x, e.y, r, bx[1], bx[2], bx[3], bx[4])
                            if nx then hit = true; e.x, e.y = nx, ny end
                        end
                    end
                end
            end
        end
        -- Casillas alrededor: el chunk se busca sólo cuando cambia.
        local lk, lc = nil, nil
        for ty = t0y, t1y do
            local cy = floor(ty / N)
            for tx = t0x, t1x do
                local cx = floor(tx / N)
                local k = cx * 100003 + cy
                if k ~= lk then lk = k; lc = data[k] or chunkSoft(cx, cy) end
                local idx = (ty - cy * N) * N + (tx - cx * N) + 1
                local tt
                if lc then tt = lc.terr[idx] else tt = terrCache[tx * 1000003 + ty] or terrainC(tx, ty) end
                if (tt == WALL or (lavaSolid and tt == LIQUID)) and abs(tx * TS + TS / 2 - e.x) < r + TS and abs(ty * TS + TS / 2 - e.y) < r + TS then
                    -- Punto más cercano de la caja del tile al centro del círculo.
                    local bx0, by0 = tx * TS, ty * TS
                    local bx1, by1 = bx0 + TS, by0 + TS
                    local qx, qy = U.clamp(e.x, bx0, bx1), U.clamp(e.y, by0, by1)
                    local dx, dy = e.x - qx, e.y - qy
                    local d2 = dx * dx + dy * dy
                    if d2 < r * r then
                        hit = true
                        if d2 > 1e-6 then
                            local d = sqrt(d2)
                            e.x = e.x + dx / d * (r - d); e.y = e.y + dy / d * (r - d)
                        else
                            -- Centro dentro de la caja: sal por el lado más cercano.
                            local l, rr, u, b = e.x - bx0, bx1 - e.x, e.y - by0, by1 - e.y
                            local m = min(l, rr, u, b)
                            if m == l then e.x = bx0 - r
                            elseif m == rr then e.x = bx1 + r
                            elseif m == u then e.y = by0 - r
                            else e.y = by1 + r end
                        end
                    end
                end
                local p = lc and lc.propAt[idx]
                if p and p.solid and (p.type ~= 'tree' or not treeBox(p)) then
                    local dx, dy = e.x - p.x, e.y - p.y
                    local mn = r + p.r
                    local d2 = dx * dx + dy * dy
                    if d2 < mn * mn then
                        hit = true
                        local d = sqrt(d2)
                        if d == 0 then d = 0.01 end
                        e.x = p.x + dx / d * mn; e.y = p.y + dy / d * mn
                    end
                end
            end
        end
    end
    return hit
end

end -- (colisión)

-- Depuración (`--treetest`): empuja un círculo contra el primer árbol con caja desde
-- abajo, arriba y la izquierda, y devuelve dónde se queda frente a la caja.
function W.debugTreeTest(r)
    -- (Los trozos de la zona, ya: las consultas de colisión no los generan.)
    for cy = -4, 3 do
        for cx = -4, 3 do chunkData(cx, cy) end
    end
    for ty = -40, 40 do
        for tx = -40, 40 do
            local p = propAtTile(tx, ty)
            local b = p and p.solid and treeBox(p)
            if b then
                -- Sólo un árbol aislado: nada sólido en 5 casillas a la redonda.
                for j = -5, 5 do
                    for i = -5, 5 do
                        local q = (i ~= 0 or j ~= 0) and propAtTile(tx + i, ty + j)
                        if (q and q.solid) or terrainAt(tx + i, ty + j) == WALL then b = nil end
                    end
                end
            end
            if b then
                local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
                local function walk(x, y, vx, vy)
                    local e = { x = x, y = y, r = r }
                    for _ = 1, 80 do e.x = e.x + vx; e.y = e.y + vy; W.collide(e) end
                    return e
                end
                local up = walk(cx, b[4] + 60, 0, -3)
                local down = walk(cx, b[2] - 60, 0, 3)
                local right = walk(b[1] - 60, cy, 3, 0)
                return string.format('caja=%d,%d,%d,%d pie=%d | desde abajo y=%.1f (borde+r=%.1f) | desde arriba y=%.1f (borde-r=%.1f) | desde izq x=%.1f (borde-r=%.1f)',
                    b[1], b[2], b[3], b[4], p.y, up.y, b[4] + r, down.y, b[2] - r, right.x, b[1] - r)
            end
        end
    end
    return 'sin árboles con caja'
end

-- ¿Choca un proyectil aquí? Devuelve 'wall', el prop sólido, o nil.
function W.projectileBlock(x, y, r)
    local tx, ty = tileOf(x), tileOf(y)
    if terrainAt(tx, ty) == WALL then return 'wall' end
    for b = -1, 1 do
        for a = -1, 1 do
            local p = propAtTile(tx + a, ty + b)
            if p and p.solid then
                local rr = r + p.r
                if U.dist2(x, y, p.x, p.y) < rr * rr then return p end
            end
        end
    end
    return nil
end

-- ---------------- daño a objetos ----------------

local function destroyProp(p)
    broken[tkey(p.tx, p.ty)] = true
    p.gone = true                 -- (G.Interact guarda la lista unos instantes)
    local c = data[ckey(floor(p.tx / N), floor(p.ty / N))]
    if c then
        local props = c.props
        for i = 1, #props do
            if props[i] == p then props[i] = props[#props]; props[#props] = nil break end
        end
        c.propAt[(p.ty - c.cy * N) * N + (p.tx - c.cx * N) + 1] = nil
        c.grassAt[(p.ty - c.cy * N) * N + (p.tx - c.cx * N) + 1] = nil
    end
    -- (Sin tocar propsVer: W.visibleSplit se salta los que tienen p.gone.)
    local B = BIOMES[biome]
    local typ = p.type
    G.Audio.sfx(typ == 'grass' and 'grass' or typ == 'chest' and 'chest' or 'break')
    if typ == 'grass' then
        G.FX.burst(p.x, p.y - 6, B.grass[2], 6, 70)
        local r = random()
        if r < 0.05 then G.Pickups.drop('heal', p.x, p.y)
        elseif r < 0.11 then G.Pickups.drop('coin', p.x, p.y, 1) end
        return
    end
    if typ == 'rock' then
        G.FX.burst(p.x, p.y - 10, B.rock[2], 14, 140)
        G.FX.ring(p.x, p.y - 8, 4, 26, B.rock[3], 0.3, 3)
        local r = random()
        if r < 0.40 then G.Pickups.dropXp(p.x, p.y, 6) end
        if r > 0.75 then G.Pickups.drop('coin', p.x, p.y, 2) end
        if r > 0.94 then G.Pickups.drop('heal', p.x + 8, p.y) end
        return
    end
    if typ == 'chest' then
        G.FX.burst(p.x, p.y - 10, '#f2c443', 22, 180)
        G.FX.ring(p.x, p.y - 8, 6, 46, '#f2c443', 0.45, 4)
        G.Camera.kick(0.25)
        local n = U.randInt(4, 7)
        for _ = 1, n do G.Pickups.drop('coin', p.x + U.rand(-14, 14), p.y + U.rand(-10, 10), 3) end
        G.Pickups.drop(random() < 0.5 and 'heal' or 'magnet', p.x, p.y)
        G.Pickups.dropXp(p.x, p.y, 20)
        if random() < 0.08 then G.Pickups.drop('item', p.x, p.y - 12, G.Items.roll()) end
        return
    end
    if typ == 'bigchest' then
        -- Botín grande: monedas, tickets y experiencia para subir un nivel.
        G.FX.burst(p.x, p.y - 12, '#f2c443', 34, 220)
        G.FX.ring(p.x, p.y - 8, 6, 80, '#f2c443', 0.6, 5)
        G.Camera.kick(0.4)
        for _ = 1, 9 do G.Pickups.drop('coin', p.x + U.rand(-22, 22), p.y + U.rand(-14, 14), 4) end
        local tk = U.randInt(1, 3)
        for _ = 1, tk do G.Pickups.drop('ticket', p.x + U.rand(-16, 16), p.y + U.rand(-10, 10), 1) end
        if random() < 0.15 then G.Pickups.drop('ticket10', p.x, p.y - 10, 1) end
        if random() < 0.5 then G.Pickups.drop('item', p.x + 14, p.y - 14, G.Items.roll()) end
        G.Pickups.dropXp(p.x, p.y, G.Game.levelXp())
        G.Progress.event('chest')
        return
    end
    if typ == 'trap' then G.Interact.trapEffect(p) end
end

function W.damageProp(p, amount, color)
    if not p.destructible or p.hp <= 0 then return false end
    p.hp = p.hp - amount
    if p.flash <= 0 then flashing[#flashing + 1] = p end
    p.flash = 0.08
    if p.type ~= 'grass' then G.FX.spark(p.x, p.y - 10, color or '#ffffff', 0, -1, 3) end
    if p.hp <= 0 then destroyProp(p) return true end
    return false
end

-- Rompe el objeto de esa casilla (aunque su chunk no esté generado).
function W.breakAt(tx, ty)
    local k = tkey(tx, ty)
    if broken[k] then return end
    local c = data[ckey(floor(tx / N), floor(ty / N))]
    local found = nil
    if c then
        local props = c.props
        for i = 1, #props do
            local o = props[i]
            if o.tx == tx and o.ty == ty then found = o break end
        end
    end
    if found then destroyProp(found) else broken[k] = true end
    -- Si su chunk está a medio generar, se rehace (puede haber colocado ya el objeto).
    local pk = ckey(floor(tx / N), floor(ty / N))
    if pending[pk] then pending[pk] = nil; nPending = nPending - 1 end
end

function W.breakProp(p)
    if not broken[tkey(p.tx, p.ty)] then destroyProp(p) end
end

-- ---------------- dibujo: tileset y batches ----------------

-- data/tiles.lua (generado por tools/gen_tiles.py; contrato en PORT.md §13).
local TILES = nil
do
    local ok, t = pcall(require, 'data.tiles')
    if ok and type(t) == 'table' then TILES = t
    else print('[World] data/tiles.lua no disponible: ' .. tostring(t)) end
end

-- Máscara canónica de líquido (8 vecinos): una diagonal sólo cuenta si sus
-- dos ortogonales están. Lua 5.1 no tiene bits: se usa floor/módulo.
local function bit(m, b) return floor(m / b) % 2 == 1 end
local function liquidCanon(m)
    local n, ne, e, se = bit(m, 1), bit(m, 2), bit(m, 4), bit(m, 8)
    local s, so, o, no = bit(m, 16), bit(m, 32), bit(m, 64), bit(m, 128)
    local out = 0
    if n then out = out + 1 end
    if e then out = out + 4 end
    if s then out = out + 16 end
    if o then out = out + 64 end
    if ne and n and e then out = out + 2 end
    if se and s and e then out = out + 8 end
    if so and s and o then out = out + 32 end
    if no and n and o then out = out + 128 end
    return out
end

-- Variantes de cada prop en el atlas y tamaño de respaldo (px de arte) si falta.
local PROP_VARIANTS = { tree = 1, rock = 2, chest = 1, grass = 2, altar = 8, spring = 2, bigchest = 1, trap = 3, rift = 4 }
local PROP_SIZE = { tree = { 30, 40 }, rock = { 22, 17 }, chest = { 16, 14 }, grass = { 20, 17 }, altar = { 18, 27 },
                    spring = { 34, 16 }, bigchest = { 24, 20 }, trap = { 14, 14 }, rift = { 30, 46 } }

local tileset = nil                          -- del bioma actual: { img, floor, dirt, wall, liquid, shadow, props, propW, propH }
local tilesetBiome = -1
local tilesetFailed = false

local function loadTileset(bi)
    if not TILES then return nil end
    local q = TILES.quads and TILES.quads[bi]
    if not q then print('[World] data/tiles.lua no tiene cuadros del bioma ' .. bi) return nil end
    if G_STEP then G_STEP("tiles del bioma " .. tostring(bi)) end
    local ok, img = pcall(lg.newImage, U.img('img/tiles/' .. bi))
    if not ok or not img then
        print('[World] no se pudo cargar img/tiles/' .. bi .. ': ' .. tostring(img))
        if G_STEP then G_STEP("FALLO al cargar img/tiles/" .. bi .. ": " .. tostring(img), true) end
        return nil
    end
    if img.setFilter then pcall(img.setFilter, img, 'nearest', 'nearest') end
    local iw, ih = img:getWidth(), img:getHeight()
    local function quad(name)
        local r = q[name]
        if not r then return nil end
        return lg.newQuad(r[1], r[2], r[3], r[4], iw, ih), r[3], r[4]
    end
    local ts = { img = img, floor = {}, dirt = {}, wall = {}, liquid = {}, props = {}, propW = {}, propH = {} }
    for v = 0, 5 do ts.floor[v] = quad('floor_' .. v) end
    for m = 0, 15 do
        ts.dirt[m] = quad('dirt_' .. m)
        ts.wall[m] = quad('wall_' .. m)
    end
    -- Líquido: 256 máscaras -> 47 cuadros canónicos (compartidos).
    local byCanon = {}
    local keyFn = TILES.liquidKey or liquidCanon
    for m = 0, 255 do
        local cm = keyFn(m)
        local qd = byCanon[cm]
        if qd == nil then
            qd = quad('liquid_' .. cm) or false
            byCanon[cm] = qd
        end
        if qd then ts.liquid[m] = qd end
    end
    -- Mar de lava animado (fotogramas liquid_<m>_f1..3): si existen, el líquido no
    -- va en el lote estático del chunk y se dibuja cada fotograma (W.drawLiquid).
    if q['liquid_0_f1'] or q['liquid_85_f1'] then
        ts.liquidAnim = { [0] = ts.liquid }
        for f = 1, 3 do
            local arr, canon = {}, {}
            for m = 0, 255 do
                local cm = keyFn(m)
                local qd = canon[cm]
                if qd == nil then qd = quad('liquid_' .. cm .. '_f' .. f) or false; canon[cm] = qd end
                arr[m] = qd or ts.liquid[m]
            end
            ts.liquidAnim[f] = arr
        end
    end
    ts.shadow = quad('wallshadow')
    for typ, n in pairs(PROP_VARIANTS) do
        local arr, aw, ah = {}, {}, {}
        for v = 0, n - 1 do
            local qd, w, h = quad('prop_' .. typ .. '_' .. v)
            if not qd and v == 0 then qd, w, h = quad('prop_' .. typ) end
            if not qd and v > 0 then qd, w, h = arr[0], aw[0], ah[0] end   -- respaldo: variante 0
            arr[v], aw[v], ah[v] = qd, w, h
        end
        ts.props[typ], ts.propW[typ], ts.propH[typ] = arr, aw, ah
    end
    return ts
end

-- Cada lote cubre un bloque de BW x BH baldosas del trozo (ver buildBatch). Van
-- aquí arriba porque dropBatch usa SUBS (antes se declaraba después y dropBatch
-- leía una global nil: al pasar de MAX_DATA chunks la partida se caía).
local BW, BH = 8, 4
local SUBX, SUBY = N / BW, N / BH
local SUBS = SUBX * SUBY

-- Lotes por bloque (sólo los visibles), en dos reservas: la del suelo (clave
-- ckey * SUBS + sub) y la del mar de lava animado (una por fotograma de la
-- animación: (ckey * SUBS + sub) * 4 + f). Cada entrada: { key, batch, used, n }.
-- Las entradas con key == nil están libres para reutilizar (sin crear objetos).
local function newPool(cap, maxN) return { map = {}, list = {}, cap = cap, max = maxN } end
local groundPool = newPool(BW * BH * 3, 96)
local liqPool = newPool(BW * BH, 96)

local function releasePool(pool)
    local list = pool.list
    for i = 1, #list do
        local e = list[i]
        if e.batch.release then pcall(e.batch.release, e.batch) end
        list[i] = nil
    end
    for k in pairs(pool.map) do pool.map[k] = nil end
end
local function releaseBatches() releasePool(groundPool); releasePool(liqPool) end

-- Invalida los batches sin soltar los objetos (nueva semilla, arena...).
local function invalidatePool(pool)
    for i = 1, #pool.list do pool.list[i].key = nil end
    for k in pairs(pool.map) do pool.map[k] = nil end
end
local function invalidateBatches() invalidatePool(groundPool); invalidatePool(liqPool) end

local function dropKey(pool, k)
    local e = pool.map[k]
    if e then pool.map[k] = nil; e.key = nil end
end
-- key es la del trozo (ckey).
dropBatch = function(key)
    for h = 0, SUBS - 1 do
        local k = key * SUBS + h
        dropKey(groundPool, k)
        for f = 0, 3 do dropKey(liqPool, k * 4 + f) end
    end
end
local function releaseTileset()
    releaseBatches()
    if tileset then
        if tileset.img.release then pcall(tileset.img.release, tileset.img) end
        tileset = nil
    end
    tilesetBiome = -1
    tilesetFailed = false
end

local function ensureTileset()
    if tileset and tilesetBiome == biome then return tileset end
    if tilesetFailed and tilesetBiome == biome then return nil end
    releaseTileset()
    tileset = loadTileset(biome)
    tilesetBiome = biome
    tilesetFailed = tileset == nil
    return tileset
end

-- Rellena el batch de un chunk: suelo, tierra, pared/líquido, sombra de pared.
-- Cada lote cubre un bloque de BW x BH baldosas del trozo (sub = 0..SUBS-1) y se
-- dibuja entero: así sólo se mandan los bloques visibles. (No se usa setDrawRange:
-- en LÖVE Potion 3.0.2 SpriteBatch::Draw toma las posiciones de buffer[start] en vez
-- de buffer[start * 6] y, con un rango que no empieza en 0, descoloca las baldosas.)
-- Máscara de 8 vecinos de una baldosa de líquido.
local function liquidMask(tx, ty)
    local m = 0
    if terrainAt(tx, ty - 1) == LIQUID then m = m + 1 end
    if terrainAt(tx + 1, ty - 1) == LIQUID then m = m + 2 end
    if terrainAt(tx + 1, ty) == LIQUID then m = m + 4 end
    if terrainAt(tx + 1, ty + 1) == LIQUID then m = m + 8 end
    if terrainAt(tx, ty + 1) == LIQUID then m = m + 16 end
    if terrainAt(tx - 1, ty + 1) == LIQUID then m = m + 32 end
    if terrainAt(tx - 1, ty) == LIQUID then m = m + 64 end
    if terrainAt(tx - 1, ty - 1) == LIQUID then m = m + 128 end
    return m
end

-- @param f  nil = el suelo; 0..3 = sólo el mar de lava animado, en ese fotograma
local function buildBatch(b, cx, cy, sub, f)
    local ts = tileset
    b:clear()
    local c = chunkData(cx, cy)
    local terr, dirt = c.terr, c.dirt
    local fl, dq, wq, lq, shadow = ts.floor, ts.dirt, ts.wall, ts.liquid, ts.shadow
    local add = function(q, x, y) b:add(q, x, y) end
    local sx, sy = sub % SUBX, floor(sub / SUBX)
    if f then
        local quads = ts.liquidAnim[f]
        for j = sy * BH, sy * BH + BH - 1 do
            for i = sx * BW, sx * BW + BW - 1 do
                if terr[j * N + i + 1] == LIQUID then
                    local qd = quads[liquidMask(cx * N + i, cy * N + j)]
                    if qd then add(qd, i * T, j * T) end
                end
            end
        end
        if b.flush then b:flush() end
        return
    end
    for j = sy * BH, sy * BH + BH - 1 do
        for i = sx * BW, sx * BW + BW - 1 do
            local tx, ty = cx * N + i, cy * N + j
            local idx = j * N + i + 1
            local kind = terr[idx]
            local px, py = i * T, j * T
            local fq = fl[floor(H(tx, ty, 14) * 6)] or fl[0]
            if fq then add(fq, px, py) end
            if kind == FLOOR then
                if dirt[idx] then
                    local m = 0
                    if dirtAt(tx, ty - 1) then m = m + 1 end
                    if dirtAt(tx + 1, ty) then m = m + 2 end
                    if dirtAt(tx, ty + 1) then m = m + 4 end
                    if dirtAt(tx - 1, ty) then m = m + 8 end
                    local qd = dq[m]
                    if qd then add(qd, px, py) end
                end
                -- Sombra de contacto bajo las paredes que hay justo al norte.
                if shadow and terrainAt(tx, ty - 1) == WALL then add(shadow, px, py) end
            elseif kind == WALL then
                local m = 0
                if terrainAt(tx, ty - 1) == WALL then m = m + 1 end
                if terrainAt(tx + 1, ty) == WALL then m = m + 2 end
                if terrainAt(tx, ty + 1) == WALL then m = m + 4 end
                if terrainAt(tx - 1, ty) == WALL then m = m + 8 end
                local qd = wq[m]
                if qd then add(qd, px, py) end
            elseif not ts.liquidAnim then            -- (el animado va en sus propios lotes)
                local qd = lq[liquidMask(tx, ty)]
                if qd then add(qd, px, py) end
            end
        end
    end
    if b.flush then b:flush() end
end

-- Devuelve la entrada { key, batch, used, n } (n = sprites del lote).
local drawTick = 0                           -- sube en cada W.drawGround (para "el menos usado")
-- @param f  nil = lote del suelo; 0..3 = lote de lava de ese fotograma
local function chunkBatch(cx, cy, sub, f)
    local pool = f and liqPool or groundPool
    local k = (cx * 100003 + cy) * SUBS + sub
    if f then k = k * 4 + f end
    local now = drawTick
    local map, list = pool.map, pool.list
    local e = map[k]
    if e then e.used = now return e end
    -- Entrada libre, o nueva si hay hueco, o la menos usada.
    for i = 1, #list do
        if list[i].key == nil then e = list[i] break end
    end
    if G_MARKF then G_MARKF(f and "LIQBATCH" or "BATCH") end
    if not e then
        if #list < pool.max then
            if G_MARKF then G_MARKF("NEWBATCH" .. #list) end
            e = { key = nil, batch = lg.newSpriteBatch(tileset.img, pool.cap, 'static'), used = 0 }
            list[#list + 1] = e
        else
            e = list[1]
            for i = 2, #list do
                if list[i].used < e.used then e = list[i] end
            end
            map[e.key] = nil
        end
    end
    e.key = k; e.used = now
    map[k] = e
    buildBatch(e.batch, cx, cy, sub, f)
    e.n = e.batch.getCount and e.batch:getCount() or 0
    return e
end

-- ¿Hay líquido en este bloque del chunk? (se calcula una vez por chunk y bloque)
local function blockHasLiquid(c, sub)
    local hl = c.liqSub
    if not hl then hl = {}; c.liqSub = hl end
    local v = hl[sub]
    if v == nil then
        v = false
        local terr = c.terr
        local sx, sy = sub % SUBX, floor(sub / SUBX)
        for j = sy * BH, sy * BH + BH - 1 do
            for i = sx * BW, sx * BW + BW - 1 do
                if terr[j * N + i + 1] == LIQUID then v = true end
            end
        end
        hl[sub] = v
    end
    return v
end

-- ---------------- dibujo ----------------

function W.drawGround(cam)
    cam = cam or G.Camera
    local ts = ensureTileset()
    if not ts then return end
    local l, t = cam.left(), cam.top()
    local x0, x1 = floor(l / CW), floor((l + cam.w) / CW)
    local y0, y1 = floor(t / CW), floor((t + cam.h) / CW)
    lg.setColor(1, 1, 1, 1)
    drawTick = drawTick + 1
    local r, bt = l + cam.w, t + cam.h
    local bw, bh = BW * TS, BH * TS
    for cy = y0, y1 do
        for cx = x0, x1 do
            for sub = 0, SUBS - 1 do
                -- Sólo los bloques que tocan la pantalla.
                local bx = cx * CW + (sub % SUBX) * bw
                local by = cy * CW + floor(sub / SUBX) * bh
                if bx < r and bx + bw > l and by < bt and by + bh > t then
                    local e = chunkBatch(cx, cy, sub)
                    -- 6 vértices por sprite (spritebatch.cpp); la cuenta global lo sabe.
                    if not G_VERT_SPEND or G_VERT_SPEND(e.n * 6 - 4) then
                        lg.draw(e.batch, cx * CW, cy * CW, 0, SC, SC)
                    end
                end
            end
        end
    end
end

-- Brillos animados sobre el agua / burbujas de la lava (y del veneno y la electricidad).
local MAX_GLINTS = 60
function W.drawLiquid(cam, t)
    cam = cam or G.Camera
    t = t or U.now()
    local B = BIOMES[biome]
    local liq = B.liquid
    local lava = liq == 'lava' or liq == 'poison' or liq == 'spark'
    local fr, fg, fb = U.rgb(B.foam)
    local P = SC
    local speed = lava and 2.2 or 1.6
    local n = 0
    local l, tp = cam.left(), cam.top()
    local x0, x1 = floor(l / CW), floor((l + cam.w) / CW)
    local y0, y1 = floor(tp / CW), floor((tp + cam.h) / CW)
    -- Vista con un margen de una baldosa (lo que antes miraba cam.sees).
    local vl, vr, vt, vb = l - TS, l + cam.w + TS, tp - TS, tp + cam.h + TS
    -- Mar de lava animado (como el mar de Diamante/Perla/Platino): 4 fotogramas.
    -- Va en lotes por bloque como el suelo, uno por fotograma de la animación (se
    -- hacen una vez y se reutilizan): antes era un lg.draw por baldosa de lava.
    local ts = tileset
    if ts and ts.liquidAnim then
        local f = floor(t * 3.5) % 4
        lg.setColor(1, 1, 1, 1)
        local r, bt = l + cam.w, tp + cam.h
        local bw, bh = BW * TS, BH * TS
        for cy = y0, y1 do
            for cx = x0, x1 do
                local c = chunkData(cx, cy)
                if #c.liquids > 0 then
                    for sub = 0, SUBS - 1 do
                        local bx = cx * CW + (sub % SUBX) * bw
                        local by = cy * CW + floor(sub / SUBX) * bh
                        if bx < r and bx + bw > l and by < bt and by + bh > tp and blockHasLiquid(c, sub) then
                            local e = chunkBatch(cx, cy, sub, f)
                            if e.n > 0 and (not G_VERT_SPEND or G_VERT_SPEND(e.n * 6 - 4)) then
                                lg.draw(e.batch, cx * CW, cy * CW, 0, SC, SC)
                            end
                        end
                    end
                end
            end
        end
    end
    for cy = y0, y1 do
        for cx = x0, x1 do
            local c = chunkData(cx, cy)
            local list = c.liquids
            -- Fase y posición del brillo de cada baldosa (fijas): se calculan una vez.
            local gl = c.glints
            if not gl then
                gl = {}
                for i = 1, #list, 2 do
                    local tx, ty = list[i], list[i + 1]
                    gl[i] = H(tx, ty, 77) * 6.28
                    gl[i + 1] = floor(H(tx, ty, 78) * 12 + 2) * P
                    gl[#list + i] = floor(H(tx, ty, 79) * 12 + 2) * P
                end
                c.glints = gl
            end
            local nl = #list
            for i = 1, nl, 2 do
                local x, y = list[i] * TS, list[i + 1] * TS
                if x + TS > vl and x < vr and y + TS > vt and y < vb then
                    local k = (sin(t * speed + gl[i]) + 1) / 2
                    lg.setColor(fr, fg, fb, lava and (0.35 + k * 0.5) or k * 0.7)
                    local sx = x + gl[i + 1]
                    local sy = y + gl[nl + i]
                    lg.rectangle('fill', sx + floor(k * 2 + 0.5) * P, sy, P * (lava and 2 or 3), P)
                    if lava and k > 0.8 then lg.rectangle('fill', sx, sy - P * 2, P, P) end
                    n = n + 1
                    if n >= MAX_GLINTS then lg.setColor(1, 1, 1, 1) return end
                end
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

-- Props visibles, para mezclarlos en el orden por Y con las entidades.
-- La tabla devuelta se REUTILIZA en la siguiente llamada.
local visibleOut = {}
function W.visibleProps(cam)
    cam = cam or G.Camera
    local out = visibleOut
    clearList(out)
    -- Los objetos se anclan por el pie y los árboles miden hasta ~140 unidades:
    -- por abajo hace falta un margen mayor para que no desaparezca un árbol cuya
    -- copa todavía se ve.
    local padX, padTop, padBot = 70, 40, 160
    local l, t = cam.left(), cam.top()
    local r, b = l + cam.w, t + cam.h
    local x0, x1 = floor((l - padX) / CW), floor((r + padX) / CW)
    local y0, y1 = floor((t - padTop) / CW), floor((b + padBot) / CW)
    for cy = y0, y1 do
        for cx = x0, x1 do
            local c = chunkSoft(cx, cy)
            local props = c and c.props or NO_PROPS
            for i = 1, #props do
                local p = props[i]
                if p.x > l - padX and p.x < r + padX and p.y > t - padTop and p.y < b + padBot then
                    out[#out + 1] = p
                end
            end
        end
    end
    return out
end

local ALTAR_COL = { [0] = '#ff5f6d', '#5fd4ff', '#ff8ad8', '#ffd23f' }
local PI = math.pi

-- Arco del cofre con candado: lg.arc si existe; si no, polilínea con tabla reutilizada.
local arcPts = {}
local function drawArc(x, y, r, frac)
    if lg.arc then
        lg.arc('line', 'open', x, y, r, -PI / 2, -PI / 2 + 2 * PI * frac)
        return
    end
    local segs = 24
    local n = max(1, floor(segs * frac + 0.5))
    for i = 0, n do
        local a = -PI / 2 + 2 * PI * frac * (i / n)
        arcPts[i * 2 + 1] = x + math.cos(a) * r
        arcPts[i * 2 + 2] = y + sin(a) * r
    end
    for i = #arcPts, (n + 1) * 2 + 1, -1 do arcPts[i] = nil end
    if #arcPts >= 4 then lg.line(arcPts) end
end

-- Color de respaldo por tipo de prop cuando no hay tileset (para poder jugar sin él).
local function fallbackColor(typ, B)
    if typ == 'tree' then return B.leaf[3]
    elseif typ == 'rock' then return B.rock[2]
    elseif typ == 'chest' or typ == 'bigchest' then return '#f2c443'
    elseif typ == 'grass' then return B.grass[2]
    elseif typ == 'altar' then return '#9aa2ae'
    elseif typ == 'spring' then return '#5fe8d8'
    elseif typ == 'trap' then return '#b45ec4'
    end
    return '#b48aff'
end

-- ---------------- decoración de ruta (atlas img/deco) ----------------
local DECO = nil            -- { img, byCat = { cat = { {quad, w, h}, ... } } } o false
local function deco()
    if DECO ~= nil then return DECO end
    DECO = false
    local okd, d = pcall(require, 'data.deco')
    if not okd or not d then return DECO end
    local ok, img = pcall(lg.newImage, U.img('img/deco'))
    if not ok or not img then return DECO end
    if img.setFilter then pcall(img.setFilter, img, 'nearest', 'nearest') end
    local byCat = {}
    for _, o in ipairs(d.list) do
        local arr = byCat[o.cat] or {}
        arr[#arr + 1] = { lg.newQuad(o.x, o.y, o.w, o.h, d.w, d.h), o.w, o.h, o.name }
        byCat[o.cat] = arr
    end
    DECO = { img = img, byCat = byCat }
    return DECO
end

local DECO_CAT = { 'bush', 'bush', 'bush' }    -- (sólo quedan matas de HGSS)

-- ---------------- hierba alta estilo 4.ª gen (img/grass4) ----------------
local GRASS4 = nil          -- { img, back = {quads}, front = {quads} } o false
local function grass4()
    if GRASS4 ~= nil then return GRASS4 end
    GRASS4 = false
    local okd, d = pcall(require, 'data.grass4')
    if not okd or not d then return GRASS4 end
    local ok, img = pcall(lg.newImage, U.img('img/grass4'))
    if not ok or not img then return GRASS4 end
    if img.setFilter then pcall(img.setFilter, img, 'nearest', 'nearest') end
    local g = { img = img, back = {}, front = {} }
    for i, q in ipairs(d.back) do g.back[i] = lg.newQuad(q[1], q[2], q[3], q[4], d.w, d.h) end
    for i, q in ipairs(d.front) do g.front[i] = lg.newQuad(q[1], q[2], q[3], q[4], d.w, d.h) end
    g.short, g.flower = {}, {}
    for i, q in ipairs(d.short or {}) do g.short[i] = lg.newQuad(q[1], q[2], q[3], q[4], d.w, d.h) end
    for i, q in ipairs(d.flower or {}) do g.flower[i] = lg.newQuad(q[1], q[2], q[3], q[4], d.w, d.h) end
    GRASS4 = g
    return GRASS4
end

-- Fotograma de la hierba: quieta (1) o agitándose (2..4) mientras dura `rustle`.
local function grassFrame(p)
    local r = p.rustle or 0
    if r <= 0 then return 1 end
    return 2 + floor((0.4 - r) / 0.4 * 3) % 3
end

local function grassGen4() return DECO_BIOME[biome] and grass4() end

-- Capa trasera de la hierba alta: se dibuja antes que las entidades (en el suelo).
function W.drawGrassBase(props)
    -- (Hierba alta desactivada a petición: en los biomas de 4.ª gen sólo hay hierba normal.)
    do return end
    if not grassGen4() then return end
    lg.setColor(1, 1, 1, 1)
    for i = 1, #props do
        local p = props[i]
        if p.type == 'grass' then
            lg.draw(GRASS4.img, GRASS4.back[grassFrame(p)], p.tx * TS, p.ty * TS, 0, SC, SC)
        end
    end
end

-- Pisar hierba alta la agita (y suelta alguna hojita). Lo llama el juego cada fotograma.
local rustleBuf = {}
function W.rustle(x, y, dt)
    local tx, ty = floor(x / TS), floor(y / TS)
    for j = -1, 1 do
        for i = -1, 1 do
            local cx, cy = floor((tx + i) / N), floor((ty + j) / N)
            local c = chunkSoft(cx, cy)
            -- (Una mata como mucho por casilla: se mira directamente, sin recorrer
            -- todos los objetos del chunk 9 veces.)
            local p = c and c.grassAt[(ty + j - cy * N) * N + (tx + i - cx * N) + 1]
            if p then
                if i == 0 and j == 0 then
                    if (p.rustle or 0) <= 0.05 and G.FX and G.FX.burst then
                        G.FX.burst(p.x, p.y - 10, '#70c050', 3, 50)
                    end
                    p.rustle = 0.4
                elseif p.rustle and p.rustle > 0 then
                    p.rustle = math.max(0, p.rustle - dt)
                end
            end
        end
    end
end

-- Dibuja un objeto de decoración anclado por el pie (centro-inferior). La posición en
-- pantalla y si lleva sombra se calculan una vez por objeto (no se mueven).
local function drawDeco(entry, p, flash)
    local qd, qw, qh = entry[1], entry[2], entry[3]
    if p._dEntry ~= entry then
        p._dEntry = entry
        p._dx, p._dy = U.snap(p.x - qw * SC / 2), U.snap(p.y + 2 - qh * SC)
        p._dShadow = not entry[4]:find('^hgss')   -- los de HGSS ya traen su sombra
    end
    local x, y = p._dx, p._dy
    if p._dShadow then
        lg.setColor(0, 0, 0, 0.28)
        lg.ellipse('fill', p.x, p.y, math.max(8, qw * 0.7), math.max(3, qw * 0.25))
    end
    lg.setColor(1, 1, 1, 1)
    lg.draw(DECO.img, qd, x, y, 0, SC, SC)
    if flash then
        lg.setBlendMode('add')
        lg.setColor(1, 1, 1, 0.6)
        lg.draw(DECO.img, qd, x, y, 0, SC, SC)
        lg.setBlendMode('alpha')
    end
    lg.setColor(1, 1, 1, 1)
end

function W.drawProp(p, t)
    t = t or U.now()
    local typ = p.type
    -- Árboles y matas de ruta en los biomas verdes.
    if (typ == 'tree' or typ == 'deco') and DECO_BIOME[biome] and deco() then
        local e = p._deco
        if not e then
            local cat = typ == 'tree' and 'tree' or DECO_CAT[p.kind] or 'bush'
            local list = DECO.byCat[cat]
            if list and #list > 0 then
                e = list[floor(H(p.tx, p.ty, 4242) * #list) + 1]
                p._deco = e
            end
        end
        if e then
            drawDeco(e, p, p.flash > 0)
            return
        end
    end
    -- Rocas rompibles de HGSS en los biomas verdes.
    if typ == 'rock' and DECO_BIOME[biome] and deco() then
        local e = p._deco
        if not e then
            local list = DECO.byCat.rock
            if list and #list > 0 then e = list[floor(H(p.tx, p.ty, 4243) * #list) + 1]; p._deco = e end
        end
        if e then
            lg.setColor(0, 0, 0, 0.22)
            lg.ellipse('fill', p.x, p.y, e[2] * 0.8, e[2] * 0.3)
            drawDeco(e, p, p.flash > 0)
            return
        end
    end
    if typ == 'deco' then return end      -- en cuevas y volcanes no hay matas
    -- Hierba normal y flores de 4.ª gen (se mecen solas; la hierba se agita al pisarla).
    -- (En los biomas de 4.ª gen la hierba de los montones también es hierba normal.)
    if typ == 'tuft' or typ == 'flower' or (typ == 'grass' and grassGen4()) then
        if not grassGen4() then return end
        local fr
        if typ == 'tuft' or typ == 'grass' then
            local r = p.rustle or 0
            if r > 0 then
                p.rustle = math.max(0, r - love.timer.getDelta() / 2)
                fr = GRASS4.short[3 + floor(r * 10) % 2]
            else
                fr = GRASS4.short[1 + floor(t * 1.5 + p.wiggle) % 2]
            end
        else
            fr = GRASS4.flower[(p.kind or 0) * 2 + 1 + floor(t * 2 + p.wiggle) % 2]
        end
        if fr then
            if not p._gx then p._gx, p._gy = U.snap(p.x - 8 * SC), U.snap(p.y + 4 - 16 * SC) end
            lg.setColor(1, 1, 1, 1)
            lg.draw(GRASS4.img, fr, p._gx, p._gy, 0, SC, SC)
        end
        return
    end
    -- Hierba alta de 4.ª gen: aquí sólo la capa delantera (tapa los pies).
    if typ == 'grass' and grassGen4() then
        if p.rustle and p.rustle > 0 then p.rustle = math.max(0, p.rustle - (love.timer.getDelta() / 2)) end
        lg.setColor(1, 1, 1, 1)
        lg.draw(GRASS4.img, GRASS4.front[grassFrame(p)], p.tx * TS, p.ty * TS, 0, SC, SC)
        if p.flash > 0 then
            lg.setBlendMode('add'); lg.setColor(1, 1, 1, 0.5)
            lg.draw(GRASS4.img, GRASS4.front[grassFrame(p)], p.tx * TS, p.ty * TS, 0, SC, SC)
            lg.setBlendMode('alpha'); lg.setColor(1, 1, 1, 1)
        end
        return
    end
    local ts = ensureTileset()
    local variant = 0
    if typ == 'grass' then variant = (sin(t * 2.4 + p.wiggle) > 0.55) and 1 or 0
    elseif typ == 'rock' then variant = (p.hp < p.maxHp * 0.5) and 1 or 0
    elseif typ == 'altar' then variant = p.kind * 2 + (p.used and 1 or 0)
    elseif typ == 'spring' then variant = (p.charge < 0.15) and 1 or 0
    elseif typ == 'trap' then variant = p.kind end

    local qd, qw, qh = nil, nil, nil
    if ts then
        local arr = ts.props[typ]
        if arr then
            qd = arr[variant] or arr[0]
            if qd then
                local v = arr[variant] and variant or 0
                qw, qh = ts.propW[typ][v], ts.propH[typ][v]
            end
        end
    end
    if not qw then
        local sz = PROP_SIZE[typ]
        qw, qh = sz and sz[1] or 16, sz and sz[2] or 16
    end
    local w, h = qw * SC, qh * SC

    if p.flat then
        -- Planos (manantial, trampa): pegados al suelo, centrados en su casilla.
        local x, y = U.snap(p.x - w / 2), U.snap(p.y - 8 - h / 2)
        if qd then
            lg.setColor(1, 1, 1, 1)
            lg.draw(ts.img, qd, x, y, 0, SC, SC)
        else
            U.setColor(fallbackColor(typ, BIOMES[biome]), 0.8)
            lg.ellipse('fill', p.x, p.y - 8, w / 2, h / 2)
        end
        if typ == 'spring' and p.charge >= 0.15 and sin(t * 3 + p.wiggle) > 0.92 and G.FX and G.FX.twinkle then
            G.FX.twinkle(p.x + U.rand(-20, 20), p.y - 8 + U.rand(-6, 6))
        end
        lg.setColor(1, 1, 1, 1)
        return
    end

    if typ == 'altar' and not p.used then
        -- Halo del orbe, latiendo.
        U.setColor(ALTAR_COL[p.kind] or ALTAR_COL[0], 0.22 + sin(t * 3 + p.wiggle) * 0.1)
        lg.circle('fill', p.x, p.y - h + 11 * SC, 13)
    end
    if typ == 'bigchest' and p.open > 0 then
        local ct = (G.Interact and G.Interact.CHEST_TIME) or 3.5
        U.setColor('#ffd23f')
        lg.setLineWidth(3)
        drawArc(p.x, p.y - h / 2, 26, min(1, p.open / ct))
        lg.setLineWidth(1)
    end
    if typ ~= 'grass' then
        lg.setColor(0, 0, 0, 0.3)
        lg.ellipse('fill', p.x, p.y, p.r * 1.1, p.r * 0.38)
    end
    -- Anclaje centro-inferior (ox = w/2, oy = h en píxeles de arte, escala 2).
    -- Esquina superior izquierda ajustada a píxel de pantalla (qw puede ser impar).
    local x = U.snap(p.x - qw * SC / 2)
    local y = U.snap(p.y + (typ == 'grass' and 4 or 2) - qh * SC)
    if qd then
        lg.setColor(1, 1, 1, 1)
        lg.draw(ts.img, qd, x, y, 0, SC, SC)
        if p.flash > 0 then
            lg.setBlendMode('add')
            lg.setColor(1, 1, 1, 0.6)
            lg.draw(ts.img, qd, x, y, 0, SC, SC)
            lg.setBlendMode('alpha')
        end
    else
        U.setColor(fallbackColor(typ, BIOMES[biome]), p.flash > 0 and 1 or 0.9)
        lg.rectangle('fill', x, y, w, h)
    end
    lg.setColor(1, 1, 1, 1)
end

-- ---------------- objetos visibles (con caché) ----------------
-- W.visibleSplit(cam) -> (planos, ordenables): las dos tablas se REUTILIZAN.
--   planos      van pegados al suelo y se dibujan antes que nadie (W.drawFlat):
--               manantial, trampa, flores, matitas y, en los biomas de 4.ª gen, la
--               hierba (allí es el mismo dibujo que una matita).
--   ordenables  árboles, matas, rocas, cofres... YA ORDENADOS por W.propSortY
--               (guardada en p._sy), para mezclarlos con las entidades sin
--               reordenar todo cada fotograma.
-- Lo que no se dibuja en este bioma (flores sin 4.ª gen, matas de ruta fuera de los
-- biomas verdes) ni aparece.
-- Los candidatos se buscan en un rectángulo algo mayor que la vista y sólo se
-- rehacen al salirse la vista de él o al cambiar los objetos (propsVer); cada
-- fotograma sólo se filtran esos candidatos.
do
local VIS_PADX, VIS_PADTOP, VIS_PADBOT = 70, 40, 160   -- (igual que W.visibleProps)
local VIS_MARGIN = 128
local candFlat, candSort = {}, {}
local candVer = -1
local flatOut, sortOut = {}, {}
local function bySortY(a, b) return a._sy < b._sy end

local function rebuildCandidates(l, t, r, b)
    clearList(candFlat); clearList(candSort)
    candL, candT = l - VIS_PADX - VIS_MARGIN, t - VIS_PADTOP - VIS_MARGIN
    candR, candB = r + VIS_PADX + VIS_MARGIN, b + VIS_PADBOT + VIS_MARGIN
    local g4 = grassGen4() and true or false
    local decoOk = DECO_BIOME[biome] and deco() and true or false
    local nf, ns = 0, 0
    for cy = floor(candT / CW), floor(candB / CW) do
        for cx = floor(candL / CW), floor(candR / CW) do
            -- (Consulta blanda: el rectángulo es mayor que la vista. Si un trozo aún no
            -- está, sus objetos entran al terminarse: commitChunk sube propsVer.)
            local c = chunkSoft(cx, cy)
            local props = c and c.props or NO_PROPS
            for i = 1, #props do
                local p = props[i]
                local x, y = p.x, p.y
                if x > candL and x < candR and y > candT and y < candB then
                    local ty = p.type
                    if ty == 'flower' or ty == 'tuft' or (ty == 'grass' and g4) then
                        if g4 then nf = nf + 1; candFlat[nf] = p end
                    elseif p.flat then
                        nf = nf + 1; candFlat[nf] = p
                    elseif ty ~= 'deco' or decoOk then
                        p._sy = W.propSortY(p)
                        ns = ns + 1; candSort[ns] = p
                    end
                end
            end
        end
    end
    table.sort(candSort, bySortY)
    candVer = propsVer
end

function W.visibleSplit(cam)
    cam = cam or G.Camera
    local l, t = cam.left(), cam.top()
    local r, b = l + cam.w, t + cam.h
    local x0, x1 = l - VIS_PADX, r + VIS_PADX
    local y0, y1 = t - VIS_PADTOP, b + VIS_PADBOT
    if candVer ~= propsVer or x0 < candL or x1 > candR or y0 < candT or y1 > candB then
        rebuildCandidates(l, t, r, b)
    end
    clearList(flatOut); clearList(sortOut)
    local n = 0
    for i = 1, #candFlat do
        local p = candFlat[i]
        local x, y = p.x, p.y
        if x > x0 and x < x1 and y > y0 and y < y1 and not p.gone then n = n + 1; flatOut[n] = p end
    end
    n = 0
    for i = 1, #candSort do
        local p = candSort[i]
        local x, y = p.x, p.y
        if x > x0 and x < x1 and y > y0 and y < y1 and not p.gone then n = n + 1; sortOut[n] = p end
    end
    return flatOut, sortOut
end

-- Dibuja los objetos planos. Las flores y matitas de 4.ª gen (casi todos los
-- objetos a la vista) van en UN SpriteBatch que se rellena cada fotograma: una
-- sola llamada de dibujo en vez de una (más su setColor) por objeto.
local FLAT_CAP = 400
local flatBatch, flatBatchImg = nil, nil
function W.drawFlat(list, t)
    t = t or U.now()
    local g = grassGen4()
    local b = nil
    if g and not (G_FLAGS and G_FLAGS.noflat) then
        if flatBatchImg ~= g.img then
            if G_MARKF then G_MARKF("FLATBATCH") end
            if flatBatch and flatBatch.release then pcall(flatBatch.release, flatBatch) end
            -- (En la consola, 'static' como los lotes del suelo, que se sabe que va;
            -- en el PC, 'dynamic', que se rellena cada fotograma sin atascar la GPU.)
            flatBatch = lg.newSpriteBatch(g.img, FLAT_CAP, U.CONSOLE and 'static' or 'dynamic')
            flatBatchImg = g.img
        end
        b = flatBatch
        b:clear()
    end
    local nb = 0
    for i = 1, #list do
        local p = list[i]
        local typ = p.type
        if b and nb < FLAT_CAP and (typ == 'tuft' or typ == 'flower' or typ == 'grass') then
            -- (Lo mismo que hace W.drawProp con ellas.)
            local fr
            if typ == 'tuft' or typ == 'grass' then
                local r = p.rustle or 0
                if r > 0 then
                    p.rustle = max(0, r - love.timer.getDelta() / 2)
                    fr = g.short[3 + floor(r * 10) % 2]
                else
                    fr = g.short[1 + floor(t * 1.5 + p.wiggle) % 2]
                end
            else
                fr = g.flower[(p.kind or 0) * 2 + 1 + floor(t * 2 + p.wiggle) % 2]
            end
            if fr then
                if not p._gx then p._gx, p._gy = U.snap(p.x - 8 * SC), U.snap(p.y + 4 - 16 * SC) end
                -- El lote se dibuja a escala SC: posiciones en píxeles de arte.
                b:add(fr, p._gx / SC, p._gy / SC)
                nb = nb + 1
            end
        else
            W.drawProp(p, t)
        end
    end
    if nb > 0 then
        if b.flush then b:flush() end
        lg.setColor(1, 1, 1, 1)
        -- 6 vértices por sprite (spritebatch.cpp); la cuenta global lo sabe.
        if not G_VERT_SPEND or G_VERT_SPEND(nb * 6 - 4) then
            lg.draw(b, 0, 0, 0, SC, SC)
        end
    end
end

end -- (objetos visibles)

-- Viñeta en coordenadas de pantalla (superior 400x240). Sin gradientes: cuatro
-- bandas finas semitransparentes en los bordes.
function W.drawVignette(w, h)
    w = w or 400; h = h or 240
    local b = 10
    lg.setColor(0, 0, 0, 0.2)
    lg.rectangle('fill', 0, 0, w, b)
    lg.rectangle('fill', 0, h - b, w, b)
    lg.rectangle('fill', 0, b, b, h - 2 * b)
    lg.rectangle('fill', w - b, b, b, h - 2 * b)
    lg.setColor(1, 1, 1, 1)
end

-- Zona dura: los trozos que se ven (con un pelo de margen por la sacudida de la
-- cámara). drawGround los necesita igual; con un margen mayor entraban antes en la
-- zona y había que generarlos de golpe con el prefetch aún en camino. (Lo de los
-- márgenes, como la copa de un árbol cuyo pie queda bajo la vista, aparece en
-- cuanto el prefetch, que da prioridad a lo que está a punto de verse, lo termina.)
local function setHard(cam)
    local l, t = cam.x - cam.w / 2, cam.y - cam.h / 2
    hardX0, hardX1 = floor((l - 16) / CW), floor((l + cam.w + 16) / CW)
    hardY0, hardY1 = floor((t - 16) / CW), floor((t + cam.h + 16) / CW)
end

-- Tiempo por fotograma para adelantar chunks: lo que le sobra al fotograma. La
-- consola va a 30 fps fijos (33 ms); el fotograma (lógica + las dos pantallas, sin
-- el propio prefetch) se mide con PERF (main.lua) y se estima con prudencia:
-- sube en el acto y baja despacio (un pico suele repetirse).
local FRAME_T = 0.030                        -- (33 ms con algo de margen)
local MIN_BUDGET, MAX_BUDGET = 0.002, 0.014  -- (siempre algo; nunca demasiado, ni en el PC)
-- Si lo que falta está a punto de verse: mejor algún fotograma algo largo que un
-- trozo de golpe.
local URGENT_BUDGET = 0.012
-- Justo tras una carga (nueva partida, menú, grieta) sólo están los trozos de la
-- vista y el jugador ya anda: unos segundos con más tiempo para el anillo de
-- alrededor (el juego va un poco más lento, a ~20 fps, en vez de dar tirones).
local WARM_TIME, WARM_BUDGET = 3, 0.025
local warmT = 0
local workEst, lastWork, lastSpent = 0.025, nil, 0
local camPX, camPY, camVX, camVY = nil, nil, 0, 0
function W.update(dt, cam)
    cam = cam or G.Camera
    -- Destello de los objetos golpeados: sólo los de la lista (antes se recorrían
    -- todos los objetos a la vista cada fotograma).
    for i = #flashing, 1, -1 do
        local p = flashing[i]
        p.flash = p.flash - dt
        if p.flash <= 0 then
            p.flash = 0
            flashing[i] = flashing[#flashing]; flashing[#flashing] = nil
        end
    end
    setHard(cam)
    -- Velocidad de la cámara (suavizada), para adelantarse en su dirección.
    if camPX and dt > 0 then
        local ivx, ivy = (cam.x - camPX) / dt, (cam.y - camPY) / dt
        if ivx * ivx + ivy * ivy > 2000 * 2000 then ivx, ivy = 0, 0 end     -- (un salto: grieta, nueva partida)
        camVX = camVX + (ivx - camVX) * 0.2
        camVY = camVY + (ivy - camVY) * 0.2
    end
    camPX, camPY = cam.x, cam.y
    -- Lo que costó el fotograma anterior sin el prefetch (PERF se pone a 0 cada 30 s:
    -- entonces se sigue con la estimación que había).
    local P = PERF
    if P then
        local w = P.upd + P.top + P.bot
        if lastWork and w >= lastWork then
            local f = w - lastWork - lastSpent
            workEst = max(f, workEst - 0.0005)
        end
        lastWork = w
    end
    local budget = min(MAX_BUDGET, max(MIN_BUDGET, FRAME_T - workEst))
    local urgent = URGENT_BUDGET
    if warmT > 0 then warmT = warmT - dt; urgent = WARM_BUDGET end
    lastSpent = prefetch(cam.x, cam.y, camVX, camVY, cam.w / 2, cam.h / 2, budget, urgent)
end

-- ---------------- control ----------------

function W.reset(s)
    seed = floor(s or 0)
    if seed == 0 then seed = 1 end
    for k in pairs(data) do data[k] = nil end
    clearList(dataOrder)
    for k in pairs(broken) do broken[k] = nil end
    arena = nil
    clearPieceCache()
    latC, latN = {}, 0                           -- (esquinas del ruido: dependen de la semilla)
    pending, nPending, prefetchDone = {}, 0, false
    -- Sin zona dura hasta el próximo W.update (que la pone donde esté la cámara).
    hardX0, hardX1, hardY0, hardY1 = 0, -1, 0, -1
    camPX, camVX, camVY = nil, 0, 0
    warmT = WARM_TIME
    propsVer = propsVer + 1
    clearList(flashing)
    invalidateBatches()
end

-- @param i        bioma (se repiten los normales en ciclo; Tiles.ARENA+ son las grietas)
-- @param instant  (ignorado: en la consola no hay fundido)
function W.setBiome(i, instant)
    local b
    if i >= ARENA then b = i else b = ((i % NORMAL) + NORMAL) % NORMAL end
    if b == biome then return end
    biome = b
    propsVer = propsVer + 1                      -- (cambian las cajas de los árboles y qué es plano)
    -- El terreno es el mismo: sólo cambia el tileset (y con él los batches).
    releaseTileset()
end

function W.biomeName() return BIOMES[biome].name end
function W.biome() return biome end

-- Arena de la grieta: { tx, ty, r, type } (en tiles) o nil.
function W.setArena(a)
    arena = a
    invalidateBatches()
    clearPieceCache()
    pending, nPending, prefetchDone = {}, 0, false   -- (el terreno de la zona cambia)
    warmT = WARM_TIME                            -- (se entra o se sale de un salto: ver W.update)
    propsVer = propsVer + 1
    if not a then return end
    a.th = ARENA_THEMES[a.type] or ARENA_THEMES.normal
    -- Olvida los chunks de esa zona (si se hubieran generado antes).
    local R = a.r + 9
    for k, c in pairs(data) do
        if abs(c.cx * N + N / 2 - a.tx) < R + N and abs(c.cy * N + N / 2 - a.ty) < R + N then
            data[k] = nil
            U.remove(dataOrder, k)
        end
    end
end
function W.arena() return arena end
