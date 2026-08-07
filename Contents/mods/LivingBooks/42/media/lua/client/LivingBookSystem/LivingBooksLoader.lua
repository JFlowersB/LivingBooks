-- client/LivingBookSystem/LivingBooksLoader.lua
require "LivingBooksSystemShared/LivingBooksRegistry"

BookLoader = {}

-- Devuelve el book.json (ya parseado y cacheado por el registry)
-- correspondiente al fullType de un item concreto.
function BookLoader.getBookForItem(itemFullType)
    return BookRegistry.getBook(itemFullType)
end

-- true si ese fullType corresponde a algun libro registrado por CUALQUIER
-- content pack activado.
function BookLoader.isLivingBook(itemFullType)
    local ok = BookRegistry.isBookItem(itemFullType)

    print("[DEBUG] Looking for:", tostring(itemFullType))
    print("[DEBUG] Result:", tostring(ok))

    return ok
end

-- Todos los libros registrados, para el preloader y las distribuciones.
function BookLoader.getAllBooks()
    return BookRegistry.getAll()
end

return BookLoader