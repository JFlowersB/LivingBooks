-- server/Items/LivingBooksDistributions.lua
require "Items/ProceduralDistributions"
require "LivingBooksSystemShared/LivingBooksRegistry"

local BASE_CHANCE = 2.0

local PRESET_MULTIPLIERS = {
    [1] = 0,
    [2] = 0.1,
    [3] = 0.2,
    [4] = 0.4,
    [5] = 0.6,
    [6] = 2.0,
    [7] = 3.0,
}

local SKILL_BOOK_PREFIXES = {
    "Aiming", "Axe", "Blunt", "Carpentry", "Cooking", "Electricity", "Farming",
    "FirstAid", "Fishing", "LongBlade", "LongBlunt", "Maintenance", "Mechanics",
    "MetalWelding", "ShortBlade", "ShortBlunt", "Sneak", "Spear", "Strength",
    "Tailoring", "Trapping",
}

local function getMultiplier()
    local sv = SandboxVars.LivingBooks
    local preset = (sv and sv.SpawnChance) or 5
    return PRESET_MULTIPLIERS[preset] or PRESET_MULTIPLIERS[5]
end

-- Devuelve true si el item es un libro de literatura de vanilla (no de
-- habilidad), que es donde queremos insertar los LivingBooks.
local function isLiteratureBook(item)

    if type(item) ~= "string" then
        return false
    end

    item = item:gsub("^Base%.", "")

    if item:match("^BookFancy_") then
        return true
    end

    if item == "Book" then
        return true
    end

    if not item:match("^Book_") then
        return false
    end

    for _, prefix in ipairs(SKILL_BOOK_PREFIXES) do
        if item:match("^Book_" .. prefix) then
            return false
        end
    end

    return true
end

local function hasLiteratureBook(items)
    for i = 1, #items, 2 do
        if isLiteratureBook(items[i]) then
            return true
        end
    end
    return false
end

local function alreadyHasItem(items, itemName)
    for i = 1, #items, 2 do
        if items[i] == itemName then
            return true
        end
    end
    return false
end

local function addSpawns()

    if not (ProceduralDistributions and ProceduralDistributions.list) then
        print("ERROR: ProceduralDistributions.list non disponible")
        return
    end

    local mult = getMultiplier()

    if mult <= 0 then
        print("[LivingBooks] Spawn disabled")
        return
    end

    local books = BookRegistry.getAll()

    if #books == 0 then
        print("[LivingBooks] No hay ningun libro registrado (revisa que los content packs esten activados)")
        return
    end

    local chance = (BASE_CHANCE * mult) / math.max(1, #books)

    local seen = {}
    local scanned = 0
    local inserted = 0

    for _, dist in pairs(ProceduralDistributions.list) do

        if type(dist) == "table" and type(dist.items) == "table" then
            scanned = scanned + 1

            if not seen[dist.items] then
                seen[dist.items] = true

                if hasLiteratureBook(dist.items) then
                    for _, book in ipairs(books) do
                        if not alreadyHasItem(dist.items, book.itemFullType) then
                            table.insert(dist.items, book.itemFullType)
                            table.insert(dist.items, chance)
                            inserted = inserted + 1
                        end
                    end
                end
            end
        end
    end

    print("[LivingBooks] " .. inserted .. " inserciones en distribuciones, " .. #books .. " libro(s), " .. scanned .. " listas escaneadas")
end

Events.OnPreDistributionMerge.Add(addSpawns)