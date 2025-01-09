local ADDON_NAME = ...
local MIN_FREE_SLOTS_FOR_AUTO_OPEN = 5
local MAX_MONEY_FOR_AUTO_OPEN = 210 * 10000000 -- первое число (210) = голда в касарях

SetCVar("autoLootDefault","1")
local f=CreateFrame("frame")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
f:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
local scanLaunched,bagsAreFull,InstanceType,curZone
local lockedBagSlot,openTryCount,settings={},{},{}
local lastBagUpdTime=0

local containerIDs =
{
  38165, -- ларец
  38702, -- красный
  10594, -- сундук наград
  44816, -- скари лутбокс
}

local function contains(table, element)
  for _, value in pairs(table) do
    if (value == element) then
      return true
    end
  end
  return false
end

local function _print(msg,msg2,msg3)
  if settings["show_addon_log_in_chat"] then
    print("|cff3399ff[AutoOpen]:|r "..msg, msg2 and "("..msg2..")" or "", msg3 and "("..msg3..")" or "")
  end
end

function f:PLAYER_LEAVING_WORLD()
  --print("PLAYER_LEAVING_WORLD")
  if f:IsEventRegistered("BAG_UPDATE") then
    f:UnregisterEvent("BAG_UPDATE")
  end
end

function f:BAG_UPDATE(...)
  if not settings["auto_open_when_received"] then return end
  if lastBagUpdTime+0.1>GetTime() then return end
  lastBagUpdTime=GetTime()
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
  InstanceType = select(2,IsInInstance())
  curZone=GetZoneText()
  lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
  if not settings["auto_open_when_received"] then return end
  local t=0
  CreateFrame("frame"):SetScript("OnUpdate", function(self, elapsed)
    t=t+elapsed
    if t>1 then
      if not f:IsEventRegistered("BAG_UPDATE") then
        f:RegisterEvent("BAG_UPDATE")
        --print("RegisterEvent BAG_UPDATE")
      end
      f:CheckAndOpenItems("PLAYER_ENTERING_WORLD")
      self:SetScript("OnUpdate", nil)
      self=nil
      return
    end
  end)
end

function f:ZONE_CHANGED_NEW_AREA()
  InstanceType = select(2,IsInInstance())
  curZone=GetZoneText()
  lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
end

function f:UI_ERROR_MESSAGE(msg)
  if msg==ERR_INV_FULL and f:HasScript("OnUpdate") then 
    _print("|cffff0000сумки фул|r")
    bagsAreFull=true
  end
end

local function inCrossZone()
  if InstanceType=="pvp" or InstanceType=="arena" or curZone=="Кратер Азшары" or curZone=="Ульдуар" or curZone=="Azshara Crater" or curZone=="Ulduar" then
    return true
  end
  return false
end

