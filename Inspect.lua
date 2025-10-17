-- InspectAchievements.lua
-- Shows recorded achievements for inspected unit/player

local InspectFrame = CreateFrame("Frame", "GroupRecorderInspectFrame", UIParent, "BasicFrameTemplateWithInset")
InspectFrame:SetSize(360, 200)
InspectFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
InspectFrame:Hide()

InspectFrame.title = InspectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
InspectFrame.title:SetPoint("TOPLEFT", InspectFrame.TitleBg or InspectFrame, "TOPLEFT", 8, -8)
InspectFrame.title:SetText("Recorded Achievements")

local scroll = CreateFrame("ScrollFrame", nil, InspectFrame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 10, -32)
scroll:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -30, 10)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1,1)
scroll:SetScrollChild(content)

local lines = {}
local LINE_HEIGHT = 18
local function EnsureLines(n)
    for i = #lines + 1, n do
        local l = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1)*LINE_HEIGHT)
        l:SetJustifyH("LEFT")
        lines[i] = l
    end
end

local function ClearContent()
    for i=1,#lines do lines[i]:SetText("") end
end

-- Helper: gather achievements for a player by guid or name
local function GetAchievementsForPlayer(identifier) -- identifier can be guid or plain name
    local results = {}
    if not GroupRecorderDB or not GroupRecorderDB.pulls then return results end
    for ts, pull in pairs(GroupRecorderDB.pulls) do
        if pull and pull.achievements then
            for key, ach in pairs(pull.achievements) do
                -- ach entry stored earlier contains class, timestamp, maybe id/name
                -- we try to attribute by matching participating players in pull (guid or name)
                if pull.players then
                    for pname, p in pairs(pull.players) do
                        if (p.guid and identifier == p.guid) or (identifier == pname) or (identifier == (pname:match("^(.-)%-.+$") or pname)) then
                            results[#results+1] = {
                                timestamp = ach.timestamp or tonumber(ts) or tonumber(pull.start) or 0,
                                boss = pull.boss,
                                achievement = ach,
                            }
                            break
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a,b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    return results
end

-- Inspect event handler: when tooltip/inspect occurs, show frame with achievements
local function ShowInspectAchievements(unit)
    if not unit then return end
    if not UnitIsPlayer(unit) then return end

    local guid = UnitGUID(unit)
    local name = UnitName(unit)
    local plainName = name and name:match("^(.-)%-.+$") or name

    local achsByGUID = guid and GetAchievementsForPlayer(guid) or {}
    local achsByName = GetAchievementsForPlayer(name) or {}
    local achsByPlain = plainName and GetAchievementsForPlayer(plainName) or {}

    -- Merge results, avoid duplicates by timestamp+boss+id
    local seen = {}
    local merged = {}
    local function addList(list)
        for _,v in ipairs(list) do
            local id = (v.achievement.id and tostring(v.achievement.id) or tostring(v.achievement.name or "")) .. "|" .. tostring(v.boss) .. "|" .. tostring(v.timestamp)
            if not seen[id] then
                seen[id] = true
                merged[#merged+1] = v
            end
        end
    end
    addList(achsByGUID); addList(achsByName); addList(achsByPlain)

    -- Display
    if #merged == 0 then
        EnsureLines(1)
        ClearContent()
        lines[1]:SetText("No recorded achievements for " .. (name or "player"))
        InspectFrame:SetHeight(80)
        InspectFrame:Show()
        return
    end

    EnsureLines(#merged)
    ClearContent()
    for i,v in ipairs(merged) do
        local timeStr = date("%Y-%m-%d %H:%M:%S", v.timestamp or 0)
        local achName = v.achievement.name or ("Achievement "..tostring(v.achievement.id or ""))
        lines[i]:SetText(("%s — %s — %s"):format(timeStr, achName, tostring(v.boss)))
    end
    local height = math.min(200, 28 + #merged * LINE_HEIGHT)
    InspectFrame:SetHeight(height)
    InspectFrame:Show()
end

-- Hook into Inspect Unit or Player Target: provide slash and right-click menu option
SLASH_GROUPREC_INSPECT1 = "/grinspect"
SlashCmdList["GROUPREC_INSPECT"] = function(msg)
    local name = (msg and msg:match("%S+")) or UnitName("target")
    if not name then print("Usage: /grinspect [name] or target a player") return end
    -- Attempt to find unit by name in group to get GUID; otherwise just search by name in DB
    local unitFound = nil
    for i=1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid"..i) or ("party"..i)
        if UnitExists(unit) and UnitName(unit) == name then unitFound = unit; break end
    end
    if not unitFound and UnitName("target") == name and UnitIsPlayer("target") then unitFound = "target" end
    if unitFound then
        ShowInspectAchievements(unitFound)
    else
        -- fallback: lookup by name string only
        local achs = GetAchievementsForPlayer(name)
        if #achs == 0 then
            print("GroupRecorder: no recorded achievements for " .. name)
        else
            EnsureLines(#achs)
            ClearContent()
            for i,v in ipairs(achs) do
                local timeStr = date("%Y-%m-%d %H:%M:%S", v.timestamp or 0)
                local achName = v.achievement.name or ("Achievement "..tostring(v.achievement.id or ""))
                lines[i]:SetText(("%s — %s — %s"):format(timeStr, achName, tostring(v.boss)))
            end
            InspectFrame:Show()
        end
    end
end

-- Auto-show when inspecting (if you use the Inspect action). Hook INSPECT_READY to try to resolve GUID/name.
InspectFrame:RegisterEvent("INSPECT_READY")
InspectFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "INSPECT_READY" then
        local unit = "mouseover" -- INSPECT_READY doesn't give unit; we rely on target/mouseover or keep manual slash
        -- best-effort: use target if inspecting target
        if UnitExists("target") and UnitIsPlayer("target") then
            ShowInspectAchievements("target")
        end
    end
end)

-- Close on Escape
tinsert(UISpecialFrames, InspectFrame:GetName())
