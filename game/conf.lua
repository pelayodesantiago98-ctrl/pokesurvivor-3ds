function love.conf(t)
    t.identity = "pokesurvivor3ds"
    -- LÖVE Potion es API 12.0; en PC se prueba con LÖVE 11.5, que muestra un cuadro
    -- de aviso BLOQUEANTE si la versión declarada no coincide.
    local major = love.getVersion and love.getVersion() or 11
    t.version = major >= 12 and "12.0" or "11.5"
    t.console = false
    t.window.title = "PokéSurvivor 3DS"
    t.window.width = 400
    t.window.height = 240
    t.window.resizable = false
    t.modules.physics = false
    t.modules.video = false
end
