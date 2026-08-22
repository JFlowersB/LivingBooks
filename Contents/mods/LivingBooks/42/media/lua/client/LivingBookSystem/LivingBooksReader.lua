--Contents\mods\LivingBooks\42\media\lua\client\LivingBookSystem\LivingBooksReader.lua
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "LivingBooksSystemShared/LivingBooksPaginator"


--Fix Crash On Search Numbers/Go to page --
local original_onKeyKeepPressed = ISHotbar.onKeyKeepPressed
local patched_onKeyKeepPressed = function(key)
    local hotbar = getPlayerHotbar(0)
    if hotbar and not hotbar.keyPressedMS then
        hotbar.keyPressedMS = getTimestampMs()
    end
    return original_onKeyKeepPressed(key)
end
----------------------------------------------------------------------
-- ¿Juego en pausa?
----------------------------------------------------------------------
local function isGamePaused()
    if getGameSpeed then
        return getGameSpeed() == 0
    end
    return false
end


BookReader = ISPanel:derive("BookReader")



----------------------------------------------------------------------
-- CONFIG DE MAQUETACIÓN
----------------------------------------------------------------------
local TOP_MARGIN = 80          -- donde empieza el texto en páginas de texto
local BOTTOM_MARGIN = 90       -- reservado para botones / número de página
local PARAGRAPH_GAP = 18       -- espacio extra tras cada párrafo
local LINE_HEIGHT_FALLBACK = 22
local LINE_SPACING = 6

local COLUMN_MARGIN = 70       -- margen exterior de cada página/columna
local GUTTER = 50              -- separación central (el "lomo" del libro)

local CLOSED_WIDTH_RATIO = 0.46 -- ancho del libro cerrado respecto al abierto

-- La textura de portada ha ganado "lienzo" al añadirle la sombra
-- (antes 778x1122, ahora 856x1234) aunque la ilustración en sí mide lo
-- mismo. Para que no se vea más pequeña, agrandamos el panel cerrado en
-- la misma proporción en que ha crecido el lienzo: así el espacio extra
-- se destina a la sombra en vez de encoger la portada.
local COVER_TEXTURE_OLD_WIDTH  = 778
local COVER_TEXTURE_NEW_WIDTH  = 856
local COVER_CANVAS_SCALE = COVER_TEXTURE_NEW_WIDTH / COVER_TEXTURE_OLD_WIDTH


local TRANSITION_STEP = 0.025   -- velocidad del fundido al pasar página
local TRANSITION_START = 0.45   -- opacidad inicial del flash

local PAGE_FRAME_MARGIN = 14    -- inset del marco cuando el libro está ABIERTO
local COVER_FRAME_MARGIN = 3    -- inset del marco cuando es la PORTADA (casi al borde)
local FRAME_THICKNESS = 5       -- nº de líneas anidadas que forman el marco (grosor visual)
local FRAME_COLOR = { r = 0.788, g = 0.729, b = 0.455, a = 0 } -- tono madera/dorado
local COVER_TEXT_COLOR = { r = 0.745, g = 0.686, b = 0.420 } -- #A2955B Color de la portada y autor

-- En vez de paginar todo el libro de golpe al abrirlo (pico de coste con
-- libros largos), se procesa en lotes de CHUNK_SIZE páginas-fuente. El
-- resto se construye sobre la marcha según el jugador avanza.
local CHUNK_SIZE = 20

-------------------------------------------------
-- FUENTES DEL LIBRO
-------------------------------------------------
local BOOK_TEXT_FONT = UIFont.Medium
local BOOK_TITLE_FONT = UIFont.Intro
local BOOK_AUTHOR_FONT = UIFont.Large

local COVER_TEXTURE_PATH = "media/ui/LivingBooksCoverTexture.png"
local PAGE_TEXTURE_PATH = "media/ui/LivingBooksPageTexture.png"

-- Icono de lupa personalizado para el botón de búsqueda.
local SEARCH_ICON_PATH = "media/ui/LivingBooksSearchIcon.png"
-- Dimensiones reales del icono (para no estirarlo/deformarlo al dibujarlo).
local SEARCH_ICON_NATIVE_WIDTH = 50
local SEARCH_ICON_NATIVE_HEIGHT = 36

-------------------------------------------------
-- SONIDOS DEL LIBRO
--
-- Estos nombres deben coincidir con los definidos en el/los fichero(s)
-- de sonido del mod (p.ej. media/sound/LivingBooksSounds.txt o el .fmod
-- correspondiente) que apuntan a los .ogg:
-------------------------------------------------
local SOUND_COGER = "LivingBooksGrabBook"                   -- abrir el lector (coger el libro para leerlo)
local SOUND_DEJAR = "LivingBooksPlaceBook"                   -- cerrar el lector (dejar el libro)
local SOUND_PASAR_PAGINA = "LivingBooksNextPage"       -- pasar página normal (sin cruzar la portada)
local SOUND_BUSCAR_PAGINA = "LivingBooksGoToPage"     -- saltar de página mediante el diálogo de búsqueda
local SOUND_TAPA_ABRIENDOSE = "LivingBooksOpenBook" -- portada -> primera página de contenido
local SOUND_TAPA_CERRANDOSE = "LivingBooksCloseBook" -- primera página de contenido -> portada

-------------------------------------------------
-- FUNDIDOS (fade in/out) Y ANIMACIÓN DE APERTURA/CIERRE
-------------------------------------------------
local OPEN_FADE_STEP = 0.080   -- velocidad del fundido de entrada al coger el libro
local CLOSE_FADE_STEP = 0.083  -- velocidad del fundido de salida al dejar el libro

-- Ya no se usa un velo de color opaco: el fundido de apertura/cierre se
-- consigue multiplicando color Y opacidad de todo lo que se dibuja
-- (textura, texto, marco, botones) por este factor, así se ve el propio
-- contenido apagarse hacia la nada en vez de un rectángulo tapando la
-- pantalla, y se evita el "lavado" de color que da mezclar solo por
-- alpha capas semitransparentes superpuestas (textura + marco dorado +
-- texto dorado).
local RESIZE_ANIM_STEP = 0.090            -- velocidad al ABRIR la tapa (portada -> libro abierto). NO TOCAR.
local CLOSE_COVER_RESIZE_ANIM_STEP = 0.180 -- velocidad al CERRAR la tapa (libro abierto -> portada). Más rápida.

