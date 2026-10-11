-- starters.lua — compañeros iniciales y test de personalidad (port de js/data/starters.js).
-- Como en Mundo Misterioso: unas preguntas deciden tu personalidad, y tu
-- personalidad decide tu compañero. Puedes rechazarlo y elegir otro.
--
-- Los stats salen de G.DEX; aquí sólo van los rasgos y el movimiento inicial.
-- Requiere G.Moves y G.DEX_BY cargados antes de llamar a G.startMoveOf.
local U = G.U

G.STARTERS = {
    { dex = 1,   start = 'vine-whip',  traits = { 'leal', 'paciente' } },
    { dex = 4,   start = 'ember',      traits = { 'valiente', 'impulsivo' } },
    { dex = 7,   start = 'water-gun',  traits = { 'prudente', 'leal' } },
    { dex = 152, start = 'vine-whip',  traits = { 'dulce', 'paciente' } },
    { dex = 155, start = 'ember',      traits = { 'tímido', 'impulsivo' } },
    { dex = 158, start = 'water-gun',  traits = { 'travieso', 'valiente' } },
    { dex = 252, start = 'razor-leaf', traits = { 'sereno', 'astuto' } },
    { dex = 255, start = 'ember',      traits = { 'alegre', 'valiente' } },
    { dex = 258, start = 'water-gun',  traits = { 'tenaz', 'leal' } },
    { dex = 387, start = 'vine-whip',  traits = { 'paciente', 'tenaz' } },
    { dex = 390, start = 'ember',      traits = { 'travieso', 'alegre' } },
    { dex = 393, start = 'bubble',     traits = { 'orgulloso', 'prudente' } },
    { dex = 495, start = 'razor-leaf', traits = { 'orgulloso', 'astuto' } },
    { dex = 498, start = 'ember',      traits = { 'tenaz', 'alegre' } },
    { dex = 501, start = 'water-gun',  traits = { 'valiente', 'travieso' } },
    { dex = 650, start = 'vine-whip',  traits = { 'travieso', 'tenaz' } },
    { dex = 653, start = 'ember',      traits = { 'astuto', 'sereno' } },
    { dex = 656, start = 'water-gun',  traits = { 'sereno', 'astuto' } },
    { dex = 722, start = 'razor-leaf', traits = { 'sereno', 'dulce' } },
    { dex = 725, start = 'ember',      traits = { 'solitario', 'orgulloso' } },
    { dex = 728, start = 'bubble',     traits = { 'alegre', 'dulce' } },
    { dex = 810, start = 'vine-whip',  traits = { 'alegre', 'travieso' } },
    { dex = 813, start = 'ember',      traits = { 'impulsivo', 'alegre' } },
    { dex = 816, start = 'water-gun',  traits = { 'tímido', 'astuto' } },
    { dex = 906, start = 'razor-leaf', traits = { 'solitario', 'astuto' } },
    { dex = 909, start = 'ember',      traits = { 'tranquilo', 'tenaz' } },
    { dex = 912, start = 'water-gun',  traits = { 'orgulloso', 'prudente' } },
    { dex = 54,  start = 'confusion',  traits = { 'caótico', 'tímido' } },
    { dex = 79,  start = 'confusion',  traits = { 'tranquilo', 'paciente' } }
}

G.STARTER_BY = {}
for i = 1, #G.STARTERS do G.STARTER_BY[G.STARTERS[i].dex] = G.STARTERS[i] end

-- Movimiento inicial de cualquier Pokémon (starter o del gacha).
function G.startMoveOf(dex)
    local s = G.STARTER_BY[dex]
    if s then return s.start end
    return G.Moves.startFor(G.DEX_BY[dex])
end

-- Descripción corta de cada rasgo, para la pantalla de resultado.
G.TRAIT_TEXT = {
    valiente  = 'No te lo piensas dos veces cuando alguien necesita ayuda.',
    impulsivo = 'Actúas primero y piensas después. ¡A veces sale bien!',
    prudente  = 'Mides cada paso antes de darlo.',
    leal      = 'Tus amigos saben que pueden contar contigo siempre.',
    paciente  = 'Sabes esperar el momento justo.',
    dulce     = 'Tu amabilidad tranquiliza a todos los que te rodean.',
    ['tímido'] = 'Te cuesta dar el primer paso, pero sientes mucho.',
    travieso  = 'Siempre tienes una broma preparada.',
    sereno    = 'Mantienes la calma cuando todo se complica.',
    astuto    = 'Ves soluciones donde otros ven problemas.',
    alegre    = 'Contagias energía allá donde vas.',
    tenaz     = 'Rendirse no entra en tus planes.',
    orgulloso = 'Te exiges ser el mejor, y casi siempre lo consigues.',
    solitario = 'Vas a tu aire y no te importa.',
    tranquilo = 'Nada te altera. Nada.',
    ['caótico'] = 'Ni tú sabes qué vas a hacer después.'
}

-- Orden de los rasgos (el de TRAIT_TEXT en el JS): sirve para desempatar en
-- personalityResult de forma determinista, ya que pairs() no tiene orden.
G.TRAIT_ORDER = { 'valiente', 'impulsivo', 'prudente', 'leal', 'paciente', 'dulce', 'tímido', 'travieso',
                  'sereno', 'astuto', 'alegre', 'tenaz', 'orgulloso', 'solitario', 'tranquilo', 'caótico' }

