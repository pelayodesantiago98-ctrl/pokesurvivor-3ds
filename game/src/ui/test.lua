-- test.lua — test de personalidad y elección de compañero (port de js/ui/test.js).
-- Pantalla inferior: preguntas y rejilla de iniciales. Superior: el compañero.
local U = G.U
local UI = G.UI
local T = {}
G.TestUI = T

local lg = love.graphics
local W, H = UI.W, UI.H
local idx, scores, result, picked = 1, {}, nil, nil

-- ---------------- preguntas ----------------
local test = {}
function test.enter() end
-- Estilos de letra y botones (tablas fijas: nada de tablas nuevas en cada fotograma).
local HEAD_ST = { s = 1, color = "#e8e4ff", shadow = "#3a3458" }
local Q_ST = { s = 2, gap = 1, color = "#ffffff", shadow = "#3a3458" }
local A_ST = { s = 1.5, gap = 1, color = "#ffffff", shadow = "#1e3a6e" }
local BTN_ON, BTN_OFF = { on = true }, { on = false }
local ANSWER_ID = { "a1", "a2", "a3", "a4", "a5", "a6", "a7", "a8" }
-- Disposición de cada pregunta (líneas partidas y sus posiciones), calculada una
-- vez: { head, hx, lines = { {texto, x, y}... } }, como hacían PF.printBlock y PF.wrap.
local layouts = {}
local function layoutOf(i)
    local L = layouts[i]
    if L then return L end
    local PF = G.PixelFont
    local Q = G.PERSONALITY_TEST
    local q = Q[i]
    L = { lines = {}, answers = {} }
    L.head = "PREGUNTA " .. i .. " DE " .. #Q
    L.hx = (W - PF.width(L.head, 1)) / 2
    -- Enunciado (lo que hace PF.printBlock(q.q, 8, 32, W - 16, Q_ST)).
    local s, x, y, w = Q_ST.s, 8, 32, W - 16
    local lh = PF.height(s) + math.max(2, math.floor(PF.height(s) / 3))
    for k, l in ipairs(PF.wrap(q.q, s, w, Q_ST.gap)) do
        L.lines[k] = { l, x + (w - PF.width(l, s, Q_ST.gap)) / 2, y + (k - 1) * lh }
    end
    -- Respuestas, centradas en su botón.
    for k, a in ipairs(q.a) do
        local by = 96 + (k - 1) * 35
        local lines = PF.wrap(a.t, 1.5, W - 36, 1)
        local alh = 12
        local ty = by + math.floor((31 - #lines * alh + 2) / 2)
        local al = {}
        for j, l in ipairs(lines) do al[j] = { l, (W - PF.width(l, 1.5, 1)) / 2, ty + (j - 1) * alh } end
        L.answers[k] = { by = by, lines = al }
    end
    layouts[i] = L
    return L
end
function test.draw()
    local Q = G.PERSONALITY_TEST
    local L = layoutOf(idx)
    UI.bar(10, 8, W - 20, 5, (idx - 1) / #Q, UI.C.gold)
    -- Con la fuente pixelada propia: se ve igual en el PC y en la 3DS (la fuente del
    -- sistema de la consola salía diminuta).
    local PF = G.PixelFont
    PF.print(L.head, L.hx, 18, HEAD_ST)
    for k = 1, #L.lines do
        local l = L.lines[k]
        PF.print(l[1], l[2], l[3], Q_ST)
    end
    for i = 1, #L.answers do
        local A = L.answers[i]
        UI.button(ANSWER_ID[i] or ("a" .. i), 10, A.by, W - 20, 31, "", picked == i and BTN_ON or BTN_OFF)
        for k = 1, #A.lines do
            local l = A.lines[k]
            PF.print(l[1], l[2], l[3], A_ST)
        end
    end
end
local function answer(i)
    local a = G.PERSONALITY_TEST[idx].a[i]
    for k, v in pairs(a.p) do scores[k] = (scores[k] or 0) + v end
    G.Audio.sfx("select")
    idx = idx + 1
    picked = nil
    if idx > #G.PERSONALITY_TEST then
        result = G.personalityResult(scores)
        UI.show("result")
    end
end
function test.touch(x, y)
    local id = UI.hit(x, y)
    local i = id and tonumber(id:match("^a(%d+)$"))
    if i then answer(i) end
end
function test.button(b)
    local n = #G.PERSONALITY_TEST[idx].a
    if b == "dpdown" then picked = ((picked or 0) % n) + 1
    elseif b == "dpup" then picked = ((picked or 1) - 2) % n + 1
    elseif b == "a" and picked then answer(picked) end
end
UI.register("test", test)

-- ---------------- resultado ----------------
local res = {}
local resTrait, resMate = "", ""      -- textos del resultado (se hacen al entrar)
local R_T1 = { size = 12, color = UI.C.muted, w = W, align = "center" }
local R_T2 = { size = 22, color = UI.C.gold, w = W, align = "center" }
local R_T3 = { size = 12, w = W - 32, align = "center" }
local R_T4 = { size = 16, w = W, align = "center" }
local R_OK = { size = 12, color = "#3c9c54" }
local R_OTHER = { size = 12 }
function res.enter()
    local mon = G.DEX_BY[result.dex]
    resTrait = result.trait:sub(1, 1):upper() .. result.trait:sub(2)
    resMate = "Tu compañero: " .. mon.name
    G.Sprites.preload({ result.dex }, false)
    local card = { footer = "¡" .. mon.name .. " quiere ir contigo!" }
    G.TopUI.overlay = function()
        G.TopUI.pokemonCard(result.dex, card)
    end
end
function res.draw()
    UI.text("Tu personalidad es...", 0, 14, R_T1)
    UI.text(resTrait, 0, 30, R_T2)
    UI.text(G.TRAIT_TEXT[result.trait] or "", 16, 62, R_T3)
    UI.text(resMate, 0, 100, R_T4)
    UI.button("ok", 30, 150, 260, 30, "¡Vamos juntos!", R_OK)
    UI.button("other", 30, 190, 260, 30, "Elegir otro", R_OTHER)
end
local function choose(dex)
    if G_STEP then G_STEP("elegir inicial " .. tostring(dex)) end
    local save = G.DB.save
    save.starter = dex
    save.partner = dex
    save.personality = result and { trait = result.trait, scores = scores } or nil
    G.DB.grant(dex, "starter")
    G.DB.commit()
    if G_STEP then G_STEP("guardado") end
    UI.toast("¡" .. G.DEX_BY[dex].name .. " se une a ti!")
    G.Flow.goMenu()
end
function res.touch(x, y)
    local id = UI.hit(x, y)
    if id == "ok" then choose(result.dex)
    elseif id == "other" then UI.show("starters") end
end
function res.button(b)
    if b == "a" then choose(result.dex) elseif b == "b" then UI.show("starters") end
end
UI.register("result", res)

-- ---------------- rejilla de iniciales ----------------
local starters = {}
local COLS, CW, CH = 6, 48, 40
function starters.enter()
    picked = result and result.dex or nil
    local dexes = {}
    for i, s in ipairs(G.STARTERS) do dexes[i] = s.dex end
    G.Sprites.preload(dexes, false)
    starters.refreshTop()
end
function starters.refreshTop()
    if picked then
        local s = G.STARTER_BY[picked]
        local mv = G.Moves.BY_ID[s.start]
        G.TopUI.overlay = function()
            G.TopUI.pokemonCard(picked, { footer = (mv and mv.name or "") .. " · " .. table.concat(s.traits, ", ") })
        end
    else
        G.TopUI.overlay = nil
    end
end
local CELL_ID = {}                    -- "st1", "st2"... (sin concatenar en cada fotograma)
local S_TITLE = { size = 12, color = UI.C.gold, w = W, align = "center" }
local S_NAME = { size = 10, color = UI.C.muted, w = 120, align = "left" }
local S_BACK = { size = 10 }
local S_OK_ON = { size = 10, color = "#3c9c54", enabled = true }
local S_OK_OFF = { size = 10, color = "#3c9c54", enabled = false }
function starters.draw()
    UI.text("Elige a tu compañero", 0, 2, S_TITLE)
    for i, s in ipairs(G.STARTERS) do
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local x, y = 16 + c * CW, 18 + r * CH
        local on = s.dex == picked
        U.setColor(on and "#2a3a1a" or UI.C.panel)
        lg.rectangle("fill", x, y, CW - 2, CH - 2, 4, 4)
        if on then U.setColor(UI.C.gold); lg.rectangle("line", x + 0.5, y + 0.5, CW - 3, CH - 3, 4, 4) end
        lg.setColor(1, 1, 1, 1)
        G.Sprites.drawStill(s.dex, x + CW / 2 - 1, y + CH - 6, 0.5)
        local id = CELL_ID[i]
        if not id then id = "st" .. i; CELL_ID[i] = id end
        UI.hitbox(id, x, y, CW - 2, CH - 2)
    end
    local name = picked and G.DEX_BY[picked].name or "Selecciona un Pokémon"
    UI.text(name, 0, 220, S_NAME)
    UI.button("back", 120, 216, 90, 20, "Volver", S_BACK)
    UI.button("ok", 216, 216, 90, 20, "Elegir", picked ~= nil and S_OK_ON or S_OK_OFF)
end
function starters.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show(result and "result" or "menu") return end
    if id == "ok" then if picked then choose(picked) end return end
    local i = tonumber(id:match("^st(%d+)$"))
    if i then picked = G.STARTERS[i].dex; G.Audio.sfx("select"); starters.refreshTop() end
end
function starters.button(b)
    local i = 1
    if picked then
        for k, s in ipairs(G.STARTERS) do if s.dex == picked then i = k break end end
    end
    local n = #G.STARTERS
    if b == "dpright" then i = i % n + 1 elseif b == "dpleft" then i = (i - 2) % n + 1
    elseif b == "dpdown" then i = (i - 1 + COLS) % n + 1 elseif b == "dpup" then i = (i - 1 - COLS) % n + 1
    elseif b == "a" then if picked then choose(picked) end return
    elseif b == "b" then UI.show(result and "result" or "menu") return
    else return end
    picked = G.STARTERS[i].dex
    starters.refreshTop()
end
UI.register("starters", starters)

function T.start()
    idx, scores, result, picked = 1, {}, nil, nil
    UI.show("test")
end
