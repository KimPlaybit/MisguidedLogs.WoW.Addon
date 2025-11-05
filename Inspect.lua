-- InspectAchievements.lua
-- Shows recorded achievements for inspected unit/player and requests inspected player's achievements

local Inspect = CreateFrame("Frame", "Inspect", nil, "BackdropTemplate")
local loaded_inspect_frame = false;

local LINE_HEIGHT = 18
local TAB_TITLE = "MisguidedLogs Achievements"

-- Addon message prefix/protocol
local ADDON_PREFIX = "GR_ACH" -- registered on login
local CHUNK_SIZE = 180 -- safe chunk size for SendAddonMessage payload (conservative)
local REQUEST_TAG = "REQ"
local RESPONSE_TAG = "RESP"
local CHUNK_TAG = "CHNK" -- used for multi-chunk responses

-- Reassembly table for incoming chunks
local incomingBuffers = {}

-- Create persistent frames (parent will be set to InspectFrame when shown)
local IPanel = CreateFrame("Frame", nil, UIParent)
IPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, -200)
IPanel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -200, 0)
IPanel:Hide()

local I_f = CreateFrame("Frame", "GroupRecorderInspectPanel", IPanel)
I_f:SetSize(400, 400)
I_f:SetPoint("CENTER")
I_f:Hide()

-- Decorative textures (reuse PaperDoll art like example)
local I_t = I_f:CreateTexture(nil, "ARTWORK")
I_t:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft")
I_t:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 2, -1)
I_t:SetWidth(256); I_t:SetHeight(256)

local I_tr = I_f:CreateTexture(nil, "ARTWORK")
I_tr:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight")
I_tr:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 258, -1)
I_tr:SetWidth(128); I_tr:SetHeight(256)

local I_bl = I_f:CreateTexture(nil, "ARTWORK")
I_bl:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft")
I_bl:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 2, -257)
I_bl:SetWidth(256); I_bl:SetHeight(256)

local I_br = I_f:CreateTexture(nil, "ARTWORK")
I_br:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight")
I_br:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 258, -257)
I_br:SetWidth(128); I_br:SetHeight(256)

local title_text = I_f:CreateFontString(nil, "ARTWORK")
title_text:SetFontObject(GameFontNormalSmall)
title_text:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 100, -50)
title_text:SetTextColor(1, 0.82, 0)
title_text:SetText(TAB_TITLE)

-- Scroll area for achievements
local content = CreateFrame("Frame", "GroupRecorderInspectContent", IPanel)
content:SetSize(293, 348)
content:SetPoint("TOPLEFT", IPanel, "TOPLEFT", 8, -60)

local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
scroll:SetAllPoints(content)
local scrollChild = CreateFrame("Frame", nil, scroll)
scrollChild:SetSize(1,1)
scroll:SetScrollChild(scrollChild)

local lines = {}
local function EnsureLines(n)
    for i = #lines + 1, n do
        local l = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(i-1)*LINE_HEIGHT)
        l:SetJustifyH("LEFT")
        lines[i] = l
    end
end
local function ClearContent() for i=1,#lines do lines[i]:SetText("") end end

