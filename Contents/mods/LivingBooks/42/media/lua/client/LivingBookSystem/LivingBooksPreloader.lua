-- client/LivingBookSystem/LivingBooksPreloader.lua
--------------------------------------------------------------------------
-- Pagina TODOS los libros registrados una sola vez, lo antes posible (al
-- llegar al menu principal). Cada libro guarda su propia entrada en
-- BookPreloader.entries, indexada por la propia tabla `book` (la misma
-- referencia que devuelve BookLoader.getBookForItem).
--
-- Las constantes de maquetacion de aqui abajo tienen que coincidir con
-- las de LivingBooksReader.lua para que la paginacion sea identica.
--------------------------------------------------------------------------

require "LivingBookSystem/LivingBooksLoader"
require "LivingBooksSystemShared/LivingBooksPaginator"

BookPreloader = {}

BookPreloader.entries = {} -- [book] = { pages, spreads, openWidth, openHeight }
BookPreloader.ready = false

-- Deben coincidir con LivingBooksReader.lua
local BOOK_TEXT_FONT       = UIFont.Medium
local TOP_MARGIN           = 80
local BOTTOM_MARGIN        = 90
local PARAGRAPH_GAP        = 18
local LINE_SPACING         = 6
local LINE_HEIGHT_FALLBACK = 22
local COLUMN_MARGIN        = 70
local GUTTER               = 50

local function computeOpenDimensions()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local h = math.floor(sh * 0.82)
    local w = math.floor(h * 1.60)
    return w, h
end

local function preloadOne(book)
    local openWidth, openHeight = computeOpenDimensions()
    local columnWidth = (openWidth / 2) - (GUTTER / 2) - (COLUMN_MARGIN * 2)

    local title = book.filename and book.filename:gsub("%.pdf", "") or "Sin titulo"
    local subtitle = book.author or book.subtitle

    local layout = {
        columnWidth = columnWidth,
        font = BOOK_TEXT_FONT,
        topMargin = TOP_MARGIN,
        bottomMargin = BOTTOM_MARGIN,
        paragraphGap = PARAGRAPH_GAP,
        lineSpacing = LINE_SPACING,
        lineHeightFallback = LINE_HEIGHT_FALLBACK,
        openHeight = openHeight,
        coverTitle = title,
        coverSubtitle = subtitle,
    }

    local pages = BookPaginator.buildPages(book, layout)
    local spreads = BookPaginator.buildSpreads(pages)

    BookPreloader.entries[book] = {
        pages = pages,
        spreads = spreads,
        openWidth = openWidth,
        openHeight = openHeight,
    }
end

-- Pagina TODOS los libros registrados. Idempotente (comprueba .ready).
function BookPreloader.run()
    if BookPreloader.ready then
        return
    end

    for _, book in ipairs(BookLoader.getAllBooks()) do
        preloadOne(book)
    end

    BookPreloader.ready = true
end

-- Devuelve la entrada precargada de un libro concreto, o nil si aun no
-- se ha precargado (p.ej. cambio de resolucion a mitad de partida).
function BookPreloader.getEntry(book)
    return BookPreloader.entries[book]
end

-- Precarga real: en cuanto se llega al menu principal.
Events.OnMainMenuEnter.Add(BookPreloader.run)
-- Red de seguridad: por si OnMainMenuEnter no llegase a dispararse.
Events.OnGameStart.Add(BookPreloader.run)

return BookPreloader