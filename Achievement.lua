-- Achievement map: map encounter name (or encounterID string) -> achievement key/info
-- Update this table to add new boss -> achievement mappings.
local ACHIEVEMENTS_BY_BOSS = {
    ["Onyxia"] = { id = 90001, name = "Onyxia: Single-Class Clear" },
    ["Lucifron"] = { id = 90002, name = "Lucifron: Single-Class Clear" },
    ["Targorr the Dread"] = { id = 1696, name = "Targorr the Dread: Single-Class Clear" },
}

-- Helper: get class from a player name entry in pull.players if available via GUID lookup
local function GetClassFromPlayerEntry(p)
    if not p then return nil end
    -- try to use stored guid to derive class token (GUID contains unit type and hex id; not class)
    -- fallback: try UnitClass for online members (may fail for logged out players)
    print(p.guid)
    if p.guid then
        -- No reliable class from GUID in Classic; attempt UnitName -> class via unit token search
        -- Try searching raid/party/player units for matching GUID
        for i=1, GetNumGroupMembers() do
            local unit = IsInRaid() and ("raid"..i) or ("party"..i)
            if UnitExists(unit) and UnitGUID(unit) == p.guid then
                local _, class = UnitClass(unit)
                return class
            end
        end
        -- check player
        if UnitExists("player") and UnitGUID("player") == p.guid then
            local _, class = UnitClass("player")
            return class
        end
    end
    -- If no GUID match, try name-based lookup (name stored as "Name-Realm" or "Name")
    if p.name then
        local plain = p.name:match("^(.-)%-.+$") or p.name
        -- check raid/party units by name
        for i=1, GetNumGroupMembers() do
            local unit = IsInRaid() and ("raid"..i) or ("party"..i)
            if UnitExists(unit) then
                local uname = UnitName(unit)
                if uname == plain then
                    local _, class = UnitClass(unit)
                    return class
                end
            end
        end
        -- check player
        if UnitExists("player") and UnitName("player") == plain then
            local _, class = UnitClass("player")
            return class
        end
    end
    return nil
end

-- Determine if a pull qualifies as a single-class clear
local function CheckSingleClassAchievement(pull)
    if not pull or not pull.players then return nil end
    local classesSeen = {}
    local contribCount = 0
    for name, p in pairs(pull.players) do
        -- consider player only if they contributed damage or healing ( >0 )
        local contrib = (p.damage or 0) + (p.healing or 0)
        if contrib > 0 then
            contribCount = contribCount + 1
            local class = GetClassFromPlayerEntry(p) or "UNKNOWN"
            classesSeen[class] = (classesSeen[class] or 0) + 1
        end
    end

    if contribCount == 0 then return false, nil end

    -- If exactly one non-UNKNOWN class present or multiple but all same class
    local distinct = 0
    local lastClass = nil
    for cls, _ in pairs(classesSeen) do
        distinct = distinct + 1
        lastClass = cls
    end

    if distinct == 1 and lastClass ~= "UNKNOWN" then
        return true, lastClass
    end
    return false, nil
end

-- Hook into ENCOUNTER_END handling: after EndPull(), evaluate achievements for the ended pull
-- Replace or augment your existing EndPull() with this behavior (keeps existing functionality).
local oldEndPull = EndPull
function EndPull()
    if not currentPull then
        return
    end

    -- capture boss/enounter details
    local pullCopy = currentPull
    pullCopy["end"] = time()

    -- Analyze single-class achievement if the boss has a mapped achievement
    local bossKey = pullCopy.boss and tostring(pullCopy.boss)
    local achInfo = bossKey and ACHIEVEMENTS_BY_BOSS[bossKey]
    if achInfo then
        local ok, cls = CheckSingleClassAchievement(pullCopy)
        if ok and cls then
            pullCopy.achievements = pullCopy.achievements or {}
            pullCopy.achievements[achInfo.id or achInfo.name or bossKey] = {
                id = achInfo.id,
                name = achInfo.name or ("Single-class clear: "..tostring(cls)),
                class = cls,
                timestamp = time(),
            }
            
            NotifyAchievement({
                id = achInfo.id,
                name = achInfo.name or ("Single-class clear: "..tostring(cls)),
                class = cls
            })

            print(("GroupRecorder: achievement '%s' fulfilled on boss %s by class %s"):format(achInfo.name or achInfo.id or bossKey, bossKey, cls))
        end
    end

    -- store final pull and clear currentPull
    GroupRecorderDB.pulls[tostring(pullCopy.start or time())] = pullCopy
    currentPull = nil
end
