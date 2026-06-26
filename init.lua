--[[

The MIT License (MIT)
Copyright (C) 2026 Flay Krunegan

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

core.register_on_leaveplayer(function(player)
    local pname = player:get_player_name()
    quit_flags[pname] = true
    core.remove_detached_inventory("target_inventory_" .. pname)
    core.remove_detached_inventory("target_craft_inventory_" .. pname)
    core.remove_detached_inventory("target_bag_inventory_" .. pname)
end)

local function handle_receive_fields(player, formname, fields)
    if formname:sub(1, 12) == "inv_manager:" then
        if fields.quit then
            local pname = player:get_player_name()
            quit_flags[pname] = true
            core.close_formspec(pname, formname)
            core.remove_detached_inventory("target_inventory_" .. pname)
            core.remove_detached_inventory("target_craft_inventory_" .. pname)
            core.remove_detached_inventory("target_bag_inventory_" .. pname)
            core.after(2, function()
                quit_flags[pname] = nil
            end)
        end
    end
end

core.register_on_player_receive_fields(handle_receive_fields)

local function create_managed_inventory(inv_name, list_name, target_inv, real_list_name, moderator, target, log_suffix)
    local function check_privs(actor_name)
        if not core.check_player_privs(actor_name, {inv_manager = true}) then
            core.chat_send_player(actor_name, "You no longer have the 'inv_manager' privilege.")
            return false
        end
        return true
    end

    local function slot_is_stale(detached_inv, listname, index)
        local detached_stack = detached_inv:get_stack(listname, index)
        local real_stack = target_inv:get_stack(real_list_name, index)
        return not detached_stack:equals(real_stack)
    end

    local function force_resync(detached_inv)
        detached_inv:set_list(list_name, target_inv:get_list(real_list_name))
    end

    local callbacks = {
        allow_move = function(inv, from_list, from_index, to_list, to_index, count, actor)
            local actor_name = actor:get_player_name()
            if not check_privs(actor_name) then return 0 end

            if slot_is_stale(inv, from_list, from_index) or slot_is_stale(inv, to_list, to_index) then
                core.chat_send_player(actor_name, target .. "'s inventory changed, refreshing...")
                force_resync(inv)
                return 0
            end
            return count
        end,
        allow_put = function(inv, listname, index, stack, actor)
            local actor_name = actor:get_player_name()
            if not check_privs(actor_name) then return 0 end

            if slot_is_stale(inv, listname, index) then
                core.chat_send_player(actor_name, target .. "'s inventory changed, refreshing...")
                force_resync(inv)
                return 0
            end
            return stack:get_count()
        end,
        allow_take = function(inv, listname, index, stack, actor)
            local actor_name = actor:get_player_name()
            if not check_privs(actor_name) then return 0 end

            if slot_is_stale(inv, listname, index) then
                core.chat_send_player(actor_name, target .. "'s inventory changed, refreshing...")
                force_resync(inv)
                return 0
            end
            return stack:get_count()
        end,
        on_put = function(inv, listname, index, stack, actor)
            target_inv:set_stack(real_list_name, index, inv:get_stack(listname, index))
            core.log("action", moderator .. " moved " .. stack:get_name() ..
                " to " .. target .. "'s " .. log_suffix .. ".")
        end,
        on_take = function(inv, listname, index, stack, actor)
            target_inv:set_stack(real_list_name, index, ItemStack())
            core.log("action", moderator .. " took " .. stack:get_name() ..
                " from " .. target .. "'s " .. log_suffix .. ".")
        end,
        on_move = function(inv, from_list, from_index, to_list, to_index, count, actor)
            target_inv:set_stack(real_list_name, from_index, inv:get_stack(from_list, from_index))
            target_inv:set_stack(real_list_name, to_index,   inv:get_stack(to_list,   to_index))
        end,
    }

    local detached = core.create_detached_inventory(inv_name, callbacks, moderator)
    detached:set_list(list_name, target_inv:get_list(real_list_name))
    return detached
end

local function sync_detached_from_real(inv_name, list_name, target_inv, real_list_name)
    local detached = core.get_inventory({type = "detached", name = inv_name})
    if detached then
        detached:set_list(list_name, target_inv:get_list(real_list_name))
    end
end

core.register_chatcommand("invm", {
    params = "<player>",
    description = "View and modify a player's main inventory",
    privs = {inv_manager = true},
    func = function(moderator, param)
        local target_name = param:match("^%S+$")
        if not target_name or target_name == "" then
            core.chat_send_player(moderator, "Usage: /invm <player>")
            return
        end

        if moderator == target_name then
            core.chat_send_player(moderator, "You can't use this command on yourself.")
            return
        end

        local mod_player = core.get_player_by_name(moderator)
        local target_player = core.get_player_by_name(target_name)

        if not mod_player then
            return
        end
        if not target_player then
            core.chat_send_player(moderator, "Player '" .. target_name .. "' not found.")
            return
        end

        local target_inv = target_player:get_inventory()
        local inv_name   = "target_inventory_" .. moderator
        local list_name  = "target_inventory"
        local formspec_name = "inv_manager:inventory_" .. moderator

        quit_flags[moderator] = nil
        create_managed_inventory(inv_name, list_name, target_inv, "main",
            moderator, target_name, "inventory")

        local function update_formspec()
            if quit_flags[moderator] then return end
            if not core.get_player_by_name(moderator) then
                quit_flags[moderator] = true
                return
            end

            if not core.get_player_by_name(target_name) then
                core.chat_send_player(moderator, target_name .. " has left the server.")
                quit_flags[moderator] = true
                core.close_formspec(moderator, formspec_name)
                return
            end

            sync_detached_from_real(inv_name, list_name, target_inv, "main")

            local fs = {
                "size[8,9]",
                "label[0,0;", core.formspec_escape(target_name), "'s Inventory]",
                "list[detached:", inv_name, ";", list_name, ";0,0.55;8,4;]",
                "label[0,4.55;", core.formspec_escape(moderator), "'s Inventory]",
                "list[current_player;main;0,5.08;8,1;]",
                "list[current_player;main;0,6.08;8,3;8]",
            }
            core.show_formspec(moderator, formspec_name, table.concat(fs))
            core.after(1, update_formspec)
        end

        update_formspec()
    end,
})

core.register_chatcommand("invc", {
    params = "<player>",
    description = "View and modify a player's crafting inventory",
    privs = {inv_manager = true},
    func = function(moderator, param)
        local target_name = param:match("^%S+$")
        if not target_name or target_name == "" then
            core.chat_send_player(moderator, "Usage: /invc <player>")
            return
        end

        if moderator == target_name then
            core.chat_send_player(moderator, "You can't use this command on yourself.")
            return
        end

        local mod_player    = core.get_player_by_name(moderator)
        local target_player = core.get_player_by_name(target_name)

        if not mod_player then return end
        if not target_player then
            core.chat_send_player(moderator, "Player '" .. target_name .. "' not found.")
            return
        end

        local target_inv    = target_player:get_inventory()
        local inv_name      = "target_craft_inventory_" .. moderator
        local list_name     = "target_craft_inventory"
        local formspec_name = "inv_manager:craft_inventory_" .. moderator

        quit_flags[moderator] = nil
        create_managed_inventory(inv_name, list_name, target_inv, "craft",
            moderator, target_name, "crafting inventory")

        local function update_formspec()
            if quit_flags[moderator] then return end
            if not core.get_player_by_name(moderator) then
                quit_flags[moderator] = true
                return
            end
            if not core.get_player_by_name(target_name) then
                core.chat_send_player(moderator, target_name .. " has left the server.")
                quit_flags[moderator] = true
                core.close_formspec(moderator, formspec_name)
                return
            end

            sync_detached_from_real(inv_name, list_name, target_inv, "craft")

            local fs = {
                "size[8,9]",
                "label[0,0;", core.formspec_escape(target_name), "'s Crafting Inventory]",
                "list[detached:", inv_name, ";", list_name, ";0,0.55;3,3;]",
                "label[0,4.55;", core.formspec_escape(moderator), "'s Inventory]",
                "list[current_player;main;0,5.08;8,1;]",
                "list[current_player;main;0,6.08;8,3;8]",
            }
            core.show_formspec(moderator, formspec_name, table.concat(fs))
            core.after(1, update_formspec)
        end

        update_formspec()
    end,
})

if core.get_modpath("unified_inventory") then
    core.register_chatcommand("invb", {
        params = "<player> <bag_number>",
        description = "View and modify a player's bag inventory (1-4)",
        privs = {inv_manager = true},
        func = function(moderator, param)
            local args = param:split(" ")
            if #args ~= 2 then
                core.chat_send_player(moderator, "Usage: /invb <player> <bag_number>")
                return
            end

            local target_name = args[1]
            local bag_number  = tonumber(args[2])

            if not bag_number or bag_number < 1 or bag_number > 4 then
                core.chat_send_player(moderator, "Bag number must be between 1 and 4.")
                return
            end

            if moderator == target_name then
                core.chat_send_player(moderator, "You can't use this command on yourself.")
                return
            end

            local mod_player    = core.get_player_by_name(moderator)
            local target_player = core.get_player_by_name(target_name)

            if not mod_player then return end
            if not target_player then
                core.chat_send_player(moderator, "Player '" .. target_name .. "' not found.")
                return
            end

            local real_list_name = "bag" .. bag_number .. "contents"
            local target_inv     = target_player:get_inventory()

            if not target_inv:get_list(real_list_name) then
                core.chat_send_player(moderator, target_name .. " has no bag " .. bag_number .. ".")
                return
            end

            local inv_name      = "target_bag_inventory_" .. moderator
            local list_name     = "target_bag_inventory"
            local formspec_name = "inv_manager:bag_inventory_" .. moderator

            quit_flags[moderator] = nil
            create_managed_inventory(inv_name, list_name, target_inv, real_list_name,
                moderator, target_name, "bag " .. bag_number .. " inventory")

            local function update_formspec()
                if quit_flags[moderator] then return end
                if not core.get_player_by_name(moderator) then
                    quit_flags[moderator] = true
                    return
                end
                if not core.get_player_by_name(target_name) then
                    core.chat_send_player(moderator, target_name .. " has left the server.")
                    quit_flags[moderator] = true
                    core.close_formspec(moderator, formspec_name)
                    return
                end

                sync_detached_from_real(inv_name, list_name, target_inv, real_list_name)

                local fs = {
                    "size[8,9]",
                    "label[0,0;", core.formspec_escape(target_name),
                        "'s Bag ", tostring(bag_number), " Inventory]",
                    "list[detached:", inv_name, ";", list_name, ";0,0.55;8,4;]",
                    "label[0,4.55;", core.formspec_escape(moderator), "'s Inventory]",
                    "list[current_player;main;0,5.08;8,1;]",
                    "list[current_player;main;0,6.08;8,3;8]",
                }
                core.show_formspec(moderator, formspec_name, table.concat(fs))
                core.after(1, update_formspec)
            end

            update_formspec()
        end,
    })
end