----------------------------------------------------------------------

function BookReader:new(x, y, w, h, book, item)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self

    o.book = book
    o.item = item
    o.currentSpread = 1
    o.pages = {}    -- unidades de contenido (title / heading / text)
    o.spreads = {}  -- agrupación en pares de páginas para mostrar juntas

    -- Dimensiones "abiertas" (libro abierto, dos páginas) = las que llegan por parámetro
    o.openX = x
    o.openY = y
    o.openWidth = w
    o.openHeight = h

    -- Dimensiones "cerradas" (portada, una sola página, más estrecha)
    o.closedWidth = math.floor(w * CLOSED_WIDTH_RATIO * COVER_CANVAS_SCALE)
    o.closedHeight = math.floor(h * COVER_CANVAS_SCALE)

    -- Centro fijo en pantalla, para recolocar el panel al cambiar de tamaño
    local centerX = x + w / 2
    local centerY = y + h / 2
    o.closedX = math.floor(centerX - o.closedWidth / 2)
    o.closedY = math.floor(centerY - o.closedHeight / 2)

    o.transitionAlpha = 0
    o.flipBackground = false

    -- Fundido de apertura: el libro "aparece" desde la nada al cogerlo.
    -- Empieza a 1 (totalmente invisible) y baja a 0 (opacidad normal).
    o.openFadeAlpha = 1
    -- Fundido de cierre: se activa al dejar el libro y sube de 0 a 1
    -- (0 = opacidad normal, 1 = totalmente invisible) antes de quitar
    -- el panel de verdad (ver close()/finishClose()).
    o.closeFadeAlpha = 0
    o.isClosing = false

    -- Animación de redimensionado (portada estrecha <-> libro abierto)
    o.resizeAnim = nil

    -- Estado de construcción perezosa (lazy build)
    o.nextSourcePageIndex = 1
    o.buildCurrentLines = {}
    o.buildCurrentY = TOP_MARGIN
    o.builtAllPages = false

    -- Sesion "fantasma" de vigilancia de movimiento (ver LivingBooksInteraction.lua)
    o.readingSession = nil

    return o
end

function BookReader:getSpread()
    return self.spreads[self.currentSpread]
end

function BookReader:getSpreadCount()
    return #self.spreads
end

----------------------------------------------------------------------
-- Medidas de columna (SIEMPRE basadas en el ancho "abierto" fijo,
-- para que la paginación del texto no cambie nunca, aunque el panel
-- se muestre más pequeño en la portada)
----------------------------------------------------------------------
function BookReader:getColumnWidth()
    return (self.openWidth / 2) - (GUTTER / 2) - (COLUMN_MARGIN * 2)
end

function BookReader:getLeftColumnX()
    return COLUMN_MARGIN
end

function BookReader:getRightColumnX()
    return (self.openWidth / 2) + (GUTTER / 2) + COLUMN_MARGIN
end

function BookReader:getMargin()
    return COLUMN_MARGIN
end

-- Reutilizable, puedes ponerla junto a wrapText o antes de drawPageUnit
local function splitLines(text)
    local lines = {}
    if not text or text == "" then return lines end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

----------------------------------------------------------------------
-- CONSTRUCCIÓN DE PÁGINAS (PEREZOSA / POR LOTES)
----------------------------------------------------------------------
-- Inicializa el estado de construcción y crea solo la portada. El resto
-- se construye bajo demanda con ensureBuiltThroughSpread()/buildNextChunk().
function BookReader:initBuildState()
    self.pages = {}
    self.spreads = {}
    self.nextSourcePageIndex = 1
    self.buildCurrentLines = {}
    self.buildCurrentY = TOP_MARGIN
    self.builtAllPages = false

    ------------------------------------------------------------------
    -- Página de portada: título + autor/subtítulo (juntos)
    ------------------------------------------------------------------
    local title = self.book.filename and self.book.filename:gsub("%.pdf", "") or "Sin titulo"
    local subtitle = self.book.author or self.book.subtitle
    table.insert(self.pages, { type = "title", text = title, subtitle = subtitle })

    self:buildSpreads()
end

-- Vuelca las líneas acumuladas como una página de tipo "text".
function BookReader:flushBuildLines()
    if #self.buildCurrentLines > 0 then
        table.insert(self.pages, { type = "text", lines = self.buildCurrentLines })
        self.buildCurrentLines = {}
    end
    self.buildCurrentY = TOP_MARGIN
end

-- Procesa el siguiente lote de CHUNK_SIZE páginas-fuente (wrap + salto
-- de página) y lo añade a self.pages. Si no quedan páginas, marca
-- builtAllPages = true.
function BookReader:buildNextChunk()
    if self.builtAllPages then return end

    local font = BOOK_TEXT_FONT
    local lineHeight = getTextManager():getFontHeight(font) or LINE_HEIGHT_FALLBACK
    local textWidth = self:getColumnWidth()
    local maxY = self.openHeight - BOTTOM_MARGIN

    local srcPages = self.book.pages or {}
    local total = #srcPages

    if self.nextSourcePageIndex > total then
        self.builtAllPages = true
        self:flushBuildLines()
        self:buildSpreads()
        return
    end

    local endIndex = math.min(self.nextSourcePageIndex + CHUNK_SIZE - 1, total)

    -- Igual que en BookPaginator.buildPages: fuerza el heading a la
    -- izquierda insertando una página en blanco si le tocaría caer
    -- en la derecha.
    local function ensureHeadingLandsOnLeft()
        if #self.pages % 2 == 0 then
            table.insert(self.pages, { type = "blank" })
        end
    end

    for idx = self.nextSourcePageIndex, endIndex do
        local srcPage = srcPages[idx]

        for _, heading in ipairs(srcPage.headings or {}) do
            self:flushBuildLines()
            ensureHeadingLandsOnLeft()
            table.insert(self.pages, {
                type = "heading",
                text = heading.text,
                level = heading.level
            })
        end

        for _, paragraph in ipairs(srcPage.paragraphs or {}) do

            local wrapped = self:wrapText(paragraph, textWidth, font)

            for _, line in ipairs(wrapped) do

                if self.buildCurrentY + lineHeight + LINE_SPACING > maxY then
                    self:flushBuildLines()
                end

                -- Las líneas vacías ahora representan un \n original y se
                -- conservan para que ocupen altura al dibujarse.
                table.insert(self.buildCurrentLines, line)

                self.buildCurrentY = self.buildCurrentY + lineHeight + LINE_SPACING

            end

            self.buildCurrentY = self.buildCurrentY + PARAGRAPH_GAP

            if self.buildCurrentY > maxY then
                self:flushBuildLines()
            end

        end
    end

    self.nextSourcePageIndex = endIndex + 1

    if self.nextSourcePageIndex > total then
        self.builtAllPages = true
        self:flushBuildLines()
    end

    self:buildSpreads()
