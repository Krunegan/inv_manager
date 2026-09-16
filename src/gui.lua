local S = inv_manager.S
local F = core.formspec_escape
local db = inv_manager.db
local util = inv_manager.util
local sessions = inv_manager.sessions
local FORMNAME = inv_manager.FORMNAME
local PICKER_FORMNAME = "inv_manager:picker"

local PAD = 0.375
local STEP = 1.25
local HIGHLIGHT_COLOR = "#FFB00090"

local mcl_formspec = rawget(_G, "mcl_formspec")
local STATUS_COLOR = mcl_formspec and "#B02020" or "#FF8080"

local function slot_bg(x, y, cols, size)
    if not (mcl_formspec and mcl_formspec.get_itemslot_bg_v4) or size <= 0 then
        return ""
    end
    local full_rows = math.floor(size / cols)
    local out = ""
    if full_rows > 0 then
        out = mcl_formspec.get_itemslot_bg_v4(x, y, cols, full_rows)
    end
    local rest = size % cols
    if rest > 0 then
        out = out .. mcl_formspec.get_itemslot_bg_v4(x, y + full_rows * STEP, rest, 1)
    end
    return out
end

local TAB_TITLES = {
    snapshots = S("Snapshots"),
    log = S("Log"),
}

local function grid_size(slots)
    return slots * STEP - 0.25
end

local function button(x, y, w, name, label, sess)
    if sess and sess.confirm == name then
        label = S("Confirm?")
    end
    return ("button[%s,%s;%s,0.7;%s;%s]"):format(x, y, w, name, F(label))
end

