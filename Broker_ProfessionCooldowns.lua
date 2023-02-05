local ignored_spell_ids = {169080 -- gearspring parts
, 177054 -- secrets of draenor engineering
, 175880 -- secrets of draenor alchemy
, 156587 -- alchemical catalyst
}

local profession_spells = {
  {388213, "Mining"}, -- Overload Elemental Deposit
  {390392, "Herbalism"} -- Overload Elemental Herb
}

------------------------------
--- Initialize Saved Variables
------------------------------
if icbat_bpc_cross_character_cache == nil then
    --    [ {
    --         recipe_id,
    --         recipe_name,
    --         qualified_char_name,
    --         cooldown_finished_date,
    --         profession_id,
    --     } ]
    icbat_bpc_cross_character_cache = {}
end
if icbat_bpc_character_class_name == nil then
    -- char name -> class name
    icbat_bpc_character_class_name = {}
end

-----------------------
--- Tim Allen Grunt.wav
-----------------------

local function should_track_recipe(recipe_id)
    local recipe_info = C_TradeSkillUI.GetRecipeInfo(recipe_id)
    if recipe_info == nil or not recipe_info["learned"] then
        return false
    end
    local seconds_left_on_cd, isDayCooldown, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipe_id)

    if seconds_left_on_cd == nil or seconds_left_on_cd < 1 then
        return false
    end

    for _i, ignored_spell_id in ipairs(ignored_spell_ids) do
        if ignored_spell_id == recipe_id then
            return false
        end
    end

    return true
end

local function get_qualified_name()
    local name, realm = UnitFullName("player")
    local qualified_name = name .. "-" .. realm
    return qualified_name
end

local function add_recipe_to_cache(recipe_id)
    local recipe_info = C_TradeSkillUI.GetRecipeInfo(recipe_id)
    local seconds_left_on_cd, isDayCooldown, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(recipe_id)
    local qualified_name = get_qualified_name()

    if seconds_left_on_cd == nil then
        seconds_left_on_cd = -1
    end

    local recipe_to_store = {
        recipe_id = recipe_id,
        recipe_name = recipe_info["name"],
        qualified_char_name = qualified_name,
        cooldown_finished_date = seconds_left_on_cd + time(),
        profession_id = C_TradeSkillUI.GetProfessionNameForSkillLineAbility(recipe_info["skillLineAbilityID"])
    }
    local _localized, canonical_class_name = UnitClass("player")
    icbat_bpc_character_class_name[qualified_name] = canonical_class_name
    for i, stored_recipe in ipairs(icbat_bpc_cross_character_cache) do
        if stored_recipe["recipe_id"] == recipe_id and stored_recipe["qualified_char_name"] == qualified_name then
            icbat_bpc_cross_character_cache[i] = recipe_to_store
            return
        end
    end
    table.insert(icbat_bpc_cross_character_cache, recipe_to_store)
end


local function add_spell_to_cache(spell_id, profession_text)
    if not IsSpellKnown(spell_id) then
        return
    end
    local spell_name = GetSpellInfo(spell_id)
    local qualified_name = get_qualified_name()
    local start, duration = GetSpellCooldown(spell_id)
    local ready_at
    if start == 0 then
        seconds_left = -1
        ready_at = time() - 1
    else
        -- For some reason, GetSpellCooldown returns time based on computer
        -- uptime, not just a clock, so we need to adjust
        ready_at = time() + start + duration - GetTime()
    end
    local recipe_to_store = {
        recipe_id = spell_id,
        recipe_name = spell_name,
        qualified_char_name = qualified_name,
        cooldown_finished_date = ready_at,
        profession_id = profession_text
    }
    local _localized, canonical_class_name = UnitClass("player")
    icbat_bpc_character_class_name[qualified_name] = canonical_class_name
    for i, stored_recipe in ipairs(icbat_bpc_cross_character_cache) do
        if stored_recipe["recipe_id"] == recipe_id and stored_recipe["qualified_char_name"] == qualified_name then
            icbat_bpc_cross_character_cache[i] = recipe_to_store
            return
        end
    end
    table.insert(icbat_bpc_cross_character_cache, recipe_to_store)
end

local function clear_recipe(i, recipe_info, qualified_name)
    -- remove old-format entries
    if recipe_info["qualified_char_name"] == nil then
        table.remove(icbat_bpc_cross_character_cache, i)
        return
    elseif recipe_info["profession_id"] == nil then
        table.remove(icbat_bpc_cross_character_cache, i)
        return
    end

    -- if it's not for this character, leave it be
    if recipe_info["qualified_char_name"] ~= qualified_name then
        return
    end
    -- Remove everything for this character
    table.remove(icbat_bpc_cross_character_cache, i)
end

local function clear_cache(qualified_name)
    for i, recipe_info in pairs(icbat_bpc_cross_character_cache) do
        clear_recipe(i, recipe_info, qualified_name)
    end
end