end

-- Construye lotes sucesivos hasta llegar al spread objetivo (o hasta
-- que no quede más libro por procesar).
function BookReader:ensureBuiltThroughSpread(targetSpreadIndex)
    while (not self.builtAllPages) and self:getSpreadCount() < targetSpreadIndex do
        self:buildNextChunk()
    end
end

----------------------------------------------------------------------
-- AGRUPACIÓN EN SPREADS (pares de páginas, como un libro abierto)
----------------------------------------------------------------------
-- Cada spread de CONTENIDO (single == false) guarda también el número
-- de PÁGINA REAL (sin contar la portada) de su columna izquierda y,
-- si existe, de su columna derecha: leftPageNum / rightPageNum. Así se
-- puede mostrar y buscar por número de página real ("1-2/xxx") en vez
-- de por índice de spread. self.pages[1] es siempre la portada, así
-- que la página real de self.pages[i] es (i - 1).
function BookReader:buildSpreads()
    local spreads = {}
    if #self.pages == 0 then
        self.spreads = spreads
        return
    end

    -- La portada va sola, centrada, como la tapa del libro cerrado
    table.insert(spreads, { single = true, left = self.pages[1] })

    -- El resto se empareja de dos en dos (izquierda/derecha)
    local i = 2
    while i <= #self.pages do
        local left = self.pages[i]
        local right = self.pages[i + 1] -- puede ser nil si es impar
        table.insert(spreads, {
            single = false,
            left = left,
            right = right,
            leftPageNum = i - 1,
            rightPageNum = right and i or nil,
        })
        i = i + 2
    end

    self.spreads = spreads
end

----------------------------------------------------------------------
-- GUARDADO DE LA ÚLTIMA PÁGINA LEÍDA (persistente entre sesiones)
----------------------------------------------------------------------
local function getBookSaveKey(book)
    return "LivingBook_" .. tostring(book and book.filename or "default")
end

-- Devuelve el spread guardado sin validar contra getSpreadCount() (en
-- carga perezosa aún no sabemos cuántos spreads tiene el libro). El
-- clamp se hace después de llamar a ensureBuiltThroughSpread().
function BookReader:loadSavedSpreadRaw()
    local data = self.item and self.item:getModData()
    if data and data.LivingBookSpread and data.LivingBookSpread >= 1 then
        return data.LivingBookSpread
    end
    return 1
end

function BookReader:saveCurrentSpread()
    local data = self.item and self.item:getModData()
    if data then
        data.LivingBookSpread = self.currentSpread
    end
end

----------------------------------------------------------------------
-- REDIMENSIONADO SEGÚN EL SPREAD ACTUAL (cerrado vs abierto)
----------------------------------------------------------------------
-- Si animate es true, el cambio de tamaño/posición se interpola suave-
-- mente (ver updateResizeAnimation) en vez de aplicarse de golpe. Se usa
-- animate=false/nil para la colocación inicial en initialise(), donde el
-- fundido de apertura ya se encarga de disimular el "salto".
function BookReader:applyLayoutForSpread(animate)
    local spread = self:getSpread()
    if not spread then return end

    -- Alternamos el volteo del fondo en páginas normales para que no
    -- se note que es siempre la misma textura repetida.
    self.flipBackground = (self.currentSpread % 2 == 0)

    local targetWidth, targetHeight, targetX, targetY
    if spread.single then
        targetWidth, targetHeight, targetX, targetY = self.closedWidth, self.closedHeight, self.closedX, self.closedY
    else
        targetWidth, targetHeight, targetX, targetY = self.openWidth, self.openHeight, self.openX, self.openY
    end

    if animate then
        -- Cerrar la tapa (ir hacia la portada) usa una velocidad propia,
        -- más rápida; abrir la tapa (salir de la portada) conserva la
        -- velocidad original sin tocar.
        local step = spread.single and CLOSE_COVER_RESIZE_ANIM_STEP or RESIZE_ANIM_STEP
        self:startResizeAnimation(targetWidth, targetHeight, targetX, targetY, step)
    else
        self.resizeAnim = nil
        self:setWidth(targetWidth)
        self:setHeight(targetHeight)
        self:setX(targetX)
        self:setY(targetY)
    end

    self:layoutControls()
end

-- Arranca una interpolación desde el tamaño/posición actual hasta el
-- tamaño/posición objetivo (efecto "la tapa se abre/cierra"). `step`
-- permite que abrir y cerrar la tapa tengan velocidades distintas.
function BookReader:startResizeAnimation(toWidth, toHeight, toX, toY, step)
    self.resizeAnim = {
        fromW = self.width, fromH = self.height, fromX = self.x, fromY = self.y,
        toW = toWidth, toH = toHeight, toX = toX, toY = toY,
        step = step or RESIZE_ANIM_STEP,
        t = 0
    }
end

