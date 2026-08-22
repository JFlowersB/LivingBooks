-- shared/LivingBooksSystemShared/LivingBooksRegistry.lua
--
-- Escanea TODOS los mods activados en busca de "content packs" de LivingBooks.
-- Un content pack es un mod aparte que SOLO necesita:
--   1) Un JSON en  media/books/book.json  (ver EN_BookImportGuide.txt)
--   2) Su propio item definido en un .txt (la plantilla no cambia nunca,
--      solo el nombre del item y el DisplayName)
--
-- El framework NO necesita tocarse para añadir un libro nuevo: basta con
-- activar el mod del content pack junto a LivingBooks. El enlace entre el
-- JSON y el item real lo da el campo "itemFullType" dentro del propio JSON.

local chcjson = require "LivingBooksSystemShared/LivingBooksJson"

BookRegistry = {}

-- Un mod puede traer VARIOS libros. Para eso lista sus ficheros JSON en un
-- manifiesto de texto plano, uno por línea (rutas relativas a media/books/).
local BOOKS_FOLDER = "media/books/"
local MANIFEST_PATH = BOOKS_FOLDER .. "books.txt"

BookRegistry.books = nil    -- { [itemFullType] = bookData }
BookRegistry.list = nil     -- array de bookData, para iterar en orden
BookRegistry.scanned = false

local function readWholeFile(modID, relativePath)
    local file = getModFileReader(modID, relativePath, false)
    if not file then
        return nil
    end

    local lines = {}
    while true do
        local line = file:readLine()
        if not line then break end
        lines[#lines + 1] = line
    end
    file:close()

    return table.concat(lines, "\n")
end

-- Lee books.txt y devuelve la lista de nombres de fichero (sin líneas
-- vacías ni espacios sobrantes).
local function readManifest(modID)
    local text = readWholeFile(modID, MANIFEST_PATH)
    if not text then
        return nil
    end

    local filenames = {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(filenames, trimmed)
        end
    end

    return filenames
end

local function registerBook(modID, filename, text)
    local ok, data = pcall(chcjson.Decode, text)

    if not ok then
        print("[LivingBooks] error parseando " .. filename .. " (" .. tostring(modID) .. "): " .. tostring(data))
        return
    end
    if type(data) ~= "table" then
        print("[LivingBooks] " .. filename .. " (" .. tostring(modID) .. ") no es un objeto JSON valido")
        return
    end
    if not data.itemFullType then
        print("[LivingBooks] " .. filename .. " (" .. tostring(modID) .. "): falta 'itemFullType', se ignora")
        return
    end
    if BookRegistry.books[data.itemFullType] then
        print("[LivingBooks] itemFullType duplicado '" .. tostring(data.itemFullType) .. "', se ignora " .. filename .. " de " .. tostring(modID))
        return
    end

    data.modID = modID
    print("[DEBUG] Registering:", tostring(data.itemFullType))
    BookRegistry.books[data.itemFullType] = data
    table.insert(BookRegistry.list, data)
    
end

-- Recorre los mods activados y carga TODOS los libros que declaren en su
-- media/books/books.txt. Se ejecuta una sola vez; llamadas siguientes son
-- gratis.
function BookRegistry.scan()
    if BookRegistry.scanned then
        return
    end

    BookRegistry.books = {}
    BookRegistry.list = {}

    local mods = getActivatedMods()

    print("========== ACTIVATED MODS ==========")

    for i = 0, mods:size() - 1 do
        print(i, mods:get(i))
    end

    print("====================================")

    for i = 0, mods:size() - 1 do
        local modID = mods:get(i)
        local filenames = readManifest(modID)

        if filenames then
            print("[LivingBooks] Manifest encontrado en:", modID)

            for _, file in ipairs(filenames) do
                print("   -> " .. file)
            end
        else
            print("[LivingBooks] NO MANIFEST:", modID)
        end

        if filenames then
            for _, filename in ipairs(filenames) do
                local text = readWholeFile(modID, BOOKS_FOLDER .. filename)
                if text then
                    print("[LivingBooks] JSON abierto:", modID, filename)
                else
                    print("[LivingBooks] NO SE PUDO ABRIR:", modID, filename)
                end
                
                if text then
                    registerBook(modID, filename, text)
                else
                    print("[LivingBooks] " .. tostring(modID) .. ": books.txt menciona '" .. filename .. "' pero no existe en media/books/")
                end
            end
        end
    end

    BookRegistry.scanned = true
    print("[LivingBooks] " .. #BookRegistry.list .. " libro(s) registrado(s)")
end

function BookRegistry.getBook(itemFullType)
    BookRegistry.scan()
    return BookRegistry.books[itemFullType]
end

function BookRegistry.isBookItem(itemFullType)
    BookRegistry.scan()
    return BookRegistry.books[itemFullType] ~= nil
end

function BookRegistry.getAll()
    BookRegistry.scan()
    return BookRegistry.list
end

function BookRegistry.reset()
    BookRegistry.scanned = false
    BookRegistry.books = nil
    BookRegistry.list = nil
end

-- ✅ SOLO reset al rebootear Lua (cambiar mods), NO en cada partida
-- Antes estaba en OnGameStart, lo que hacía que se escanearan los mods CADA VEZ
Events.OnGameBoot.Add(BookRegistry.reset)

return BookRegistry