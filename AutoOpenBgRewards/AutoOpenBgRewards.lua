-- 10.1.25
-- добавить диалоги с запросами на авто-опен и авто-дел
-- удаление персональных уже изученных итемов 

local ADDON_NAME = ...
local MIN_FREE_SLOTS_FOR_AUTO_OPEN = 5
local MAX_MONEY_FOR_AUTO_OPEN = 210 * 10000000 -- первое число (210) = голда в касарях, лимит выше которого не будем опенить автоматом

SetCVar("autoLootDefault","1")
local f=CreateFrame("frame")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
--f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
local scanLaunched,bagsAreFull,InstanceType,curZone
local lockedBagSlot,openTryCount,settings={},{},{}
local lastBagUpdTime=0

-- айди итемов-контейнеров которые будем опенить в авто-моде
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

-- function f:PLAYER_LOGIN()
  -- --print("PLAYER_LOGIN")
  -- f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- end

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
  local t=GetTime()+2
  CreateFrame("frame"):SetScript("OnUpdate", function(self)
    if t<GetTime() then
      if not f:IsEventRegistered("BAG_UPDATE") then
        f:RegisterEvent("BAG_UPDATE")
        print("RegisterEvent BAG_UPDATE")
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

local function CannotScan()
  -- InstanceType = select(2,IsInInstance())
  -- curZone=GetZoneText()
  if 
    scanLaunched
    or not UnitIsConnected("player")
    --or bagsAreFull  
    or curZone==nil
    or curZone==""
    or InstanceType=="pvp" 
    or InstanceType=="arena"
    --or inCrossZone()
    or UnitExists("npc")
    or MerchantFrame:IsVisible()  
    or LootFrame:IsVisible()
    or BankFrame:IsVisible()
    --or MailFrame:IsVisible()
    or TradeFrame:IsVisible()
    or (AuctionFrame and AuctionFrame:IsVisible())
    or (GuildBankFrame and GuildBankFrame:IsVisible())
    --or (settings["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN)  
    --or (settings["stop_if_more_then_X_money"] and GetMoney() > MAX_MONEY_FOR_AUTO_OPEN) 
  then
    return true
  end
  return false
end

function f:CheckAndOpenItems(reason)
  if CannotScan() then 
    --_print("|cffff0000CannotOpen()|r",reason)
    return 
  end

  --_print("|cff00ff00запуск скана итемов...|r", reason..", "..curZone..", "..tostring(inCrossZone())..", "..select(2,IsInInstance()).."")
  _print("|cff00ff00запуск скана итемов...|r", reason)
  scanLaunched=true
  local t=0
  
  f:SetScript("OnUpdate",function(_,elapsed)
    if not scanLaunched then
      _print("|cffff0000скан итемов отмененен по одной из причин: открытие окна вендора/трейда/гб/банка/аука/взаимодействие с нпц/смерть перса/нахождение на кросе/фул сумки/итем заблокирован/не открывается/автолут забагался/лимит голды на открытие в опциях/не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." слотов в сумках в опциях|r")
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
    if reason and reason~="/opentest" then
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
                   (itemID==38233 and settings["auto_delete_path_of_illidan"]) or
                   (itemID==33447 and settings["auto_delete_runic_healing_potion"]) or
                   (itemID==33079 and settings["auto_delete_murloc_costume"] and GetItemCount(33079,true) > 1) or 
                   (itemID==38578 and settings["auto_delete_flag_of_ownership"] and GetItemCount(38578,true) > 1) 
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
      _print("|cff00ff00сумки на наличие треша просканированы|r",reason)
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
              _print("|cffff0000итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r", itemLink, bag, slot)
              if lockedBagSlot[bag.."-"..slot] > 10 then
                _print("|cffff0000скан итемов по опену прерван, итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r", itemLink, bag, slot)
                scanLaunched=nil
                return
              end
              --return
            else
              if lootable and contains(containerIDs, itemID) then
                if UnitExists("npc") then
                  _print("|cffff0000опен итемов прерван изза взаимодействия с нпц|r")
                  scanLaunched=nil
                  return 
                end
                
                if UnitIsDead("player") then
                  _print("|cffff0000опен итемов прерван изза смерти перса|r")
                  scanLaunched=nil
                  return 
                end
              
                if MerchantFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна вендора|r")
                  scanLaunched=nil
                  return 
                end
                
                if MailFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна почты|r")
                  scanLaunched=nil
                  return 
                end
                
                if TradeFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна трейда|r")
                  scanLaunched=nil
                  return 
                end

                if BankFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна банка перса|r")
                  scanLaunched=nil
                  return 
                end
                
                if AuctionFrame and AuctionFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна аука|r")
                  scanLaunched=nil
                  return 
                end
                
                if GuildBankFrame and GuildBankFrame:IsVisible() then
                  _print("|cffff0000опен итемов прерван изза открытия окна гб|r")
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
                
                openTryCount[bag.."-"..slot] = openTryCount[bag.."-"..slot] and openTryCount[bag.."-"..slot]+1 or 1
                
                _print("|cffddff55опеним итем:|r", itemLink, openTryCount[bag.."-"..slot]>1 and "x"..openTryCount[bag.."-"..slot].."", bag, slot)
                
                UseContainerItem(bag, slot)
                
                lockedBagSlot[bag.."-"..slot]=nil
                
                if openTryCount[bag.."-"..slot] > 10 then
                  _print("|cffff0000опен итемов прерван, итем не открывается (x"..openTryCount[bag.."-"..slot].."):|r", itemLink, bag, slot)
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
local width, height = 800, 500
local settingsScrollFrame = CreateFrame("ScrollFrame",ADDON_NAME.."SettingsScrollFrame",InterfaceOptionsFramePanelContainer,"UIPanelScrollFrameTemplate")
settingsScrollFrame.name = GetAddOnMetadata(ADDON_NAME, "Title") .. "" -- Название во вкладке интерфейса
settingsScrollFrame:SetSize(width, height)
settingsScrollFrame:SetVerticalScroll(10)
settingsScrollFrame:SetHorizontalScroll(10)
settingsScrollFrame:Hide()
_G[ADDON_NAME.."SettingsScrollFrameScrollBar"]:SetPoint("topleft",ADDON_NAME.."SettingsScrollFrame","topright",-25,-25)
_G[ADDON_NAME.."SettingsScrollFrameScrollBar"]:SetFrameLevel(1000)
_G[ADDON_NAME.."SettingsScrollFrameScrollBarScrollDownButton"]:SetPoint("top",ADDON_NAME.."SettingsScrollFrameScrollBar","bottom",0,7)

local settingsFrame = CreateFrame("button", nil, InterfaceOptionsFramePanelContainer)
settingsFrame:SetSize(width, height) 
settingsFrame:SetAllPoints(InterfaceOptionsFramePanelContainer)
settingsFrame:Hide()

settingsScrollFrame:SetScrollChild(settingsFrame)

InterfaceOptions_AddCategory(settingsScrollFrame)

settingsScrollFrame:SetScript("OnShow", function()
  settingsFrame:Show()
end)

settingsScrollFrame:SetScript("OnHide", function()
  settingsFrame:Hide()
end)

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
      settings["auto_delete_runic_healing_potion"]=false
      settings["auto_delete_murloc_costume"]=false
      settings["auto_delete_flag_of_ownership"]=false
    end
    _print(""..GetAddOnMetadata(ADDON_NAME, "Title")..": loaded. |cff33aaff/opentest|r - for use or Interface>AddOns for options.")
  end
end)

settingsFrame.TitleText = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
settingsFrame.TitleText:SetPoint("TOPLEFT", 16, -16)
settingsFrame.TitleText:SetText(""..GetAddOnMetadata(ADDON_NAME, "Title")..": Settings")

do
  local tip = CreateFrame("button", nil, settingsFrame)
  tip:SetPoint("center",settingsFrame.TitleText,"center")
  tip:SetSize(settingsFrame.TitleText:GetStringWidth()+11,settingsFrame.TitleText:GetStringHeight()+1) 
  
  tip:SetScript("OnEnter", function(self) 
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(""..GetAddOnMetadata(ADDON_NAME, "Title").."\n\n"..GetAddOnMetadata(ADDON_NAME, "Notes").."", nil, nil, nil, nil, true)
    GameTooltip:Show() 
  end)

  tip:SetScript("OnLeave", function(self) 
    GameTooltip:Hide() 
  end)
end

local options =
{
  {"show_addon_log_in_chat","Выводить лог работы скрипта в чат"},
  {"auto_open_when_received","Открывать все боксы автоматом, при условии, что не на кроссе"},
  {"stop_if_less_then_X_free_bag_slots","Не открывать всё автоматом если меньше, чем "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках"},
  {"stop_if_more_then_X_money","Не открывать всё автоматом если больше, чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках"},
  {"auto_delete_mohawk_grenade","|cffff0000Удалять Индейская граната"},
  {"auto_delete_voodoo_skull","|cffff0000Удалять Череп вудуиста"},
  {"auto_delete_party_grenade","|cffff0000Удалять П.Е.Т.А.Р.Д.А. для вечеринки"},
  {"auto_delete_pot_of_nightmares","|cffff0000Удалять Зелье ночных кошмаров"},
  {"auto_delete_pot_powerful_rejuv","|cffff0000Удалять Мощное зелье омоложения"},
  {"auto_delete_flask_of_pure_mojo","|cffff0000Удалять Настой чистого колдунства"},
  {"auto_delete_path_of_cenarius","|cffff0000Удалять Путь Кенария"},
  {"auto_delete_path_of_illidan","|cffff0000Удалять Путь Иллидана"},
  {"auto_delete_runic_healing_potion","|cffff0000Удалять Рунический флакон с лечебным зельем"},
  {"auto_delete_murloc_costume","|cffff0000Удалять Костюм мурлока если такой уже имеется"},
  {"auto_delete_flag_of_ownership","|cffff0000Удалять Знамя победителя если такое уже имеется"},
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


