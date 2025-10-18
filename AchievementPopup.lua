-- AchievePopup.lua
-- Simple popup for achievement notification

local POPUP_FADE_IN = 0.2
local POPUP_SHOW = 3.0
local POPUP_FADE_OUT = 0.5

local popup = CreateFrame("Frame", "GroupRecorderAchPopup", UIParent)
popup:SetSize(220, 60)
popup:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
popup:Hide()

-- Background
popup.bg = popup:CreateTexture(nil, "BACKGROUND")
popup.bg:SetAllPoints(popup)
popup.bg:SetColorTexture(0, 0, 0, 0.6)

-- Icon
popup.icon = popup:CreateTexture(nil, "ARTWORK")
popup.icon:SetSize(48,48)
popup.icon:SetPoint("LEFT", 8, 0)
popup.icon:SetTexture("Interface\\PVPFrame\\Icon-Combat") -- default icon; you can change per-achievement

-- Title text
popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
popup.title:SetPoint("TOPLEFT", popup.icon, "TOPRIGHT", 8, -6)
popup.title:SetJustifyH("LEFT")
popup.title:SetTextColor(1, 0.82, 0)

-- Subtext
popup.sub = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
popup.sub:SetPoint("BOTTOMLEFT", popup.icon, "BOTTOMRIGHT", 8, 6)
popup.sub:SetJustifyH("LEFT")
popup.sub:SetTextColor(1, 1, 1)

-- Animation group
popup.anim = popup:CreateAnimationGroup()
popup.fadeIn = popup.anim:CreateAnimation("Alpha")
popup.fadeIn:SetFromAlpha(0)
popup.fadeIn:SetToAlpha(1)
popup.fadeIn:SetDuration(POPUP_FADE_IN)

popup.pause = popup.anim:CreateAnimation("Alpha")
popup.pause:SetFromAlpha(1)
popup.pause:SetToAlpha(1)
popup.pause:SetDuration(POPUP_SHOW)

popup.fadeOut = popup.anim:CreateAnimation("Alpha")
popup.fadeOut:SetFromAlpha(1)
popup.fadeOut:SetToAlpha(0)
popup.fadeOut:SetDuration(POPUP_FADE_OUT)

popup.anim:SetScript("OnFinished", function()
    popup:Hide()
end)

local function ShowAchievementPopup(title, subtext, iconPath)
    if not title then return end
    popup.title:SetText(title)
    popup.sub:SetText(subtext or "")
    if iconPath and type(iconPath) == "string" then
        popup.icon:SetTexture(iconPath)
    else
        popup.icon:SetTexture("Interface\\PVPFrame\\Icon-Combat")
    end
    popup:SetAlpha(0)
    popup:Show()
    popup.anim:Stop()
    popup.anim:Play()
end

-- Public API: call when an achievement is fulfilled
-- ach: table with fields id (optional), name (string), class (string), icon (optional texture path)
GroupRecorder = GroupRecorder or {}
function GroupRecorder.NotifyAchievement(ach)
    if not ach or not ach.name then return end
    local title = ach.name
    local sub = ach.class and ("Class: "..tostring(ach.class)) or ""
    local icon = ach.icon or ach.iconPath or nil
    ShowAchievementPopup(title, sub, icon)
end