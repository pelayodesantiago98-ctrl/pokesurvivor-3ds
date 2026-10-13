#!/usr/bin/env python3
"""
Genera el atlas de iconos de PokéSurvivor para la 3DS a partir de los mapas de
caracteres de js/ui/icons.js (copiados aquí tal cual).

  python tools/gen_icons.py          -> game/img/icons.png + game/data/icons.lua

Contenido del atlas (todo a tamaño nativo, con sus colores reales):
  - Iconos de interfaz: heart, fist, coin, ticket, medal1..3, medalOff, los objetos
    equipables (leftovers, choiceband...), las bolas del gacha (ball, ball2..4,
    ballLux), el clima (wsun, wrain...), etc. 12x12 salvo cursor (8x12).
  - type_<tipo>: emblema circular 16x16 del tipo con su glifo (G.Icons 'type:<t>').
  - fam_<kind>: insignia 7x7 de la familia de movimiento (projectile, melee, beam...).
    'move:<id>' = type_<m.type> + fam_<m.kind> dibujada encima en (9, 9).
"""
import math
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(os.path.dirname(HERE), 'game')
OUT_PNG = os.path.join(GAME, 'img', 'icons.png')
OUT_LUA = os.path.join(GAME, 'data', 'icons.lua')
MAX_TEX = 512
PAD = 1

K = '#1b1528'                           # contorno
FAM_OX, FAM_OY = 9, 9                   # dónde va la insignia sobre el emblema
FAM_BG, FAM_FG = '#2b3454', '#ffd23f'

TYPE_COLOR = {
    'normal': '#b0a99f', 'fire': '#ff7b3d', 'water': '#4b9bff', 'grass': '#5fcb6a',
    'electric': '#ffd33d', 'ice': '#7fe0e0', 'fighting': '#e0533d', 'poison': '#b45ec4',
    'ground': '#d6b25c', 'flying': '#9bb8ff', 'psychic': '#ff5f9e', 'bug': '#a3c43d',
    'rock': '#bfa96b', 'ghost': '#7a6bc4', 'dragon': '#6b58ff', 'dark': '#6b5c52',
    'steel': '#a8b8c4', 'fairy': '#ff9ed8',
}

MEDAL = ['.kkk....kkk.', '.krk....kqk.', '..krk..kqk..', '...krkkqk...', '....kkkk....', '...kmmmmk...',
         '..kmwmmmnk..', '.kmwmsmmmnk.', '.kmmsssmmnk.', '.kmmmsmmmnk.', '..kmmmmmnk..', '...kkkkkk...']

BALL_ROWS = ['....kkkk....', '..kkrrrrkk..', '.krwrrrrrrk.', '.krwrrrrrsk.', 'krrrrkkrrssk', 'kkkkkbbkkkkk',
             'kbbbkbbkbbbk', 'kbbbbkkbbbbk', '.kbbbbbbbbk.', '.kbbbbbbbbk.', '..kkbbbbkk..', '....kkkk....']

