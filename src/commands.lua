local S = inv_manager.S
local db = inv_manager.db
local util = inv_manager.util

local function open(name, target, section)
    local ok, err = inv_manager.open(name, target, section)
    if not ok then
        return false, err
    end
    return true
end

local function view_command(section, description)
    return {
        params = S("<player>"),
        description = description,
        func = function(name, param)
            if not util.can_view(name) then
                return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
            end
            local target = param:trim()
            if target == "" or target:find("%s") then
                return false, S("Usage: /@1 <player>", "inv" .. section:sub(1, 1))
            end
            return open(name, target, section)
        end,
    }
end

core.register_chatcommand("inv", {
    params = S("[<player> [<section>]]"),
    description = S("Open the inventory manager (without arguments: list of online players)"),
    func = function(name, param)
        if not util.can_view(name) then
            return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
        end
        local args = param:trim():split(" ")
        if #args == 0 then
            inv_manager.show_picker(name)
            return true
        end
        return open(name, args[1], args[2])
    end,
})

core.register_chatcommand("invm", view_command("main", S("Open a player's main inventory")))
core.register_chatcommand("invc", view_command("craft", S("Open a player's crafting grid")))

if core.get_modpath("unified_inventory") then
    core.register_chatcommand("invb", {
        params = S("<player> [<bag number>]"),
        description = S("Open a player's bags (without number: the bag slots)"),
        func = function(name, param)
            if not util.can_view(name) then
                return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
            end
            local target, bag = param:trim():match("^(%S+)%s*(%S*)$")
            if not target then
                return false, S("Usage: /invb <player> [<bag number>]")
            end
            if bag == "" then
                return open(name, target, "bags")
            end
            bag = tonumber(bag)
            if not bag or bag < 1 or bag > 4 then
                return false, S("The bag number must be between 1 and 4.")
            end
            -- Without that bag, show the bag slots
            local player = core.get_player_by_name(target)
            if player and not inv_manager.sections["bag" .. bag].get(player) then
                core.chat_send_player(name, S("@1 has no bag in slot @2.", target, bag))
                return open(name, target, "bags")
            end
            return open(name, target, "bag" .. bag)
        end,
    })
end

core.register_chatcommand("invsave", {
    params = S("<player>"),
    description = S("Save a snapshot of a player's inventory"),
    privs = {inv_manager = true},
    func = function(name, param)
        local target = param:trim()
        local player = target ~= "" and core.get_player_by_name(target)
        if not player then
            return false, S("Player '@1' is not online.", target)
        end
        inv_manager.take_snapshot(player, "manual", name)
        db.add_log(target, name, "saved snapshot")
        return true, S("Snapshot of @1 saved.", target)
    end,
})

core.register_chatcommand("invsnapshots", {
    params = S("<player>"),
    description = S("List the saved snapshots of a player"),
    func = function(name, param)
        if not util.can_view(name) then
            return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
        end
        local target = param:trim()
        local snapshots = db.get_snapshots(target)
        if #snapshots == 0 then
            return true, S("@1 has no snapshots.", target)
        end
        local lines = {S("Snapshots of @1:", target)}
        for i, snapshot in ipairs(snapshots) do
            lines[#lines + 1] = "  " .. inv_manager.describe_snapshot(snapshot, i)
        end
        return true, table.concat(lines, "\n")
    end,
})

core.register_chatcommand("invrestore", {
    params = S("<player> <number>"),
    description = S("Restore a snapshot (applied when the player joins if they are offline)"),
    privs = {inv_manager = true},
    func = function(name, param)
        local target, index = param:trim():match("^(%S+)%s+(%d+)$")
        if not target then
            return false, S("Usage: /invrestore <player> <number>")
        end
        if util.readonly_reason(name, target) then
            return false, S("You can't modify @1's inventory.", target)
        end
        local snapshot = db.get_snapshots(target)[tonumber(index)]
        if not snapshot then
            return false, S("Snapshot @1 doesn't exist, see /invsnapshots @2", index, target)
        end
        if inv_manager.request_restore(target, snapshot, name) then
            return true, S("Snapshot restored.")
        end
        return true, S("@1 is offline, the snapshot will be restored when they join.", target)
    end,
})

core.register_chatcommand("invlog", {
    params = S("<player> [<count>]"),
    description = S("Show the latest inventory changes made by moderators to a player"),
    func = function(name, param)
        if not util.can_view(name) then
            return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
        end
        local target, count = param:trim():match("^(%S+)%s*(%d*)$")
        if not target then
            return false, S("Usage: /invlog <player> [<count>]")
        end
        count = tonumber(count) or 10
        local entries = db.get_log(target)
        if #entries == 0 then
            return true, S("No entries.")
        end
        local lines = {S("Log of @1:", target)}
        for i = #entries, math.max(1, #entries - count + 1), -1 do
            local e = entries[i]
            lines[#lines + 1] = "  " .. util.format_time(e.time) .. "  " .. e.actor .. "  " ..
                e.action .. (e.detail ~= "" and ("  " .. e.detail) or "")
        end
        return true, table.concat(lines, "\n")
    end,
})
