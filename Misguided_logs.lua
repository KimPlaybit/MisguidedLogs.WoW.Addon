-- GroupRecorder with GUIDs, boss-pull, role detection and hybrid detection (Classic Era)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")

-- Config: hybrid threshold (players with healing ratio between LOW and HIGH are hybrids)
local HYBRID_LOW = 0.45
local HYBRID_HIGH = 0.55

-- DB init
local function InitDB()
    if not GroupRecorderDB then GroupRecorderDB = {} end
    if not GroupRecorderDB.groups then GroupRecorderDB.groups = {} end
    if not GroupRecorderDB.pulls then GroupRecorderDB.pulls = {} end
end

-- Helpers
local function FullName(name, realm)
    if not name then return nil end
    if not realm or realm == "" then return name end
    return name .. "-" .. realm
end

-- Record current group including GUIDs
local function RecordGroup(timestamp)
    timestamp = timestamp or time()
    local members = {}
    local num = GetNumGroupMembers()
    if IsInRaid() and num and num > 0 then
        for i = 1, num do
            local name, _, subgroup, _, _, class, _, online, isDead, role, isML = GetRaidRosterInfo(i)
            -- GetRaidRosterInfo does not return GUID; try UnitGUID with raid unit
            local unit = "raid"..i
            local guid = UnitExists(unit) and UnitGUID(unit) or nil
            if name then
                members[#members+1] = {name = FullName(name), guid = guid}
            end
        end
    else
        print("testing Group")
        -- player
        local pname = UnitName("player")
        local pguid = UnitGUID("player")
        if pname then members[#members+1] = {name = FullName(pname), guid = pguid} end
        for i = 1, 4 do
            local unit = "party"..i
            if UnitExists(unit) then
                local n = UnitName(unit)
                local g = UnitGUID(unit)
                if n then members[#members+1] = {name = FullName(n), guid = g} end
            end
        end
    end
    GroupRecorderDB.groups[tostring(timestamp)] = members
    
    print(members)
    return members
end

-- Pull tracking state
currentPull = nil
local function StartPull(bossName)
    local ts = time()
    currentPull = {
        start = ts,
        boss = bossName or "unknown",
        players = {}, -- players[name] = {guid=..., fullName=..., realm=..., class=..., damage=0, healing=0, damageTaken=0}
        damageDone = {},
        healingDone = {},
        damageTaken = {},
    }

    -- include all group members and the player
    local function AddUnit(unit)
        if not UnitExists(unit) or not UnitIsPlayer(unit) then return end
        local name = UnitName(unit)
        if not name then return end
        local fullName = name
        local realm = nil
        local short = name:match("^(.-)%-.+$")
        if short then fullName = name; realm = name:match("%-(.+)$") end
        local guid = UnitGUID(unit)
        local class, classFile = UnitClass(unit)
        -- avoid duplicate entries by full name (realm-qualified) or short name
        if not currentPull.players[fullName] then
            currentPull.players[fullName] = {
                guid = guid,
                name = fullName,
                realm = realm,
                class = classFile,
                damage = 0,
                healing = 0,
                damageTaken = 0,
            }
        end
    end

    -- party/raid members
    if IsInRaid() then
        for i=1, GetNumGroupMembers() do
            AddUnit("raid"..i)
        end
    elseif GetNumGroupMembers() > 0 then
        -- party includes player as "player" and party1..party4
        AddUnit("player")
        for i=1, GetNumGroupMembers()-1 do
            AddUnit("party"..i)
        end
    else
        -- solo: add player only
        AddUnit("player")
    end

    -- ensure player present if not already
    AddUnit("player")

    print(currentPull.boss)
    GroupRecorderDB.pulls[tostring(ts)] = currentPull
end

local function EnsurePlayerEntry(name, guid)
    if not name then return nil end
    local p = currentPull.players[name]
    if not p then
        p = {guid = guid, damage = 0, healing = 0, damageTaken = 0}
        currentPull.players[name] = p
    else
        -- fill in guid if previously missing and now available
        if not p.guid and guid then p.guid = guid end
    end
    return p
end

-- Combat log parsing
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        print("Loading DB and group")
        InitDB()
        RecordGroup()
    elseif event == "GROUP_ROSTER_UPDATE" then
        RecordGroup()
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        StartPull(encounterName)
    elseif event == "ENCOUNTER_END" then
        print("EncounterEnded")
        EndPull()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local timestamp, subevent, hideCaster,
              srcGUID, srcName, srcFlags, srcRaidFlags,
              dstGUID, dstName, dstFlags, dstRaidFlags,
              arg11, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19 = CombatLogGetCurrentEventInfo()

        -- Normalize amount for common events
        local amount = nil
        if subevent == "SWING_DAMAGE" then
            amount = arg11
        elseif subevent:match("SPELL_DAMAGE") or subevent:match("RANGE_DAMAGE") then
            amount = arg15 or arg11
            if amount == 0 or amount == -1 then
                amount = arg14
            end
        elseif subevent:match("SPELL_HEAL") or subevent:match("HEAL") then
            amount = arg15 or arg11
        end

        -- Start a pull if none active and a hostile mob gets hit by a player
        if not currentPull then
            if (subevent == "SWING_DAMAGE" or subevent:match("SPELL_DAMAGE") or subevent:match("RANGE_DAMAGE")) then
                if dstGUID and dstGUID:sub(1,6) ~= "Player" and srcGUID and srcGUID:sub(1,6) == "Player" then
                    StartPull(dstName)
                end
            end
        end

        if currentPull then
            -- Track damage done by players
            if subevent == "SWING_DAMAGE" or subevent:match("SPELL_DAMAGE") or subevent:match("RANGE_DAMAGE") then
                local dmg = tonumber(amount) or 0
                if srcName and srcGUID and srcGUID:sub(1,6) == "Player" then
                    -- use srcName as key, store GUID
                    local p = EnsurePlayerEntry(srcName, srcGUID)
                    if p then p.damage = p.damage + dmg end
                    currentPull.damageDone[srcName] = (currentPull.damageDone[srcName] or 0) + dmg
                    print("Damage Done" .. tostring(currentPull.damageDone[srcName]).. ", " .. p.guid)
                    print("Current Damage Done by attack: " .. dmg.. ", " .. p.guid)
                    EndPull()
                end
                -- track damageTaken for targets (who the boss is hitting)
                if dstName and dstGUID and dstGUID:sub(1,6) == "Player" then
                    local p = EnsurePlayerEntry(dstName, dstGUID)
                    if p then p.damageTaken = p.damageTaken + dmg end
                    currentPull.damageTaken[dstName] = (currentPull.damageTaken[dstName] or 0) + dmg
                    print("Damage Taken" .. tostring(currentPull.damageTaken[dstName]) .. ", " .. p.guid)
                    print("sourceGuid" .. srcGUID)
                end
            end

            -- Track healing done by players
            if subevent:match("HEAL") then
                local heal = tonumber(amount) or 0
                if srcName and srcGUID and srcGUID:sub(1,6) == "Player" then
                    local p = EnsurePlayerEntry(srcName, srcGUID)
                    if p then p.healing = p.healing + heal end
                    currentPull.healingDone[srcName] = (currentPull.healingDone[srcName] or 0) + heal
                    print("Heal Done" .. tostring(currentPull.healingDone[srcName]) .. ", " .. p.guid)
                end
            end
        end
    end
end)

-- Analysis utilities
GroupRecorder = GroupRecorder or {}

function GroupRecorder.GetLastGroup()
    local latest, ts = nil, 0
    if not GroupRecorderDB or not GroupRecorderDB.groups then return nil end
    for k,v in pairs(GroupRecorderDB.groups) do
        local t = tonumber(k) or 0
        if t > ts then ts = t; latest = v end
    end
    return latest, ts
end

function GroupRecorder.GetLastPull()
    local latest, ts = nil, 0
    if not GroupRecorderDB or not GroupRecorderDB.pulls then return nil end
    for k,v in pairs(GroupRecorderDB.pulls) do
        local t = tonumber(k) or 0
        if t > ts then ts = t; latest = v end
    end
    return latest, ts
end

function GroupRecorder.AnalyzePull(pull)
    if not pull then return nil end

    -- Determine tank by damageTaken (highest)
    local tankName, tankVal = nil, 0
    for name, dmg in pairs(pull.damageTaken or {}) do
        if dmg > tankVal then tankVal = dmg; tankName = name end
    end

    -- Healers sorted by healing done
    local healers = {}
    for name, amt in pairs(pull.healingDone or {}) do
        -- include GUID from players table if available
        local guid = pull.players and pull.players[name] and pull.players[name].guid or nil
        healers[#healers+1] = {name = name, guid = guid, amount = amt}
    end
    table.sort(healers, function(a,b) return a.amount > b.amount end)

    -- DPS sorted by damage done
    local dps = {}
    for name, amt in pairs(pull.damageDone or {}) do
        local guid = pull.players and pull.players[name] and pull.players[name].guid or nil
        dps[#dps+1] = {name = name, guid = guid, amount = amt}
    end
    table.sort(dps, function(a,b) return a.amount > b.amount end)

    -- Hybrids detection using per-player aggregated players table when available
    local hybrids = {}
    for name, p in pairs(pull.players or {}) do
        local dmg = p.damage or 0
        local heal = p.healing or 0
        local total = dmg + heal
        if total > 0 then
            local healRatio = heal / total
            if healRatio >= HYBRID_LOW and healRatio <= HYBRID_HIGH then
                hybrids[#hybrids+1] = {name = name, guid = p.guid, damage = dmg, healing = heal, healRatio = healRatio}
            end
        end
    end
    table.sort(hybrids, function(a,b) return (a.healRatio > b.healRatio) end)

    return {
        tank = tankName,
        tankDamageTaken = tankVal,
        healers = healers,
        dps = dps,
        hybrids = hybrids,
        raw = pull
    }
end

-- Slash command: summary of last pull (includes GUIDs where available)
SLASH_GROUPREC1 = "/grouprec"
SlashCmdList["GROUPREC"] = function(msg)
    local pull = GroupRecorder.GetLastPull()
    if not pull then
        print("GroupRecorder: no pull recorded")
        return
    end
    local analysis = GroupRecorder.AnalyzePull(pull)
    print(("GroupRecorder: pull on %s started at %s"):format(pull.boss or "unknown", date("%H:%M:%S", pull.start or 0)))
    if analysis.tank then
        local guid = pull.players and pull.players[analysis.tank] and pull.players[analysis.tank].guid or "unknown"
        print(("Tank (most damage taken): %s — %d received — GUID: %s"):format(analysis.tank, analysis.tankDamageTaken, guid))
    else
        print("Tank: unknown")
    end

    if #analysis.healers > 0 then
        print("Healers:")
        for i=1, math.min(5,#analysis.healers) do
            local h = analysis.healers[i]
            print(("  %s — %d — GUID: %s"):format(h.name, h.amount, h.guid or "unknown"))
        end
    else
        print("Healers: none recorded")
    end

    if #analysis.dps > 0 then
        print("DPS:")
        for i=1, math.min(8,#analysis.dps) do
            local d = analysis.dps[i]
            print(("  %s — %d — GUID: %s"):format(d.name, d.amount, d.guid or "unknown"))
        end
    else
        print("DPS: none recorded")
    end

    if #analysis.hybrids > 0 then
        print("Hybrids (≈50/50 heal/dmg):")
        for i=1,#analysis.hybrids do
            local h = analysis.hybrids[i]
            print(("  %s — dmg: %d, heal: %d, heal%%: %.0f%% — GUID: %s"):format(h.name, h.damage, h.healing, h.healRatio*100, h.guid or "unknown"))
        end
    else
        print("Hybrids: none detected")
    end
end