local function CannotOpen()
  -- InstanceType = select(2,IsInInstance())
  -- curZone=GetZoneText()
  if 
    scanLaunched
    or not UnitIsConnected("player")
    or bagsAreFull  
    or curZone==nil
    or curZone==""
    or InstanceType=="pvp" 
    or InstanceType=="arena"
    --or inCrossZone()
    or MerchantFrame:IsVisible()  
    or (settings["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN)  
    or (settings["stop_if_more_then_X_money"] and GetMoney() > MAX_MONEY_FOR_AUTO_OPEN) 
  then
    return true
  end
  return false
end

function f:CheckAndOpenItems(reason)
  if CannotOpen() then 
    --_print("|cffff0000CannotOpen()|r",reason)
    return 
  end

  --_print("|cff00ff00запуск скана итемов...|r", reason..", "..curZone..", "..tostring(inCrossZone())..", "..select(2,IsInInstance()).."")
  _print("|cff00ff00запуск скана итемов...|r", reason)
  scanLaunched=true
  local t=0
  
  f:SetScript("OnUpdate",function(_,elapsed)
    if not scanLaunched then
      _print("|cffff0000скан итемов отмененен изза: открытия окна вендора/нахождения на кросе/фул сумок/итем заблокирован/не открывается/автолут забагался/кап голды включен в опциях/не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." слотов в сумках в опциях|r")
      f:SetScript("OnUpdate",nil)
      lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
      return 
    end
    
    t=t+elapsed
    
    --_print(t)
    if t<(0.05+select(3, GetNetStats())/1000) or LootFrame:IsVisible() then -- ожидание если фрейм лута открыт
      return 
    end
    --if t<0.01 or LootFrame:IsVisible() then return end
    
    -- сначала скан по очистке, удалять вроде как можно на кроссе
    for bag = 0,4 do
      for slot = 1,GetContainerNumSlots(bag) do
        local itemID = GetContainerItemID(bag,slot)

        if itemID then 
          --local itemLink = GetContainerItemLink(bag,slot)
          --local itemName = GetItemInfo(itemID)
          local _, _, locked, _, _, _, itemLink = GetContainerItemInfo(bag,slot)
          
          if itemLink then
            if locked then
              lockedBagSlot[bag.."-"..slot] = lockedBagSlot[bag.."-"..slot] and lockedBagSlot[bag.."-"..slot]+1 or 1
              _print("|cffff0000итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
              if lockedBagSlot[bag.."-"..slot] > 20 then
                _print("|cffff0000скан итемов по очистке треша прерван, итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
                scanLaunched=nil
                return
              end
              --return
            else
              if (itemID==43489 and settings["auto_delete_mohawk_grenade"]) or
                 (itemID==33081 and settings["auto_delete_voodoo_skull"]) or
                 (itemID==38577 and settings["auto_delete_party_grenade"]) or
                 (itemID==40081 and settings["auto_delete_pot_of_nightmares"]) or
                 (itemID==40087 and settings["auto_delete_pot_powerful_rejuv"]) or
                 (itemID==46378 and settings["auto_delete_flask_of_pure_mojo"]) or
                 (itemID==46779 and settings["auto_delete_path_of_cenarius"]) or
                 (itemID==38233 and settings["auto_delete_path_of_illidan"]) 
              then 
                _print("|cffff0000удаляем хлам:|r",itemLink)
                ClearCursor()
                PickupContainerItem(bag, slot)
                DeleteCursorItem()
                lockedBagSlot[bag.."-"..slot]=nil
                t=0
                return
              end
            end
          end
        end
      end
    end
    
    -- потом по открытию. тут условия по жестче
    for bag = 0,4 do
      for slot = 1,GetContainerNumSlots(bag) do
        local itemID = GetContainerItemID(bag,slot)

        if itemID then 
          --local itemLink = GetContainerItemLink(bag,slot)
          --local itemName = GetItemInfo(itemID)
          local _, _, locked, _, _, lootable, itemLink = GetContainerItemInfo(bag,slot)
          
          if itemLink then
            if locked then
              lockedBagSlot[bag.."-"..slot] = lockedBagSlot[bag.."-"..slot] and lockedBagSlot[bag.."-"..slot]+1 or 1
              _print("|cffff0000итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
              if lockedBagSlot[bag.."-"..slot] > 10 then
                _print("|cffff0000скан итемов по опену прерван, итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
                scanLaunched=nil
                return
              end
              --return
            else
              if lootable and contains(containerIDs, itemID) then
                if MerchantFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна вендора|r")
                  scanLaunched=nil
                  return 
                end
                
                if inCrossZone() then 
                  _print("|cffff0000опен итемов прерван изза нахождения на кросе|r")
                  scanLaunched=nil
                  return 
                end
                
                if bagsAreFull then 
                  _print("|cffff0000опен итемов прерван изза фул сумок|r")
                  scanLaunched=nil
                  return 
                end
                
                if (settings["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN) then
                  _print("|cffff0000опен итемов прерван изза опции: не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках|r")
                  scanLaunched=nil
                  return 
                end
                
                if (settings["stop_if_more_then_X_money"] and GetMoney()>MAX_MONEY_FOR_AUTO_OPEN) then
                  _print("|cffff0000опен итемов прерван изза опции: не открывать если больше чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках|r")
                  scanLaunched=nil
                  return
                end
                
                _print("|cffddff55опеним итем:|r", itemLink, openTryCount[bag.."-"..slot]>1 and "x"..openTryCount[bag.."-"..slot].."")
                
                UseContainerItem(bag, slot)
                
                lockedBagSlot[bag.."-"..slot]=nil
                
                openTryCount[bag.."-"..slot] = openTryCount[bag.."-"..slot] and openTryCount[bag.."-"..slot]+1 or 1
                
                if openTryCount[bag.."-"..slot] > 10 then
                  _print("|cffff0000опен итемов прерван, итем не открывается (x"..openTryCount[bag.."-"..slot].."):|r",itemLink)
                  scanLaunched=nil
                end
                
                t=0
                return
              end
            end
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
      settings["auto_delete_mohawk_grenade"]=false
      settings["auto_delete_voodoo_skull"]=false
      settings["auto_delete_party_grenade"]=false
      settings["auto_delete_pot_of_nightmares"]=false
      settings["auto_delete_pot_powerful_rejuv"]=false
      settings["auto_delete_flask_of_pure_mojo"]=false
      settings["auto_delete_path_of_cenarius"]=false
      settings["auto_delete_path_of_illidan"]=false
    end
    _print(""..GetAddOnMetadata(ADDON_NAME, "Title")..": loaded. |cff33aaff/opentest|r - for use or Interface>AddOns for options.")
  end
end)

settingsFrame.TitleText = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
settingsFrame.TitleText:SetPoint("TOPLEFT", 16, -16)
settingsFrame.TitleText:SetText(""..GetAddOnMetadata(ADDON_NAME, "Title")..": Settings")

local options =
{
  {"show_addon_log_in_chat","Выводить лог работы скрипта в чат"},
  {"auto_open_when_received","Открывать все боксы автоматом, при условии, что не на кроссе"},
  {"stop_if_less_then_X_free_bag_slots","НЕ открывать автоматом если меньше, чем "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках"},
  {"stop_if_more_then_X_money","НЕ открывать автоматом если больше, чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках"},
  {"auto_delete_mohawk_grenade","Удалять  |T"..select(10,GetItemInfo(43489))..":15|t "..select(1,GetItemInfo(43489)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_voodoo_skull","Удалять  |T"..select(10,GetItemInfo(33081))..":15|t "..select(1,GetItemInfo(33081)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_party_grenade","Удалять  |T"..select(10,GetItemInfo(38577))..":15|t "..select(1,GetItemInfo(38577)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_pot_of_nightmares","Удалять  |T"..select(10,GetItemInfo(40081))..":15|t "..select(1,GetItemInfo(40081)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_pot_powerful_rejuv","Удалять  |T"..select(10,GetItemInfo(40087))..":15|t "..select(1,GetItemInfo(40087)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_flask_of_pure_mojo","Удалять  |T"..select(10,GetItemInfo(46378))..":15|t "..select(1,GetItemInfo(46378)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_path_of_cenarius","Удалять  |T"..select(10,GetItemInfo(46779))..":15|t "..select(1,GetItemInfo(46779)).." |cffff0000(не протестировано, на свой страх и риск)"},
  {"auto_delete_path_of_illidan","Удалять  |T"..select(10,GetItemInfo(38233))..":15|t "..select(1,GetItemInfo(38233)).." |cffff0000(не протестировано, на свой страх и риск)"},
}

local function CreateOptionCheckbox(optionName,optionDescription,num)
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -10-(num*10))

  checkbox.label = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  checkbox.label:SetText(optionDescription or "")

  checkbox:SetScript("OnClick", function(self)
    settings[optionName]=self:GetChecked()
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(settings[optionName])
  end)
end

do
  local num=0
  for _,v in ipairs(options) do
    CreateOptionCheckbox(v[1],v[2],num)
    num=num+2
  end
end

-- Регистрация страницы опций
InterfaceOptions_AddCategory(settingsFrame)


