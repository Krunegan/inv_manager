local S = inv_manager.S
local util = {}
inv_manager.util = util

function util.can_edit(name)
    return core.check_player_privs(name, {inv_manager = true})
end

function util.can_view(name)
    return util.can_edit(name) or core.check_player_privs(name, {inv_viewer = true})
end

function util.is_protected(moderator, target)
    if core.check_player_privs(moderator, {server = true}) then
        return false
    end
    local target_privs = core.get_player_privs(target)
    for priv in pairs(inv_manager.settings.protected_privs) do
        if target_privs[priv] then
            return true
        end
    end
    return false
end

function util.readonly_reason(moderator, target)
    if not util.can_edit(moderator) then
        return S("read only")
    elseif moderator == target then
        return S("your own inventory")
    elseif util.is_protected(moderator, target) then
        return S("protected player")
    end
end

function util.stack_to_log(stack)
    stack = ItemStack(stack)
    if stack:is_empty() then
        return "nothing"
    end
    return stack:get_name() .. " " .. stack:get_count()
end

function util.list_to_strings(list)
    local out = {}
    for i, stack in ipairs(list or {}) do
        out[i] = ItemStack(stack):to_string()
    end
    return out
end

function util.strings_to_list(strings)
    local out = {}
    for i, str in ipairs(strings or {}) do
        out[i] = ItemStack(str)
    end
    return out
end

function util.format_time(timestamp)
    return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

function util.columns_for(size, width)
    if width and width > 0 and width <= 9 then
        return width
    end
    if size <= 0 then
        return 1
    elseif size <= 9 and size % 3 == 0 and size ~= 3 then
        return 3
    elseif size % 9 == 0 then
        return 9
    elseif size % 8 == 0 or size > 9 then
        return math.min(size, 8)
    end
    return size
end