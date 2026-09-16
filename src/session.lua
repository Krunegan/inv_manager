local S = inv_manager.S
local db = inv_manager.db
local util = inv_manager.util
local settings = inv_manager.settings

local FORMNAME = "inv_manager:gui"
inv_manager.FORMNAME = FORMNAME

local MIRROR_LIST = "main"

local sessions = {}
inv_manager.sessions = sessions

local function mirror_name(moderator)
    return "inv_manager_mirror_" .. moderator
end

local function preview_name(moderator)
    return "inv_manager_preview_" .. moderator
end

inv_manager.mirror_name = mirror_name
inv_manager.preview_name = preview_name

local function get_mirror(moderator)
    return core.get_inventory({type = "detached", name = mirror_name(moderator)})
end

local function action_context(moderator, actor)
    local sess = sessions[moderator]
    if not sess or not sess.online or sess.readonly then
        return nil
    end
    if not actor or not actor:is_player() or actor:get_player_name() ~= moderator then
        return nil
    end
    if not util.can_edit(moderator) then
        core.chat_send_player(moderator, S("You no longer have the 'inv_manager' privilege."))
        return nil
    end
    local target = core.get_player_by_name(sess.target)
    local def = inv_manager.sections[sess.section]
    if not target or not def then
        return nil
    end
    local real_inv, real_list = def.get(target)
    if not real_inv then
        return nil
    end
    return sess, target, def, real_inv, real_list
end

-- true if the mirror doesn't match the real list in any of the given slots
local function is_stale(mirror, size, real_inv, real_list, ...)
    if mirror:get_size(MIRROR_LIST) ~= size then
        return true
    end
    for _, index in ipairs({...}) do
        if not mirror:get_stack(MIRROR_LIST, index):equals(real_inv:get_stack(real_list, index)) then
            return true
        end
    end
    return false
end

local function refuse_stale(sess)
    core.chat_send_player(sess.moderator,
        S("@1's inventory changed, try again.", sess.target))
    inv_manager.sync_session(sess)
    return 0
end

local function return_lost_item(sess, stack, receiver)
    local player = core.get_player_by_name(receiver)
    if not player then
        return
    end
    local leftover = player:get_inventory():add_item("main", stack)
    if not leftover:is_empty() then
        core.add_item(player:get_pos(), leftover)
    end
    core.chat_send_player(sess.moderator,
        S("@1 was rejected by another mod and returned to @2.", stack:get_short_description(), receiver))
    db.add_log(sess.target, sess.moderator, "returned rejected item",
        util.stack_to_log(stack) .. " -> " .. receiver)
end

-- the item counts of a list, by item string without the count (metadata/wear)
local function count_items(list)
    local counts = {}
    for _, stack in ipairs(list or {}) do
        if not stack:is_empty() then
            local single = ItemStack(stack)
            single:set_count(1)
            local key = single:to_string()
            counts[key] = (counts[key] or 0) + stack:get_count()
        end
    end
    return counts
end