local function header(sess, fs, subtitle)
    local title = sess.target .. "  -  " .. subtitle
    local status = {}
    if not sess.online then
        status[#status + 1] = S("offline")
    end
    if sess.readonly then
        status[#status + 1] = sess.readonly
    end
    if #status > 0 then
        title = title .. "  " .. core.colorize(STATUS_COLOR, "[" .. table.concat(status, ", ") .. "]")
    end
    fs[#fs + 1] = ("label[%s,0.45;%s]"):format(PAD, F(title))
end

local function build_section(sess, def, fs)
    local target = core.get_player_by_name(sess.target)
    local moderator = core.get_player_by_name(sess.moderator)
    local real_inv, real_list = def.get(target)
    local mirror = "detached:" .. inv_manager.mirror_name(sess.moderator)

    local size = inv_manager.section_size(def, target, real_inv, real_list)
    local cols = util.columns_for(size, real_inv:get_width(real_list))
    local rows = math.max(1, math.ceil(size / cols))

    local my_size = moderator:get_inventory():get_size("main")
    local my_cols = (my_size % 9 == 0) and 9 or 8
    local my_rows = math.max(1, math.ceil(my_size / my_cols))

    local width = math.max(PAD * 2 + grid_size(math.max(cols, my_cols)), 10.5)
    local editable = not sess.readonly and sess.online

    header(sess, fs, def.title)

    local list_y = 1.0
    if editable then
        local x = PAD
        fs[#fs + 1] = button(x, 0.85, 2.3, "clear", S("Clear"), sess)
        x = x + 2.45
        fs[#fs + 1] = button(x, 0.85, 2.3, "take_all", S("Take all"), sess)
        x = x + 2.45
        if core.check_player_privs(sess.moderator, {give = true}) then
            fs[#fs + 1] = button(x, 0.85, 2.3, "copy", S("Copy to me"), sess)
        end
        list_y = 1.8
    end

    fs[#fs + 1] = slot_bg(PAD, list_y, cols, size)

    -- Slots changed by someone else in the last seconds
    for index in pairs(sess.highlight) do
        if index <= size then
            local col = (index - 1) % cols
            local row = math.floor((index - 1) / cols)
            fs[#fs + 1] = ("box[%s,%s;1,1;%s]"):format(
                PAD + col * STEP, list_y + row * STEP, HIGHLIGHT_COLOR)
        end
    end

    fs[#fs + 1] = ("list[%s;main;%s,%s;%d,%d;]"):format(mirror, PAD, list_y, cols, rows)

    local my_y = list_y + grid_size(rows) + 0.5
    fs[#fs + 1] = ("label[%s,%s;%s]"):format(PAD, my_y, F(S("Your inventory")))
    local hotbar_y = my_y + 0.35
    fs[#fs + 1] = slot_bg(PAD, hotbar_y, my_cols, math.min(my_cols, my_size))
    fs[#fs + 1] = ("list[current_player;main;%s,%s;%d,1;]"):format(PAD, hotbar_y, my_cols)
    local height = hotbar_y + 1 + PAD
    if my_rows > 1 then
        local rest_y = hotbar_y + STEP + 0.15
        fs[#fs + 1] = slot_bg(PAD, rest_y, my_cols, my_size - my_cols)
        fs[#fs + 1] = ("list[current_player;main;%s,%s;%d,%d;%d]"):format(
            PAD, rest_y, my_cols, my_rows - 1, my_cols)
        height = rest_y + grid_size(my_rows - 1) + PAD
    end

    fs[#fs + 1] = "listring[" .. mirror .. ";main]"
    fs[#fs + 1] = "listring[current_player;main]"
    return width, height
end

local function build_snapshots(sess, fs)
    local snapshots = db.get_snapshots(sess.target)
    local can_edit = util.can_edit(sess.moderator)

    header(sess, fs, TAB_TITLES.snapshots)

    local list_h = 6.5
    local items = {}
    for i, snapshot in ipairs(snapshots) do
        items[i] = F(inv_manager.describe_snapshot(snapshot, i))
    end
    sess.snapshot = math.max(1, math.min(sess.snapshot, #snapshots))

    local right_x = PAD + 5.6 + 0.35
    local content_w = 4.5
    local content_h = 0

    if #snapshots == 0 then
        fs[#fs + 1] = ("textlist[%s,1;5.6,%s;snapshot;%s;0;false]"):format(
            PAD, list_h, F(S("No snapshots saved.")))
    else
        fs[#fs + 1] = ("textlist[%s,1;5.6,%s;snapshot;%s;%d;false]"):format(
            PAD, list_h, table.concat(items, ","), sess.snapshot)

        local snapshot = snapshots[sess.snapshot]
        local lists = inv_manager.snapshot_lists(snapshot)
        -- Keep the same list selected when another snapshot is chosen
        sess.snapshot_list = 1
        sess.snapshot_list_keys = {}
        for i, l in ipairs(lists) do
            sess.snapshot_list_keys[i] = l.key
            if l.key == sess.snapshot_list_key then
                sess.snapshot_list = i
            end
        end

        local preview = core.get_inventory({
            type = "detached",
            name = inv_manager.preview_name(sess.moderator),
        })
        local entry = lists[sess.snapshot_list]
        if entry and preview then
            local titles = {}
            for i, l in ipairs(lists) do
                titles[i] = F(l.title)
            end
            fs[#fs + 1] = ("dropdown[%s,1;4.5,0.7;snapshot_list;%s;%d;true]"):format(
                right_x, table.concat(titles, ","), sess.snapshot_list)

            local stacks = util.strings_to_list(entry.strings)
            preview:set_size("main", math.max(#stacks, 1))
            preview:set_list("main", stacks)

            local cols = util.columns_for(#stacks)
            local rows = math.max(1, math.ceil(#stacks / cols))
            fs[#fs + 1] = slot_bg(right_x, 1.9, cols, #stacks)
            fs[#fs + 1] = ("list[detached:%s;main;%s,1.9;%d,%d;]"):format(
                inv_manager.preview_name(sess.moderator), right_x, cols, rows)
            content_w = math.max(content_w, grid_size(cols))
            content_h = 0.9 + grid_size(rows)
        end
    end

    local height = 1 + math.max(list_h, content_h)
    if db.get_pending(sess.target) then
        height = height + 0.2
        fs[#fs + 1] = ("label[%s,%s;%s]"):format(PAD, height + 0.2,
            F(S("A restore is pending, it will be applied when the player joins.")))
        height = height + 0.4
    end

    local y = height + 0.3
    local x = PAD
    if can_edit and sess.online then
        fs[#fs + 1] = button(x, y, 2.6, "snapshot_save", S("Save now"), sess)
        x = x + 2.75
    end
    if #snapshots > 0 and not sess.readonly then
        fs[#fs + 1] = button(x, y, 2.6, "snapshot_restore", S("Restore"), sess)
        x = x + 2.75
        fs[#fs + 1] = button(x, y, 2.6, "snapshot_delete", S("Delete"), sess)
    end

    return math.max(right_x + content_w + PAD, 11), y + 0.7 + PAD
end

-- Logs

local function build_log(sess, fs)
    header(sess, fs, TAB_TITLES.log)
    local entries = db.get_log(sess.target)
    local items = {}
    for i = #entries, 1, -1 do
        local e = entries[i]
        items[#items + 1] = F(util.format_time(e.time) .. "  " .. e.actor .. "  " ..
            e.action .. (e.detail ~= "" and ("  " .. e.detail) or ""))
    end
    if #items == 0 then
        items[1] = F(S("No entries."))
    end
    fs[#fs + 1] = ("textlist[%s,1;13.25,7.5;log;%s;0;false]"):format(PAD, table.concat(items, ","))
    return 14, 8.5 + PAD
end

function inv_manager.build_formspec(sess)
    local body = {}
    local def = inv_manager.sections[sess.section]
    local target = core.get_player_by_name(sess.target)

    local width, height
    if def and sess.online and target and def.get(target) then
        width, height = build_section(sess, def, body)
    elseif sess.section == "log" then
        width, height = build_log(sess, body)
    else
        width, height = build_snapshots(sess, body)
    end

    sess.tabs = inv_manager.session_tabs(sess)
    local captions, current = {}, 1
    for i, tab in ipairs(sess.tabs) do
        local tab_def = inv_manager.sections[tab]
        captions[i] = F(tab_def and tab_def.title or TAB_TITLES[tab])
        if tab == sess.section then
            current = i
        end
    end

    return table.concat({
        "formspec_version[6]",
        ("size[%s,%s]"):format(width, height),
        ("tabheader[0,0;tabs;%s;%d;false;false]"):format(table.concat(captions, ","), current),
        table.concat(body),
    })
end

-- Returns target, section def, InvRef and list if the moderator can modify them
local function editable_section(sess)
    if not sess.online or sess.readonly or not util.can_edit(sess.moderator) then
        return nil
    end
    local target = core.get_player_by_name(sess.target)
    local def = inv_manager.sections[sess.section]
    if not target or not def then
        return nil
    end
    local inv, listname = def.get(target)
    if inv then
        return target, def, inv, listname
    end
end

-- Whether the section allows removing the whole slot
local function can_take(target, def, inv, listname, index)
    local stack = inv:get_stack(listname, index)
    if stack:is_empty() or not def.allow_take then
        return true
    end
    return def.allow_take(target, inv, listname, index, stack, true) >= stack:get_count()
end

local function confirmed(sess, action)
    if sess.confirm == action then
        sess.confirm = nil
        return true
    end
    sess.confirm = action
    return false
end

local function resync(sess)
    sess.fresh = true
    inv_manager.sync_session(sess)
end

local actions = {}

function actions.clear(sess)
    local target, def, inv, listname = editable_section(sess)
    if not target or not confirmed(sess, "clear") then
        return
    end
    inv_manager.take_snapshot(target, "before_clear", sess.moderator)
    local empty = {}
    for i = 1, inv:get_size(listname) do
        empty[i] = can_take(target, def, inv, listname, i) and ItemStack()
            or inv:get_stack(listname, i)
    end
    inv_manager.apply_list(target, def, empty)
    db.add_log(sess.target, sess.moderator, "cleared", def.name)
    core.chat_send_player(sess.moderator,
        S("Cleared. A snapshot was saved in case you need to undo it."))
    resync(sess)
end

function actions.take_all(sess)
    local target, def, inv, listname = editable_section(sess)
    if not target then
        return
    end
    local my_inv = core.get_player_by_name(sess.moderator):get_inventory()
    local new_list, taken, full = {}, 0, false
    for i = 1, inv:get_size(listname) do
        local stack = inv:get_stack(listname, i)
        local leftover = stack
        if not stack:is_empty() and can_take(target, def, inv, listname, i) then
            leftover = my_inv:add_item("main", stack)
            taken = taken + stack:get_count() - leftover:get_count()
            full = full or not leftover:is_empty()
        end
        new_list[i] = leftover
    end
    inv_manager.apply_list(target, def, new_list)
    db.add_log(sess.target, sess.moderator, "took all", def.name .. " (" .. taken .. " items)")
    if full then
        core.chat_send_player(sess.moderator, S("Your inventory is full, some items were left."))
    end
    resync(sess)
end

function actions.copy(sess)
    local target, def, inv, listname = editable_section(sess)
    if not target or not core.check_player_privs(sess.moderator, {give = true}) then
        return
    end
    local my_inv = core.get_player_by_name(sess.moderator):get_inventory()
    local full = false
    for _, stack in ipairs(inv:get_list(listname)) do
        if not stack:is_empty() then
            full = not my_inv:add_item("main", stack):is_empty() or full
        end
    end
    db.add_log(sess.target, sess.moderator, "copied", def.name)
    if full then
        core.chat_send_player(sess.moderator, S("Your inventory is full, some items were not copied."))
    end
end

function actions.snapshot_save(sess)
    local target = core.get_player_by_name(sess.target)
    if not target or not util.can_edit(sess.moderator) then
        return
    end
    inv_manager.take_snapshot(target, "manual", sess.moderator)
    db.add_log(sess.target, sess.moderator, "saved snapshot")
    sess.snapshot = 1
end

function actions.snapshot_restore(sess)
    local snapshot = db.get_snapshots(sess.target)[sess.snapshot]
    if sess.readonly or not snapshot or not confirmed(sess, "snapshot_restore") then
        return
    end
    if inv_manager.request_restore(sess.target, snapshot, sess.moderator) then
        core.chat_send_player(sess.moderator, S("Snapshot restored."))
        sess.snapshot = 1 -- the "before restore" snapshot
    else
        core.chat_send_player(sess.moderator,
            S("@1 is offline, the snapshot will be restored when they join.", sess.target))
    end
end

function actions.snapshot_delete(sess)
    local snapshots = db.get_snapshots(sess.target)
    if sess.readonly or not snapshots[sess.snapshot] or not confirmed(sess, "snapshot_delete") then
        return
    end
    local removed = table.remove(snapshots, sess.snapshot)
    db.set_snapshots(sess.target, snapshots)
    db.add_log(sess.target, sess.moderator, "deleted snapshot", util.format_time(removed.time))
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= FORMNAME then
        return false
    end
    local name = player:get_player_name()
    local sess = sessions[name]
    if not sess then
        return true
    end

    if fields.quit then
        inv_manager.close(name)
        return true
    end

    local previous_confirm = sess.confirm

    if fields.tabs then
        local tab = sess.tabs and sess.tabs[tonumber(fields.tabs)]
        if tab and tab ~= sess.section then
            inv_manager.set_section(sess, tab)
            inv_manager.show_session(sess)
            return true
        end
    end

    for action, func in pairs(actions) do
        if fields[action] then
            func(sess)
            -- Clicking any other button cancels a pending confirmation
            if sess.confirm == previous_confirm and previous_confirm ~= action then
                sess.confirm = nil
            end
            inv_manager.show_session(sess)
            return true
        end
    end

    if fields.snapshot then
        local event = core.explode_textlist_event(fields.snapshot)
        if (event.type == "CHG" or event.type == "DCL") and event.index ~= sess.snapshot then
            sess.snapshot = event.index
            sess.confirm = nil
            inv_manager.show_session(sess)
            return true
        end
    end

    local list_index = tonumber(fields.snapshot_list)
    if list_index and list_index ~= sess.snapshot_list then
        sess.snapshot_list = list_index
        sess.snapshot_list_key = (sess.snapshot_list_keys or {})[list_index]
        inv_manager.show_session(sess)
    end
    return true
end)

local picker_lists = {}

function inv_manager.show_picker(name)
    local names = {}
    for _, player in ipairs(core.get_connected_players()) do
        local pname = player:get_player_name()
        if pname ~= name or inv_manager.settings.allow_self then
            names[#names + 1] = pname
        end
    end
    table.sort(names)
    picker_lists[name] = names

    local items = {}
    for i, pname in ipairs(names) do
        items[i] = F(pname)
    end

    core.show_formspec(name, PICKER_FORMNAME, table.concat({
        "formspec_version[6]",
        "size[7,9]",
        ("label[%s,0.5;%s]"):format(PAD, F(S("Online players (double click to open)"))),
        ("textlist[%s,0.9;6.25,6;player;%s;0;false]"):format(PAD, table.concat(items, ",")),
        ("field[%s,7.3;4.2,0.8;name;;]"):format(PAD),
        "field_close_on_enter[name;false]",
        ("button[%s,7.3;1.9,0.8;open;%s]"):format(PAD + 4.35, F(S("Open"))),
    }))
end

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= PICKER_FORMNAME then
        return false
    end
    local name = player:get_player_name()
    local target

    if fields.player then
        local event = core.explode_textlist_event(fields.player)
        if event.type == "DCL" then
            target = (picker_lists[name] or {})[event.index]
        end
    end
    if (fields.open or fields.key_enter_field == "name") and fields.name then
        target = fields.name:trim()
    end

    if fields.quit and not target then
        picker_lists[name] = nil
        return true
    end
    if target and target ~= "" then
        local ok, err = inv_manager.open(name, target)
        if not ok then
            core.chat_send_player(name, err)
        end
    end
    return true
end)

core.register_on_leaveplayer(function(player)
    picker_lists[player:get_player_name()] = nil
end)
