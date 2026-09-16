local storage = core.get_mod_storage()
local settings = inv_manager.settings

local db = {}
inv_manager.db = db

local function read(key)
    local raw = storage:get_string(key)
    if raw == "" then
        return nil
    end
    return core.parse_json(raw)
end

local function write(key, value)
    if value == nil then
        storage:set_string(key, "")
    else
        storage:set_string(key, core.write_json(value))
    end
end

function db.get_snapshots(name)
    return read("snapshots:" .. name) or {}
end

function db.set_snapshots(name, snapshots)
    while #snapshots > settings.max_snapshots do
        table.remove(snapshots)
    end
    write("snapshots:" .. name, #snapshots > 0 and snapshots or nil)
end

function db.has_data(name)
    return storage:contains("snapshots:" .. name) or storage:contains("log:" .. name)
end

function db.get_pending(name)
    return read("pending:" .. name)
end

function db.set_pending(name, snapshot)
    write("pending:" .. name, snapshot)
end

function db.get_log(name)
    return read("log:" .. name) or {}
end

function db.add_log(target, actor, action, detail)
    core.log("action", "[inv_manager] " .. actor .. " " .. action .. " " .. target .. (detail and detail ~= "" and (": " .. detail) or ""))

    local entries = db.get_log(target)
    entries[#entries + 1] = {
        time = os.time(),
        actor = actor,
        action = action,
        detail = detail or "",
    }
    while #entries > settings.max_log_entries do
        table.remove(entries, 1)
    end
    write("log:" .. target, entries)
end
