--Contents\mods\LivingBooks\42\media\lua\shared\LivingBooksSystemShared\LivingBooksPaginator.lua
-- Lógica de paginación PURA (sin estado de UI), compartida entre:
--   - LivingBooksReader.lua      (construcción perezosa, por lotes, como red
--                          de seguridad si no hubo precarga)
--   - LivingBooksPreloader   (construcción completa de una sola vez, al
--                          arrancar la partida)
-- Vive en "shared" porque no depende de nada específico de un panel de
-- UI concreto, solo de getTextManager() (disponible en cliente).
--------------------------------------------------------------------------

BookPaginator = {}

-- Envuelve un texto en líneas que quepan en maxWidth con la fuente dada.
function BookPaginator.wrapText(text, maxWidth, font)

    local lines = {}

    -- Procesar cada línea original por separado para conservar \n
    for rawLine in (text .. "\n"):gmatch("(.-)\n") do

        -- Línea vacía = mantener salto
        if rawLine == "" then
            table.insert(lines, "")
        else

            local line = ""

            for word in rawLine:gmatch("%S+") do

                local test = (line == "") and word or (line .. " " .. word)

                if getTextManager():MeasureStringX(font, test) > maxWidth then
                    table.insert(lines, line)
                    line = word
                else
                    line = test
                end

            end

            if line ~= "" then
                table.insert(lines, line)
            end

        end

    end

    return lines

end

--------------------------------------------------------------------------
-- Construye TODAS las páginas del libro de una sola vez.
--
-- layout = {
--   columnWidth        = ancho de columna para el wrap del texto
--   font               = fuente del cuerpo de texto
--   topMargin          = margen superior de las páginas de texto
--   bottomMargin       = margen inferior reservado (botones/nº página)
--   paragraphGap       = espacio extra tras cada párrafo
--   lineSpacing        = espacio entre líneas
--   lineHeightFallback = altura de línea si getFontHeight() falla
--   openHeight         = alto del panel "abierto" (2 páginas)
--   coverTitle         = texto de portada (título)
--   coverSubtitle      = texto de portada (autor/subtítulo)
-- }
--------------------------------------------------------------------------
function BookPaginator.buildPages(book, layout)

    local font = layout.font
    local lineHeight = getTextManager():getFontHeight(font) or layout.lineHeightFallback
    local textWidth = layout.columnWidth
    local maxY = layout.openHeight - layout.bottomMargin

    local pages = {}

    ------------------------------------------------------------------
    -- Página de portada
    ------------------------------------------------------------------
    table.insert(pages, {
        type = "title",
        text = layout.coverTitle,
        subtitle = layout.coverSubtitle
    })

    ------------------------------------------------------------------
    -- Aplanamos + paginamos el resto del contenido
    ------------------------------------------------------------------
    local currentLines = {}
    local currentY = layout.topMargin

    local function flushTextPage()
        if #currentLines > 0 then
            table.insert(pages, { type = "text", lines = currentLines })
            currentLines = {}
        end
        currentY = layout.topMargin
    end

    -- Los headings SIEMPRE deben caer en la página izquierda de un
    -- spread. pages[1] es la portada (va sola); a partir de pages[2]
    -- se emparejan de dos en dos: posición impar de #pages = va a
    -- caer a la izquierda, posición par = caería a la derecha, así
    -- que en ese caso rellenamos con una página en blanco antes.
    local function ensureHeadingLandsOnLeft()
        if #pages % 2 == 0 then
            table.insert(pages, { type = "blank" })
        end
    end

    for _, srcPage in ipairs(book.pages or {}) do

        for _, heading in ipairs(srcPage.headings or {}) do
            flushTextPage()
            ensureHeadingLandsOnLeft()
            table.insert(pages, {
                type = "heading",
                text = heading.text,
                level = heading.level
            })
        end

        for _, paragraph in ipairs(srcPage.paragraphs or {}) do

            local wrapped = BookPaginator.wrapText(paragraph, textWidth, font)

            for _, line in ipairs(wrapped) do

                if currentY + lineHeight + layout.lineSpacing > maxY then
                    flushTextPage()
                end

                -- También conserva líneas vacías ("") para respetar los \n
                table.insert(currentLines, line)
                currentY = currentY + layout.lineSpacing + lineHeight

            end

            currentY = currentY + layout.paragraphGap

            if currentY > maxY then
                flushTextPage()
            end

        end

    end

    flushTextPage()

    return pages

end

-- Agrupa páginas en spreads (pares izquierda/derecha), portada sola.
-- Es barato (solo agrupa referencias), así que se puede llamar entero
-- cada vez sin preocuparse de rendimiento.
--
-- Cada spread de CONTENIDO (single == false) guarda también el número
-- de PÁGINA REAL (sin contar la portada) que corresponde a su columna
-- izquierda y, si existe, a su columna derecha:
--   leftPageNum  = número de página real de spread.left
--   rightPageNum = número de página real de spread.right (nil si no hay)
-- Así la UI puede mostrar/buscar por número de página real ("1-2/xxx")
-- en vez de por índice de spread. pages[1] es siempre la portada, así
-- que la página real de pages[i] es (i - 1).
function BookPaginator.buildSpreads(pages)

    local spreads = {}

    if #pages == 0 then
        return spreads
    end

    table.insert(spreads, { single = true, left = pages[1] })

    local i = 2

    while i <= #pages do
        table.insert(spreads, {
            single = false,
            left = pages[i],
            right = pages[i + 1],
            leftPageNum = i - 1,
            rightPageNum = pages[i + 1] and i or nil,
        })
        i = i + 2
    end

    return spreads

end

return BookPaginator