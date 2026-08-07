-- client/LivingBookSystem/LivingBooksInteraction.lua
require "LivingBookSystem/LivingBooksReader"
require "LivingBookSystem/LivingBooksLoader"
require "LivingBookSystem/LivingBooksPreloader"

require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"

local BOOK_ICON = "Item_Book_OldFancy" -- icono generico para todos los libros
local READ_TIME = 20 -- duracion de la action bar (ticks)

local window = nil

--------------------------------------------------------
-- Abrir libro (ahora recibe el item para saber CUAL libro es)
--------------------------------------------------------

local function OpenBook(item)

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()

    local h = math.floor(sh * 0.82)
    local w = math.floor(h * 1.60)

    local book = BookLoader.getBookForItem(item:getFullType())

    if not book then
        print("[LivingBooks] No se encontro contenido registrado para " .. tostring(item:getFullType()))
        return
    end

    if window then
        window:removeFromUIManager()
        window = nil
    end

    window = BookReader:new(
        (sw - w) / 2,
        (sh - h) / 2,
        w,
        h,
        book
    )

    window:initialise()
    window:addToUIManager()

end

--------------------------------------------------------
-- TimedAction: ReadBook
--------------------------------------------------------

ISLivingBooksReadAction = ISBaseTimedAction:derive("ISLivingBooksReadAction")

function ISLivingBooksReadAction:isValidStart()
    return self.character:getInventory():contains(self.item)
end

function ISLivingBooksReadAction:isValid()
    return self.character:isAlive() and self.character:getInventory():contains(self.item)
end

function ISLivingBooksReadAction:update()
    self.character:faceLocation(self.character:getX(), self.character:getY())
end

function ISLivingBooksReadAction:start()
    self:setActionAnim("Read")
    self.character:reportEvent("EventReading")
    self.character:setVariable("bookHoldType", "Big")
end

function ISLivingBooksReadAction:stop()
    ISBaseTimedAction.stop(self)
end

function ISLivingBooksReadAction:perform()
    ISBaseTimedAction.perform(self)
    OpenBook(self.item)
end

function ISLivingBooksReadAction:new(character, item, time)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.maxTime = time or READ_TIME

    o.stopOnWalk = true
    o.stopOnRun = true
    o.stopOnAim = true

    return o
end

--------------------------------------------------------
-- Buscar libro: ahora acepta CUALQUIER item registrado en BookRegistry,
-- no solo un fullType fijo.
--------------------------------------------------------

local function findBook(items)

    for _, entry in ipairs(items) do

        local item = entry

        if not instanceof(item, "InventoryItem") then
            if entry.items then
                item = entry.items[1]
            else
                item = nil
            end
        end

        if item then
            -- TEMP DEBUG: comparar el fullType real del item contra lo
            -- que el registry tiene guardado, en el lado CLIENTE.
            print("[LivingBooks][DEBUG] item fullType = '" .. tostring(item:getFullType()) .. "'")
            for fullType, _ in pairs(BookRegistry.books or {}) do
                print("[LivingBooks][DEBUG] registry key = '" .. tostring(fullType) .. "'")
            end
        end

        if item and BookLoader.isLivingBook(item:getFullType()) then
            return item
        end

    end

    return nil

end

--------------------------------------------------------
-- Leer
--------------------------------------------------------

local function ReadBook(item)

    local player = getPlayer()

    if item:getContainer() == player:getInventory() then
        ISTimedActionQueue.add(ISLivingBooksReadAction:new(player, item))
        return
    end

    local pickupAction = ISInventoryTransferAction:new(
        player,
        item,
        item:getContainer(),
        player:getInventory()
    )

    pickupAction:setOnComplete(function()
        ISTimedActionQueue.add(ISLivingBooksReadAction:new(player, item))
    end)

    ISTimedActionQueue.add(pickupAction)

end

--------------------------------------------------------
-- Menu contextual
--------------------------------------------------------

local function AddMenu(playerNum, context, items)

    local item = findBook(items)

    if not item then
        return
    end

    local option = context:addOption(
        getText("UI_LivingBooks_Read"),
        item,
        ReadBook
    )

    option.iconTexture = getTexture(BOOK_ICON)

    table.insert(context.options, 1, table.remove(context.options))

end

Events.OnFillInventoryObjectContextMenu.Add(AddMenu)