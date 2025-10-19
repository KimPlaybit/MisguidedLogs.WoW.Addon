-- Export.lua
-- JSON export helper for GroupRecorder

-- JSON encoder
local function encodeString(s)
    s = s or ""
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function encodeValue(v)
    local t = type(v)
    if t == "string" then return encodeString(v) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then return encodeTable(v) end
    return "null"
end

function encodeTable(tbl) -- local intentionally global only within file scope for recursion
    -- detect array-like
    local isArray = true
    local max = 0
    for k,_ in pairs(tbl) do
        if type(k) ~= "number" then isArray = false; break end
        if k > max then max = k end
    end
    if isArray then
        local parts = {}
        for i = 1, max do parts[#parts+1] = encodeValue(tbl[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        local parts = {}
        for k,v in pairs(tbl) do
            parts[#parts+1] = encodeString(tostring(k)) .. ":" .. encodeValue(v)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end

-- sanitize to remove functions/userdata and convert keys to strings/numbers
local function sanitize(obj)
    if type(obj) ~= "table" then return obj end
    local out = {}
    for k,v in pairs(obj) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            k = tostring(k)
        end
        local vt = type(v)
        if vt == "table" then out[k] = sanitize(v)
        elseif vt == "string" or vt == "number" or vt == "boolean" then out[k] = v
        else out[k] = tostring(v) end
    end
    return out
end

local function ExportToJSON(data, filename)
    if not data then print("GroupRecorder: no data to export") return end
    filename = filename or ("GroupRecorder_" .. date("%Y%m%d_%H%M%S") .. ".json")
    print(filename)
    local ok, content = pcall(function()
        local sanitized = sanitize(data)
        return encodeValue(sanitized)
    end)
    if not ok or not content then
        print("GroupRecorder: failed to encode JSON")
        return
    end
    print(content)
    local success, err = pcall(function() WriteFile(filename, content) end)
    if success then
        print(("GroupRecorder: exported to %s"):format(filename))
    else
        print("GroupRecorder: failed to write file (WriteFile unavailable or error)" .. tostring(err))
    end
end

-- Slash command
SLASH_GROUPRECEXPORT1 = "/grouprecexport"
SlashCmdList["GROUPRECEXPORT"] = function(msg)
    local what, custom = (msg or ""):match("^(%S*)%s*(%S*)")
    if what == "" then what = "pulls" end

    if what == "pulls" then
        ExportToJSON(GroupRecorderDB and GroupRecorderDB.pulls or nil, custom ~= "" and custom or nil)
    elseif what == "groups" then
        ExportToJSON(GroupRecorderDB and GroupRecorderDB.groups or nil, custom ~= "" and custom or nil)
    elseif what == "all" then
        ExportToJSON(GroupRecorderDB, custom ~= "" and custom or nil)
    else
        print("Usage: /grouprecexport [pulls|groups|all] [optional_filename.json]")
    end
end