UI = {
    'gear': ({'g': '#c9d6ff', 'd': '#7f93c9'}, [
        '....kkkk....', '.kk.kggk.kk.', '.kgkkggkkgk.', '..kggggggk..', 'kkggkkkkggkk', 'kgggk..kgddk',
        'kgggk..kgddk', 'kkggkkkkddkk', '..kggddddk..', '.kgkkddkkdk.', '.kk.kddk.kk.', '....kkkk....']),
    'full': ({'w': '#f4f8ff'}, [
        'kkkkk..kkkkk', 'kwwwk..kwwwk', 'kwkk....kkwk', 'kwk......kwk', 'kkk......kkk', '............',
        '............', 'kkk......kkk', 'kwk......kwk', 'kwkk....kkwk', 'kwwwk..kwwwk', 'kkkkk..kkkkk']),
    'phone': ({'b': '#2c519f', 's': '#9fd8ff', 'w': '#e6f4ff'}, [
        '...kkkkkk...', '...kbbbbk...', '...kssssk...', '...kswssk...', '...kssssk...', '...kssssk...',
        '...kssssk...', '...kssssk...', '...kssssk...', '...kbbbbk...', '...kbwwbk...', '...kkkkkk...']),
    # Prohibido (Mejoras > Veto: movimiento bloqueado).
    'ban': ({'r': '#ff5f6d'}, [
        '...kkkkkk...', '..krrrrrrk..', '.krrkkkkrrk.', 'krrk..krrrrk', 'krk..krrkkrk', 'krk.krrk.krk',
        'krkkrrk..krk', 'krrrrk..krrk', '.krrkkkkrrk.', '..krrrrrrk..', '...kkkkkk...', '............']),
    'heart': ({'r': '#ff5f6d', 's': '#c23a4b', 'w': '#ffd3d8'}, [
        '............', '.kkk....kkk.', 'kwwrk..krrrk', 'kwrrrkkrrrsk', 'krrrrrrrrrsk', 'krrrrrrrrrsk',
        '.krrrrrrrsk.', '..krrrrrsk..', '...krrrsk...', '....krsk....', '.....kk.....', '............']),
    'fist': ({'r': '#ff5f6d', 's': '#c23a4b', 'w': '#ffd3d8', 'c': '#e8e8f0'}, [
        '............', '..kkkkkk....', '.krrrrrrk...', 'krwwrrrrrkk.', 'krwrrrrrrrrk', 'krrrrrrrkrsk',
        'krrrrrrrkrsk', '.krrrrrrskk.', '..kssssssk..', '..kcccccck..', '..kkkkkkkk..', '............']),
    'up': ({'g': '#5fe08a', 'd': '#2f9a52', 'w': '#c8ffd8'}, [
        '.....kk.....', '....kwgk....', '...kwgggk...', '..kwgggggk..', '.kwgggggggk.', 'kkkkggggkkkk',
        '...kggggk...', '...kggggk...', '...kggddk...', '...kgdddk...', '...kddddk...', '...kkkkkk...']),
    'boot': ({'b': '#4fb4ff', 'd': '#2a6fb0', 'w': '#e6f4ff', 'g': '#e8e8f0'}, [
        '............', '....kkkk....', '....kbbk....', '....kbbk....', '....kbbk....', '....kbbbkk..',
        '...kbwbbbbk.', '..kbbbbbbbbk', '..kdddddddbk', '..kgggggggk.', '...kkkkkkk..', '............']),
    'bond': ({'y': '#ffd23f', 'w': '#fff3b0', 'p': '#ff8ad8', 'q': '#ffd3f1'}, [
        '.kkkkk......', 'kwyyyyk.....', 'kykkkyk.....', 'kyk.kyk.....', 'kykkkyk.....', 'kyyyyykkkkk.',
        '.kkkkkqppppk', '.....kpkkkpk', '.....kpk.kpk', '.....kpkkkpk', '.....kpppppk', '......kkkkk.']),
    'clock': ({'w': '#f4f4ff', 'y': '#ffd23f', 'o': '#c9c9e0'}, [
        '....kkkk....', '..kkyyyykk..', '.kyywwwwyyk.', '.kywwwkwwyk.', 'kywwwwkwwwyk', 'kywwwwkwwwyk',
        'kywwwwkkkwyk', 'kywwwwwwwwyk', '.kywwwwwwyk.', '.kyyowwwyyk.', '..kkyyyykk..', '....kkkk....']),
    'shield': ({'s': '#9fb1c9', 'd': '#5d6f8c', 'w': '#e6eef8', 'r': '#4fb4ff'}, [
        '............', '.kkkkkkkkkk.', '.kwwsssssdk.', '.kwssrrssdk.', '.kwssrrssdk.', '.kssrrrrsdk.',
        '.kssrrrrsdk.', '..kssrrsdk..', '..kssssddk..', '...ksssdk...', '....kddk....', '.....kk.....']),
    'sprout': ({'g': '#5fe08a', 'd': '#2f9a52', 'b': '#8a5a2b'}, [
        '............', '..kkk..kkk..', '.kgggk.kgggk', '.kggggkgggdk', '..kdggkggdk.', '...kkdgdkk..',
        '.....kgk....', '.....kgk....', '...kkkdkkk..', '..kbbbbbbbk.', '..kbbbbbbbk.', '...kkkkkkk..']),
    'magnet': ({'r': '#ff5f6d', 's': '#c23a4b', 'w': '#e8e8f0'}, [
        '............', '..kkkkkkkk..', '.krrrrrrrrk.', 'krrsskkssrrk', 'krrk....krrk', 'krrk....krrk',
        'krrk....krrk', 'kwwk....kwwk', 'kwwk....kwwk', 'kkkk....kkkk', '............', '............']),
    'book': ({'c': '#4fb4ff', 'd': '#2a6fb0', 'p': '#f4f4ff', 'y': '#ffd23f'}, [
        '............', '.kkkkkkkkkk.', '.kcccccccck.', '.kcyyyyyyck.', '.kcccccccck.', '.kccyyyyyck.',
        '.kcccccccck.', '.kcccccccck.', '.kddddddddk.', '.kppppppppk.', '.kkkkkkkkkk.', '............']),
    'coin': ({'y': '#ffd23f', 'o': '#c08a10', 'w': '#fff4b0'}, [
        '....kkkk....', '..kkyyyykk..', '.kyywwyyyyk.', '.kywyyyyyok.', 'kyyyyooyyyok', 'kywyoyyoyyok',
        'kyyyoyyoyyok', 'kyyyyooyyyok', '.kyyyyyyyok.', '.kooyyyyook.', '..kkooookk..', '....kkkk....']),
    'cards': ({'a': '#ffd23f', 'b': '#4fb4ff', 'w': '#e6f4ff'}, [
        '............', '.kkkkkk.....', '.kaaaaakkkk.', '.kaaaakbbbbk', '.kaaaakbwwbk', '.kaaaakbwwbk',
        '.kaaaakbbbbk', '.kaaaakbwwbk', '.kkkkkkbwwbk', '......kbbbbk', '......kkkkkk', '............']),
    'berry': ({'r': '#ff7a9e', 's': '#c23a6b', 'w': '#ffd3e0', 'g': '#5fe08a', 'd': '#2f9a52'}, [
        '............', '.....kkk....', '....kgggk...', '..kkkgdkkk..', '.krrrkkrrrk.', 'krwwrrrrrrsk',
        'krwrrrrrrrsk', 'krrrrrrrrrsk', 'krrrrrrrrssk', '.krrrrrrssk.', '..kkssssskk.', '....kkkkk...']),
    'bomb': ({'b': '#3a3a4a', 'w': '#8a8aa0', 'f': '#ffd23f', 'r': '#ff7b3d'}, [
        '........r...', '.......rfr..', '......kfr...', '.....kfk....', '...kkkkkk...', '..kbbbbbbk..',
        '.kbwwbbbbbk.', '.kbwbbbbbbk.', '.kbbbbbbbbk.', '.kbbbbbbbbk.', '..kbbbbbbk..', '...kkkkkk...']),
    'star': ({'y': '#ffd23f', 'o': '#c08a10', 'w': '#fff4b0'}, [
        '.....kk.....', '.....kk.....', '....kwyk....', '....kyyk....', 'kkkkwyyykkkk', 'kwyyyyyyyyok',
        '.kyyyyyyyok.', '..kyyyyyyk..', '..kyyyoyyk..', '.kyok..koyk.', '.kok....kok.', '.kk......kk.']),
    'shiny': ({'y': '#ff4d5e', 'w': '#ffd0d6', 'o': '#b8283a', 'x': '#fff6b0'}, [
        '.....kk...x.', '.....kk..xxx', '....kwyk..x.', '....kyyk....', 'kkkkwyyykkkk', 'kwyyyyyyyyok',
        '.kyyyyyyyok.', '..kyyyyyyk..', '..kyyyoyyk..', '.kyok..koyk.', '.kok....kok.', '.kk......kk.']),
    'crown': ({'y': '#ffd23f', 'o': '#c08a10', 'r': '#ff5f6d'}, [
        '............', '............', 'k....k....k.', 'kk..kyk..kk.', 'kyk.kyk.kyk.', 'kyykyyykyyk.',
        'kyyyyyyyyyk.', 'kyyryyyryyk.', 'kyyyyyyyyyk.', 'koooooooook.', 'kkkkkkkkkkk.', '............']),
    'user': ({'u': '#b9cbf0', 'd': '#7f93c0'}, [
        '............', '....kkkk....', '...kuuuuk...', '...kuuuuk...', '...kuuuuk...', '....kuuk....',
        '..kkkuukkk..', '.kuuuuuuuuk.', '.kuuuuuuuuk.', '.kdduuuuddk.', '.kkkkkkkkkk.', '............']),
    'cursor': ({'y': '#ffd23f'}, [
        'k.......', 'kk......', 'kyk.....', 'kyyk....', 'kyyyk...', 'kyyyyk..',
        'kyyyk...', 'kyyk....', 'kyk.....', 'kk......', 'k.......', '........']),
    'sound': ({'w': '#e8eef8'}, [
        '............', '.....kk.....', '....kwk..k..', '...kwwk...k.', 'kkkwwwk.k..k', 'kwwwwwk..k.k',
        'kwwwwwk..k.k', 'kkkwwwk.k..k', '...kwwk...k.', '....kwk..k..', '.....kk.....', '............']),
    'mute': ({'w': '#e8eef8', 'r': '#ff5f6d'}, [
        '............', '.....kk.....', '....kwk.....', '...kwwk.....', 'kkkwwwk.r..r', 'kwwwwwk..rr.',
        'kwwwwwk..rr.', 'kkkwwwk.r..r', '...kwwk.....', '....kwk.....', '.....kk.....', '............']),
    'ticket': ({'y': '#ffd23f', 'd': '#c08a10', 'w': '#fff3b0', 'r': '#ff5f6d'}, [
        '............', '............', 'kkkkkkkkkkkk', 'kwyyydyyyyyk', 'kyyyyyyrryyk', '.kyyydyrryk.',
        '.kyyyyyrryk.', 'kyyyydyyyyyk', 'kddddddddddk', 'kkkkkkkkkkkk', '............', '............']),
    'ticket10': ({'p': '#c47bff', 'q': '#8a3fd0', 'w': '#f0d8ff', 'y': '#ffd23f'}, [
        '............', '............', 'kkkkkkkkkkkk', 'kwpppqppyypk', 'kppppqpyyypk', '.kpppqpyyyk.',
        '.kpppqppyyk.', 'kppppqpppppk', 'kqqqqqqqqqqk', 'kkkkkkkkkkkk', '............', '............']),
    'wsun': ({'y': '#ffd23f', 'o': '#ff9a3d'}, [
        '.....yy.....', '..y..yy..y..', '...y....y...', '....kkkk....', 'yy.kyyyyk.yy', 'yy.kyyoyk.yy',
        '...kyooyk...', '....kkkk....', '...y....y...', '..y..yy..y..', '.....yy.....', '............']),
    'wrain': ({'w': '#e8eef8', 'g': '#9fb1c9', 'b': '#4fb4ff'}, [
        '............', '...kkkk.....', '..kwwwwkkk..', '.kwwwwwwwwk.', 'kwwwwwwwwwgk', 'kggggggggggk',
        '.kkkkkkkkkk.', '..b...b...b.', '.b...b...b..', '..b...b...b.', '.b...b...b..', '............']),
    'wsand': ({'s': '#e0bf73', 'd': '#9a7a3a'}, [
        '............', '..ssssss....', '........ss..', 'ssssssss..s.', '.........s..', '..dddddd....',
        '........dd..', 'dddddd....d.', '.........d..', '...sssss....', '............', '............']),
    'wsnow': ({'w': '#ffffff', 'c': '#9fe0ff'}, [
        '.....w......', '...w.w.w....', '....www.....', '.w..cwc..w..', '..w.cwc.w...', 'wwwwwwwwwww.',
        '..w.cwc.w...', '.w..cwc..w..', '....www.....', '...w.w.w....', '.....w......', '............']),
    'wfog': ({'g': '#c9cfdc', 'd': '#8f98ab'}, [
        '............', '............', '..gggggg....', '.g......gg..', '............', '....gggggg..',
        '..dd......d.', '............', '.ggggggg....', 'g.......gg..', '............', '............']),
    'ball2': ({'r': '#3d7bff', 's': '#2a56b8', 'w': '#cfe0ff', 'b': '#f4f4f4'}, BALL_ROWS),
    'ball3': ({'r': '#3a3a46', 's': '#1d1d26', 'w': '#ffd23f', 'b': '#f4f4f4'}, BALL_ROWS),
    'ball4': ({'r': '#8a3fd0', 's': '#5e2a96', 'w': '#ff8ad8', 'b': '#f4f4f4'}, BALL_ROWS),
    'ballLux': ({'r': '#30303a', 's': '#18181e', 'w': '#ff5f6d', 'b': '#ffd23f'}, BALL_ROWS),
    # ---------- objetos equipables (data/items.js) ----------
    'leftovers': ({'r': '#ff5f6d', 'd': '#b8283a', 'w': '#ffd8d8', 'g': '#5fe08a'}, [
        '.....kgk....', '....kggk....', '..kkkkkkkk..', '.krwrrrrrrk.', 'krwrrrrrrrdk', 'krrrrrrrrrdk',
        'krrrrrrrrrdk', 'krrrrrrrrddk', '.krrrrrrrdk.', '..kdrrrrdk..', '...kkkkkk...', '............']),
    'choiceband': ({'p': '#ff8ad8', 'q': '#c04a98', 'w': '#ffe0f4'}, [
        '............', '............', '...kkkkkk...', '.kkppwwppkk.', 'kpp......ppk', 'kq........qk',
        'kq........qk', 'kpp......ppk', '.kkppppppkk.', '...kkkkkk...', '............', '............']),
    'quickclaw': ({'y': '#ffd23f', 'o': '#c08a10', 'b': '#8a5a2b'}, [
        '........kk..', '.......kyk..', '......kyok..', '..kk..kyok..', '.kyk.kyok...', '.kyokyok....',
        '.kyyyok..kk.', '.kbbbbk.kyk.', 'kbbbbbbkyok.', 'kbbbbbbyok..', '.kkkkkkkk...', '............']),
    'focussash': ({'o': '#ff9a3d', 'd': '#c0601a', 'w': '#ffd0a0'}, [
        '.kk.........', 'kook........', 'kwook.......', '.kwook......', '..kwook.....', '...kwook....',
        '....kwook...', '.....kwook..', '......kwook.', '.......koodk', '........kddk', '.........kk.']),
    'shellbell': ({'p': '#ff9ec4', 'q': '#c05a88', 'w': '#ffe0ee', 'y': '#ffd23f'}, [
        '.....kk.....', '....kyyk....', '...kkkkkk...', '..kwppppqk..', '.kwppppppqk.', '.kpppppppqk.',
        'kpppppppppqk', 'kppqpqpqppqk', 'kkkkkkkkkkkk', '....kyyk....', '.....kk.....', '............']),
    'amuletcoin': ({'y': '#ffd23f', 'o': '#c08a10', 'w': '#fff3b0', 'r': '#ff5f6d'}, [
        '..kk....kk..', '..krk..krk..', '...krkkrk...', '....kkkk....', '...kyyyyk...', '..kywyyyok..',
        '..kyyooyok..', '..kyyooyok..', '..kyyyyyok..', '...kooook...', '....kkkk....', '............']),
    'luckyegg': ({'w': '#fffaf0', 's': '#e0d6c8', 'r': '#ff5f6d'}, [
        '....kkkk....', '...kwwwwk...', '..kwwrwwwk..', '..kwwwwwwk..', '.kwrwwwwrwk.', '.kwwwwwwwwk.',
        '.kwwwrwwwsk.', '.kwwwwwwwsk.', '.kwrwwwwssk.', '..kwwwwssk..', '...kkkkkk...', '............']),
    'lifeorb': ({'p': '#c04a98', 'd': '#7a1f5a', 'w': '#ffb0e0', 'r': '#ff3048'}, [
        '....kkkk....', '..kkpppdkk..', '.kwwpppppdk.', '.kwpprrpppk.', 'kppprrrrppdk', 'kpprrrrrrpdk',
        'kpprrrrrrpdk', 'kppprrrrppdk', '.kpppprppdk.', '.kdpppppddk.', '..kkddddkk..', '....kkkk....']),
    'choicescarf': ({'b': '#4fb4ff', 'd': '#2a6fb0', 'w': '#cfe8ff'}, [
        '............', '............', 'kkkkkkkkkk..', 'kwbbbbbbbbk.', 'kbbbbbbbbdk.', 'kkkkkkkbbdk.',
        '......kbbdk.', '......kbbdk.', '.....kbbbdk.', '.....kbbddk.', '.....kkkkkk.', '............']),
    'rockyhelmet': ({'g': '#9aa6b5', 'd': '#5d6773', 'w': '#e0e6ee'}, [
        '............', '.k...k...k..', 'kgk.kgk.kgk.', '.kkkkkkkkk..', 'kwggggggggk.', 'kwgggggggdk.',
        'kggggggggdk.', 'kgggkkkkgdk.', 'kggk....kdk.', 'kkk......kk.', '............', '............']),
    'assaultvest': ({'g': '#4f8a3a', 'd': '#2f5a22', 'y': '#ffd23f'}, [
        '............', '.kkk....kkk.', 'kggk....kggk', 'kgggkkkkgggk', 'kgggyggygggk', 'kgggggggggdk',
        'kggyggggygdk', 'kgggggggggdk', 'kgggggggggdk', 'kddddddddddk', 'kkkkkkkkkkkk', '............']),
    # ---------- medallas de logros (bronce, plata, oro) ----------
    'medal1': ({'r': '#ff5f6d', 'q': '#b8283a', 'm': '#d08a4a', 'n': '#8a5226', 'w': '#ffd0a0', 's': '#ffe8c8'}, MEDAL),
    'medal2': ({'r': '#4fb4ff', 'q': '#2a6fb0', 'm': '#c9d2de', 'n': '#7d8899', 'w': '#ffffff', 's': '#ffffff'}, MEDAL),
    'medal3': ({'r': '#c47bff', 'q': '#7a3fb0', 'm': '#ffd23f', 'n': '#c08a10', 'w': '#fff3b0', 's': '#fffbe0'}, MEDAL),
    'medalOff': ({'r': '#3a4870', 'q': '#2a3458', 'm': '#3a4870', 'n': '#2a3458', 'w': '#4a5a88', 's': '#4a5a88'}, MEDAL),
    'trophy': ({'y': '#ffd23f', 'd': '#c08a10', 'w': '#fff3b0'}, [
        '............', '..kkkkkkkk..', 'kkkwyyyydkkk', 'k.kwyyyydk.k', 'k.kwyyyydk.k', '.kkwyyyydkk.',
        '...kyyyyk...', '....kyyk....', '....kyyk....', '...kddddk...', '..kyyyyyyk..', '..kkkkkkkk..']),
    'friends': ({'b': '#4fb4ff', 'd': '#2a6fb0', 'g': '#5fe08a', 'h': '#2f9a52'}, [
        '............', '..kkk..kkk..', '.kbbbkkgggk.', '.kbbbkkgggk.', '..kkk..kkk..', '............',
        '.kkkkkkkkkk.', 'kbbbbkkggggk', 'kbbbbkkggggk', 'kddddkkhhhhk', 'kkkkkkkkkkkk', '............']),
    'ball': ({'r': '#ff4d4d', 'w': '#f4f4f4', 's': '#c23a3a'}, [
        '....kkkk....', '..kkrrrrkk..', '.krwrrrrrrk.', '.krwrrrrrsk.', 'krrrrkkrrssk', 'kkkkkwwkkkkk',
        'kwwwkwwkwwwk', 'kwwwwkkwwwwk', '.kwwwwwwwwk.', '.kwwwwwwwwk.', '..kkwwwwkk..', '....kkkk....']),
}
UI['starDim'] = ({'y': '#3a4870', 'o': '#2a3458', 'w': '#4a5a88'}, UI['star'][1])

