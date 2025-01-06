local ADDON_NAME = ...
local MIN_FREE_SLOTS_FOR_AUTO_OPEN = 5
local MAX_MONEY_FOR_AUTO_OPEN = 210 * 10000000 -- первое число (210) = голда в касарях

SetCVar("autoLootDefault","1")
local f=CreateFrame("frame")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
--f:RegisterEvent("BAG_UPDATE")
f:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
local scanLaunched,bagsAreFull
local lockedBagSlot,settings={},{}

local function _print(msg,msg2)
  if settings["show_addon_log_in_chat"] then
    print("|cff3399ff[AutoOpen]:|r "..msg, msg2 and "("..msg2..")" or "")
  end
end

function f:BAG_UPDATE(...)
  if not settings["auto_open_when_received"] then return end
  f:CheckAndOpenItems("BAG_UPDATE")
end

local function getNumFreeBagSlots()
  local count = 0
  for i = 0, 4 do
    local numberOfFreeSlots, bagType = GetContainerNumFreeSlots(i)
    if not bagType then
      break
    end
    --_print(bagType,numberOfFreeSlots)
    if bagType == 0 then
      count = count + numberOfFreeSlots
    end
  end
  return count
end

function f:PLAYER_ENTERING_WORLD()
  --print("PLAYER_ENTERING_WORLD")
  if not settings["auto_open_when_received"] then return end
  local t=0
  CreateFrame("frame"):SetScript("OnUpdate", function(self, elapsed)
    t=t+elapsed
    if t>1 then
      if not f:IsEventRegistered("BAG_UPDATE") then
        f:RegisterEvent("BAG_UPDATE")
      end
      f:CheckAndOpenItems("PLAYER_ENTERING_WORLD")
      self:SetScript("OnUpdate", nil)
      self=nil
      return
    end
  end)
end

function f:UI_ERROR_MESSAGE(msg)
  if msg==ERR_INV_FULL and f:HasScript("OnUpdate") then 
    _print("|cffff0000сумки фул|r")
    bagsAreFull=true
  end
end

function f:inCrossZone()
  local isInstance, InstanceType = IsInInstance()
  local curZone=GetZoneText()
  if InstanceType=="pvp" or InstanceType=="arena" or curZone=="Кратер Азшары" or curZone=="Ульдуар" or curZone=="Azshara Crater" or curZone=="Ulduar" then
    return true
  end
  return nil
end

