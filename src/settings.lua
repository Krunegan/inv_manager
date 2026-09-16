local settings = core.settings

local function number(key, default, min)
    local value = tonumber(settings:get("inv_manager." .. key)) or default
    if min and value < min then
        value = min
    end
    return value
end

inv_manager.settings = {
    sync_interval     = number("sync_interval", 0.1, 0.05),
    highlight_time    = number("highlight_time", 3, 0),
    allow_self        = settings:get_bool("inv_manager.allow_self", false),
    protected_privs   = core.string_to_privs(settings:get("inv_manager.protected_privs") or "server"),
    max_snapshots     = math.floor(number("max_snapshots", 10, 1)),
    snapshot_interval = number("snapshot_interval", 600, 0),
    snapshot_on_death = settings:get_bool("inv_manager.snapshot_on_death", true),
    snapshot_on_leave = settings:get_bool("inv_manager.snapshot_on_leave", true),
    max_log_entries   = math.floor(number("max_log_entries", 200, 1)),
}