TYPE_GLYPH = {
    'normal':   ['..####..', '.#....#.', '#......#', '#..##..#', '#..##..#', '#......#', '.#....#.', '..####..'],
    'fire':     ['...#....', '...##...', '..###.#.', '.#####..', '.######.', '##.####.', '##..###.', '.######.'],
    'water':    ['...##...', '...##...', '..####..', '.######.', '.##.###.', '.#.####.', '.######.', '..####..'],
    'grass':    ['.....###', '...#####', '..######', '.####.##', '.###.###', '.##.####', '.#.####.', '#.......'],
    'electric': ['....###.', '...###..', '..###...', '.######.', '...###..', '..###...', '.##.....', '#.......'],
    'psychic':  ['.######.', '#......#', '#.####.#', '#.#..#.#', '#.#.##.#', '#.#....#', '#.######', '#.......'],
    'ice':      ['...#....', '.#.#.#..', '..###...', '#######.', '..###...', '.#.#.#..', '...#....', '........'],
    'fighting': ['.######.', '########', '########', '#.#.#.##', '########', '.#######', '..#####.', '..####..'],
    'poison':   ['.....##.', '....####', '.....##.', '.###....', '#####...', '#####.##', '.###.###', '.....##.'],
    'ground':   ['........', '...##...', '..####..', '.##..##.', '.######.', '##.##.##', '########', '........'],
    'flying':   ['#.......', '##......', '###.....', '####....', '######..', '########', '.#######', '...####.'],
    'bug':      ['.#....#.', '..#..#..', '..####..', '.##.###.', '########', '###.####', '.######.', '..####..'],
    'rock':     ['...###..', '..#####.', '.###.###', '######.#', '##.#####', '#######.', '.#####..', '........'],
    'ghost':    ['..####..', '.######.', '##.##.##', '##.##.##', '########', '########', '########', '#.#..#.#'],
    'dragon':   ['#.......', '##....#.', '.##..##.', '.######.', '..####..', '.######.', '##.##.##', '#..##..#'],
    'dark':     ['..####..', '.###....', '###.....', '###.....', '###.....', '###.....', '.###....', '..####..'],
    'steel':    ['..####..', '.######.', '###..###', '##....##', '##....##', '###..###', '.######.', '..####..'],
    'fairy':    ['...#....', '...#....', '..###...', '#######.', '..###...', '..#.#...', '.#...#..', '........'],
}