G.PERSONALITY_TEST = {
    { q = '¡Hay una pelea en mitad del pueblo! ¿Qué haces?', a = {
        { t = 'Me meto a ayudar sin pensarlo.',       p = { valiente = 2, impulsivo = 1 } },
        { t = 'Busco a alguien que pueda pararla.',    p = { prudente = 2, leal = 1 } },
        { t = 'Lo observo todo desde lejos.',          p = { sereno = 1, ['tímido'] = 1, solitario = 1 } },
        { t = 'Me río y animo a los dos.',             p = { travieso = 2, ['caótico'] = 1 } } } },
    { q = 'Te encuentras una cartera en el suelo.', a = {
        { t = 'La llevo enseguida a la policía.',      p = { leal = 2, dulce = 1 } },
        { t = 'Busco a su dueño aunque tarde horas.',  p = { tenaz = 2, paciente = 1 } },
        { t = 'Primero miro qué hay dentro…',         p = { astuto = 2, travieso = 1 } },
        { t = 'Ni la toco, no vaya a ser.',            p = { prudente = 1, ['tímido'] = 2 } } } },
    { q = 'Tu día libre ideal es…', a = {
        { t = 'Una aventura sin ningún plan.',         p = { impulsivo = 2, alegre = 1 } },
        { t = 'Leer, pensar, estar tranquilo.',        p = { sereno = 2, tranquilo = 1 } },
        { t = 'Quedar con todos mis amigos.',          p = { alegre = 2, leal = 1 } },
        { t = 'Entrenar para ser mejor.',              p = { tenaz = 2, orgulloso = 1 } } } },
    { q = 'Mañana tienes un examen importante.', a = {
        { t = 'Estudio hasta las tantas.',             p = { tenaz = 2, prudente = 1 } },
        { t = 'Repaso lo justo: confío en mí.',        p = { orgulloso = 2, sereno = 1 } },
        { t = 'Me agobio muchísimo.',                  p = { ['tímido'] = 2, dulce = 1 } },
        { t = '¿Examen? Ya veré mañana.',              p = { ['caótico'] = 2, tranquilo = 1 } } } },
    { q = '¿Qué dicen de ti tus amigos?', a = {
        { t = 'Que soy lo más divertido del grupo.',   p = { alegre = 2, travieso = 1 } },
        { t = 'Que siempre pueden contar conmigo.',    p = { leal = 2, dulce = 1 } },
        { t = 'Que soy un poco misterioso.',           p = { solitario = 2, astuto = 1 } },
        { t = 'Que no me rindo nunca.',                p = { valiente = 1, tenaz = 2 } } } },
    { q = 'El camino se divide: uno oscuro y corto, otro largo y soleado.', a = {
        { t = 'El oscuro, ¡más emoción!',              p = { valiente = 2, impulsivo = 1 } },
        { t = 'El largo, sin prisa.',                  p = { paciente = 2, prudente = 1 } },
        { t = 'Me siento a pensarlo un rato.',         p = { tranquilo = 2, sereno = 1 } },
        { t = 'Ninguno: abro un atajo nuevo.',         p = { astuto = 2, ['caótico'] = 1 } } } },
    { q = 'Alguien se burla de ti delante de todos.', a = {
        { t = 'Le contesto en el acto.',               p = { orgulloso = 2, impulsivo = 1 } },
        { t = 'Le ignoro por completo.',               p = { sereno = 2, solitario = 1 } },
        { t = 'Me afecta, aunque no lo diga.',         p = { ['tímido'] = 2, dulce = 1 } },
        { t = 'Le devuelvo una broma mejor.',          p = { travieso = 2, astuto = 1 } } } },
    { q = '¿Qué es lo más importante para ti?', a = {
        { t = 'La amistad.',                           p = { leal = 2, alegre = 1 } },
        { t = 'La libertad.',                          p = { solitario = 2, impulsivo = 1 } },
        { t = 'La calma.',                             p = { tranquilo = 2, paciente = 1 } },
        { t = 'Ser el mejor.',                         p = { orgulloso = 2, tenaz = 1 } } } }
}

-- Puntuaciones de rasgos ({rasgo = puntos}) -> { trait, dex } con el compañero
-- que mejor encaja. Si `scores` tiene un campo `order` (lista de rasgos en el
-- orden en que se fueron sumando) se usa para desempatar como el JS; si no, el
-- orden fijo de G.TRAIT_ORDER.
function G.personalityResult(scores)
    local order = scores.order or G.TRAIT_ORDER
    local trait, best = nil, nil
    for i = 1, #order do
        local k = order[i]
        local v = scores[k]
        if type(v) == "number" and (best == nil or v > best) then trait, best = k, v end
    end
    -- Rasgos con puntuación que no estén en la lista de orden.
    for k, v in pairs(scores) do
        if k ~= 'order' and type(v) == "number" and (best == nil or v > best) then trait, best = k, v end
    end
    local cands, bestScore = {}, -1
    for i = 1, #G.STARTERS do
        local s = G.STARTERS[i]
        -- El rasgo principal pesa el doble.
        local v = (scores[s.traits[1]] or 0) * 2 + (scores[s.traits[2]] or 0)
        if v > bestScore then bestScore = v; cands = { s }
        elseif v == bestScore then cands[#cands + 1] = s end
    end
    return { trait = trait, dex = U.pick(cands).dex }
end
