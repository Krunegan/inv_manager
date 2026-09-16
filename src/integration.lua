local S = inv_manager.S
local util = inv_manager.util

if core.get_modpath("unified_inventory") and rawget(_G, "unified_inventory") then
    unified_inventory.register_button("inv_manager", {
        type = "image",
        image = "inv_manager_icon.png",
        tooltip = S("Inventory manager"),
        condition = function(player)
            return util.can_view(player:get_player_name())
        end,
        action = function(player)
            local name = player:get_player_name()
            if util.can_view(name) then
                inv_manager.show_picker(name)
            end
        end,
    })
end

if core.get_modpath("sfinv") and rawget(_G, "sfinv") and sfinv.enabled ~= false then
    sfinv.register_page("inv_manager:players", {
        title = S("Players"),
        is_in_nav = function(self, player)
            return util.can_view(player:get_player_name())
        end,
        get = function(self, player, context)
            return sfinv.make_formspec(player, context,
                "label[0,0.2;" .. core.formspec_escape(S("Inventory manager")) .. "]" ..
                "button[0,1;3,1;inv_manager_open;" ..
                core.formspec_escape(S("Choose a player")) .. "]", true)
        end,
        on_player_receive_fields = function(self, player, context, fields)
            local name = player:get_player_name()
            if fields.inv_manager_open and util.can_view(name) then
                inv_manager.show_picker(name)
                return true
            end
        end,
    })
end

-- Embedded player list (i3 and VoxeLibre tabs)

local tab_players = {}

local function online_players(name)
    local names = {}
    for _, player in ipairs(core.get_connected_players()) do
        local pname = player:get_player_name()
        if pname ~= name or inv_manager.settings.allow_self then
            names[#names + 1] = pname
        end
    end
    table.sort(names)
    tab_players[name] = names
    return names
end

local function player_list_fs(name, x, y, w, h)
    local F = core.formspec_escape
    local items = {}
    for i, pname in ipairs(online_players(name)) do
        items[i] = F(pname)
    end
    return table.concat({
        ("label[%s,%s;%s]"):format(x, y, F(S("Online players (double click to open)"))),
        ("textlist[%s,%s;%s,%s;inv_manager_player;%s;0;false]"):format(
            x, y + 0.4, w, h - 1.5, table.concat(items, ",")),
        ("button[%s,%s;%s,0.8;inv_manager_open;%s]"):format(
            x, y + h - 0.8, w, F(S("Choose a player"))),
    })
end

-- Returns true if the fields were handled
local function player_list_fields(player, fields)
    local name = player:get_player_name()
    if not util.can_view(name) then
        return false
    end
    if fields.inv_manager_open then
        inv_manager.show_picker(name)
        return true
    end
    if fields.inv_manager_player then
        local event = core.explode_textlist_event(fields.inv_manager_player)
        local target = event.type == "DCL" and (tab_players[name] or {})[event.index]
        if target then
            local ok, err = inv_manager.open(name, target)
            if not ok then
                core.chat_send_player(name, err)
            end
        end
        return true
    end
    return false
end

core.register_on_leaveplayer(function(player)
    tab_players[player:get_player_name()] = nil
end)

if core.get_modpath("i3") and rawget(_G, "i3") and i3.new_tab then
    local ok, err = pcall(i3.new_tab, "inv_manager", {
        description = S("Players"),
        image = "inv_manager_icon.png",
        access = function(player)
            return util.can_view(player:get_player_name())
        end,
        formspec = function(player, data, fs)
            fs(player_list_fs(player:get_player_name(), 0.5, 0.8, 9.23, 10.6))
        end,
        fields = function(player, data, fields)
            if player_list_fields(player, fields) then
                return false
            end
        end,
    })
    if not ok then
        core.log("warning", "[inv_manager] Couldn't add the i3 tab: " .. tostring(err))
    end
end

if core.get_modpath("mcl_inventory") and rawget(_G, "mcl_inventory")
        and mcl_inventory.register_survival_inventory_tab then
    local ok, err = pcall(mcl_inventory.register_survival_inventory_tab, {
        id = "inv_manager",
        description = S("Inventory manager"),
        item_icon = "mcl_chests:chest",
        show_inventory = false,
        access = function(player)
            return util.can_view(player:get_player_name())
        end,
        build = function(player)
            return player_list_fs(player:get_player_name(), 0.375, 0.375, 11, 9.5)
        end,
        handle = function(player, fields)
            player_list_fields(player, fields)
        end,
    })
    if not ok then
        core.log("warning", "[inv_manager] Couldn't add the VoxeLibre tab: " .. tostring(err))
    end
end