KIND_GLYPH = {
    'projectile': ['..#..', '...#.', '#####', '...#.', '..#..'],
    'melee':      ['....#', '...#.', '..#..', '.#...', '#....'],
    'beam':       ['.....', '#####', '.....', '#####', '.....'],
    'orbit':      ['.###.', '#...#', '#...#', '#...#', '.###.'],
    'nova':       ['#.#.#', '.###.', '#####', '.###.', '#.#.#'],
    'aura':       ['.###.', '#...#', '#.#.#', '#...#', '.###.'],
    'buff':       ['..#..', '.###.', '#####', '..#..', '..#..'],
    'boomerang':  ['####.', '#....', '#....', '#....', '#....'],
    'chain':      ['##...', '..#..', '...##', '..#..', '##...'],
    'mine':       ['..#..', '.###.', '##.##', '.###.', '..#..'],
    'meteor':     ['....#', '...#.', '.##..', '####.', '.##..'],
    'turret':     ['.###.', '.#.#.', '.###.', '..#..', '#####'],
    'dash':       ['#.#..', '.#.#.', '..#.#', '.#.#.', '#.#..'],
    'trail':      ['#....', '.....', '..#..', '.....', '....#'],
    'cone':       ['....#', '..###', '#####', '..###', '....#'],
}

