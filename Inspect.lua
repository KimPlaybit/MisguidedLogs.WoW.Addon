-- InspectAchievements.lua
-- Shows recorded achievements for inspected unit/player

local Inspect = CreateFrame("Frame", "Inspect", nil, "BackdropTemplate")
local loaded_inspect_frame = false;

local LINE_HEIGHT = 18
local TAB_TITLE = "MisguidedLogs Achievements"

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
    local nameFull = inspectedUnit and UnitName(inspectedUnit) or other_name or UnitName("target")
    local guid = inspectedUnit and UnitGUID(inspectedUnit)

    -- populate
    local results = {}
    if guid then results = GetAchievementsForPlayer(guid) end
    if #results == 0 and nameFull then results = GetAchievementsForPlayer(nameFull) end
    if #results == 0 and nameFull then
        local plain = nameFull:match("^(.-)%-.+$") or nameFull
        results = GetAchievementsForPlayer(plain)
    end
    PopulateForList(results, nameFull)

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
	-- called inside loading screen before player sees world, some api functions are not available yet.
	-- event handling helper
	self:SetScript("OnEvent", function(self, event, ...)
		self[event](self, ...)
	end)
    
    self:RegisterEvent("PLAYER_LOGIN")
	-- actually start loading the addon once player ui is loading
	self:RegisterEvent("INSPECT_READY")
end

function Inspect:PLAYER_LOGIN()
	self:RegisterEvent("INSPECT_READY")
end

function Inspect:INSPECT_READY(...) 
    if InspectFrame == nil then
        print("InspectFrame is null")
        return
    end
    print("Continued")
    if loaded_inspect_frame == false then
        print("loaded_inspect_frame is false")
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
end

Inspect:Startup()