local function CanOpen()
  return not 
  (
  scanLaunched
  or bagsAreFull  
  or f:inCrossZone()  
  or MerchantFrame:IsVisible()  
  or (settings["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN)  
  or (settings["stop_if_more_then_X_money"] and GetMoney()>MAX_MONEY_FOR_AUTO_OPEN)
  )
end

function f:CheckAndOpenItems(reason)
  if not CanOpen() then 
    --_print("|cffff0000not CanOpen()|r",reason)
    return 
  end

  _print("|cff00ff00запуск скана итемов...|r",reason)
  scanLaunched=true
  local t=0
  
  f:SetScript("OnUpdate",function(_,elapsed)
    if not scanLaunched then
      _print("|cffff0000скан итемов отмененен изза: открытия окна вендора/нахождения в крос зоне/фул сумок/итем заблокирован(серый) множество раз/автолут забагался/кап голды включен в опциях/не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." слотов в опциях|r")
      f:SetScript("OnUpdate",nil)
      lockedBagSlot,bagsAreFull={},nil
      return 
    end
    
    t=t+elapsed
    
    --_print(t)
    if t<(0.02+select(3, GetNetStats())/1000) or LootFrame:IsVisible() then 
      return 
    end
    --if t<0.01 or LootFrame:IsVisible() then return end
    
    for bag = 0,4 do
      for slot = 1,GetContainerNumSlots(bag) do
        if MerchantFrame:IsVisible() then
          _print("|cffff0000скан итемов прерван изза открытия окна вендора|r")
          scanLaunched=nil
          return 
        end
        
        if f:inCrossZone() then 
          _print("|cffff0000скан итемов прерван изза нахождения в крос зоне|r")
          scanLaunched=nil
          return 
        end
        
        if bagsAreFull then 
          _print("|cffff0000скан итемов прерван изза фул сумок|r")
          scanLaunched=nil
          return 
        end
        
        if (settings["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN) then
          _print("|cffff0000скан итемов прерван изза опции: Не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках|r")
          scanLaunched=nil
          return 
        end
        
        if (settings["stop_if_more_then_X_money"] and GetMoney()>MAX_MONEY_FOR_AUTO_OPEN) then
          _print("|cffff0000скан итемов прерван, кап голды + открывался ларец|r")
          scanLaunched=nil
          return
        end
        
        local itemID = GetContainerItemID(bag,slot)

        if itemID and (itemID==38165 or itemID==38702 or id==10594) then -- 38165 - ларец, 38702 - красный, 10594 - сундук наград
          --local itemLink = GetContainerItemLink(bag,slot)
          --local itemName = GetItemInfo(itemID)
          local _, _, locked, _, _, lootable, itemLink = GetContainerItemInfo(bag,slot)
          
          if lootable and itemLink then
            if locked then
              lockedBagSlot[bag.."-"..slot] = lockedBagSlot[bag.."-"..slot] and lockedBagSlot[bag.."-"..slot]+1 or 1
              _print("|cffff0000итем заблокирован(серый) "..lockedBagSlot[bag.."-"..slot].." раз(а):|r",itemLink)
              if lockedBagSlot[bag.."-"..slot] > 50 then
                _print("|cffff0000скан итемов прерван, итем заблокирован(серый) "..lockedBagSlot[bag.."-"..slot].." раз(а):|r",itemLink)
                scanLaunched=nil
              end
              return
            end
            
            -- if (settings["stop_if_more_then_X_money"] and GetMoney()>MAX_MONEY_FOR_AUTO_OPEN) and itemID==38165 then
              -- _print("|cffff0000скан итемов прерван, кап голды + открывался ларец|r")
              -- scanLaunched=nil
              -- return
            -- end
            
            _print("|cff00ff00открываем итем:|r",itemLink)
            UseContainerItem(bag, slot)
            t=0
            return
          end
        end
      end
    end
    
    _print("|cff00ff00скан итемов завершен успешно|r",reason)
    scanLaunched=nil
    f:SetScript("OnUpdate",nil)
    return
  end)
end

SlashCmdList["opentestqweewq"] = function()
  f:CheckAndOpenItems("/opentest") 
end
SLASH_opentestqweewq1 = "/opentest"

-- опции\настройки\конфиг
local settingsFrame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
settingsFrame.name = GetAddOnMetadata(ADDON_NAME, "Title") -- Название во вкладке интерфейса
settingsFrame:Hide()

settingsFrame:RegisterEvent("ADDON_LOADED")
settingsFrame:SetScript("onevent", function(_, event, ...) 
  if arg1==ADDON_NAME then
    settings=AutoOpenBgRewards_Settings or {}
    if AutoOpenBgRewards_Settings == nil then 
      AutoOpenBgRewards_Settings = {}
      settings=AutoOpenBgRewards_Settings
      _print(""..GetAddOnMetadata(ADDON_NAME, "Title")..": first load, settings created.")
      settings["auto_open_when_received"]=true
      settings["show_addon_log_in_chat"]=true
      settings["stop_if_less_then_X_free_bag_slots"]=true
      settings["stop_if_more_then_X_money"]=true
    end
    _print(""..GetAddOnMetadata(ADDON_NAME, "Title")..": loaded. |cff33aaff/opentest|r - for use or Interface>AddOns for options.")
  end
end)

settingsFrame.TitleText = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
settingsFrame.TitleText:SetPoint("TOPLEFT", 16, -16)
settingsFrame.TitleText:SetText(""..GetAddOnMetadata(ADDON_NAME, "Title")..": Settings")

do
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -10)

  checkbox.label = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.label:SetText("Открывать все боксы автоматом (при условии что не на кроссе)")

  checkbox:SetScript("OnClick", function(self)
    settings["auto_open_when_received"]=self:GetChecked()
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(settings["auto_open_when_received"])
  end)
end

do
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -30)

  checkbox.label = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.label:SetText("Выводить лог работы скрипта в чат")

  checkbox:SetScript("OnClick", function(self)
    settings["show_addon_log_in_chat"]=self:GetChecked()
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(settings["show_addon_log_in_chat"])
  end)
end

do
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -50)

  checkbox.label = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.label:SetText("Не открывать если меньше чем "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках")

  checkbox:SetScript("OnClick", function(self)
    settings["stop_if_less_then_X_free_bag_slots"]=self:GetChecked()
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(settings["stop_if_less_then_X_free_bag_slots"])
  end)
end

do
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -70)

  checkbox.label = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.label:SetText("Не открывать если больше чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках")

  checkbox:SetScript("OnClick", function(self)
    settings["stop_if_more_then_X_money"]=self:GetChecked()
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(settings["stop_if_more_then_X_money"])
  end)
end

-- Регистрация страницы опций
InterfaceOptions_AddCategory(settingsFrame)