RARITY_BALL = {1: 'ball', 2: 'ball2', 3: 'ball3', 4: 'ballLux', 5: 'ball4'}


# ---------------- render ----------------

def rgb(hexs):
    n = int(hexs[1:], 16)
    return ((n >> 16) & 255, (n >> 8) & 255, n & 255, 255)


def shade(hexs, k):
    n = int(hexs[1:], 16)
    f = lambda c: max(0, min(255, int(round(c * k))))   # noqa: E731
    return '#%02x%02x%02x' % (f((n >> 16) & 255), f((n >> 8) & 255), f(n & 255))


def from_rows(pal, rows):
    h = len(rows)
    w = max(len(r) for r in rows)
    pal = dict(pal)
    pal['k'] = K
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in '. ' or ch not in pal:
                continue
            px[x, y] = rgb(pal[ch])
    return img


def emblem(t):
    S = 16
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    px = img.load()
    col = TYPE_COLOR.get(t, '#b0a99f')
    dark, lite = shade(col, 0.55), shade(col, 1.3)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - 7.5, y - 7.5)
            if d > 7.6:
                continue
            f = col
            if d > 6.6:
                f = K
            elif (x - 7.5) + (y - 7.5) > 6:
                f = dark
            elif (x - 7.5) + (y - 7.5) < -6.5:
                f = lite
            px[x, y] = rgb(f)
    g = TYPE_GLYPH.get(t, TYPE_GLYPH['normal'])
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch == '#':
                px[x + 5, y + 5] = rgb(dark)
    for y, row in enumerate(g):
        for x, ch in enumerate(row):
            if ch == '#':
                px[x + 4, y + 4] = rgb('#ffffff')
    return img