-- Avanza un paso la animación de redimensionado activa, si la hay.
-- Debe llamarse una vez por frame desde prerender().
function BookReader:updateResizeAnimation()
    local anim = self.resizeAnim
    if not anim then return end

    anim.t = anim.t + (anim.step or RESIZE_ANIM_STEP)
    if anim.t >= 1 then anim.t = 1 end

    -- easeOutCubic: arranca rápido y frena suavemente al final, como
    -- una tapa que se abre y se va deteniendo.
    local e = 1 - ((1 - anim.t) ^ 3)

    local w = anim.fromW + (anim.toW - anim.fromW) * e
    local h = anim.fromH + (anim.toH - anim.fromH) * e
    local x = anim.fromX + (anim.toX - anim.fromX) * e
    local y = anim.fromY + (anim.toY - anim.fromY) * e

    self:setWidth(math.floor(w))
    self:setHeight(math.floor(h))
    self:setX(math.floor(x))
    self:setY(math.floor(y))
    self:layoutControls()

    if anim.t >= 1 then
        self.resizeAnim = nil
    end
end

----------------------------------------------------------------------
-- REPOSICIONAR BOTONES SEGÚN EL TAMAÑO ACTUAL DEL PANEL
----------------------------------------------------------------------
function BookReader:layoutControls()
    local spread = self:getSpread()
    local m = (spread and spread.single) and COVER_FRAME_MARGIN or PAGE_FRAME_MARGIN

    if self.closeButton then
        self.closeButton:setX(self.width - 50 - m)
        self.closeButton:setY(10 + m)
    end

    if self.searchButton then
        -- En la portada no tiene sentido buscar/ir a página: se oculta.
        self.searchButton:setVisible(not (spread and spread.single))
        self.searchButton:setX(10 + m)
        self.searchButton:setY(10 + m)
    end

    if self.leftButton then
        self.leftButton:setX(40 + m)
        self.leftButton:setY(self.height - 55 - m)
    end

    if self.rightButton then
        self.rightButton:setX(self.width - 90 - m)
        self.rightButton:setY(self.height - 55 - m)
    end
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
function BookReader:initialise()
    ISPanel.initialise(self)

    ISHotbar.onKeyKeepPressed = patched_onKeyKeepPressed

    self.backgroundTexture = getTexture(PAGE_TEXTURE_PATH)
    self.coverTexture = getTexture(COVER_TEXTURE_PATH)
    self.backgroundColor = { r = 0.12, g = 0.09, b = 0.05, a = 1 }
    self.borderColor = { r = 1, g = 1, b = 1, a = 0 }

    self.closeButton = ISButton:new(
        self.width - 50, 10, 35, 35,
        "X", self, self.close
    )
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self:addChild(self.closeButton)
    self.closeButton.backgroundColor.a = 0.35
    self.closeButton.backgroundColorMouseOver.a = 0.55

    -- Botón de búsqueda / ir a página (icono de lupa, sin texto ni tooltip)
    self.searchButton = ISButton:new(
        10, 10, 35, 35,
        "", self, self.onSearchButtonClick
    )
    self.searchButton:initialise()
    self.searchButton:instantiate()
    self:addChild(self.searchButton)
    self.searchButton.backgroundColor.a = 0.35
    self.searchButton.backgroundColorMouseOver.a = 0.55

    local searchIcon = getTexture(SEARCH_ICON_PATH)
    if searchIcon then
        local btn = self.searchButton
        local baseRender = btn.prerender
        -- Mantenemos la proporción real del icono (50x36) para que no
        -- salga deformado dentro del botón.
        local iconAspect = SEARCH_ICON_NATIVE_WIDTH / SEARCH_ICON_NATIVE_HEIGHT
        local iconHeight = 20
        local iconWidth = iconHeight * iconAspect
        function btn:prerender()
            baseRender(self)
            local ix = (self.width - iconWidth) / 2
            local iy = (self.height - iconHeight) / 2
            local a = self.fadeAlpha
            if a == nil then a = 1 end
            self:drawTextureScaled(searchIcon, ix, iy, iconWidth, iconHeight, a, a, a, a)
        end
    end

    self.leftButton = ISButton:new(
        40, self.height - 55, 50, 30,
        "<", self, self.previousPage
    )
    self.leftButton:initialise()
    self.leftButton:instantiate()
    self:addChild(self.leftButton)
    self.leftButton.backgroundColor.a = 0.35
    self.leftButton.backgroundColorMouseOver.a = 0.55

    self.rightButton = ISButton:new(
        self.width - 90, self.height - 55, 50, 30,
        ">", self, self.nextPage
    )
    self.rightButton:initialise()
    self.rightButton:instantiate()
    self:addChild(self.rightButton)
    self.rightButton.backgroundColor.a = 0.35
    self.rightButton.backgroundColorMouseOver.a = 0.55

    self:setWantKeyEvents(true)

    -- Si el libro ya fue precargado al arrancar la partida (ver
    -- LivingBooksPreloader.lua) y las dimensiones coinciden, reutilizamos esas
    -- páginas ya construidas: abrir el libro es instantáneo.
    local preloaded = _G.BookPreloader
    local entry = preloaded and preloaded.ready and preloaded.getEntry(self.book)
    local canUsePreload = entry
        and entry.openWidth == self.openWidth
        and entry.openHeight == self.openHeight

    if canUsePreload then
        self.pages = entry.pages
        self.spreads = entry.spreads
        self.builtAllPages = true
        self.nextSourcePageIndex = #(self.book.pages or {}) + 1
        self.buildCurrentLines = {}
        self.buildCurrentY = TOP_MARGIN
    else
        -- Sin precarga (o no coincide, p. ej. cambio de resolución a
        -- mitad de partida): construimos por lotes como siempre.
        self:initBuildState()
    end

    -- Recuperamos la última página leída (si la hay) y construimos solo
    -- los lotes necesarios para llegar hasta ahí.
    local savedSpread = self:loadSavedSpreadRaw()
    self:ensureBuiltThroughSpread(savedSpread)
    self.currentSpread = math.max(1, math.min(savedSpread, self:getSpreadCount()))

    self:applyLayoutForSpread()

    -- El jugador acaba de coger el libro para leerlo.
    self:playSound(SOUND_COGER)
