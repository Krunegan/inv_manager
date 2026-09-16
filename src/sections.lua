local S = inv_manager.S

inv_manager.sections = {}
inv_manager.section_order = {}

function inv_manager.register_section(name, def)
    def.name = name
    def.order = def.order or 100
    inv_manager.sections[name] = def

    local order = inv_manager.section_order
    for i = #order, 1, -1 do
        if order[i].name == name then
            table.remove(order, i)
        end
    end
    order[#order + 1] = def
    table.sort(order, function(a, b) return a.order < b.order end)
end

-- Sections the given online player has
function inv_manager.get_available_sections(player)
    local out = {}
    for _, def in ipairs(inv_manager.section_order) do
        if not def.hidden and def.get(player) then
            out[#out + 1] = def
        end
    end
    return out
end

-- Usable slots of a section list
function inv_manager.section_size(def, player, inv, listname)
    local size = inv:get_size(listname)
    if def.size then
        size = math.min(size, def.size(player))
    end
    return size
end

-- Section that manages a player inventory list, if any
function inv_manager.section_for_player_list(player, listname)
    for _, def in ipairs(inv_manager.section_order) do
        if not def.external then
            local inv, list = def.get(player)
            if inv and list == listname then
                return def
            end
        end
    end
end

-- Replaces a whole section list, running the section hooks
function inv_manager.apply_list(player, def, new_list)
    local inv, listname = def.get(player)
    if not inv then
        return false
    end

    if def.resize and #new_list > inv:get_size(listname) then
        inv:set_size(listname, #new_list)
    end

    local changes = {}
    local size = inv:get_size(listname)
    for i = 1, size do
        local old = inv:get_stack(listname, i)
        local new = ItemStack(new_list[i])
        if not old:equals(new) then
            inv:set_stack(listname, i, new)
            changes[#changes + 1] = {index = i, old = old, new = new}
        end
    end

    -- Items that don't fit (the list is smaller now)
    local player_inv = player:get_inventory()
    for i = size + 1, #new_list do
        local leftover = player_inv:add_item("main", ItemStack(new_list[i]))
        if not leftover:is_empty() then
            core.add_item(player:get_pos(), leftover)
        end
    end

    if #changes > 0 and def.on_change then
        def.on_change(player, changes)
    end
    return true
end

local function player_list(listname)
    return function(player)
        local inv = player:get_inventory()
        if inv and inv:get_size(listname) > 0 then
            return inv, listname
        end
    end
end

inv_manager.register_section("main", {
    title = S("Main"),
    order = 10,
    get = player_list("main"),
})

inv_manager.register_section("craft", {
    title = S("Crafting"),
    order = 20,
    get = player_list("craft"),
})

if core.get_modpath("unified_inventory") then
    local S_bag_first = S("Empty the bag before removing it.")
    local META_KEY = "unified_inventory:bags"

    local function bags_detached(player)
        return core.get_inventory({type = "detached", name = player:get_player_name() .. "_bags"})
    end

    local function bag_slots_inv(player)
        local inv = player:get_inventory()
        if inv:get_size("bag1") > 0 then
            return inv -- old version
        end
        local detached = bags_detached(player)
        if detached and detached:get_size("bag1") > 0 then
            return detached
        end
    end

    local function bag_stack(player, i)
        local inv = bag_slots_inv(player)
        return inv and inv:get_stack("bag" .. i, 1) or ItemStack()
    end

    local function save_bags_meta(player, inv)
        local bags, empty = {}, true
        for i = 1, 4 do
            local stack = inv:get_stack("bag" .. i, 1)
            if not stack:is_empty() then
                bags[i] = stack:get_name()
                empty = false
            end
        end
        player:get_meta():set_string(META_KEY, empty and "" or core.serialize(bags))
    end

    local function bag_slots(player)
        local inv = bag_slots_inv(player)
        if not inv then
            return nil
        end
        local adapter = {}
        function adapter:get_size() return 4 end
        function adapter:get_width() return 4 end
        function adapter:get_stack(_, i) return inv:get_stack("bag" .. i, 1) end
        function adapter:set_stack(_, i, stack) inv:set_stack("bag" .. i, 1, stack) end
        function adapter:get_list()
            local list = {}
            for i = 1, 4 do
                list[i] = inv:get_stack("bag" .. i, 1)
            end
            return list
        end
        return adapter, "bags"
    end

    local function notify_moderators(player, message)
        for name, sess in pairs(inv_manager.sessions) do
            if sess.target == player:get_player_name() then
                core.chat_send_player(name, message)
            end
        end
    end

    inv_manager.register_section("bags", {
        title = S("Bags"),
        order = 30,
        external = true,
        get = bag_slots,
        disable_move = true,
        allow_put = function(player, inv, listname, index, stack)
            local def = stack:get_definition()
            if not (def and def.groups and def.groups.bagslots) then
                return 0
            end
            if not player:get_inventory():is_empty("bag" .. index .. "contents") then
                return 0
            end
            return 1
        end,
        allow_take = function(player, inv, listname, index, stack, silent)
            if player:get_inventory():is_empty("bag" .. index .. "contents") then
                return stack:get_count()
            end
            if not silent then
                notify_moderators(player, S_bag_first)
            end
            return 0
        end,
        on_change = function(player, changes)
            local inv = player:get_inventory()
            local legacy = inv:get_size("bag1") > 0
            for _, change in ipairs(changes) do
                local contents = "bag" .. change.index .. "contents"
                if not change.new:is_empty() then
                    local slots = change.new:get_definition().groups.bagslots or 0
                    local used = 0
                    for i, stack in ipairs(inv:get_list(contents) or {}) do
                        if not stack:is_empty() then
                            used = i
                        end
                    end
                    inv:set_size(contents, math.max(slots, used))
                elseif not legacy then
                    inv:set_size(contents, 0)
                end
                local ui = rawget(_G, "unified_inventory")
                local name = player:get_player_name()
                if change.new:is_empty() and ui and ui.current_page
                        and ui.current_page[name] == "bag" .. change.index then
                    ui.set_inventory_formspec(player, "bags")
                end
            end
            if not legacy then
                save_bags_meta(player, bags_detached(player))
            end
        end,
    })

    for i = 1, 4 do
        local get_contents = player_list("bag" .. i .. "contents")
        inv_manager.register_section("bag" .. i, {
            title = S("Bag @1", i),
            order = 30 + i,
            resize = true,
            get = function(player)
                if bag_stack(player, i):is_empty() then
                    return nil
                end
                return get_contents(player)
            end,
            allow_put = function(player, inv, listname, index, stack)
                local def = stack:get_definition()
                if def and def.groups and def.groups.bagslots then
                    return 0
                end
                return stack:get_count()
            end,
        })
    end
end

-- Armors

if core.get_modpath("3d_armor") and rawget(_G, "armor") then
    local I3_ARMOR_SLOTS = {"armor_head", "armor_torso", "armor_legs", "armor_feet", "armor_shield"}

    local function i3_armor()
        return rawget(_G, "i3") and i3.modules and i3.modules.armor
    end

    inv_manager.register_section("armor", {
        title = S("Armor"),
        order = 40,
        external = true,
        get = function(player)
            local inv = core.get_inventory({
                type = "detached",
                name = player:get_player_name() .. "_armor",
            })
            if inv and inv:get_size("armor") > 0 then
                return inv, "armor"
            end
        end,
        size = function(player)
            return i3_armor() and #I3_ARMOR_SLOTS or 6
        end,
        allow_put = function(player, inv, listname, index, stack)
            local element = armor:get_element(stack:get_name())
            if not element then
                return 0
            end
            if i3_armor() then
                local group = I3_ARMOR_SLOTS[index]
                local groups = stack:get_definition().groups or {}
                if not group or (groups[group] or 0) <= 0 then
                    return 0
                end
            end
            for i = 1, inv:get_size(listname) do
                if i ~= index then
                    local def = inv:get_stack(listname, i):get_definition()
                    if def and def.groups and def.groups["armor_" .. element] then
                        return 0
                    end
                end
            end
            return 1
        end,
        on_change = function(player, changes)
            for _, change in ipairs(changes) do
                if not change.old:is_empty() then
                    armor:run_callbacks("on_unequip", player, change.index, change.old)
                end
                if not change.new:is_empty() then
                    armor:run_callbacks("on_equip", player, change.index, change.new)
                end
            end
            armor:save_armor_inventory(player)
            armor:set_player_armor(player)
        end,
    })
elseif core.get_modpath("mcl_armor") and rawget(_G, "mcl_armor") then
    inv_manager.register_section("armor", {
        title = S("Armor"),
        order = 40,
        get = player_list("armor"),
        allow_put = function(player, inv, listname, index, stack)
            local def = stack:get_definition()
            local element = def and mcl_armor.elements[def._mcl_armor_element or ""]
            if not element or element.index ~= index then
                return 0
            end
            return 1
        end,
        on_change = function(player, changes)
            for _, change in ipairs(changes) do
                if not change.old:is_empty() then
                    mcl_armor.on_unequip(change.old, player)
                end
                if not change.new:is_empty() then
                    mcl_armor.on_equip(change.new, player)
                end
            end
            mcl_armor.update(player)
        end,
    })
end

-- MineClone / VoxeLibre / Mineclonia

if core.get_modpath("mcl_offhand") then
    inv_manager.register_section("offhand", {
        title = S("Offhand"),
        order = 45,
        get = player_list("offhand"),
    })
end

if core.get_modpath("mcl_chests") then
    inv_manager.register_section("enderchest", {
        title = S("Ender chest"),
        order = 50,
        get = player_list("enderchest"),
    })
end

if core.get_modpath("i3") and rawget(_G, "i3") then
    local i3_S = core.get_translator("i3")

    local function i3_inv(kind, player)
        return core.get_inventory({
            type = "detached",
            name = "i3_" .. kind .. "_" .. player:get_player_name(),
        })
    end

    local function i3_data(player)
        return i3.data and i3.data[player:get_player_name()]
    end

    local function refresh_i3(player)
        if i3_data(player) and i3.set_fs then
            i3.set_fs(player)
        end
    end

    local function save_bag_content(player)
        local bag = i3_inv("bag", player)
        local content = i3_inv("bag_content", player)
        if not bag or not content then
            return
        end
        local bagstack = bag:get_stack("main", 1)
        if bagstack:is_empty() then
            return
        end

        local info = core.get_player_information(player:get_player_name())
        local desc = core.get_translated_string(info and info.lang_code or "",
            ItemStack(bagstack:get_name()):get_description())
        desc = (desc:split("(")[1] or desc):trim():upper()

        local meta = bagstack:get_meta()
        if content:is_empty("main") then
            meta:set_string("description", desc)
            meta:set_string("content", "")
        else
            local t, used = {}, 0
            for i, stack in ipairs(content:get_list("main")) do
                if not stack:is_empty() then
                    used = used + 1
                    t[i] = stack:to_string()
                end
            end
            local bag_size = core.get_item_group(bagstack:get_name(), "bag")
            local percent = ("%d"):format((used * 100) / (bag_size * 4))
            meta:set_string("description",
                core.formspec_escape(i3_S("@1 (@2% full)", desc, percent)))
            meta:set_string("content", core.serialize(t))
        end

        bag:set_stack("main", 1, bagstack)
        local data = i3_data(player)
        if data then
            data.bag = bagstack:to_string()
        end
    end

    local function load_bag_content(player)
        local bag = i3_inv("bag", player)
        local content = i3_inv("bag_content", player)
        if not bag or not content then
            return
        end
        local bagstack = bag:get_stack("main", 1)
        local data = i3_data(player)
        if data then
            data.bag = not bagstack:is_empty() and bagstack:to_string() or nil
        end

        local saved = not bagstack:is_empty()
            and core.deserialize(bagstack:get_meta():get_string("content")) or {}
        local list = {}
        for i = 1, content:get_size("main") do
            list[i] = ItemStack(saved[i])
        end
        content:set_list("main", list)
    end

    local function is_bag(stack)
        local group = core.get_item_group(stack:get_name(), "bag")
        return group > 0 and group <= 4
    end

    inv_manager.register_section("i3_bag", {
        title = S("Backpack (item)"),
        order = 29,
        external = true,
        hidden = true,
        get = function(player)
            local inv = i3_inv("bag", player)
            if inv and inv:get_size("main") > 0 then
                return inv, "main"
            end
        end,
        allow_put = function(player, inv, listname, index, stack)
            return is_bag(stack) and 1 or 0
        end,
        on_change = function(player)
            load_bag_content(player)
            refresh_i3(player)
        end,
    })

    inv_manager.register_section("i3_bag_content", {
        title = S("Backpack"),
        order = 30,
        external = true,
        get = function(player)
            local bag = i3_inv("bag", player)
            local inv = i3_inv("bag_content", player)
            if bag and inv and not bag:is_empty("main") and inv:get_size("main") > 0 then
                return inv, "main"
            end
        end,
        size = function(player)
            local bag = i3_inv("bag", player)
            return bag and core.get_item_group(bag:get_stack("main", 1):get_name(), "bag") * 4 or 0
        end,
        allow_put = function(player, inv, listname, index, stack)
            -- i3 doesn't allow bags inside bags
            if core.deserialize(stack:get_meta():get_string("content")) then
                return 0
            end
            return stack:get_count()
        end,
        on_change = function(player)
            save_bag_content(player)
            refresh_i3(player)
        end,
    })
end
