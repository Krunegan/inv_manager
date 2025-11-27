--[[

The MIT License (MIT)
Copyright (C) 2025 Flay Krunegan

Permission is hereby granted, free of charge, to any person obtaining a copy of this
software and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

]]

core.register_privilege("inv_manager", {
    description = "Manage players' inventory",
    give_to_singleplayer = false,
})

local quit_flags = {}

local function handle_receive_fields(player, formname, fields)
    if formname:match("^inv_manager:inventory_") or formname:match("^inv_manager:craft_inventory_") or formname:match("^inv_manager:bag_inventory_") or formname:match("^inv_manager:armor_inventory_") then
        if fields.quit then
            local player_name = player:get_player_name()
            quit_flags[player_name] = true
            core.close_formspec(player_name, formname)
            core.after(1, function()
                quit_flags[player_name] = nil
            end)
        end
    end
end

core.register_on_player_receive_fields(handle_receive_fields)

core.register_chatcommand("invm", {
    params = "<player>",
    description = "View and modify a player's main inventory",
    privs = {
        inv_manager = true
    },
    func = function(name, param)
        local player = core.get_player_by_name(name)
        local target_player = core.get_player_by_name(param)

        if not player or not target_player then
            core.chat_send_player(name, "Player not found.")
            return
        end

        if name == param then
            core.chat_send_player(name, "You can't use this command on yourself.")
            return
        end

        local player_inv = player:get_inventory()
        local target_inv = target_player:get_inventory()

        local player_name = player:get_player_name()
        local target_name = target_player:get_player_name()
        local formspec_name = "inv_manager:inventory_" .. player_name
        local formspec = "size[8,10]"
        local quit_button_clicked = false

        local function update_formspec()
            local target_obj = core.get_player_by_name(target_name)
            local player_obj = core.get_player_by_name(player_name)
            if not player_obj or not target_obj or quit_flags[name] then
                core.close_formspec(player_name, formspec_name)
                return
            end

            local target_list_updated = target_inv:get_list("main")
            local player_list_updated = player_inv:get_list("main")

            formspec = "size[8,9]"
            formspec = formspec .. "label[0,0;"..target_name.."'s Inventory]"
            formspec = formspec .. "list[detached:target_inventory_" .. player_name .. ";target_inventory;0,0.55;8,4;]"
            core.create_detached_inventory("target_inventory_" .. player_name, {
                allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return 0
                    end
                    return count
                end,                
                on_put = function(inv, listname, index, stack, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if listname == "target_inventory" then
                        local existing_stack = target_list_updated[index]
                        if existing_stack:is_empty() then
                            target_list_updated[index] = stack
                        else
                            local leftover = existing_stack:add_item(stack)
                            target_list_updated[index] = existing_stack
                            if not leftover:is_empty() then
                                player_inv:add_item("main", leftover)
                            end
                        end
                        target_inv:set_list("main", target_list_updated)
                        core.log("action", name .. " moved " .. stack:get_name() .. " to " .. param .. "'s inventory.")
                    end
                end,
                on_take = function(inv, listname, index, stack, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if listname == "target_inventory" then
                        target_list_updated[index] = ItemStack("")
                        target_inv:set_list("main", target_list_updated)
                        core.log("action", name .. " took " .. stack:get_name() .. " from " .. param .. "'s inventory.")
                    end
                end,
                on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if from_list == "target_inventory" and to_list == "target_inventory" then
                        local stack = target_list_updated[from_index]
                        target_list_updated[from_index] = target_list_updated[to_index]
                        target_list_updated[to_index] = stack
                        target_inv:set_list("main", target_list_updated)
                    end
                end,
            }, player_name):set_list("target_inventory", target_list_updated)

            formspec = formspec .. "label[0,4.55;"..name.."'s Inventory]"
            formspec = formspec .. "list[current_player;main;0,5.08;8,1;]"
            formspec = formspec .. "list[current_player;main;0,6.08;8,3;8]"

            -- formspec = formspec .. "button_exit[6.5,8.2;1,0.5;cancel;Cancel]"

            core.show_formspec(name, formspec_name, formspec)
            core.after(1, update_formspec)
        end

        update_formspec()
    end,
})

core.register_chatcommand("invc", {
    params = "<player>",
    description = "View and modify a player's crafting inventory",
    privs = {
        inv_manager = true
    },
    func = function(name, param)
        local player = core.get_player_by_name(name)
        local target_player = core.get_player_by_name(param)

        if not player or not target_player then
            core.chat_send_player(name, "Player not found.")
            return
        end

        if name == param then
            core.chat_send_player(name, "You can't use this command on yourself.")
            return
        end

        local player_inv = player:get_inventory()
        local target_inv = target_player:get_inventory()

        local player_name = player:get_player_name()
        local target_name = target_player:get_player_name()
        local formspec_name = "inv_manager:craft_inventory_" .. player_name
        local formspec = "size[8,10]"
        local quit_button_clicked = false

        local function update_formspec()
            local target_obj = core.get_player_by_name(target_name)
            local player_obj = core.get_player_by_name(player_name)
            if not player_obj or not target_obj or quit_flags[name] then
                core.close_formspec(player_name, formspec_name)
                return
            end

            local target_craft_list_updated = target_inv:get_list("craft")
            local player_main_list_updated = player_inv:get_list("main")

            formspec = "size[8,9]"
            formspec = formspec .. "label[0,0;"..target_name.."'s Inventory]"
            formspec = formspec .. "list[detached:target_craft_inventory_" .. player_name .. ";target_craft_inventory;0,0.55;3,3;]"
            core.create_detached_inventory("target_craft_inventory_" .. player_name, {
                allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return 0
                    end
                    return count
                end,                
                on_put = function(inv, listname, index, stack, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if listname == "target_craft_inventory" then
                        local existing_stack = target_craft_list_updated[index]
                        if existing_stack:is_empty() then
                            target_craft_list_updated[index] = stack
                        else
                            local leftover = existing_stack:add_item(stack)
                            target_craft_list_updated[index] = existing_stack
                            if not leftover:is_empty() then
                                player_inv:add_item("main", leftover)
                            end
                        end
                        target_inv:set_list("craft", target_craft_list_updated)
                        core.log("action", name .. " moved " .. stack:get_name() .. " to " .. param .. "'s crafting inventory.")
                    end
                end,
                on_take = function(inv, listname, index, stack, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if listname == "target_craft_inventory" then
                        target_craft_list_updated[index] = ItemStack("")
                        target_inv:set_list("craft", target_craft_list_updated)
                        core.log("action", name .. " took " .. stack:get_name() .. " from " .. param .. "'s crafting inventory.")
                    end
                end,
                on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                    local player_name = player:get_player_name()
                    if not core.check_player_privs(player_name, {inv_manager=true}) then
                        core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                        return
                    end
                    if from_list == "target_craft_inventory" and to_list == "target_craft_inventory" then
                        local stack = target_craft_list_updated[from_index]
                        target_craft_list_updated[from_index] = target_craft_list_updated[to_index]
                        target_craft_list_updated[to_index] = stack
                        target_inv:set_list("craft", target_craft_list_updated)
                    end
                end,
            }, player_name):set_list("target_craft_inventory", target_craft_list_updated)

            formspec = formspec .. "label[0,4.55;"..name.."'s Inventory]"
            formspec = formspec .. "list[current_player;main;0,5.08;8,1;]"
            formspec = formspec .. "list[current_player;main;0,6.08;8,3;8]"

            -- formspec = formspec .. "button_exit[6.5,8.2;1,0.5;cancel;Cancel]"

            core.show_formspec(name, formspec_name, formspec)
            core.after(1, update_formspec)
        end

        update_formspec()
    end,
})

if core.get_modpath("unified_inventory") then
    core.register_chatcommand("invb", {
        params = "<player> <bag_number>",
        description = "View and modify a player's bag inventory",
        privs = {
            inv_manager = true
        },
        func = function(name, param)
            local args = param:split(" ")
            if #args ~= 2 then
                core.chat_send_player(name, "Usage: /invb <player> <bag_number>")
                return
            end

            local target_player = core.get_player_by_name(args[1])
            local bag_number = tonumber(args[2])

            if not target_player or not bag_number or bag_number < 1 or bag_number > 4 then
                core.chat_send_player(name, "Invalid player or bag number.")
                return
            end

            local player_inv = core.get_player_by_name(name):get_inventory()
            local target_inv = target_player:get_inventory()
            local player_name = name
            local target_name = target_player:get_player_name()
            local formspec_name = "inv_manager:bag_inventory_" .. player_name
            local formspec = "size[8,10]"
            local quit_button_clicked = false

            local function update_formspec()
                local target_obj = core.get_player_by_name(target_name)
                local player_obj = core.get_player_by_name(player_name)
                if not player_obj or not target_obj or quit_flags[name] then
                    core.close_formspec(player_name, formspec_name)
                    return
                end

                local target_bag_list_updated = target_inv:get_list("bag" .. bag_number .. "contents")
                local player_main_list_updated = player_inv:get_list("main")

                formspec = "size[8,9]"
                formspec = formspec .. "label[0,0;"..target_name.."'s Bag "..bag_number.." Inventory]"
                formspec = formspec .. "list[detached:target_bag_inventory_" .. player_name .. ";target_bag_inventory;0,0.55;8,4;]"
                core.create_detached_inventory("target_bag_inventory_" .. player_name, {
                    allow_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                        local player_name = player:get_player_name()
                        if not core.check_player_privs(player_name, {inv_manager=true}) then
                            core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                            return 0
                        end
                        return count
                    end,
                    on_put = function(inv, listname, index, stack, player)
                        local player_name = player:get_player_name()
                        if not core.check_player_privs(player_name, {inv_manager=true}) then
                            core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                            return
                        end
                        if listname == "target_bag_inventory" then
                            local existing_stack = target_bag_list_updated[index]
                            if existing_stack:is_empty() then
                                target_bag_list_updated[index] = stack
                            else
                                local leftover = existing_stack:add_item(stack)
                                target_bag_list_updated[index] = existing_stack
                                if not leftover:is_empty() then
                                    player_inv:add_item("main", leftover)
                                end
                            end
                            target_inv:set_list("bag" .. bag_number .. "contents", target_bag_list_updated)
                            core.log("action", name .. " moved " .. stack:get_name() .. " to " .. target_name .. "'s bag "..bag_number.." inventory.")
                        end
                    end,
                    on_take = function(inv, listname, index, stack, player)
                        local player_name = player:get_player_name()
                        if not core.check_player_privs(player_name, {inv_manager=true}) then
                            core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                            return
                        end
                        if listname == "target_bag_inventory" then
                            target_bag_list_updated[index] = ItemStack("")
                            target_inv:set_list("bag" .. bag_number .. "contents", target_bag_list_updated)
                            core.log("action", name .. " took " .. stack:get_name() .. " from " .. target_name .. "'s bag "..bag_number.." inventory.")
                        end
                    end,
                    on_move = function(inv, from_list, from_index, to_list, to_index, count, player)
                        local player_name = player:get_player_name()
                        if not core.check_player_privs(player_name, {inv_manager=true}) then
                            core.chat_send_player(player_name, "You no longer have the 'inv_manager' privilege.")
                            return
                        end
                        if from_list == "target_bag_inventory" and to_list == "target_bag_inventory" then
                            local stack = target_bag_list_updated[from_index]
                            target_bag_list_updated[from_index] = target_bag_list_updated[to_index]
                            target_bag_list_updated[to_index] = stack
                            target_inv:set_list("bag" .. bag_number .. "contents", target_bag_list_updated)
                        end
                    end,
                }, player_name):set_list("target_bag_inventory", target_bag_list_updated)

                formspec = formspec .. "label[0,4.55;"..name.."'s Inventory]"
                formspec = formspec .. "list[current_player;main;0,5.08;8,1;]"
                formspec = formspec .. "list[current_player;main;0,6.08;8,3;8]"

                core.show_formspec(name, formspec_name, formspec)
                core.after(1, update_formspec)
            end

            update_formspec()
        end,
    })
end

if core.get_modpath("3d_armor") then
    core.register_chatcommand("inva", {
        params = "<player>",
        description = "View a player's armor inventory",
        privs = {
            inv_manager = true
        },
        func = function(name, param)
            local player = core.get_player_by_name(name)
            local target_player = core.get_player_by_name(param)

            if not player or not target_player then
                return false, "Player not found."
            end

            if name == param then
                return false, "You cannot view your own armor with this command."
            end

            local real_detached_name = param .. "_armor"
            local real_detached_inv = core.get_inventory({type="detached", name=real_detached_name})
            if not real_detached_inv then
                return false, "The player does not have an available armor inventory."
            end

            local armor_size = real_detached_inv:get_size("armor") or 0
            local view_detached_name = "inv_manager_view_armor_" .. param
            local view_detached_inv = core.get_inventory({type="detached", name=view_detached_name})
            if not view_detached_inv then
                view_detached_inv = core.create_detached_inventory(view_detached_name, {
                    allow_move = function()
                        return 0
                    end,
                    allow_put = function()
                        return 0
                    end,
                    allow_take = function()
                        return 0
                    end,
                })
                view_detached_inv:set_size("armor", armor_size)
            end
            local player_name = name
            local target_name = param
            local formspec_name = "inv_manager:armor_inventory_" .. player_name

            local function update_formspec()
                local target_obj = core.get_player_by_name(target_name)
                if not target_obj or quit_flags[player_name] then
                    core.close_formspec(player_name, formspec_name)
                    return
                end
                for i = 1, armor_size do
                    local real_stack = real_detached_inv:get_stack("armor", i)
                    view_detached_inv:set_stack("armor", i, real_stack)
                end
                local formspec = "size[8,6]"
                    .. "label[0,0;" .. target_name .. "'s Armor Inventory (Read-Only)]"
                    .. "list[detached:" .. view_detached_name .. ";armor;0,1;" .. armor_size .. ",1]"
                    .. "list[current_player;main;0,3;8,3]"
                core.show_formspec(player_name, formspec_name, formspec)
                core.after(1, update_formspec)
            end

            update_formspec()
        end,
    })
end