local function scan_for_recipes()
    clear_cache(get_qualified_name())
    local recipes_in_open_profession = C_TradeSkillUI.GetAllRecipeIDs()
    for _i, recipeID in pairs(recipes_in_open_profession) do
        local recipe_info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        if should_track_recipe(recipeID) then
            add_recipe_to_cache(recipeID)
        end
    end
    for _, spell_details in ipairs(profession_spells) do
        add_spell_to_cache(spell_details[1], spell_details[2])
    end

    table.sort(icbat_bpc_cross_character_cache, function(a, b)
        if a["qualified_char_name"] ~= b["qualified_char_name"] then
            return a["qualified_char_name"] < b["qualified_char_name"]
        end

        return a["recipe_name"] < b["recipe_name"]
    end)
end

local function update_cooldown(_, _event, unit, _cast_guid, spell_id)
    if unit ~= "player" then
        return
    end

    if should_track_recipe(spell_id) then
        add_recipe_to_cache(spell_id)
    end
end

-------------
--- View Code
-------------
local function build_tooltip(self)
    self:AddHeader("") -- filled in later w/ colspan
    self:AddSeparator()

    for i, table_entry in ipairs(icbat_bpc_cross_character_cache) do
        local qualified_char_name = table_entry["qualified_char_name"]
        local cooldown_finished_date = table_entry["cooldown_finished_date"]
        local recipe_name = table_entry["recipe_name"]
        local recipe_id = table_entry["recipe_id"]

        if cooldown_finished_date > time() then
            self:AddLine(Ambiguate(qualified_char_name, "all"), recipe_name, "Cooling Down")
            self:SetCellTextColor(self:GetLineCount(), 3, 1, 0.5, 0, 1)
        else
            self:AddLine(Ambiguate(qualified_char_name, "all"), recipe_name, "Ready")
            self:SetCellTextColor(self:GetLineCount(), 3, 0, 1, 0, 1)
        end

        local class_name = icbat_bpc_character_class_name[qualified_char_name]
        if class_name ~= nil then
            local rgb = C_ClassColor.GetClassColor(class_name)
            self:SetCellTextColor(self:GetLineCount(), 1, rgb.r, rgb.g, rgb.b, 1)
        end

        local function drop_from_cache()
            self:Clear()
            table.remove(icbat_bpc_cross_character_cache, i)
        end

        self:SetLineScript(self:GetLineCount(), "OnMouseUp", drop_from_cache)
    end

    self:AddSeparator()
    self:AddLine("") -- filled in later w/ colspan
    self:AddLine("") -- filled in later w/ colspan

    -- lineNum, colNum, value[, font][, justification][, colSpan]
    self:SetCell(1, 1, "Profession Cooldowns", nil, "CENTER", 3)
    self:SetCell(self:GetLineCount() - 1, 1, "To scan for more cooldowns,", nil, "CENTER", 3)
    self:SetCell(self:GetLineCount(), 1, "open and close the profession skills on your characters", nil, "CENTER", 3)

    self:AddLine("") -- spacer
    self:AddLine("") -- filled in later w/ colspan
    self:SetCell(self:GetLineCount(), 1, "Clicking lines will remove it until re-added", nil, "CENTER", 3)
end

--------------------
--- Wiring/LDB/QTip
--------------------

local ADDON, namespace = ...
local LibQTip = LibStub('LibQTip-1.0')
local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local dataobj = ldb:NewDataObject(ADDON, {
    type = "data source",
    text = "Profession Cooldowns"
})

local function OnRelease(self)
    LibQTip:Release(self.tooltip)
    self.tooltip = nil
end

local function anchor_OnEnter(self)
    if self.tooltip then
        LibQTip:Release(self.tooltip)
        self.tooltip = nil
    end

    local tooltip = LibQTip:Acquire(ADDON, 3, "LEFT", "LEFT")
    self.tooltip = tooltip
    tooltip.OnRelease = OnRelease
    tooltip.OnLeave = OnLeave
    tooltip:SetAutoHideDelay(.1, self)

    build_tooltip(tooltip)

    tooltip:SmartAnchorTo(self)

    tooltip:Show()
end

function dataobj:OnEnter()
    anchor_OnEnter(self)
end

--- Nothing to do. Needs to be defined for some display addons apparently
function dataobj:OnLeave()
end

local green = "0000ff00"
local function coloredText(text, color, is_eligible)
    return "\124c" .. color .. text .. "\124r"
end

local function set_label()
    local cooldowns_available = 0
    local qualified_name = get_qualified_name()

    for qualified_char_name, recipe_to_cd in pairs(icbat_bpc_cross_character_cache) do
        if qualified_char_name == qualified_name then
            for recipeID, stored_recipe in pairs(recipe_to_cd) do
                local cooldown_finished_date = stored_recipe["cooldown_finished_date"]

                if cooldown_finished_date < time() then
                    cooldowns_available = cooldowns_available + 1
                end
            end
        end
    end

    if cooldowns_available > 0 then
        dataobj.text = coloredText(cooldowns_available .. " cooldowns available!", green)
    else
        dataobj.text = "Profession Cooldowns"
    end
end

-- invisible frame for updating/hooking events
local f = CreateFrame("frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD") -- on login
f:RegisterEvent("NEW_RECIPE_LEARNED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", set_label)

local g = CreateFrame("frame")
g:RegisterEvent("PLAYER_ENTERING_WORLD") -- on login
g:RegisterEvent("NEW_RECIPE_LEARNED")
g:SetScript("OnEvent", scan_for_recipes)

local h = CreateFrame("frame")
h:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
h:SetScript("OnEvent", update_cooldown)
