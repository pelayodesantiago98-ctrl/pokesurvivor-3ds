-- input.lua — entrada unificada: mando de 3DS (gamepad en LÖVE Potion) y teclado (PC).
--
-- Botones tal y como los expone LÖVE Potion: a, b, x, y, dpup/dpdown/dpleft/dpright,
-- leftshoulder (L), rightshoulder (R), start, back (SELECT). Ejes leftx/lefty (circle
-- pad), rightx/righty (C-stick), triggerleft/right (ZL/ZR). En PC nest los emula.
local U = G.U
local Input = {}
G.Input = Input

local down    = {}   -- botón -> true mientras está pulsado
local pressed = {}   -- botón -> true solo el frame en que se pulsa
local axes    = { leftx = 0, lefty = 0, rightx = 0, righty = 0 }

function Input.load()
    down, pressed = {}, {}
end

function Input.gamepadPressed(button)
    down[button] = true
    pressed[button] = true
end

function Input.gamepadReleased(button)
    down[button] = nil
end

function Input.gamepadAxis(axis, value)
    -- En la 3DS LÖVE Potion entrega el eje vertical tal cual lo da libctru
    -- (positivo = arriba); en LÖVE/nest positivo es abajo. Se invierte solo en consola.
    if U.CONSOLE and (axis == "lefty" or axis == "righty") then
        value = -value
    end
    axes[axis] = value
end

function Input.isDown(button) return down[button] == true end
Input.held = Input.isDown
function Input.pressed(button) return pressed[button] == true end
Input.tap = Input.pressed

-- Vector de movimiento normalizado (dos valores): circle pad o cruceta.
-- Con Input.auto (prueba de resistencia) el jugador da vueltas solo.
function Input.axis()
    if Input.auto then
        -- Modo demostración: huye del enemigo más cercano y, si no hay peligro, da vueltas.
        local pl = G.Game and G.Game.player()
        local t = love.timer.getTime() * 0.9
        local x, y = math.cos(t), math.sin(t) * 0.7
        if pl and G.EnemyMgr then
            local all = G.EnemyMgr.all()
            local fx, fy = 0, 0
            for i = 1, #all do
                local e = all[i]
                if not e.dead then
                    local dx, dy = pl.x - e.x, pl.y - e.y
                    local d2 = dx * dx + dy * dy
                    if d2 < 160 * 160 and d2 > 1 then
                        local w = 1 / d2
                        fx, fy = fx + dx * w, fy + dy * w
                    end
                end
            end
            local m = math.sqrt(fx * fx + fy * fy)
            if m > 0 then
                local ex, ey = fx / m, fy / m
                -- Huir de lado (rodear la horda) en vez de en línea recta.
                x, y = ex * 0.7 - ey * 0.7, ey * 0.7 + ex * 0.7
            end
        end
        local len = math.sqrt(x * x + y * y)
        if len > 1 then x, y = x / len, y / len end
        return x, y
    end
    local x, y = axes.leftx or 0, axes.lefty or 0
    if math.abs(x) < 0.2 then x = 0 end
    if math.abs(y) < 0.2 then y = 0 end

    if down.dpleft  then x = -1 end
    if down.dpright then x =  1 end
    if down.dpup    then y = -1 end
    if down.dpdown  then y =  1 end

    -- Respaldo de teclado para PC sin nest (WASD / flechas).
    if love.keyboard and not U.CONSOLE then
        if love.keyboard.isDown("left")  then x = -1 end
        if love.keyboard.isDown("right") then x =  1 end
        if love.keyboard.isDown("up")    then y = -1 end
        if love.keyboard.isDown("down")  then y =  1 end
    end

    local len = math.sqrt(x * x + y * y)
    if len > 1 then x, y = x / len, y / len end
    return x, y
end

-- Llamar al final de love.update para limpiar los "pressed" de un frame.
function Input.endFrame()
    for k in pairs(pressed) do pressed[k] = nil end
end
