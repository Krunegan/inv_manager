local S = inv_manager.S
local db = inv_manager.db
local util = inv_manager.util
local settings = inv_manager.settings

local EXCLUDED_LISTS = {craftpreview = true, craftresult = true}

inv_manager.snapshot_reasons = {
    manual         = S("manual"),
    death          = S("death"),
    leave          = S("left the game"),
    auto           = S("automatic"),
    before_restore = S("before restore"),
    before_clear   = S("before clear"),
}

local function capture(player)
    local lists = {}
    for listname, list in pairs(player:get_inventory():get_lists()) do
        if not EXCLUDED_LISTS[listname] and #list > 0 then
            lists[listname] = util.list_to_strings(list)
        end
    end

    local extra = {}
    for _, def in ipairs(inv_manager.section_order) do
        if def.external then
            local inv, listname = def.get(player)
            if inv then
                extra[def.name] = util.list_to_strings(inv:get_list(listname))
            end
        end
    end
    return lists, extra
end

local function same_content(a, b)
    return core.write_json(a.lists or {}) == core.write_json(b.lists or {})
        and core.write_json(a.extra or {}) == core.write_json(b.extra or {})
end

function inv_manager.take_snapshot(player, reason, actor, skip_duplicate)
    local name = player:get_player_name()
    local lists, extra = capture(player)
    local snapshot = {
        time = os.time(),
        reason = reason,
        actor = actor or "",
        lists = lists,
        extra = extra,
    }

    local snapshots = db.get_snapshots(name)
    if skip_duplicate and snapshots[1] and same_content(snapshots[1], snapshot) then
        return snapshots[1], false
    end

    table.insert(snapshots, 1, snapshot)
    db.set_snapshots(name, snapshots)
    return snapshot, true
end

function inv_manager.describe_snapshot(snapshot, index)
    local reason = inv_manager.snapshot_reasons[snapshot.reason] or snapshot.reason or "?"
    local text = index .. ")  " .. util.format_time(snapshot.time) .. "  " .. reason
    if snapshot.actor and snapshot.actor ~= "" then
        text = text .. " (" .. snapshot.actor .. ")"
    end
    return text
end

local LIST_INFO = {
    main       = {order = 10, title = S("Main")},
    craft      = {order = 20, title = S("Crafting")},
    armor      = {order = 40, title = S("Armor")},
    offhand    = {order = 45, title = S("Offhand")},
    enderchest = {order = 50, title = S("Ender chest")},
}

local has_unified_inventory = core.get_modpath("unified_inventory") ~= nil

local function not_loaded(title)
    return S("@1 [mod not loaded]", title)
end

local function player_list_info(listname)
    local info = LIST_INFO[listname]
    if info then
        return info.order, info.title
    end
    local bag = listname:match("^bag(%d)$")
    local bag_contents = listname:match("^bag(%d)contents$")
    if bag or bag_contents then
        local title = bag and S("Bag @1 (item)", bag) or S("Bag @1", bag_contents)
        if not has_unified_inventory then
            title = not_loaded(title)
        end
        return bag and (30 + tonumber(bag) - 0.5) or (30 + tonumber(bag_contents)), title
    end
    return 100, listname
end

local function count_items(strings)
    local count = 0
    for _, str in ipairs(strings or {}) do
        count = count + ItemStack(str):get_count()
    end
    return count
end

function inv_manager.snapshot_lists(snapshot)
    local out = {}
    local function add(key, order, title, strings)
        local count = count_items(strings)
        if count > 0 or key == "main" then
            out[#out + 1] = {
                key = key,
                order = order,
                title = title .. " (" .. count .. ")",
                strings = strings,
            }
        end
    end

    for listname, strings in pairs(snapshot.lists or {}) do
        -- Old Unified Inventory bag slots are already included in "Bags"
        if not (listname:match("^bag%d$") and snapshot.extra and snapshot.extra.bags) then
            local order, title = player_list_info(listname)
            add(listname, order, title, strings)
        end
    end
    for section, strings in pairs(snapshot.extra or {}) do
        local def = inv_manager.sections[section]
        if def then
            add("extra:" .. section, def.order, def.title, strings)
        else
            add("extra:" .. section, 100, not_loaded(section), strings)
        end
    end

    table.sort(out, function(x, y)
        if x.order ~= y.order then
            return x.order < y.order
        end
        return x.key < y.key
    end)
    return out
end