def fam_badge(kind):
    img = Image.new('RGBA', (7, 7), rgb(K))
    px = img.load()
    for y in range(1, 6):
        for x in range(1, 6):
            px[x, y] = rgb(FAM_BG)
    for y, row in enumerate(KIND_GLYPH[kind]):
        for x, ch in enumerate(row):
            if ch == '#':
                px[x + 1, y + 1] = rgb(FAM_FG)
    return img


def pack(items):
    items = sorted(items, key=lambda it: (-it[2], -it[1], it[0]))
    area = sum(w * h for _, w, h in items)
    size = 16
    while size * size < area:
        size *= 2
    while size <= MAX_TEX:
        for W, Hh in ((size, size // 2), (size // 2, size), (size, size)):
            pos, x, y, shelf = {}, 0, 0, 0
            ok = True
            for key, w, h in items:
                if x + w > W:
                    x, y, shelf = 0, y + shelf, 0
                if y + h > Hh:
                    ok = False
                    break
                pos[key] = (x, y)
                x += w
                shelf = max(shelf, h)
            if ok:
                return W, Hh, pos
        size *= 2
    raise SystemExit('el atlas de iconos no cabe en %dx%d' % (MAX_TEX, MAX_TEX))


def lua_key(k):
    return k if k.isidentifier() else '["%s"]' % k


def main():
    icons = {}
    for name, (pal, rows) in UI.items():
        icons[name] = from_rows(pal, rows)
    for t in TYPE_COLOR:
        icons['type_' + t] = emblem(t)
    for kind in KIND_GLYPH:
        icons['fam_' + kind] = fam_badge(kind)

    items = [(k, im.width + PAD, im.height + PAD) for k, im in icons.items()]
    W, Hh, pos = pack(items)
    atlas = Image.new('RGBA', (W, Hh), (0, 0, 0, 0))
    for k, im in icons.items():
        atlas.paste(im, pos[k])
    os.makedirs(os.path.dirname(OUT_PNG), exist_ok=True)
    os.makedirs(os.path.dirname(OUT_LUA), exist_ok=True)
    atlas.save(OUT_PNG, optimize=True)

    L = []
    L.append('-- GENERADO por tools/gen_icons.py a partir de js/ui/icons.js. NO EDITAR A MANO.')
    L.append('-- Atlas: img/icons.png (%dx%d). quads[nombre] = {x, y, w, h} a tamaño nativo.' % (W, Hh))
    L.append('-- Nombres = los de G.Icons.draw/html del JS (coin, ticket, medal1, leftovers, ball2...).')
    L.append('--   type_<tipo>  = emblema 16x16 ("type:<tipo>" en la web)')
    L.append('--   fam_<kind>   = insignia 7x7 de la familia del movimiento')
    L.append('--   "move:<id>"  = type_<m.type> y encima fam_<m.kind> en (fam.ox, fam.oy) del emblema.')
    L.append('-- Un nombre desconocido cae en "star" (como en la web). Dibujar siempre a múltiplo')
    L.append('-- entero del tamaño nativo (snap): size = w * max(1, round(size / w)).')
    L.append('-- rarityBall[rareza] = icono de la Poké Ball de esa rareza (G.Icons.RARITY_BALL).')
    L.append('-- twinkle: colores del centelleo de shiny (G.Icons.twinkle, que se dibuja a píxeles).')
    L.append('return {')
    L.append('  image = "img/icons.png", width = %d, height = %d,' % (W, Hh))
    L.append('  fam = { ox = %d, oy = %d },' % (FAM_OX, FAM_OY))
    L.append('  fallback = "star",')
    L.append('  rarityBall = { [1] = "ball", [2] = "ball2", [3] = "ball3", [4] = "ballLux", [5] = "ball4" },')
    L.append('  twinkle = { core = "#ffffff", arm = "#fff3a8", tip = "#9ae6ff" },')
    L.append('  quads = {')
    for k in sorted(icons):
        im = icons[k]
        x, y = pos[k]
        L.append('    %s = {%d, %d, %d, %d},' % (lua_key(k), x, y, im.width, im.height))
    L.append('  },')
    L.append('}')
    with open(OUT_LUA, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')

    print('icons: %d iconos (%d ui + %d tipos + %d familias), atlas %dx%d -> %s'
          % (len(icons), len(UI), len(TYPE_COLOR), len(KIND_GLYPH), W, Hh, OUT_PNG))
    print('       %s' % OUT_LUA)


if __name__ == '__main__':
    main()