local function write_back(sess, target, def, real_inv, real_list, mirror, indexes, owner)
    local changes = {}
    for _, index in ipairs(indexes) do
        local old = real_inv:get_stack(real_list, index)
        local new = mirror:get_stack(MIRROR_LIST, index)
        if not old:equals(new) then
            real_inv:set_stack(real_list, index, new)
            changes[#changes + 1] = {index = index, old = old, new = new}
        end
    end
    if #changes == 0 or not def.on_change then
        return changes
    end

    local before = count_items(real_inv:get_list(real_list))
    def.on_change(target, changes)

    local after = count_items(real_inv:get_list(real_list))
    for key, count in pairs(before) do
        local missing = count - (after[key] or 0)
        if missing > 0 then
            local lost = ItemStack(key)
            lost:set_count(missing)
            return_lost_item(sess, lost, owner)
        end
    end
    return changes
end

local function create_mirror(moderator)
    if get_mirror(moderator) then
        return false
    end

    local inv = core.create_detached_inventory(mirror_name(moderator), {
        allow_move = function(mirror, from_list, from_index, to_list, to_index, count, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return 0
            end
            if is_stale(mirror, inv_manager.section_size(def, target, real_inv, real_list),
                    real_inv, real_list, from_index, to_index) then
                return refuse_stale(sess)
            end
            if def.disable_move then
                return 0
            end
            if def.allow_put then
                local stack = mirror:get_stack(from_list, from_index)
                stack:set_count(count)
                -- The slot being moved is considered empty for the check
                local saved = real_inv:get_stack(real_list, from_index)
                real_inv:set_stack(real_list, from_index, ItemStack())
                local allowed = def.allow_put(target, real_inv, real_list, to_index, stack)
                real_inv:set_stack(real_list, from_index, saved)
                count = math.min(count, allowed)
            end
            return count
        end,

        allow_put = function(mirror, listname, index, stack, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return 0
            end
            if is_stale(mirror, inv_manager.section_size(def, target, real_inv, real_list),
                    real_inv, real_list, index) then
                return refuse_stale(sess)
            end
            local count = stack:get_count()
            if def.allow_put then
                count = math.min(count, def.allow_put(target, real_inv, real_list, index, stack))
            end
            return count
        end,

        allow_take = function(mirror, listname, index, stack, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return 0
            end
            if is_stale(mirror, inv_manager.section_size(def, target, real_inv, real_list),
                    real_inv, real_list, index) then
                return refuse_stale(sess)
            end
            local count = stack:get_count()
            if def.allow_take then
                count = math.min(count, def.allow_take(target, real_inv, real_list, index, stack))
            end
            return count
        end,

        on_move = function(mirror, from_list, from_index, to_list, to_index, count, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return
            end
            write_back(sess, target, def, real_inv, real_list, mirror, {from_index, to_index}, sess.target)
            db.add_log(sess.target, moderator, "moved",
                util.stack_to_log(mirror:get_stack(MIRROR_LIST, to_index):get_name() .. " " .. count) ..
                " (" .. def.name .. " " .. from_index .. " -> " .. to_index .. ")")
        end,

        on_put = function(mirror, listname, index, stack, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return
            end
            write_back(sess, target, def, real_inv, real_list, mirror, {index}, moderator)
            db.add_log(sess.target, moderator, "put",
                util.stack_to_log(stack) .. " (" .. def.name .. " " .. index .. ")")
        end,

        on_take = function(mirror, listname, index, stack, actor)
            local sess, target, def, real_inv, real_list = action_context(moderator, actor)
            if not sess then
                return
            end
            -- Copy what is left in the slot: taking half a stack keeps the rest
            write_back(sess, target, def, real_inv, real_list, mirror, {index}, sess.target)
            db.add_log(sess.target, moderator, "took",
                util.stack_to_log(stack) .. " (" .. def.name .. " " .. index .. ")")
        end,
    }, moderator)
    inv:set_size(MIRROR_LIST, 1)

    local preview = core.create_detached_inventory(preview_name(moderator), {
        allow_move = function() return 0 end,
        allow_put = function() return 0 end,
        allow_take = function() return 0 end,
    }, moderator)
    preview:set_size(MIRROR_LIST, 1)
    return true
end

local function remove_mirror(moderator)
    core.remove_detached_inventory(mirror_name(moderator))
    core.remove_detached_inventory(preview_name(moderator))
end

function inv_manager.sync_session(sess, now)
    now = now or core.get_us_time() / 1e6
    local mirror = get_mirror(sess.moderator)
    local target = core.get_player_by_name(sess.target)
    local def = inv_manager.sections[sess.section]
    if not mirror or not target or not def then
        return false
    end
    local real_inv, real_list = def.get(target)
    if not real_inv then
        return false
    end

    local refresh = false
    local size = inv_manager.section_size(def, target, real_inv, real_list)
    if mirror:get_size(MIRROR_LIST) ~= math.max(size, 1) then
        mirror:set_size(MIRROR_LIST, math.max(size, 1))
        refresh = true
    end

    for i = 1, size do
        local real = real_inv:get_stack(real_list, i)
        if not mirror:get_stack(MIRROR_LIST, i):equals(real) then
            mirror:set_stack(MIRROR_LIST, i, real)
            if settings.highlight_time > 0 and not sess.fresh then
                sess.highlight[i] = now + settings.highlight_time
                refresh = true
            end
        end
    end
    sess.fresh = false

    for index, expires in pairs(sess.highlight) do
        if expires <= now or index > size then
            sess.highlight[index] = nil
            refresh = true
        end
    end
    return refresh
end

function inv_manager.session_tabs(sess)
    local tabs = {}
    local target = sess.online and core.get_player_by_name(sess.target)
    if target then
        for _, def in ipairs(inv_manager.get_available_sections(target)) do
            tabs[#tabs + 1] = def.name
        end
    end
    tabs[#tabs + 1] = "snapshots"
    tabs[#tabs + 1] = "log"
    return tabs
end

local function update_access(sess)
    local reason = util.readonly_reason(sess.moderator, sess.target)
    local changed = (reason ~= sess.readonly)
    sess.readonly = reason
    return changed
end

function inv_manager.set_section(sess, section)
    local tabs = inv_manager.session_tabs(sess)
    local valid = false
    for _, tab in ipairs(tabs) do
        if tab == section then
            valid = true
            break
        end
    end
    if not valid then
        section = tabs[1]
    end

    sess.section = section
    sess.highlight = {}
    sess.confirm = nil
    sess.fresh = true

    if inv_manager.sections[section] then
        inv_manager.sync_session(sess)
    end
end

function inv_manager.show_session(sess)
    core.show_formspec(sess.moderator, FORMNAME, inv_manager.build_formspec(sess))
end

function inv_manager.open(moderator, target, section)
    if not core.get_player_by_name(moderator) then
        return false, S("You must be online.")
    end
    if not util.can_view(moderator) then
        return false, S("You need the 'inv_manager' or 'inv_viewer' privilege.")
    end
    if moderator == target and not settings.allow_self then
        return false, S("You can't use this on yourself.")
    end

    local online = core.get_player_by_name(target) ~= nil
    if not online and not core.player_exists(target) and not db.has_data(target) then
        return false, S("Player '@1' doesn't exist.", target)
    end

    local created = create_mirror(moderator)

    local sess = {
        moderator = moderator,
        target = target,
        online = online,
        highlight = {},
        snapshot = 1,
        snapshot_list = 1,
    }
    update_access(sess)
    sessions[moderator] = sess

    if not online then
        core.chat_send_player(moderator,
            S("@1 is offline, showing saved snapshots.", target))
    end
    inv_manager.set_section(sess, section or (online and "main" or "snapshots"))
    if online and section and sess.section ~= section then
        local def = inv_manager.sections[section]
        core.chat_send_player(moderator, S("@1 doesn't have '@2'.", target,
            def and def.title or section))
    end

    if created then
        core.after(0.1, function()
            if sessions[moderator] == sess then
                inv_manager.show_session(sess)
            end
        end)
    else
        inv_manager.show_session(sess)
    end
    return true
end

function inv_manager.close(moderator)
    if not sessions[moderator] then
        return
    end
    sessions[moderator] = nil
end

local function update_session(moderator, sess, check_access, now)
    local refresh = false

    if check_access then
        if not util.can_view(moderator) then
            core.chat_send_player(moderator, S("You can no longer view inventories."))
            inv_manager.close(moderator)
            core.close_formspec(moderator, FORMNAME)
            return
        end
        refresh = update_access(sess)
    end

    local target = core.get_player_by_name(sess.target)
    local online = target ~= nil
    if online ~= sess.online then
        sess.online = online
        core.chat_send_player(moderator, online
            and S("@1 joined the game.", sess.target)
            or S("@1 left the game.", sess.target))
        inv_manager.set_section(sess, online and "main" or "snapshots")
        refresh = true
    elseif online then
        local def = inv_manager.sections[sess.section]
        if def and not def.get(target) then
            inv_manager.set_section(sess, nil)
            refresh = true
        elseif def and inv_manager.sync_session(sess, now) then
            refresh = true
        end
    end

    if refresh then
        inv_manager.show_session(sess)
    end
end

local timer = 0
local access_timer = 0

core.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < settings.sync_interval then
        return
    end
    access_timer = access_timer + timer
    timer = 0

    local check_access = access_timer >= 1
    if check_access then
        access_timer = 0
    end

    local now = core.get_us_time() / 1e6
    for moderator, sess in pairs(sessions) do
        update_session(moderator, sess, check_access, now)
    end
end)

core.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    sessions[name] = nil
    remove_mirror(name)
end)

local show_formspec = core.show_formspec
function core.show_formspec(name, formname, ...)
    if formname ~= FORMNAME and sessions[name] then
        inv_manager.close(name)
    end
    return show_formspec(name, formname, ...)
end