end

----------------------------------------------------------------------
-- DIBUJADO DE UNA "UNIDAD" DE PÁGINA (título / heading / texto)
----------------------------------------------------------------------
-- fadeMult multiplica la opacidad de todo lo dibujado, para el efecto
-- de fundido de apertura/cierre (1 = opacidad normal, 0 = invisible).
function BookReader:drawPageUnit(unit, columnX, columnCenterX, fadeMult)
    if not unit then
        return -- página en blanco (spread impar)
    end
    if unit.type == "blank" then
        return -- página de relleno para forzar que un heading caiga a la izquierda
    end
    fadeMult = fadeMult or 1

    if unit.type == "title" then
        local font = BOOK_TITLE_FONT
        local lineHeight = getTextManager():getFontHeight(font) or LINE_HEIGHT_FALLBACK

        local titleLines = splitLines(unit.text or "")
        if #titleLines == 0 then titleLines = { "" } end

        local titleBlockHeight = (#titleLines - 1) * (lineHeight + LINE_SPACING)
        local y = self.height / 2 - 40 - titleBlockHeight / 2

        for _, line in ipairs(titleLines) do
            self:drawTextCentre(
                line, columnCenterX, y,
                COVER_TEXT_COLOR.r * fadeMult, COVER_TEXT_COLOR.g * fadeMult, COVER_TEXT_COLOR.b * fadeMult, fadeMult, font
            )
            y = y + lineHeight + LINE_SPACING
        end

        if unit.subtitle then
            self:drawTextCentre(
                unit.subtitle, columnCenterX, y + 10,
                COVER_TEXT_COLOR.r * fadeMult, COVER_TEXT_COLOR.g * fadeMult, COVER_TEXT_COLOR.b * fadeMult, fadeMult, BOOK_AUTHOR_FONT
            )
        end


    elseif unit.type == "heading" then

        local font = UIFont.Intro
        if unit.level == 3 then
            font = UIFont.MainMenu1
        end

        local lineHeight = getTextManager():getFontHeight(font) or LINE_HEIGHT_FALLBACK

        local lines = splitLines(unit.text or "")
        if #lines == 0 then
            lines = { "" }
        end

        local totalHeight = (#lines * lineHeight) + ((#lines - 1) * LINE_SPACING)

        local maxY = self.height - BOTTOM_MARGIN
        local availableHeight = maxY - TOP_MARGIN
        local y = TOP_MARGIN + math.max(0, (availableHeight - totalHeight) / 2)

        for _, line in ipairs(lines) do
            local textWidth = getTextManager():MeasureStringX(font, line)

            self:drawText(
                line,
                columnCenterX - textWidth / 2,
                y,
                0.18 * fadeMult,
                0.13 * fadeMult,
                0.08 * fadeMult,
                fadeMult,
                font
            )

            y = y + lineHeight + LINE_SPACING
        end

    elseif unit.type == "text" then
        local font = BOOK_TEXT_FONT
        local lineHeight = getTextManager():getFontHeight(font) or LINE_HEIGHT_FALLBACK

        -- Centrado vertical: calculamos la altura total del bloque de
        -- líneas y arrancamos a mitad del hueco disponible entre
        -- TOP_MARGIN y el límite inferior de la página.
        local maxY = self.height - BOTTOM_MARGIN
        local availableHeight = maxY - TOP_MARGIN
        local numLines = #unit.lines
        local totalHeight = 0
        if numLines > 0 then
            totalHeight = numLines * lineHeight + (numLines - 1) * LINE_SPACING
        end
        local y = TOP_MARGIN + math.max(0, (availableHeight - totalHeight) / 2)

        -- Centrado horizontal: cada línea se centra respecto al centro
        -- de la columna, en vez de alinearse a la izquierda.
        for _, line in ipairs(unit.lines) do
            if line ~= "" then
                self:drawTextCentre(
                    line,
                    columnCenterX,
                    y,
                    0.18 * fadeMult,
                    0.13 * fadeMult,
                    0.08 * fadeMult,
                    0.9 * fadeMult,
                    font
                )
            end

            y = y + lineHeight + LINE_SPACING
        end
    end
end

----------------------------------------------------------------------
-- NÚMERO DE PÁGINA (dibujado a mano, sin depender de ISLabel)
----------------------------------------------------------------------
-- Muestra el número de PÁGINA REAL (sin contar la portada), no el
-- índice de spread. Un spread con dos columnas muestra "L-R / total"
-- (p.ej. "1-2 / 40"); si solo tiene columna izquierda (última página,
-- número impar de páginas totales) muestra solo "L / total".
function BookReader:drawPageNumber(fadeMult)
    fadeMult = fadeMult or 1
    local spread = self:getSpread()
    if not spread or spread.single then
        return -- en la portada no mostramos número
    end

    -- Total de páginas reales construidas hasta ahora (sin contar la
    -- portada). Mientras el libro se sigue construyendo por lotes, es
    -- el total "construido hasta ahora", no el total final del libro.
    local totalPages = math.max(0, #self.pages - 1)

    local text
    if spread.rightPageNum then
        text = tostring(spread.leftPageNum) .. "-" .. tostring(spread.rightPageNum) .. " / " .. tostring(totalPages)
    else
        text = tostring(spread.leftPageNum) .. " / " .. tostring(totalPages)
    end

    local font = UIFont.NewSmall
    local textW = getTextManager():MeasureStringX(font, text)
    local textH = getTextManager():getFontHeight(font)

    local px = self.width / 2
    local py = self.height - PAGE_FRAME_MARGIN - textH - 6

    local padX, padY = 10, 4
    -- Placa oscura detrás para que el número se lea SIEMPRE,
    -- sea cual sea el color de la textura de fondo en ese punto.
    self:drawRect(
        px - textW / 2 - padX, py - padY,
        textW + padX * 2, textH + padY * 2,
        0.55 * fadeMult, 0.05 * fadeMult, 0.03 * fadeMult, 0.02 * fadeMult
    )
    self:drawRectBorder(
        px - textW / 2 - padX, py - padY,
        textW + padX * 2, textH + padY * 2,
        1 * fadeMult, FRAME_COLOR.r * fadeMult, FRAME_COLOR.g * fadeMult, FRAME_COLOR.b * fadeMult
    )

    self:drawTextCentre(text, px, py, 0.95 * fadeMult, 0.85 * fadeMult, 0.65 * fadeMult, fadeMult, font)
end

----------------------------------------------------------------------
-- MARCO DECORATIVO DEL LIBRO
----------------------------------------------------------------------
function BookReader:drawFrame(fadeMult)
    fadeMult = fadeMult or 1
    local spread = self:getSpread()
    local m = (spread and spread.single) and COVER_FRAME_MARGIN or PAGE_FRAME_MARGIN
    local c = FRAME_COLOR

    for i = 0, FRAME_THICKNESS - 1 do
        self:drawRectBorder(
            m + i, m + i,
            self.width - (m + i) * 2, self.height - (m + i) * 2,
            c.a * fadeMult, c.r * fadeMult, c.g * fadeMult, c.b * fadeMult
        )
    end
end

----------------------------------------------------------------------
-- Aplica fadeMult a los botones (fondo, hover y borde) para que se
-- desvanezcan junto con el resto del libro en vez de aparecer/
-- desaparecer de golpe.
----------------------------------------------------------------------
local function fadeButton(btn, fadeMult, baseAlpha, baseHoverAlpha)
    if not btn then return end
    if btn.backgroundColor then btn.backgroundColor.a = baseAlpha * fadeMult end
    if btn.backgroundColorMouseOver then btn.backgroundColorMouseOver.a = baseHoverAlpha * fadeMult end
    if btn.borderColor then btn.borderColor.a = fadeMult end
    if btn.textColor then btn.textColor.a = fadeMult end
    -- Multiplicador propio de fundido (independiente de backgroundColor.a,
    -- que en reposo es solo 0.35): lo usa p.ej. el icono de la lupa para
    -- dibujarse a opacidad plena cuando no hay transición en curso.
    btn.fadeAlpha = fadeMult
end

function BookReader:prerender()

    -- Mantiene al personaje en pose/animación de lectura mientras el
    -- libro esté abierto (si no se refresca cada frame, el juego la
    -- pisa con su estado por defecto).
    local readingPlayer = getPlayer()
    if readingPlayer then
        readingPlayer:setVariable("bookHoldType", "Big")
        readingPlayer:setVariable("PerformingAction", "read")
    end

    -- Avanza (si la hay) la animación de "la tapa se abre/cierra" antes
    -- de dibujar nada, para usar siempre el tamaño ya interpolado.
    self:updateResizeAnimation()

    -- Multiplicador de opacidad para el fundido de apertura/cierre:
    -- 1 = opacidad normal, 0 = totalmente invisible. Se aplica a TODO
    -- lo que se dibuja este frame (fondo, texto, marco, botones), en
    -- vez de tapar la pantalla con un rectángulo de color.
    local fadeMult = 1 - math.max(self.openFadeAlpha or 0, self.closeFadeAlpha or 0)
    if fadeMult < 0 then fadeMult = 0 end

    local spread = self:getSpread()

    -- En la portada, el panel no debe pintar un fondo opaco propio:
    -- así las zonas transparentes del PNG de la portada dejan ver
    -- de verdad lo que hay detrás, en vez de un color sólido.
    if spread and spread.single then
        self.backgroundColor.a = 0
    else
        self.backgroundColor.a = 1 * fadeMult
    end

    ISPanel.prerender(self)

    ------------------------------------------------------------------
    -- Fondo: portada usa su propia textura; el resto usa la genérica,
    -- alternando un volteo horizontal para que no se vea siempre igual.
    ------------------------------------------------------------------
    if spread and spread.single and self.coverTexture then
        self:drawTextureScaled(
            self.coverTexture, 0, 0, self.width, self.height, fadeMult, fadeMult, fadeMult, fadeMult
        )
    elseif self.backgroundTexture then
        if self.flipBackground then
            self:drawTextureScaled(
                self.backgroundTexture, self.width, 0, -self.width, self.height, fadeMult, fadeMult, fadeMult, fadeMult
            )
        else
            self:drawTextureScaled(
                self.backgroundTexture, 0, 0, self.width, self.height, fadeMult, fadeMult, fadeMult, fadeMult
            )
        end
    end

    if spread then
        if spread.single then
            -- Portada: centrada en el panel (ya redimensionado a "cerrado")
            self:drawPageUnit(spread.left, COLUMN_MARGIN, self.width / 2, fadeMult)
        else
            local leftX = self:getLeftColumnX()
            local rightX = self:getRightColumnX()
            local leftCenterX = leftX + self:getColumnWidth() / 2
            local rightCenterX = rightX + self:getColumnWidth() / 2

            self:drawPageUnit(spread.left, leftX, leftCenterX, fadeMult)
            self:drawPageUnit(spread.right, rightX, rightCenterX, fadeMult)

            -- Línea del "lomo" central
            self:drawRect(
                self.width / 2 - 1, TOP_MARGIN - 40,
                2, self.height - (TOP_MARGIN - 40) - BOTTOM_MARGIN + 40,
                0.4 * fadeMult, 0.05 * fadeMult, 0.03 * fadeMult, 0.02 * fadeMult
            )
        end

        self.leftButton:setEnable(self.currentSpread > 1)
        -- El botón "siguiente" se deshabilita solo si ya sabemos con
        -- certeza que no hay más contenido (libro construido del todo).
        local canGoNext = (self.currentSpread < self:getSpreadCount()) or (not self.builtAllPages)
        self.rightButton:setEnable(canGoNext)
    end

    self:drawPageNumber(fadeMult)

    ------------------------------------------------------------------
    -- Transición al pasar página (SOLO en páginas normales; al cruzar
    -- la tapa este flash se deja a 0 desde nextPage()/previousPage(),
    -- porque ahí el redimensionado del panel ya vende la transición
    -- por sí solo, y superponer el flash con el resize es lo que
    -- provocaba el rastro negro).
    ------------------------------------------------------------------
    if self.transitionAlpha and self.transitionAlpha > 0 then
        self:drawRect(
            0, 0, self.width, self.height,
            self.transitionAlpha * fadeMult, 0.03, 0.02, 0.01
        )
        self.transitionAlpha = self.transitionAlpha - TRANSITION_STEP
        if self.transitionAlpha < 0 then self.transitionAlpha = 0 end
    end

    -- El marco se dibuja el último para que quede siempre nítido.
    self:drawFrame(fadeMult)

    ------------------------------------------------------------------
    -- Botones: se desvanecen junto con el resto (sin ocultarse de
    -- golpe), multiplicando su alpha base por fadeMult cada frame.
    ------------------------------------------------------------------
    fadeButton(self.closeButton, fadeMult, 0.35, 0.55)
    fadeButton(self.searchButton, fadeMult, 0.35, 0.55)
    fadeButton(self.leftButton, fadeMult, 0.35, 0.55)
    fadeButton(self.rightButton, fadeMult, 0.35, 0.55)

    if self.openFadeAlpha and self.openFadeAlpha > 0 then
        self.openFadeAlpha = self.openFadeAlpha - OPEN_FADE_STEP
        if self.openFadeAlpha < 0 then self.openFadeAlpha = 0 end
    end

    if self.isClosing then
        self.closeFadeAlpha = (self.closeFadeAlpha or 0) + CLOSE_FADE_STEP
        if self.closeFadeAlpha >= 1 then
            self.closeFadeAlpha = 1
            self:finishClose()
        end
    end
end

-- Delegado en LivingBooksPaginator para no duplicar la lógica de wrap entre
-- LivingBooksReader y LivingBooksPreloader.
function BookReader:wrapText(text, maxWidth, font)
    return BookPaginator.wrapText(text, maxWidth, font)
end

----------------------------------------------------------------------
-- Elige qué sonido corresponde a una transición entre spreads:
-- cruzar la portada (single) hacia/desde el contenido usa el sonido
-- de tapa; cualquier otro cambio usa el pasar-página normal.
----------------------------------------------------------------------
function BookReader:soundForTransition(fromSpreadIndex, toSpreadIndex)
    local fromSpread = self.spreads[fromSpreadIndex]
    local toSpread = self.spreads[toSpreadIndex]

    local fromIsCover = fromSpread and fromSpread.single
    local toIsCover = toSpread and toSpread.single

    if (not fromIsCover) and toIsCover then
        return SOUND_TAPA_CERRANDOSE -- volviendo a la portada: se cierra la tapa
    end
    if fromIsCover and (not toIsCover) then
        return SOUND_TAPA_ABRIENDOSE -- saliendo de la portada: se abre la tapa
    end
    return SOUND_PASAR_PAGINA
end

-- El flash de "pasar página" (transitionAlpha) solo tiene sentido
-- cuando el panel NO cambia de tamaño entre spreads. Al cruzar la
-- tapa el panel se redimensiona (portada <-> libro abierto), y ese
-- redimensionado ya vende la transición por sí solo: superponer el
-- flash encima de un panel cuyo tamaño está cambiando frame a frame
-- es justo lo que provocaba el rastro negro. Por eso aquí se deja a 0
-- en cualquier transición que implique la tapa.
function BookReader:nextPage()

    if self.isClosing then return end
    if isGamePaused() then return end
    -- Aseguramos que existe el siguiente spread antes de intentar
    -- avanzar (puede requerir construir un nuevo lote de contenido).
    self:ensureBuiltThroughSpread(self.currentSpread + 1)
    if self.currentSpread < self:getSpreadCount() then
        local previousSpread = self.currentSpread
        self.currentSpread = self.currentSpread + 1
        self:applyLayoutForSpread(true)

        local sound = self:soundForTransition(previousSpread, self.currentSpread)
        self.transitionAlpha = (sound == SOUND_PASAR_PAGINA) and TRANSITION_START or 0

        self:playSound(sound)
        self:saveCurrentSpread()
    end
end

function BookReader:previousPage()
    if self.isClosing then return end
    if isGamePaused() then return end
    if self.currentSpread > 1 then
        local previousSpread = self.currentSpread
        self.currentSpread = self.currentSpread - 1
        self:applyLayoutForSpread(true)

        local sound = self:soundForTransition(previousSpread, self.currentSpread)
        self.transitionAlpha = (sound == SOUND_PASAR_PAGINA) and TRANSITION_START or 0

        self:playSound(sound)
        self:saveCurrentSpread()
    end
end

----------------------------------------------------------------------
-- BÚSQUEDA / SALTO A UNA PÁGINA CONCRETA
----------------------------------------------------------------------
-- Dada una página REAL (1 = primera página de contenido, sin contar la
-- portada), devuelve el índice de spread que la contiene. Las páginas
-- de contenido se emparejan de dos en dos: (1,2) -> spread 2,
-- (3,4) -> spread 3, etc. (el spread 1 es siempre la portada). Pedir
-- la página 1 o la página 2 lleva siempre al MISMO spread, porque
-- ambas se muestran juntas ("1-2 / xxx").
function BookReader:pageNumberToSpreadIndex(pageNumber)
    pageNumber = math.max(1, math.floor(pageNumber))
    return math.floor((pageNumber - 1) / 2) + 2
end

-- Salta directamente a la página REAL indicada (1 = primera página de
-- contenido, sin contar la portada), construyendo primero, si hace
-- falta, todos los lotes necesarios para llegar hasta ahí. Si el
-- número pedido es mayor que el total del libro, se queda en la
-- última página disponible.
function BookReader:goToPage(pageNumber)
    pageNumber = math.floor(pageNumber or 1)
    if pageNumber < 1 then pageNumber = 1 end

    local targetSpread = self:pageNumberToSpreadIndex(pageNumber)
    self:ensureBuiltThroughSpread(targetSpread)

    -- Si el libro ya está construido del todo y la página pedida se
    -- pasa del total real de páginas, clampamos a la última página
    -- existente en vez de quedarnos en un spread vacío/inexistente.
    if self.builtAllPages then
        local totalPages = math.max(0, #self.pages - 1)
        if totalPages > 0 and pageNumber > totalPages then
            pageNumber = totalPages
            targetSpread = self:pageNumberToSpreadIndex(pageNumber)
        end
    end

    targetSpread = math.max(1, math.min(targetSpread, self:getSpreadCount()))

    self.currentSpread = targetSpread
    self:applyLayoutForSpread(true)
    self.transitionAlpha = TRANSITION_START
    -- Esto viene siempre del diálogo de búsqueda, así que usa su
    -- propio sonido independientemente de si cruza la portada o no.
    self:playSound(SOUND_BUSCAR_PAGINA)
    self:saveCurrentSpread()
end

function BookReader:onSearchButtonClick()
    if isGamePaused() then return end
    self:openGoToPageDialog()
end

-- ISTextEntryBox es solo el campo de texto, sin target/callback ni
-- botones propios. Montamos un panel con el campo + botones "Ir"/
-- "Cancelar", igual que el resto de botones del lector.
function BookReader:openGoToPageDialog()
    self:closeGoToPageDialog()

    local w, h = 260, 110
    local dx = self.x + math.floor((self.width - w) / 2)
    local dy = self.y + math.floor((self.height - h) / 2)

    local dialog = ISPanel:new(dx, dy, w, h)
    dialog:initialise()
    dialog.backgroundColor = { r = 0.05, g = 0.04, b = 0.02, a = 0.95 }
    dialog.borderColor = { r = 0.788, g = 0.729, b = 0.455, a = 1 }
    dialog.moveWithMouse = false

    function dialog:prerender()
        ISPanel.prerender(self)
        self:drawTextCentre(getText("UI_QJBook_GoToPage_Title"), self.width / 2, 12, 0.95, 0.85, 0.65, 1, UIFont.Small)
    end

    dialog.entry = ISTextEntryBox:new("", 15, 35, w - 30, 25)
    dialog.entry:initialise()
    dialog.entry:instantiate()
    dialog.entry:setOnlyNumbers(true)
    dialog:addChild(dialog.entry)

    local okButton = ISButton:new(
        w / 2 - 90, h - 40, 80, 25,
         getText("UI_QJBook_GoToPage_Confirm"), self, self.onGoToPageConfirm
    )
    okButton:initialise()
    okButton:instantiate()
    dialog:addChild(okButton)

    local cancelButton = ISButton:new(
        w / 2 + 10, h - 40, 80, 25,
        getText("UI_QJBook_GoToPage_Cancel"), self, self.onGoToPageCancel
    )
    cancelButton:initialise()
    cancelButton:instantiate()
    dialog:addChild(cancelButton)

    -- Pulsar Enter en el campo de texto equivale a pulsar "Ir".
    local reader = self
    function dialog.entry:onCommandEntered()
        reader:onGoToPageConfirm()
    end

    self.goToPageDialog = dialog
    dialog:addToUIManager()
    dialog.entry:focus()
end

function BookReader:onGoToPageConfirm()
    if self.goToPageDialog and self.goToPageDialog.entry then
        local value = tonumber(self.goToPageDialog.entry:getText())
        if value then
            self:goToPage(value)
        end
    end
    self:closeGoToPageDialog()
end

function BookReader:onGoToPageCancel()
    self:closeGoToPageDialog()
end

function BookReader:closeGoToPageDialog()
    if self.goToPageDialog then
        self.goToPageDialog:removeFromUIManager()
        self.goToPageDialog = nil
    end
end

-- Único punto por el que pasan todos los sonidos del libro.
function BookReader:playSound(soundName)
    getSoundManager():playUISound(soundName or SOUND_PASAR_PAGINA)
end

-- Pide cerrar el lector: dispara el sonido y el fundido de salida al
-- instante, pero la limpieza real (quitar el panel) se hace en
-- finishClose() cuando el fundido termina de dejar la pantalla en
-- opacidad 0.
function BookReader:close()
    if self.isClosing then
        return -- ya se está cerrando, ignoramos pulsaciones repetidas
    end
    if isGamePaused() then return end
    self:closeGoToPageDialog()
    self:saveCurrentSpread()
    -- El jugador deja el libro / cierra el lector.
    self:playSound(SOUND_DEJAR)
    self.isClosing = true
    self.closeFadeAlpha = self.closeFadeAlpha or 0

    -- Si la sesion "fantasma" de vigilancia de movimiento sigue viva
    -- (p.ej. cerramos con el boton X, no por movimiento), la cortamos
    -- aqui. Se quita el closer antes para que forceStop() no vuelva a
    -- llamar a close() en bucle.
    if self.readingSession then
        local session = self.readingSession
        self.readingSession = nil
        session.closer = nil
        session:forceStop()
    end
end

-- Limpieza real del panel, llamada automáticamente desde prerender()
-- cuando el fundido de cierre llega a opacidad 0 (closeFadeAlpha = 1).
function BookReader:finishClose()
    ISHotbar.onKeyKeepPressed = original_onKeyKeepPressed

    local player = getPlayer()
    if player then
        player:setVariable("bookHoldType", "")
        player:setVariable("PerformingAction", "")
    end

    self:removeFromUIManager()
    self:clearChildren()
end

-- Códigos LWJGL estándar como respaldo, por si Keyboard.KEY_LEFT/KEY_RIGHT
-- no estuvieran expuestos tal cual en esta build.
local KEY_LEFT = (Keyboard and Keyboard.KEY_LEFT) or 203
local KEY_RIGHT = (Keyboard and Keyboard.KEY_RIGHT) or 205

function BookReader:onKeyPress(key)
    if self.isClosing then
        return
    end
    if isGamePaused() then return end

    if key == KEY_RIGHT then
        self:nextPage()
        return
    end
    if key == KEY_LEFT then
        self:previousPage()
        return
    end
    -- cualquier otra tecla se ignora: el libro ya no se cierra con teclas
end