function inv_manager.restore_snapshot(player, snapshot)
    local name = player:get_player_name()
    local inv = player:get_inventory()
    local skipped = {}

    local listnames = {}
    for listname in pairs(snapshot.lists or {}) do
        listnames[#listnames + 1] = listname
    end
    table.sort(listnames, function(a, b)
        local a_contents = a:find("contents$") ~= nil
        local b_contents = b:find("contents$") ~= nil
        if a_contents ~= b_contents then
            return b_contents
        end
        return a < b
    end)

    for _, listname in ipairs(listnames) do
        local list = util.strings_to_list(snapshot.lists[listname])
        local def = inv_manager.section_for_player_list(player, listname)
        if def then
            inv_manager.apply_list(player, def, list)
        elseif listname:match("^bag%dcontents$") then
            inv:set_size(listname, math.max(#list, inv:get_size(listname)))
            inv:set_list(listname, list)
        elseif inv:get_size(listname) > 0 then
            inv:set_list(listname, list)
        elseif count_items(snapshot.lists[listname]) > 0
                and not (listname:match("^bag%d$") and inv_manager.sections.bags) then
            skipped[#skipped + 1] = select(2, player_list_info(listname))
        end
    end

    -- Old Unified Inventory versions kept the bag items in player lists
    local legacy_bags = inv:get_size("bag1") > 0
    if legacy_bags then
        for i = 1, 4 do
            local contents = "bag" .. i .. "contents"
            if snapshot.lists and snapshot.lists["bag" .. i] and not snapshot.lists[contents]
                    and inv:get_size(contents) > 0 then
                inv:set_list(contents, {})
            end
        end
        local bags = core.get_inventory({type = "detached", name = name .. "_bags"})
        if bags then
            for i = 1, 4 do
                if bags:get_size("bag" .. i) > 0 then
                    bags:set_stack("bag" .. i, 1, inv:get_stack("bag" .. i, 1))
                end
            end
        end
    end

    local extra = snapshot.extra or {}
    -- A snapshot taken with an old Unified Inventory restored with a new one:
    -- its bag lists become the bag slots
    local has_old_bag_lists = false
    for i = 1, 4 do
        if snapshot.lists and snapshot.lists["bag" .. i] then
            has_old_bag_lists = true
        end
    end
    if not extra.bags and has_old_bag_lists and not legacy_bags
            and inv_manager.sections.bags then
        local bags = {}
        for i = 1, 4 do
            bags[i] = (snapshot.lists["bag" .. i] or {})[1] or ""
        end
        extra = table.copy(extra)
        extra.bags = bags
    end

    for _, def in ipairs(inv_manager.section_order) do
        local strings = extra[def.name]
        if strings and not inv_manager.apply_list(player, def, util.strings_to_list(strings))
                and count_items(strings) > 0 then
            skipped[#skipped + 1] = def.title
        end
    end
    for section, strings in pairs(extra) do
        if not inv_manager.sections[section] and count_items(strings) > 0 then
            skipped[#skipped + 1] = not_loaded(section)
        end
    end
    return skipped
end

local function report_skipped(actor, skipped)
    if #skipped > 0 and core.get_player_by_name(actor) then
        core.chat_send_player(actor, S("Not restored: @1", table.concat(skipped, ", ")))
    end
end

function inv_manager.request_restore(target, snapshot, actor)
    local player = core.get_player_by_name(target)
    if player then
        inv_manager.take_snapshot(player, "before_restore", actor)
        report_skipped(actor, inv_manager.restore_snapshot(player, snapshot))
        db.add_log(target, actor, "restored", util.format_time(snapshot.time))
        return true
    end
    snapshot.actor_restore = actor
    db.set_pending(target, snapshot)
    db.add_log(target, actor, "queued restore", util.format_time(snapshot.time))
    return false
end

core.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    if not db.get_pending(name) then
        return
    end
    core.after(1, function()
        local pending = db.get_pending(name)
        player = core.get_player_by_name(name)
        if not pending or not player then
            return
        end
        db.set_pending(name, nil)
        local actor = pending.actor_restore or "?"
        inv_manager.take_snapshot(player, "before_restore", actor)
        report_skipped(actor, inv_manager.restore_snapshot(player, pending))
        db.add_log(name, actor, "restored (on join)", util.format_time(pending.time))
    end)
end)

if settings.snapshot_on_death then
    core.register_on_player_hpchange(function(player, hp_change)
        if hp_change >= 0 or not player:is_player() then
            return
        end
        local hp = player:get_hp()
        if hp > 0 and hp + hp_change <= 0 then
            inv_manager.take_snapshot(player, "death")
        end
    end)
end

if settings.snapshot_on_leave then
    core.register_on_leaveplayer(function(player)
        inv_manager.take_snapshot(player, "leave", nil, true)
    end)
end

if settings.snapshot_interval > 0 then
    local timer = 0
    core.register_globalstep(function(dtime)
        timer = timer + dtime
        if timer < settings.snapshot_interval then
            return
        end
        timer = 0
        for _, player in ipairs(core.get_connected_players()) do
            inv_manager.take_snapshot(player, "auto", nil, true)
        end
    end)
end
