-- client/LivingBookSystem/LivingBooksPreloader.lua
-- Precarga UNA SOLA VEZ al rebootear el juego (cambiar mods)
-- NO cada vez que entras a una partida

require "LivingBookSystem/LivingBooksLoader"
require "LivingBooksSystemShared/LivingBooksPaginator"

BookPreloader = {}
BookPreloader.entries = {}
BookPreloader.ready = false

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

function BookPreloader.run()
    if BookPreloader.ready then
        return
    end

    for _, book in ipairs(BookLoader.getAllBooks()) do
        preloadOne(book)
    end

    BookPreloader.ready = true
    print("[LivingBooks] ✅ Precarga completada (sólo se hace UNA VEZ)")
end

function BookPreloader.getEntry(book)
    return BookPreloader.entries[book]
end

-- UNA SOLA VEZ: al rebootear el juego (cambiar mods, reiniciar)
Events.OnGameBoot.Add(BookPreloader.run)

return BookPreloader