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
function test.draw()
    local Q = G.PERSONALITY_TEST
    local q = Q[idx]
    UI.bar(10, 8, W - 20, 5, (idx - 1) / #Q, UI.C.gold)
    -- Con la fuente pixelada propia: se ve igual en el PC y en la 3DS (la fuente del
    -- sistema de la consola salía diminuta).
    local PF = G.PixelFont
    local head = "PREGUNTA " .. idx .. " DE " .. #Q
    PF.print(head, (W - PF.width(head, 1)) / 2, 18, { s = 1, color = "#e8e4ff", shadow = "#3a3458" })
    PF.printBlock(q.q, 8, 32, W - 16, { s = 2, gap = 1, color = "#ffffff", shadow = "#3a3458" })
    for i, a in ipairs(q.a) do
        local by = 96 + (i - 1) * 35
        UI.button("a" .. i, 10, by, W - 20, 31, "", { on = picked == i })
        local lines = PF.wrap(a.t, 1.5, W - 36, 1)
        local lh = 12
        local ty = by + math.floor((31 - #lines * lh + 2) / 2)
        for k, l in ipairs(lines) do
            PF.print(l, (W - PF.width(l, 1.5, 1)) / 2, ty + (k - 1) * lh, { s = 1.5, gap = 1, color = "#ffffff", shadow = "#1e3a6e" })
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
function res.enter()
    local mon = G.DEX_BY[result.dex]
    G.Sprites.preload({ result.dex }, false)
    G.TopUI.overlay = function()
        G.TopUI.pokemonCard(result.dex, { footer = "¡" .. mon.name .. " quiere ir contigo!" })
    end
end
function res.draw()
    local mon = G.DEX_BY[result.dex]
    local trait = result.trait:sub(1, 1):upper() .. result.trait:sub(2)
    UI.text("Tu personalidad es...", 0, 14, { size = 12, color = UI.C.muted, w = W, align = "center" })
    UI.text(trait, 0, 30, { size = 22, color = UI.C.gold, w = W, align = "center" })
    UI.text(G.TRAIT_TEXT[result.trait] or "", 16, 62, { size = 12, w = W - 32, align = "center" })
    UI.text("Tu compañero: " .. mon.name, 0, 100, { size = 16, w = W, align = "center" })
    UI.button("ok", 30, 150, 260, 30, "¡Vamos juntos!", { size = 12, color = "#3c9c54" })
    UI.button("other", 30, 190, 260, 30, "Elegir otro", { size = 12 })
end
local function choose(dex)
    if G_STEP then G_STEP("elegir inicial " .. tostring(dex)) end
    local save = G.DB.save
    save.starter = dex
    save.partner = dex
    save.personality = result and { trait = result.trait, scores = scores } or nil
    G.DB.grant(dex, "starter")
    if G_STEP then G_STEP("concedido; guardando") end
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
function starters.draw()
    UI.text("Elige a tu compañero", 0, 2, { size = 12, color = UI.C.gold, w = W, align = "center" })
    for i, s in ipairs(G.STARTERS) do
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local x, y = 16 + c * CW, 18 + r * CH
        local on = s.dex == picked
        U.setColor(on and "#2a3a1a" or UI.C.panel)
        lg.rectangle("fill", x, y, CW - 2, CH - 2, 4, 4)
        if on then U.setColor(UI.C.gold); lg.rectangle("line", x + 0.5, y + 0.5, CW - 3, CH - 3, 4, 4) end
        lg.setColor(1, 1, 1, 1)
        G.Sprites.drawStill(s.dex, x + CW / 2 - 1, y + CH - 6, 0.5)
        UI.hitbox("st" .. i, x, y, CW - 2, CH - 2)
    end
    local name = picked and G.DEX_BY[picked].name or "Selecciona un Pokémon"
    UI.text(name, 0, 220, { size = 10, color = UI.C.muted, w = 120, align = "left" })
    UI.button("back", 120, 216, 90, 20, "Volver", { size = 10 })
    UI.button("ok", 216, 216, 90, 20, "Elegir", { size = 10, color = "#3c9c54", enabled = picked ~= nil })
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
    local i = picked and U.indexOf((function() local t = {} for k, s in ipairs(G.STARTERS) do t[k] = s.dex end return t end)(), picked) or 1
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
