---@diagnostic disable: undefined-global
-- Maybe find a better HideyHole?
local HideyHole

local TransmogCharacter
local ReplacedItem
local ControlItem
local TransmogTemplate
local CombineRequest
local isGlamoured
local isWielding
local isHidingAppearance

---@param character CHARACTER
---@param controlItem ITEM
---@param item2 ITEM
---@param glamourAppearance ITEM
---@diagnostic disable-next-line: duplicate-doc-param
---@param _ ITEM
---@diagnostic disable-next-line: duplicate-doc-param
---@param _ ITEM
---@param requestID integer
Ext.Osiris.RegisterListener("RequestCanCombine", 7, "before", function(character, controlItem, item2, glamourAppearance, _, _, requestID)
    -- Only do the work if the first combo item is the tmog item
    if Utils.UUIDEquals(Osi.GetTemplate(controlItem), Constants.ControlItems["TMogReplacerTemplate"]) or Utils.UUIDEquals(Osi.GetTemplate(controlItem), Constants.ControlItems["TMogCleanerTemplate"]) then
        ControlItem = controlItem

        CombineRequest = requestID

        TransmogCharacter = character

        ReplacedItem = item2
        TransmogTemplate = Osi.GetTemplate(glamourAppearance)

        ReplacedEntity = Utils.RepairNestedEntity(Ext.Entity.Get(item2))
        local TransmogEntity = Utils.RepairNestedEntity(Ext.Entity.Get(glamourAppearance))

        if TransmogEntity ~= nil and Utils.UUIDEquals(TransmogTemplate, Constants.ControlItems["TMogHiderTemplate"]) then
            -- If the second item is the Hider Control Item then we use a basic ring template to avoid trouble when deactivating the mod
            TransmogTemplate = Constants.DefaultUUIDs["TMogVanillaRingTemplate"]
            isHidingAppearance = true
        end

        if (Utils.AllowGlamour(ReplacedEntity, TransmogEntity, isHidingAppearance)) then
            if (PersistentVars["GlamouredItems"][item2] ~= nil) then
                isGlamoured = true
            end

            -- Unequip replaced item before copying
            if (Utils.IsWielding(ReplacedEntity, TransmogCharacter)) then
                Osi.Unequip(TransmogCharacter, ReplacedItem)
                isWielding = true
            end

            -- I wish we could get the uuid of the new item, but alas, we must listen to it and pray no one else is tmoging at the same time.
            Osi.TemplateAddTo(TransmogTemplate, HideyHole, 1, 0)
        elseif (ReplacedEntity ~= nil and not TransmogEntity) and (PersistentVars["GlamouredItems"][item2] ~= nil) then
            CombineRequest = requestID

            Osi.ToInventory(PersistentVars["GlamouredItems"][item2], TransmogCharacter, 1, 1, 0)

            -- Unequip and re-equip if current character is wielding
            if (Utils.IsWielding(ReplacedEntity, TransmogCharacter)) then
                Osi.Unequip(TransmogCharacter, ReplacedItem)
                Osi.Equip(TransmogCharacter, PersistentVars["GlamouredItems"][item2])
            end

            PersistentVars["GlamouredItems"][item2] = nil
            Osi.RequestDelete(ReplacedItem)

            Osi.RequestProcessed(TransmogCharacter, CombineRequest, 1)

            Osi.Use(TransmogCharacter, controlItem, "")
        end
    end
end)

