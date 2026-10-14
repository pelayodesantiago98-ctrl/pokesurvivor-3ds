# Cambios

Errores arreglados y mejoras de cada versión del port a 3DS. Todo lo de esta lista se
encontró y se comprobó en una **New 3DS real** (rastro de depuración en la SD), no sólo
en el PC.

## v0.3.0

### Errores arreglados
- **El juego se cerraba solo a los pocos minutos de partida (sin mensaje de error).**
  Causa: los efectos de sonido. LÖVE Potion suelta desde otro hilo los canales de audio
  que terminan, sin proteger bien `play`/`stop`/`clone` del mismo sonido; con cientos
  de golpes por minuto acababan chocando. Se encontró desactivando por partes las
  novedades desde un fichero de opciones en la SD (`pokesurvivor-flags.txt`). Ahora, en
  la consola, cada efecto tiene una sola copia, nunca se corta uno que está sonando y
  suenan como mucho 6 a la vez.
- **La pantalla de abajo parpadeaba y se veía en la de arriba.** Pintar el HUD en una
  imagen aparte (`Canvas`) funciona en el PC pero no en la consola. En la 3DS ya no se
  usa: las partes fijas van en imágenes ya pintadas.
- **El Pokémon se movía solo hacia un lado.** Se perdía el aviso de soltar la cruceta y
  el juego creía que seguía pulsada. Ahora en la consola se consulta el estado real del
  mando en cada fotograma (también para los demás botones), y el *circle pad* necesita
  algo más de recorrido.
- **La partida se paraba con un error tras explorar mucho el mapa** (más de 120 trozos
  generados): `dropBatch` usaba una variable antes de declararla.
- **Tirones al subir de nivel y al cambiar de pantalla:** cada cambio de pantalla
  escribía en la SD (~20 ms). Ahora el rastro se guarda en memoria y se escribe junto.
- **Tirones de 130-350 ms al moverse por el mapa** (y 1,7 s al empezar la partida):
  generar un trozo nuevo del mapa cuesta ~70-100 ms en la consola y lo pedían de golpe
  consultas lejanas (colisiones de enemigos, la rejilla de colisión de los árboles
  vecinos, la lista de objetos visibles). Ahora esas consultas no generan nada; los
  trozos se generan por adelantado, en la dirección en que se mueve la cámara y con el
  tiempo que sobra de cada fotograma. Al empezar sólo se generan los 4 de la vista. El
  mapa sale idéntico (misma semilla, mismos trozos).
- **La Pokédex tardaba en enseñar los sprites** y daba tirones al pasar de página
  (cargaba la hoja de animaciones entera de cada Pokémon, hasta 9 en un fotograma).
  Ahora usa una hoja de miniaturas por generación: pasar de página no carga nada.

### Rendimiento (medido en la consola)
- Partida: de 15-26 fps a **30 fps estables**.
- Pantalla de abajo (HUD): de 21-27 ms a 3-4 ms por fotograma. Fondo, caja de vida y
  marcos de los botones de movimiento ya pintados en imágenes, y cada texto del HUD
  dibujado de una vez con letras ya coloreadas.
- Menús fluidos: textos agrupados, botones e iconos ya pintados, menos cargas al entrar.
- Sombras, auras y burbujas de los enemigos con una textura (4 vértices en vez de 20-30).
- Generación del mapa ~3 veces más barata y por adelantado; colisiones más rápidas.
- Sonidos cargados en los menús, no durante la partida; arranque más rápido.

### Cambios
- Pokédex: abajo sólo los sprites, en casillas con marco estilo Platino; arriba, toda la
  información del Pokémon.
- Quitada la barra de experiencia de la pantalla de arriba (ya está en la caja de abajo).

## v0.2.0

Primera versión que funciona en la New 3DS real.

### Errores arreglados
- **La consola se cerraba en el cuestionario y en los menús.** LÖVE Potion no comprueba
  el límite de vértices por fotograma (24.576 para las dos pantallas) y al pasarlo
  corrompía la memoria. Ahora se cuentan y se salta lo que no cabe. La fuente pixelada
  dibujaba cada píxel como un rectángulo (>14.000 por fotograma): ahora va en un atlas.
- **Se cerraba al guardar por primera vez.** `love.filesystem.write` falla en la
  consola: se guarda con `io.open` en `sdmc:/3ds/pokesurvivor-save.json`.
- **Se cerraba al abrir un baúl tras pasar por la Pokédex.** Los menús cargaban
  cientos de hojas de sprites sin soltarlas y se llenaba la memoria de texturas. Ahora
  hay un límite y se sueltan las menos usadas.
- **Se cerraba al arrancar** con `love.graphics.set3D(false)`: el ojo derecho del 3D
  simplemente no se dibuja.
- **El mapa de arriba salía descolocado.** `SpriteBatch:setDrawRange` de LÖVE Potion
  3.0.2 descoloca las baldosas con un inicio distinto de 0: el suelo va en bloques
  de 8x4 que se dibujan enteros.
- **Código que el PC aceptaba y la consola no** (`goto`, que no existe en Lua 5.1):
  `tools/check_lua51.py` compila todo con Lua 5.1.
- Los tickets se guardaban al cogerlos, escribiendo en la SD en plena partida: ahora al
  pausar o cada 60 s.
