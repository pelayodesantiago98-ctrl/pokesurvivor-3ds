-- camera.lua — vista y transformación mundo<->pantalla (port de js/core/camera.js).
-- La pantalla superior (400x240) muestra 800x480 unidades de mundo (scale 0.5):
-- un píxel de arte (PX = 2 unidades) es un píxel de pantalla.
local U = G.U
local C = {
    x = 0, y = 0,
    scale = 0.5,
    w = 800, h = 480,
    shake = 0,
    _sx = 0, _sy = 0,
}
G.Camera = C

function C.follow(tx, ty, dt)
    C.x = U.damp(C.x, tx, 9, dt)
    C.y = U.damp(C.y, ty, 9, dt)
    if C.shake > 0 then
        C.shake = math.max(0, C.shake - dt * 2.4)
        local a = C.shake * 7
        C._sx = U.rand(-a, a)
        C._sy = U.rand(-a, a)
    else
        C._sx, C._sy = 0, 0
    end
end

function C.kick(amount)
    C.shake = math.min(1.2, C.shake + amount)
end

function C.left() return C.x - C.w / 2 end
function C.top() return C.y - C.h / 2 end

-- Aplica la transformación de cámara (redondeada a píxeles de pantalla).
function C.apply()
    love.graphics.push()
    love.graphics.scale(C.scale, C.scale)
    local k = C.scale
    local tx = math.floor((-C.left() + C._sx) * k + 0.5) / k
    local ty = math.floor((-C.top() + C._sy) * k + 0.5) / k
    love.graphics.translate(tx, ty)
end

function C.unapply()
    love.graphics.pop()
end

-- ¿Está el punto dentro de la vista (con margen)?
function C.sees(x, y, pad)
    pad = pad or 60
    local l, t = C.left(), C.top()
    return x > l - pad and x < l + C.w + pad and y > t - pad and y < t + C.h + pad
end

-- Radio del círculo que envuelve la vista: usado para spawnear fuera.
function C.outerRadius()
    return U.hypot(C.w, C.h) / 2 + 40
end

-- Mundo -> pantalla superior (para flechas en el borde, etc.).
function C.toScreen(x, y)
    return (x - C.left()) * C.scale, (y - C.top()) * C.scale
end
