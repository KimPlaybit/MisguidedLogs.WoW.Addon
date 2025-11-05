-- RaidAddonPresenceChecker_withEncounterFlag.lua
local PREFIX = "PROBECHK"
local TARGETS = { "weakauras", "details", "dbm-core", "threat" }
local RESPONSE_WINDOW = 1.5

local f = CreateFrame("Frame")
local pendingResponders = {}
local results = {}
local awaiting = false
local initiator = nil

-- Public boolean: true if any responder reported target addons at last probe or at encounter start probe
encounterHasTargetAddons = false

local function GroupChannel()
    if IsInRaid() then return "RAID" elseif IsInGroup() then return "PARTY" else return nil end
  end

local function Send(prefix, msg, channel, target)
  C_ChatInfo.RegisterAddonMessagePrefix(prefix)
  if channel == "WHISPER" and target then
    C_ChatInfo.SendAddonMessage(prefix, msg, "WHISPER", target)
  else
    C_ChatInfo.SendAddonMessage(prefix, msg, "RAID")
  end
end

local function matches_target_substr(addonName)
    if not addonName then return false end
    local subs = TARGETS or {}
    local s = addonName:lower()
    for _, sub in ipairs(subs) do
      if string.find(s, sub, 1, true) then 
        return true end
    end
    return false
  end

local function join(tbl)
  if not tbl or #tbl == 0 then return "" end
  return table.concat(tbl, ",")
end


local function CheckLocalTargets()
  local found = {}
  for i = 1, GetNumAddOns() do
    local name = GetAddOnInfo(i)
    if name and name ~= "" then
      local enabled = GetAddOnEnableState(UnitName("player"), name)
      if enabled and enabled > 0 and matches_target_substr(name) then
        table.insert(found, name)
      end
    end
  end
  return join(found)
end

local function summarizeAndSetFlag()
    local any = false
    for pname, tbl in pairs(results) do
        if matches_target_substr(tostring(tbl)) then 
            any = true 
        end
    end
    encounterHasTargetAddons = any
  
    if not awaiting then
      if any then
        print("CheckAddons: one or more responders have WeakAuras/Details/DBM enabled.")
        for pname, tbl in pairs(results) do
            local list = {}
            if matches_target_substr(tostring(tbl)) then 
               print(("CheckAddons: %s has %s enabled."):format(pname, tostring(tbl))) 
            end
        end
      else
        print("CheckAddons complete: no responders reported WeakAuras, Details!, Threatmeters or DBM enabled.")
      end
    end
end



function StartProbe()
    local channel = GroupChannel()
    if not channel then
      print("Probe: not in party or raid.")
      encounterHasTargetAddons = false
      return
    end

    if IsInRaid() then
        channel = "RAID"
    end

    if awaiting then return end
    pending = {}
    results = {}
    
    awaiting = true  
    -- Build expected member list (short names) and check online status
    local expectedMembers = {}
    if IsInRaid() then
      for i = 1, GetNumGroupMembers() do
        local name, _, subgroup, _, _, _, _, online = GetRaidRosterInfo(i)
        if name then
          local sname = Ambiguate(name, "short")
          table.insert(expectedMembers, sname)
          if not online then
            print(("'" .. sname .. "' player is offline, kick in order to fulfill"))
            return
          end
        end
      end
    elseif UnitInParty("player") then
      -- include player
      table.insert(expectedMembers, Ambiguate(UnitName("player"), "short"))
      for i = 1, GetNumSubgroupMembers() do
        local unit = "party"..i
        if UnitExists(unit) then
          local name = UnitName(unit)
          local online = UnitIsConnected(unit)
          if name then
            local sname = Ambiguate(name, "short")
            table.insert(expectedMembers, sname)
            if not online then
              print(("'" .. sname .. "' player is offline, kick in order to fulfill addon achievement"))
              return
            end
          end
        end
      end
    else
      table.insert(expectedMembers, Ambiguate(UnitName("player"), "short"))
    end
    print("checking")
    local me = UnitName("player")

    -- broadcast probe
    Send(PREFIX, "PROBE|" .. me, channel)
    -- immediately record initiator's local missing list so initiator is checked without waiting
    local myMissing = CheckLocalTargets()
    results[me] = myMissing
    print(results[me])

    C_Timer.After(RESPONSE_WINDOW, function()
      -- request details via whisper to each responder
      for name in pairs(pending) do
        Send(PREFIX, "REQ|" .. me, "WHISPER", name)
      end
      C_Timer.After(RESPONSE_WINDOW, function()
        awaiting = false
        
        -- Check for non-responders among expected group members
        for _, member in ipairs(expectedMembers) do
          if not results[member] then
            print(("No answer from '%s' player, is this player missing the addon misguidedlogs?"):format(member))
            encounterHasTargetAddons = true
            return;
          end
        end

        summarizeAndSetFlag()
      end)
    end)
end


f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(_, event, prefix, message, channel, sender, ...)
  if prefix ~= PREFIX then return end
  local senderName = sender:match("([^%-]+)") or sender
  local cmd, payload = message:match("^(%w+)|?(.*)$")
  if cmd == "PROBE" then
    Send(PREFIX, "I_HAVE|" .. UnitName("player"), "RAID")
  elseif cmd == "I_HAVE" then
    pendingResponders[senderName] = true
  elseif cmd == "REQ" then
    local requester = payload
    local found = CheckLocalTargets()
    Send(PREFIX, "RES|" .. found, "WHISPER", requester)
  elseif cmd == "RES" then
    local list = payload
    local tbl = {}
    if list ~= "" then
      for token in string.gmatch(list, "([^,]+)") do
        tbl[token] = true
      end
    end
    results[senderName] = tbl
  end
end)

SLASH_CHECKADDONS1 = "/checkaddons"
SlashCmdList["CHECKADDONS"] = StartProbe