---@param template ROOT
---@param uuid GUIDSTRING
---@param character GUIDSTRING
---@param _ string
Ext.Osiris.RegisterListener("TemplateAddedTo", 4, "before", function(template, uuid, character, _)
    -- Handle TMOG
    if (Utils.UUIDEquals(template, TransmogTemplate) and Utils.UUIDEquals(character, HideyHole)) then
        TransmogTemplate = nil

        local NewItem = Utils.RepairNestedEntity(Ext.Entity.Get(uuid))

        for _, entry in ipairs(Constants.Replications) do
            Utils.CloneEntityEntry(NewItem, ReplacedEntity, entry)
        end

        NewItem.Use.Boosts = { table.unpack(ReplacedEntity.Use.Boosts) }

        -- Part for the hide appearance ring, just copy icon from replaceditem to new item
        if Utils.UUIDEquals(template, Constants.DefaultUUIDs["TMogVanillaRingTemplate"]) and isHidingAppearance then
            isHidingAppearance = nil
            for _, entry in ipairs(Constants.HideAppearanceRing) do
                Utils.CloneEntityEntry(NewItem, ReplacedEntity, entry)
            end
        end

        -- Let's Replicate again for funzies
        for _, entry in ipairs(Constants.Replications) do
            local ExcludedReps = Utils.Set(Constants.ExcludedReplications)

            if (not ExcludedReps[entry]) then
                NewItem:Replicate(entry)
            end
        end

        -- We do it this way to show a notification of the new item :)
        Osi.ToInventory(uuid, TransmogCharacter, 1, 1, 1)

        -- Re-equip only if the tmogging character had it equipped
        -- Modified the if statement, kept the ancient in case you want to revert changes
        if (isWielding) then
            Osi.Equip(TransmogCharacter, uuid)
            isWielding = false
        end

        Osi.RequestProcessed(TransmogCharacter, CombineRequest, 1)

        --Register Base item
        if (isGlamoured) then
            PersistentVars["GlamouredItems"][uuid] = PersistentVars["GlamouredItems"][ReplacedItem]
            PersistentVars["GlamouredItems"][ReplacedItem] = nil

            Osi.RequestDelete(ReplacedItem)
            isGlamoured = false
        else
            PersistentVars["GlamouredItems"][uuid] = ReplacedItem
            Osi.ToInventory(ReplacedItem, HideyHole, 1, 0, 0)
        end

        Osi.Use(TransmogCharacter, ControlItem, "")

        ReplacedItem = nil
        CombineRequest = nil
        TransmogCharacter = nil
    elseif (Utils.TemplateIsControlItem(template)) then
        -- Handle Control Items

        local tempControlItems = Utils.Set(PersistentVars["ControlItems"])
        local normalizedUUID = Utils.GetGUID(uuid)

        if (not tempControlItems[normalizedUUID]) then
            table.insert(PersistentVars["ControlItems"], normalizedUUID)
        end
    end
end)


Ext.Osiris.RegisterListener("SavegameLoaded", 0, "after", function()
    local success, _ = pcall(Utils.TryGetDB, "DB_CharacterCreationDummy", 1)
    if success then
        for _, entry in pairs(Osi["DB_CharacterCreationDummy"]:Get(nil)) do
            if (entry[1] ~= nil and type(entry[1]) == "string" and string.len(entry[1]) > 0) then
                HideyHole = entry[1]
                break
            end
        end
    end

    if (HideyHole == nil) then
        HideyHole = Constants.DefaultUUIDs["HideyHoleFallback"]
    end

    -- Add control items
    Utils.GiveControlItems()

    -- Fix Names (replication of ServerDisplayNameList isn't done so we have to do this for now)
    for glamouredItem, originItem in pairs(PersistentVars["GlamouredItems"]) do
        local GlamouredEntity = Utils.RepairNestedEntity(Ext.Entity.Get(glamouredItem))
        local OriginEntity = Utils.RepairNestedEntity(Ext.Entity.Get(originItem))

        Utils.DeepWrite(GlamouredEntity["ServerDisplayNameList"], OriginEntity["ServerDisplayNameList"])
        Utils.DeepWrite(GlamouredEntity["DisplayName"], OriginEntity["DisplayName"])
        GlamouredEntity:Replicate("DisplayName")

        local OriginEntityEquipableSuccess, OriginEntityEquipable = pcall(Utils.TryGetProxy, OriginEntity, "Equipable")

        if (OriginEntityEquipableSuccess and Utils.UUIDEquals(Osi.GetTemplate(glamouredItem), Constants.DefaultUUIDs["TMogVanillaRingTemplate"]) and OriginEntityEquipable["Slot"] ~= "Ring") then
            Utils.DeepWrite(GlamouredEntity["ServerIconList"], OriginEntity["ServerIconList"])
            Utils.DeepWrite(GlamouredEntity["Icon"], OriginEntity["Icon"])
            GlamouredEntity:Replicate("Icon")
        end
    end
end)

Ext.Osiris.RegisterListener("CharacterCreationFinished", 0, "after", function()
    -- Give control items to new game characters
    Utils.GiveControlItems()

    if (HideyHole == nil) then
        local success, _ = pcall(Utils.TryGetDB, "DB_CharacterCreationDummy", 1)
        if success then
            for _, entry in pairs(Osi["DB_CharacterCreationDummy"]:Get(nil)) do
                if (entry[1] ~= nil and type(entry[1]) == "string" and string.len(entry[1]) > 0) then
                    HideyHole = entry[1]
                    break
                end
            end
        end

        if (HideyHole == nil) then
            HideyHole = Constants.DefaultUUIDs["HideyHoleFallback"]
        end
    end
end)