-- Data lookup (your original logic)
local function GetAchievementsForPlayer(identifier)
    local results = {}
    if not GroupRecorderDB or not GroupRecorderDB.pulls then return results end
    for ts, pull in pairs(GroupRecorderDB.pulls) do
        if pull and pull.achievements and pull.players then
            for key, ach in pairs(pull.achievements) do
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
    table.sort(results, function(a,b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    return results
end

local function PopulateForList(list, displayName)
    if #list == 0 then
        EnsureLines(1); ClearContent()
        lines[1]:SetText("No recorded achievements for " .. (displayName or "player"))
        return
    end
    EnsureLines(#list); ClearContent()
    for i,v in ipairs(list) do
        local timeStr = date("%Y-%m-%d %H:%M:%S", v.timestamp or 0)
        local achName = v.achievement.name or ("Achievement "..tostring(v.achievement.id or ""))
        lines[i]:SetText(("%s — %s — %s"):format(timeStr, achName, tostring(v.boss)))
    end
end

-- Serialization helpers (very simple, uses ; to separate entries and , for fields)
local function serializeResults(results)
    -- each entry: ts,id,name,boss
    local parts = {}
    for _,v in ipairs(results) do
        local ts = tostring(v.timestamp or 0)
        local id = tostring(v.achievement.id or "")
        local name = (v.achievement.name or ""):gsub("%|", ""):gsub(";", ",")
        local boss = tostring(v.boss or ""):gsub("%|", ""):gsub(";", ",")
        parts[#parts+1] = table.concat({ts, id, name, boss}, "|")
    end
    return table.concat(parts, ";")
end

local function deserializeResults(s)
    if not s or s == "" then return {} end
    local out = {}
    for entry in s:gmatch("[^;]+") do
        local ts, id, name, boss = entry:match("^([^|]+)|([^|]*)|([^|]*)|([^|]*)$")
        out[#out+1] = {
            timestamp = tonumber(ts) or 0,
            boss = boss,
            achievement = { id = tonumber(id) or nil, name = name }
        }
    end
    return out
end

-- Send addon message utilities (handles chunking)
local function SendAddonMessageChunks(prefix, payload, channel, target)
    if #payload <= CHUNK_SIZE then
        C_ChatInfo.SendAddonMessage(prefix, payload, channel, target)
        return
    end
    -- split
    local total = math.ceil(#payload / CHUNK_SIZE)
    for i = 1, total do
        local start = (i-1)*CHUNK_SIZE + 1
        local chunk = payload:sub(start, start + CHUNK_SIZE - 1)
        local header = table.concat({CHUNK_TAG, tostring(i), tostring(total)}, "|")
        local msg = header .. "|" .. chunk
        C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    end
end

-- Request/response logic
local function SendRequestToPlayer(targetName, identifier)
    if not targetName or targetName == "" then return end
    local payload = table.concat({REQUEST_TAG, identifier}, "|")
    -- prefer WHISPER directly to target (inspected player)
    pcall(function()
        SendAddonMessageChunks(ADDON_PREFIX, payload, "WHISPER", targetName)
    end)
end

local function SendResponseToRequester(prefix, channel, requester, payload)
    -- payload should be small-chunked by SendAddonMessageChunks
    SendAddonMessageChunks(prefix, table.concat({RESPONSE_TAG, payload}, "|"), channel, requester)
end

-- Incoming message handler
local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end
    if not message then return end

    local tag, rest = message:match("^([^|]+)|?(.*)$")
    if not tag then return end

    if tag == REQUEST_TAG then
        -- sender requests achievements for identifier rest
        local identifier = rest or ""
        -- get local results from DB
        local results = GetAchievementsForPlayer(identifier)
        local serialized = serializeResults(results)
        -- send response back to sender (use WHISPER)
        SendResponseToRequester(ADDON_PREFIX, "WHISPER", sender, serialized)
        return
    end

    if tag == RESPONSE_TAG then
        -- entire payload single-chunk response
        local payload = rest or ""
        local results = deserializeResults(payload)
        -- display results using sender as displayName
        PopulateForList(results, sender)
        return
    end

    if tag == CHUNK_TAG then
        -- chunked incoming: format "CHNK|index|total|<chunkdata>"
        local idx, total, chunk = rest:match("^(%d+)|(%d+)|(.+)$")
        idx = tonumber(idx); total = tonumber(total)
        if not idx or not total or not chunk then return end
        -- key by sender
        local buf = incomingBuffers[sender] or { total = total, parts = {} }
        buf.total = total
        buf.parts[idx] = chunk
        incomingBuffers[sender] = buf
        -- check if complete
        local complete = true
        for i=1,buf.total do
            if not buf.parts[i] then complete = false; break end
        end
        if complete then
            local full = table.concat(buf.parts)
            incomingBuffers[sender] = nil
            -- full may start with RESP| or similar (if we chunked a RESP payload)
            local subt, subrest = full:match("^([^|]+)|?(.*)$")
            if subt == RESPONSE_TAG then
                local results = deserializeResults(subrest or "")
                PopulateForList(results, sender)
            end
        end
        return
    end
end

-- Show/hide functions modeled after example
function ShowInspectGR(_dummy, other_name)
    if not InspectFrame then return end
    IPanel:SetParent(InspectFrame)
    IPanel:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", -50, -200)
    IPanel:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -200, 0)

    -- reposition textures/title/content relative to InspectFrame
    I_t:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 2, -1)
    I_tr:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 258, -1)
    I_bl:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 2, -257)
    I_br:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 258, -257)
    title_text:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 125, -40)
    content:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 25, -80)

    -- determine inspected unit: prefer InspectFrame.unit if provided by client, else target
    local inspectedUnit = InspectFrame.unit
    if not inspectedUnit or not UnitExists(inspectedUnit) then
        if UnitExists("target") and UnitIsPlayer("target") then inspectedUnit = "target" end
    end
    local nameFull = inspectedUnit and UnitName(inspectedUnit) or other_name or (UnitExists("target") and UnitName("target")) or other_name
    local guid = inspectedUnit and UnitGUID(inspectedUnit)

    -- populate from local DB first
    local results = {}
    if guid then results = GetAchievementsForPlayer(guid) end
    if #results == 0 and nameFull then results = GetAchievementsForPlayer(nameFull) end
    if #results == 0 and nameFull then
        local plain = nameFull:match("^(.-)%-.+$") or nameFull
        results = GetAchievementsForPlayer(plain)
    end
    PopulateForList(results, nameFull)

    -- send a request to the inspected player to return their achievements (if not enough local data)
    if nameFull and (not guid or #results == 0) then
        -- send request using target's name (include realm if returned by UnitName)
        SendRequestToPlayer(nameFull, guid or nameFull)
    end

    IPanel:Show()
    I_f:Show()
    content:Show()
end

function HideInspectGR()
    IPanel:Hide()
    I_f:Hide()
    content:Hide()
    ClearContent()
end


-- Close on Escape
function Inspect:Startup()
	-- the entry point of our addon
	self:SetScript("OnEvent", function(self, event, ...)
		self[event](self, ...)
	end)
    
    self:RegisterEvent("PLAYER_LOGIN")
	self:RegisterEvent("INSPECT_READY")
end

function Inspect:PLAYER_LOGIN()
	-- register addon prefix for messages
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
    end
	self:RegisterEvent("INSPECT_READY")
end

function Inspect:INSPECT_READY(...) 
    if InspectFrame == nil then
        return
    end
    if loaded_inspect_frame == false then
        loaded_inspect_frame = true
        local ITabName = "Achievements"
        local ITabID = InspectFrame.numTabs + 1
        local ITab =
            CreateFrame("Button", "$parentTab" .. ITabID, InspectFrame, "CharacterFrameTabButtonTemplate", ITabName)
        PanelTemplates_SetNumTabs(InspectFrame, ITabID)
        PanelTemplates_SetTab(InspectFrame, 1)

        ITab:SetPoint("LEFT", "$parentTab" .. (ITabID - 1), "RIGHT", -16, 0)
        ITab:SetText(ITabName)
    end
    if _G["InspectHonorFrame"] ~= nil then
		hooksecurefunc(_G["InspectHonorFrame"], "Show", function(self)
			HideInspectGR()
		end)
	end

	if _G["InspectPaperDollFrame"] ~= nil then
		hooksecurefunc(_G["InspectPaperDollFrame"], "Show", function(self)
			HideInspectGR()
		end)
	end

	if _G["InspectPVPFrame"] ~= nil then
		hooksecurefunc(_G["InspectPVPFrame"], "Show", function(self)
			HideInspectGR()
		end)
	end

	if _G["InspectTalentFrame"] ~= nil then
		hooksecurefunc(_G["InspectTalentFrame"], "Show", function(self)
			HideInspectGR()
		end)
	end

    hooksecurefunc("CharacterFrameTab_OnClick", function(self)
		local name = self:GetName()
		if
			(name ~= "InspectFrameTab3" and _G["MisguidedLogsBuildLabel"] ~= "WotLK")
			or (name ~= "InspectFrameTab4" and _G["MisguidedLogsBuildLabel"] == "WotLK")
		then -- 3:era, 4:wotlk
			return
		end
		if _G["MisguidedLogsBuildLabel"] == "WotLK" then
			PanelTemplates_SetTab(InspectFrame, 4)
		else
			PanelTemplates_SetTab(InspectFrame, 3)
		end
		if _G["InspectPaperDollFrame"] ~= nil then
			_G["InspectPaperDollFrame"]:Hide()
		end
		if _G["InspectHonorFrame"] ~= nil then
			_G["InspectHonorFrame"]:Hide()
		end
		if _G["InspectPVPFrame"] ~= nil then
			_G["InspectPVPFrame"]:Hide()
		end
		if _G["InspectTalentFrame"] ~= nil then
			_G["InspectTalentFrame"]:Hide()
		end

		target_name = UnitName("target")			
		ShowInspectGR(nil)
	end)

	hooksecurefunc(InspectFrame, "Hide", function(self, button)
		HideInspectGR()
	end)

    -- listen for addon messages
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:SetScript("OnEvent", function(_, _, prefix, message, channel, sender, ...)
        OnAddonMessage(prefix, message, channel, sender)
    end)
end

Inspect:Startup()
