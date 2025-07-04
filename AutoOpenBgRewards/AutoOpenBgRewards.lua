local ADDON_NAME, core = ...

local LOCALE = GetLocale()

local ADDON_NAME_LOCALE = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Title-ruRU") or GetAddOnMetadata(ADDON_NAME,"Title")
local ADDON_NAME_LOCALE_SHORT = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"TitleS-ruRU") or GetAddOnMetadata(ADDON_NAME,"TitleShort")
local ADDON_NOTES = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Notes-ruRU") or GetAddOnMetadata(ADDON_NAME,"Notes")
local ADDON_NAME_ABBREV = GetAddOnMetadata(ADDON_NAME,"TitleAbbrv")
local ADDON_VERSION = GetAddOnMetadata(ADDON_NAME,"Version")

local MIN_FREE_SLOTS_FOR_AUTO_OPEN = 5
local MAX_MONEY_FOR_AUTO_OPEN = 210 * 10000000 -- первое число(210) = голда в касарях, лимит выше которого НЕ будем опенить автоматом

local f=CreateFrame("frame")
f.Tip = CreateFrame("GameTooltip",ADDON_NAME.."_ItemCheckTooltip",nil,"GameTooltipTemplate")
f.Tip:SetOwner(UIParent, "ANCHOR_NONE")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
f:RegisterEvent("MERCHANT_CLOSED")
--f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
local _,scanLaunched,bagsAreFull,InstanceType,curZone
local lockedBagSlot,openTryCount,cfg,gcfg,trashItemsCount,containerItemsCount={},{},{},{},{},{}
local lastBagUpdTime=0
local oldAutoLootState=GetCVar("autoLootDefault")

local ZONE_ULDUAR = LOCALE=="ruRU" and "Ульдуар" or "Ulduar"
local ZONE_AZSHARA_CRATER = LOCALE=="ruRU" and "Кратер Азшары" or "Azshara Crater"
local AUCTION_ITEM_SUB_CATEGORY_PET = LOCALE=="ruRU" and "Питомцы" or "Pet"
local AUCTION_ITEM_SUB_CATEGORY_MOUNT = LOCALE=="ruRU" and "Верховые животные" or "Mount"
local BUG_CATEGORY13,ITEM_SOULBOUND,ITEM_SPELL_KNOWN = BUG_CATEGORY13,ITEM_SOULBOUND,ITEM_SPELL_KNOWN
local ITEM_TOOLTIP_SPELL_TEXT_LEARN_COMPANION = LOCALE=="ruRU" and "Использование: Учит призывать этого спутника." or "Use: Teaches you how to summon this companion."
local ITEM_TOOLTIP_SPELL_TEXT_LEARN_COMPANION2 = LOCALE=="ruRU" and "Использование: Учит призывать и отпускать этого спутника." or "Use: Teaches you how to summon and dismiss this companion."
local ITEM_TOOLTIP_SPELL_TEXT_LEARN_MOUNT = LOCALE=="ruRU" and "Использование: Обучает управлению этим верховым животным. Это очень быстрое верховое животное." or "Use: Teaches you how to summon this mount.  This is a very fast mount."
local ITEM_TOOLTIP_TEXT_MOUNT = LOCALE=="ruRU" and "Верховые животные" or "Mount"

local GetContainerNumFreeSlots,GetItemInfo,GetItemCount = GetContainerNumFreeSlots,GetItemInfo,GetItemCount
local GetContainerItemInfo,GetContainerNumSlots,GetContainerItemID = GetContainerItemInfo,GetContainerNumSlots,GetContainerItemID
local GetContainerItemLink = GetContainerItemLink
local GetNetStats, GetTime = GetNetStats, GetTime
local UnitExists, UnitIsDead, UnitIsConnected, UnitIsPVPSanctuary = UnitExists, UnitIsDead, UnitIsConnected, UnitIsPVPSanctuary
local SetCVar, GetCVar = SetCVar, GetCVar
local GetRealZoneText = GetRealZoneText
local UnitName, GetRealmName = UnitName, GetRealmName
local select = select
local print = print
local format = string.format
local floor = math.floor
local tinsert = table.insert 
local tremove = table.remove
local _G = _G

-- стремные функции, которые будут использоваться в коде. надеюсь все проверки правильно сделаю... 
local ClearCursor,PickupContainerItem,DeleteCursorItem,UseContainerItem=ClearCursor,PickupContainerItem,DeleteCursorItem,UseContainerItem

-- айди итемов-контейнеров которые будем опенить в авто-моде
local containerIDs =
{
  38165, -- ларец
  38702, -- красный
  10594, -- сундук наград с поля боя
  44816, -- скари лутбокс
  8507,  -- Festive
  44951, -- ящик бомб (на тест)
}

-- функция отложенного вызова другой функции
local DelayedCall
do
  local f = CreateFrame("Frame")  -- Создаем один фрейм для всех отложенных вызовов
  local calls = {}  -- Таблица для хранения отложенных вызовов
  
  local function OnUpdate(self, elapsed)
    for i, call in ipairs(calls) do
      call.time = call.time + elapsed
      if call.time >= call.delay then
        call.func()
        tremove(calls, i)  -- Удаляем вызов из списка
      end
    end
  end
  
  f:SetScript("OnUpdate", OnUpdate)
  
  -- Основная функция для отложенных вызовов
  DelayedCall = function(delay, func)
    tinsert(calls, { delay = delay, time = 0, func = func })
  end
end

local function contains(table, element)
  for _, value in pairs(table) do
    if (value == element) then
      return true
    end
  end
  return false
end

-- local function rgbToHex(r, g, b)
  -- return format("%02x%02x%02x", floor(255 * r), floor(255 * g), floor(255 * b))
-- end

local function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

local function ChatLink(text,arg1,colorHex)
  text = text or "ТЫК"
  arg1 = arg1 or "TEST"
  colorHex = colorHex or "71d5ff"
  return "|cff"..colorHex.."|Haddon:"..ADDON_NAME.."_link:"..arg1..":|h["..text.."|r|cff"..colorHex.."]|h|r"
end

-- local function _print(msg,msg2,msg3)
  -- if cfg["show_addon_log_in_chat"] then
    -- print(""..ChatLink(ADDON_NAME_ABBREV,"Settings","3399ff")..": "..msg, msg2 and "("..msg2..")" or "", msg3 and "("..msg3..")" or "")
  -- end
-- end

local function _print(...)
  local arg2 = select(2,...)
  if cfg["show_addon_log_in_chat"] or gcfg == nil or (arg2 and type(arg2)=="boolean" and arg2==true) then
    local args = { ... }
    local header = ChatLink(ADDON_NAME_ABBREV, "Settings", "3399ff")
    
    -- Преобразуем первый аргумент в строку; его выводим без скобок
    local output = header .. ": " .. (args[1] or "")
    
    -- Для всех последующих аргументов оборачиваем их в круглые скобки
    for i = 2, #args do
      output = output .. " (" .. tostring(args[i]) .. ")"
    end

    print(output)
  end
end

DEFAULT_CHAT_FRAME:HookScript("OnHyperlinkClick", function(self, link, str, button, ...)
  local linkType, arg1, arg2 = strsplit(":", link)
  if linkType == "addon" and arg1 and arg2 and arg1==""..ADDON_NAME.."_link" then
    _print(arg1,arg2)
    if arg2 == "Settings" then
      InterfaceOptionsFrame_OpenToCategory(f.settingsScrollFrame)
    elseif arg2 == "Confirm_Delete" then
      --f:ScanBags(""..ADDON_NAME.."_Confirm_Delete",true)
      f:ScanBags("OnHyperlinkClick", not cfg["auto_del_trash_confirm"], cfg["auto_open_when_received"] and not cfg["auto_open_confirm"])
    elseif arg2 == "Confirm_Open" then
      --f:ScanBags(""..ADDON_NAME.."_Confirm_Open",nil,true)
      f:ScanBags("OnHyperlinkClick", not cfg["auto_del_trash_confirm"], cfg["auto_open_when_received"] and not cfg["auto_open_confirm"])
    end
  end
end)

do
  local old = ItemRefTooltip.SetHyperlink 
  function ItemRefTooltip:SetHyperlink(link, ...)
    if link:find(ADDON_NAME.."_link") then return end
    return old(self, link, ...)
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

function f:BAG_UPDATE()
  if not cfg["enable_addon"] then return end
  --print("BAG_UPDATE")
  if lastBagUpdTime>=(GetTime()-0.1) then return end
  lastBagUpdTime=GetTime()
  --print("BAG_UPDATE (+)")
  f:ScanBags("BAG_UPDATE", not cfg["auto_del_trash_confirm"], cfg["auto_open_when_received"] and not cfg["auto_open_confirm"])
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

function f:PLAYER_ENTERING_WORLD(byCheckbox)
  InstanceType = select(2,IsInInstance())
  curZone=GetRealZoneText()
  lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
  oldAutoLootState=GetCVar("autoLootDefault")
  
  if not cfg["enable_addon"] then return end
  
  if byCheckbox then _print("f:PLAYER_ENTERING_WORLD(byCheckbox)") end
  
  local t = not byCheckbox and 1 or 0

  DelayedCall(t, function()
    if not f:IsEventRegistered("BAG_UPDATE") then
      f:RegisterEvent("BAG_UPDATE")
      _print("RegisterEvent BAG_UPDATE")
    end
    f:ScanBags("PLAYER_ENTERING_WORLD", nil, cfg["auto_open_when_received"] and not cfg["auto_open_confirm"]) -- скан при входе в игру
    --f:ScanBags("PLAYER_ENTERING_WORLD", not cfg["auto_del_trash_confirm"]) -- скан при входе в игру
    --f:ScanBags(reason, ForceDelTrash, ForceOpen)
    --f:ScanBags(""..ADDON_NAME.."_Confirm_Delete",true)
    --f:ScanBags(""..ADDON_NAME.."_Confirm_Open",nil,true)
  end)
end

function f:MERCHANT_CLOSED()
  f:ScanBags("MERCHANT_CLOSED", nil, cfg["auto_open_when_received"] and not cfg["auto_open_confirm"]) 
  --f:ScanBags("PLAYER_ENTERING_WORLD", not cfg["auto_del_trash_confirm"]) 
end

function f:ZONE_CHANGED_NEW_AREA()
  InstanceType = select(2,IsInInstance())
  curZone=GetRealZoneText()
  lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
end

function f:UI_ERROR_MESSAGE(msg)
  if msg==ERR_INV_FULL and f:HasScript("OnUpdate") then 
    _print("|cffff0000сумки фул|r")
    bagsAreFull=true
  end
end

local function inCrossZone()
  if InstanceType=="pvp" or InstanceType=="arena" or curZone==ZONE_ULDUAR or curZone==ZONE_AZSHARA_CRATER or (InstanceType=="raid" and UnitIsPVPSanctuary("player")) then
    return true
  end
  return false
end

--[[
local function ItemIsSoulbound(bag,slot)
  if not (bag and slot) then return nil end
  f.Tip:ClearLines()
  f.Tip:SetBagItem(bag,slot)
  --f.Tip:Show()
  --print(_G[ADDON_NAME.."_ItemCheckTooltip"]:NumLines(),bag,slot)
  for i = 1, f.Tip:NumLines() do
    if (_G[f.Tip:GetName().."TextLeft"..i]:GetText() == ITEM_SOULBOUND) then
      --local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag,slot)
      --local link = GetContainerItemLink(bag,slot)
      --local id = GetContainerItemID(bag,slot)
      --print(_G[ADDON_NAME.."_ItemCheckTooltipTextLeft"..i]:GetTextColor())
      --print("персональная шмотка детектед:",bag,slot,link,id)
      return true
    end
  end
  --f.Tip:ClearLines()
  return false
end

local function ItemIsAlreadyKnown(bag,slot)
  if not (bag and slot) then return nil end
  f.Tip:ClearLines()
  f.Tip:SetBagItem(bag,slot)
  --f.Tip:Show()
  for i = 1, f.Tip:NumLines() do
    if (_G[f.Tip:GetName().."TextLeft"..i]:GetText() == ITEM_SPELL_KNOWN) then
      --local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag,slot)
      local link = GetContainerItemLink(bag,slot)
      local id = GetContainerItemID(bag,slot)
      --print(_G[ADDON_NAME.."_ItemCheckTooltipTextLeft"..i]:GetTextColor())
      _print("изученная шмотка детектед:",bag,slot,link,id)
      return true
    end
  end
  --f.Tip:ClearLines()
  return false
end

local function ItemIsMount(bag,slot)
  if not (bag and slot) then return nil end
  f.Tip:ClearLines()
  f.Tip:SetBagItem(bag,slot)
  --f.Tip:Show()
  for i = 1, f.Tip:NumLines() do
    local text=_G[f.Tip:GetName().."TextLeft"..i]:GetText()
    if (text == ITEM_TOOLTIP_TEXT_MOUNT or text == ITEM_TOOLTIP_SPELL_TEXT_LEARN_MOUNT) then
      --local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag,slot)
      local link = GetContainerItemLink(bag,slot)
      local id = GetContainerItemID(bag,slot)
      _print("маунт детектед:",bag,slot,link,id)
      return true
    end
  end
  --f.Tip:ClearLines()
  return false
end

local function ItemIsCompanion(bag,slot)
  if not (bag and slot) then return nil end
  f.Tip:ClearLines()
  f.Tip:SetBagItem(bag,slot)
  --f.Tip:Show()
  for i = 1, f.Tip:NumLines() do
    if (_G[f.Tip:GetName().."TextLeft"..i]:GetText() == ITEM_TOOLTIP_SPELL_TEXT_LEARN_COMPANION) then
      --local texture, count, locked, quality, readable, lootable, link = GetContainerItemInfo(bag,slot)
      local link = GetContainerItemLink(bag,slot)
      local id = GetContainerItemID(bag,slot)
      _print("компанион детектед:",bag,slot,link,id)
      return true
    end
  end
  --f.Tip:ClearLines()
  return false
end
]]

local function GetItemTooltipInfo(bag,slot)
  if not (bag and slot) then 
    return nil,nil,nil,nil 
  end
  
  f.Tip:ClearLines()
  f.Tip:SetBagItem(bag,slot)
  
  local isSoulbound,isAlreadyKnown,isMount,isCompanion
  
  for i = 1, f.Tip:NumLines() do
    local text = _G[f.Tip:GetName().."TextLeft"..i]:GetText()
    
    local link = GetContainerItemLink(bag,slot)
    local id = GetContainerItemID(bag,slot)
    
    if (text == ITEM_SOULBOUND) then
      isSoulbound=true
      --_print("персональная шмотка детектед:",bag,slot,link,id)
    elseif (text == ITEM_SPELL_KNOWN) then
      isAlreadyKnown=true
      _print("изученная шмотка детектед:",bag,slot,link,id)
    elseif (text == ITEM_TOOLTIP_SPELL_TEXT_LEARN_COMPANION or text == ITEM_TOOLTIP_SPELL_TEXT_LEARN_COMPANION2) then
      isCompanion=true
      _print("пет детектед:",bag,slot,link,id)
    elseif (text == ITEM_TOOLTIP_TEXT_MOUNT or text == ITEM_TOOLTIP_SPELL_TEXT_LEARN_MOUNT) then
      isMount=true
      _print("маунт детектед:",bag,slot,link,id)
    end
  end
  
  return isSoulbound,isAlreadyKnown,isMount,isCompanion
end

local function CannotScan()
  if
    not cfg["enable_addon"]
    or scanLaunched
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
    --or (cfg["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN)  
    --or (cfg["stop_if_more_then_X_money"] and GetMoney() > MAX_MONEY_FOR_AUTO_OPEN) 
  then
    return true
  end
  return false
end

local function CanOpen()
  if
  (
    not cfg["enable_addon"]
    or UnitExists("npc") 
    or UnitIsDead("player") 
    or MerchantFrame:IsVisible() 
    or SendMailFrame:IsVisible()
    --or MailFrame:IsVisible()
    or TradeFrame:IsVisible()
    or BankFrame:IsVisible() 
    or (AuctionFrame and AuctionFrame:IsVisible())
    or (GuildBankFrame and GuildBankFrame:IsVisible())
    or inCrossZone()
    --or InstanceType=="pvp" 
    --or InstanceType=="arena" 
    or bagsAreFull
    or (cfg["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN)
    or (cfg["stop_if_more_then_X_money"] and GetMoney() > MAX_MONEY_FOR_AUTO_OPEN)
  )
  then
    return false
  end
  return true
end

local function CanDelete()
  if not cfg["enable_addon"] or GetCursorInfo()~=nil then
    return false
  end
  for k,v in pairs(cfg) do
    if k:find("auto_delete") and v==true then
      return true
    end
  end
  return false
end

function f:ScanBags(reason, ForceDelTrash, ForceOpen)
  --print("CanOpen()",CanOpen(),"CannotScan()",CannotScan(),"scanLaunched",scanLaunched)
  if CannotScan() then 
    --_print("|cffff0000CannotOpen()|r",reason)
    return 
  end
  
  --print("ForceDelTrash:",ForceDelTrash,"ForceOpen:",ForceOpen)

  --_print("|cff00ff00запуск скана итемов...|r", reason..", "..curZone..", "..tostring(inCrossZone())..", "..select(2,IsInInstance()).."")
  _print("|cff00ffffзапуск скана итемов...|r", reason)
  scanLaunched=true
  local t=0
  
  --local scanForTrash=not ForceDelTrash
  --local scanForOpen=not ForceOpen
  
  f:SetScript("OnUpdate",function(_,elapsed)
    if not scanLaunched then
      _print("|cffff0000скан итемов отмененен по одной из причин: открытие окна вендора/отправки почты/трейда/гб/банка/аука/взаимодействие с нпц/смерть перса/нахождение на кросе/фул сумки/итем заблокирован/не открывается/автолут забагался/лимит голды на открытие в опциях/не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." слотов в сумках в опциях|r")
      bagsAreFull=nil
      lockedBagSlot,openTryCount,trashItemsCount,containerItemsCount={},{},{},{}
      
      if GetCVar("autoLootDefault")~=oldAutoLootState then
        SetCVar("autoLootDefault",oldAutoLootState)
      end
      
      f:SetScript("OnUpdate",nil)
      return 
    end
    
    t=t+elapsed

    --_print(t)
    if t<(0.1+select(3, GetNetStats())/1000) or LootFrame:IsVisible() then -- ожидание если фрейм лута открыт. анти-тротл система
      return 
    end
    --if t<0.01 or LootFrame:IsVisible() then return end

    -- скан по очистке мусора. если не выбран режим форс автооткрытия 
    if not ForceOpen and CanDelete() then
      for bag = 0,4 do
        for slot = 1,GetContainerNumSlots(bag) do
          local itemID = GetContainerItemID(bag,slot)

          if itemID then 
            --local itemLink = GetContainerItemLink(bag,slot)
            --local itemName = GetItemInfo(itemID)
            local _, _, locked, _, _, _, itemLink = GetContainerItemInfo(bag,slot)
            
            if itemLink then
                
              --local q=ItemIsAlreadyKnown(bag,slot)
              --local w=ItemIsSoulbound(bag,slot)
              -- if ItemIsAlreadyKnown(bag,slot) then
                -- print("ItemIsAlreadyKnown",itemLink)
              -- end
                
              if locked then
                lockedBagSlot[bag.."-"..slot] = lockedBagSlot[bag.."-"..slot] and lockedBagSlot[bag.."-"..slot]+1 or 1
                _print("|cffff0000итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
                if lockedBagSlot[bag.."-"..slot] > 20 then
                  _print("|cffff0000скан итемов по очистке мусора прерван, итем заблокирован (x"..lockedBagSlot[bag.."-"..slot].."):|r",itemLink)
                  scanLaunched=nil
                  return
                end
                --return
              else
                local countInBags=GetItemCount(itemID)
                local countFull=GetItemCount(itemID,true)
                local countInBank=countFull-countInBags
                
                local _, _, quality, _, _, class, subclass = GetItemInfo(itemID)
                
                local isSoulbound,isAlreadyKnown,isMount,isCompanion
                
                if class and subclass and class==BUG_CATEGORY13 and (subclass==AUCTION_ITEM_SUB_CATEGORY_PET or subclass==AUCTION_ITEM_SUB_CATEGORY_MOUNT) then
                  isSoulbound,isAlreadyKnown,isMount,isCompanion = GetItemTooltipInfo(bag,slot) -- судя по всему функция получилась жрущей, юзать ее осторожно - только для категорий маунтов/петов
                end

                if countInBags>0 and quality then
                  if (itemID==43489 and cfg["auto_delete_mohawk_grenade"]) or
                     (itemID==33081 and cfg["auto_delete_voodoo_skull"]) or
                     (itemID==38577 and cfg["auto_delete_party_grenade"]) or
                     (itemID==40081 and cfg["auto_delete_pot_of_nightmares"]) or
                     (itemID==40087 and cfg["auto_delete_pot_powerful_rejuv"]) or
                     (itemID==46378 and cfg["auto_delete_flask_of_pure_mojo"]) or
                     (itemID==46779 and cfg["auto_delete_path_of_cenarius"]) or
                     (itemID==38233 and cfg["auto_delete_path_of_illidan"]) or
                     (itemID==33447 and cfg["auto_delete_runic_healing_potion"]) or
                     (itemID==35223 and cfg["auto_delete_pet_biscuit"]) or
                     (itemID==36930 and cfg["auto_delete_monarch_topaz"]) or
                     (itemID==36918 and cfg["auto_delete_scarlet_ruby"]) or
                     (itemID==36924 and cfg["auto_delete_sky_sapphire"]) or
                     (itemID==36921 and cfg["auto_delete_autumns_glow"]) or
                     (itemID==36927 and cfg["auto_delete_twilight_opal"]) or
                     (itemID==36933 and cfg["auto_delete_forest_emerald"]) or
                     (itemID==33448 and cfg["auto_delete_runic_mana_potion"]) or
                     (itemID==33079 and cfg["auto_delete_murloc_costume_if_has"] and countFull > 1) or 
                     (itemID==38578 and cfg["auto_delete_flag_of_ownership_if_has"] and countFull > 1) or
                     (cfg["auto_delete_soulbound_already_known_mounts_pets"] and (isCompanion or isMount) and isSoulbound and isAlreadyKnown) or
                     (cfg["auto_delete_already_known_pets"] and isCompanion and isAlreadyKnown) or -- изученные спутники
                     (cfg["auto_delete_all_commons_pets"] and isCompanion and quality==1) or -- белые спутники
                     (cfg["auto_delete_all_rare_epic_pets"] and isCompanion and (quality==3 --[[or quality==4]])) -- синие спутники
                     --or ((itemID==159 or itemID==1179 or itemID==1205 or itemID==1645 or itemID==1708 or itemID==2512 or itemID==12644 or itemID==41119) and cfg["auto_delete_test_159"]) -- test
                     --or (itemID==41119) -- test saronite bomb
                     --/dump GetItemCount(38578)
                  then 
                    if not trashItemsCount[itemID] then
                      local countToDel=countInBags
                      if itemID==33079 or itemID==38578 then
                        countToDel=countInBank>0 and countInBags or countInBags-1
                      end
                      trashItemsCount[itemID]=countToDel
                    end

                    if ForceDelTrash then
                      if cfg["show_bags_when_processing"] then
                        OpenAllBags(true)
                      end
                    
                      _print("|cffff0000удаляем мусор:|r",itemLink)
                      ClearCursor()
                      PickupContainerItem(bag, slot)
                      DeleteCursorItem()
                      lockedBagSlot[bag.."-"..slot]=nil
                      trashItemsCount[itemID]=nil
                      t=0
                      return
                    end
                  end
                end
              end
            end
          end
        end
      end
      
      _print("|cff00ff00сумки на наличие мусора просканированы|r",reason)
    end
    
    -- скан по автооткрытию. если не выбран режим форс удаления и включена опция по автооткрытию
    if not ForceDelTrash and cfg["auto_open_when_received"] then
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
                  if not containerItemsCount[itemID] then
                    containerItemsCount[itemID]=GetItemCount(itemID)
                  end
                
                  if ForceOpen then
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
                    
                    if --[[MailFrame:IsVisible()]] SendMailFrame:IsVisible() then
                      _print("|cffff0000опен итемов прерван изза открытия окна отправки почты|r")
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
                    
                    if (cfg["stop_if_less_then_X_free_bag_slots"] and getNumFreeBagSlots() < MIN_FREE_SLOTS_FOR_AUTO_OPEN) then
                      _print("|cffff0000опен итемов прерван изза опции: не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках|r")
                      scanLaunched=nil
                      return 
                    end
                    
                    if (cfg["stop_if_more_then_X_money"] and GetMoney() > MAX_MONEY_FOR_AUTO_OPEN) then
                      _print("|cffff0000опен итемов прерван изза опции: не открывать если больше чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках|r")
                      scanLaunched=nil
                      return
                    end
                    
                    if cfg["show_bags_when_processing"] then
                      OpenAllBags(true)
                    end
                    
                    if GetCVar("autoLootDefault")~="1" then
                      SetCVar("autoLootDefault","1")
                    end
    
                    openTryCount[bag.."-"..slot] = openTryCount[bag.."-"..slot] and openTryCount[bag.."-"..slot]+1 or 1
                    
                    _print("|cffddff55опеним итем:|r", itemLink, openTryCount[bag.."-"..slot]>1 and "x"..openTryCount[bag.."-"..slot].."", bag, slot)
                    
                    UseContainerItem(bag, slot)
                    
                    lockedBagSlot[bag.."-"..slot]=nil
                    
                    if openTryCount[bag.."-"..slot] > 50 then
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
      end
    end
    
    -- сводка по мусору/боксам если не выбран режим форс удаления/открытия
    if not ForceDelTrash and cfg["auto_del_trash_confirm"] and tablelength(trashItemsCount)>0 and CanDelete() then
      --print("test1")
      local allItemsText = ""
      local num = 0
      
      for itemID,itemCount in pairs(trashItemsCount) do
        local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        if name and quality and texture and link then  
          num=num+1
          --local r, g, b = GetItemQualityColor(quality)
          --local qualityColorHex = rgbToHex(r, g, b)
          local curItemText = "|T" .. texture .. ":14|t " ..link.. " |cff888888" .. "x" ..itemCount.. "|r"
          allItemsText = allItemsText == "" and curItemText or allItemsText .. "\n" .. curItemText
        end
      end
      
      local popup = StaticPopup_Show(""..ADDON_NAME.."_Confirm_Delete")
      if popup then
        popup.data = "|cff44aaeeВ сумках найден следующий мусор:|r\n\n"..allItemsText.."\n\n|T" .. STATICPOPUP_TEXTURE_ALERT .. ":15|t |cffff0000УДАЛИМ ЭТОТ ТРЭШ, БРО?|r"
        _print("\n"..popup.data.." => "..ChatLink("Удалить трэш (кликабельно)","Confirm_Delete").." <=")
      end
    end
    
    if not ForceOpen and cfg["auto_open_confirm"] and tablelength(containerItemsCount)>0 and CanOpen() then
      --print("test2")
      local allItemsText = ""
      local num = 0
      
      for itemID,itemCount in pairs(containerItemsCount) do
        local name, link, quality, _, _, _, _, _, _, texture = GetItemInfo(itemID)
        if name and quality and texture and link then
          num=num+1
          --local r, g, b = GetItemQualityColor(quality)
          --local qualityColorHex = rgbToHex(r, g, b)
          local curItemText = "|T" .. texture .. ":14|t " ..link.. " |cff888888" .. "x" ..itemCount.. "|r"
          allItemsText = allItemsText == "" and curItemText or allItemsText .. "\n" .. curItemText
        end
      end
      
      local popup = StaticPopup_Show(""..ADDON_NAME.."_Confirm_Open")
      if popup then
        popup.data = "|cff44aaeeВ сумках найден следующий контейнер:|r\n\n"..allItemsText.."\n\n|cffff0000Открываем всё?|r"
        _print("\n"..popup.data.." "..ChatLink("Открыть всё (кликабельно)","Confirm_Open"))
      end
    end

    _print("|cff00ffffскан итемов завершен успешно|r",reason)
    scanLaunched=nil
    bagsAreFull=nil
    lockedBagSlot,openTryCount,trashItemsCount,containerItemsCount={},{},{},{}
    
    if GetCVar("autoLootDefault")~=oldAutoLootState then
      SetCVar("autoLootDefault",oldAutoLootState)
    end
    
    f:SetScript("OnUpdate",nil)
    
    -- if ForceDelTrash then
      -- f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
    -- elseif ForceOpen then
      -- f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
    -- end
    
    if ForceOpen then
      f:ScanBags("check trash after ForceOpen", not cfg["auto_del_trash_confirm"]) 
    end
    
    return
  end)
end

-- SlashCmdList["opentestqweewq"] = function()
  -- f:ScanBags("/opentest") 
-- end
-- SLASH_opentestqweewq1 = "/opentest"

-- опции: параметр/описание/значение по умолчанию для дефолт конфига
local options =
{
  -- [1] - settingName, 
  -- [2] - checkboxText, 
  -- [3] - tooltipText, 
  -- [4] - значение по умолчанию, не должно быть nil
  -- [5] - minValue, 
  -- [6] - maxValue  
  {"enable_addon","Включить аддон",nil,true},
  {"show_addon_log_in_chat","Выводить лог работы аддона в чат |cffffff00(рекомендуется оставить включенным)",nil,true},
  {"auto_open_when_received","Открывать все боксы автоматически, когда мы не на кроссе",nil,true},
  {"auto_open_confirm","Всегда спрашивать разрешение перед массовым открытием боксов",nil,true},
  {"auto_del_trash_confirm","Всегда спрашивать разрешение перед массовым удалением мусора",nil,true},
  {"show_bags_when_processing","Показывать инвентарь(сумки) в процессе открытия/удаления",nil,true},
  {"stop_if_less_then_X_free_bag_slots","Не открывать боксы если меньше чем "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках",nil,true},
  {"stop_if_more_then_X_money","Не открывать боксы если больше чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках",nil,true},
  {"auto_delete_mohawk_grenade","|cffff0000Удалять мусор: Индейская граната",nil,false},
  {"auto_delete_voodoo_skull","|cffff0000Удалять мусор: Череп вудуиста",nil,false},
  {"auto_delete_party_grenade","|cffff0000Удалять мусор: П.Е.Т.А.Р.Д.А. для вечеринки",nil,false},
  {"auto_delete_pot_of_nightmares","|cffff0000Удалять мусор: Зелье ночных кошмаров",nil,false},
  {"auto_delete_pot_powerful_rejuv","|cffff0000Удалять мусор: Мощное зелье омоложения",nil,false},
  {"auto_delete_flask_of_pure_mojo","|cffff0000Удалять мусор: Настой чистого колдунства",nil,false},
  {"auto_delete_path_of_cenarius","|cffff0000Удалять мусор: Путь Кенария",nil,false},
  {"auto_delete_path_of_illidan","|cffff0000Удалять мусор: Путь Иллидана",nil,false},
  {"auto_delete_runic_healing_potion","|cffff0000Удалять мусор: Рунический флакон с лечебным зельем",nil,false},
  {"auto_delete_murloc_costume_if_has","|cffff0000Удалять мусор: Костюм мурлока если уже есть",nil,false},
  {"auto_delete_flag_of_ownership_if_has","|cffff0000Удалять мусор: Знамя победителя если уже есть",nil,false},
  {"auto_delete_soulbound_already_known_mounts_pets","|cffff0000Удалять мусор: персональные маунты/петы(спутники) если те уже изучены",nil,false},
  {"auto_delete_already_known_pets","|cffff0000Удалять мусор: уже изученные петы(спутники)",nil,false},
  {"auto_delete_all_commons_pets","|cffff0000Удалять мусор: белые петы(спутники), даже если те НЕ изучены",nil,false},
  {"auto_delete_all_rare_epic_pets","|cffff0000Удалять мусор: синие петы(спутники), даже если те НЕ изучены",nil,false},
  {"auto_delete_pet_biscuit","|cffff0000Удалять мусор: Старомодное лакомство для питомцев",nil,false},
  {"auto_delete_monarch_topaz","|cffff0000Удалять мусор: Императорский топаз",nil,false}, -- 36930
  {"auto_delete_scarlet_ruby","|cffff0000Удалять мусор: Алый рубин",nil,false}, -- 36918
  {"auto_delete_sky_sapphire","|cffff0000Удалять мусор: Небесный сапфир",nil,false}, -- 36924
  {"auto_delete_autumns_glow","|cffff0000Удалять мусор: Сияние осени",nil,false}, -- 36921
  {"auto_delete_twilight_opal","|cffff0000Удалять мусор: Сумеречный опал",nil,false}, -- 36927
  {"auto_delete_forest_emerald","|cffff0000Удалять мусор: Лесной изумруд",nil,false}, -- 36933
  {"auto_delete_runic_mana_potion","|cffff0000Удалять мусор: Рунический флакон с зельем маны",nil,false}, -- 33448
  --{"auto_delete_test_159","|cffff0000Удалять мусор: test",nil,false},
}

-- опции\настройки\конфиг - создание фреймов
local width, height = 800, 550
local settingsScrollFrame = CreateFrame("ScrollFrame",ADDON_NAME.."SettingsScrollFrame",InterfaceOptionsFramePanelContainer,"UIPanelScrollFrameTemplate")
settingsScrollFrame.name = ADDON_NAME_LOCALE -- Название во вкладке интерфейса
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

do
  local text = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("TOPLEFT", 16, -16)
  text:SetFont(GameFontNormal:GetFont(), 20, "OUTLINE")
  text:SetText(ADDON_NAME_LOCALE.." ("..ADDON_VERSION..")")
  text:SetJustifyH("LEFT")
  text:SetJustifyV("BOTTOM")
  settingsFrame.TitleText = text
end

do
  local f = CreateFrame("button", nil, settingsFrame)
  f:SetPoint("center",settingsFrame.TitleText,"center")
  f:SetSize(settingsFrame.TitleText:GetStringWidth()+11,settingsFrame.TitleText:GetStringHeight()+1) 
  
  f:SetScript("OnEnter", function(self) 
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(""..ADDON_NAME_LOCALE.." ("..ADDON_VERSION..")\n\n"..ADDON_NOTES.."", nil, nil, nil, nil, true)
    GameTooltip:Show() 
  end)

  f:SetScript("OnLeave", function(self) 
    GameTooltip:Hide() 
  end)
end

-- локальные параметры (более не лезем нонстопом в глобальную область) 27.6.25
function settingsFrame:UpdateLocalConfig()
  for k,v in pairs(gcfg) do
    cfg[k] = v
  end
end

-- функция по созданию чекбокса для конфига
function settingsFrame:CreateCheckbox(settingName,checkboxText,tooltipText,defaultValue,optNum)
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -10-(optNum*10))
  checkbox:SetSize(28,28)
  
  local textFrame = CreateFrame("Button",nil,checkbox) 
  textFrame:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)

  local textRegion = textFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  textRegion:SetText(checkboxText)
  
  textRegion:SetJustifyH("LEFT")
  textRegion:SetJustifyV("BOTTOM")
  
  textRegion:SetAllPoints(textFrame)
  
  textFrame:SetSize(textRegion:GetStringWidth(),textRegion:GetStringHeight()) 
  textFrame:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)

  checkbox:SetScript("OnClick", function(self)
    gcfg[settingName]=self:GetChecked() and true or false
    settingsFrame:UpdateLocalConfig()
    if settingName=="enable_addon" then
      f:PLAYER_ENTERING_WORLD(true)
    end
  end)

  checkbox:SetScript("OnShow", function(self)
    self:SetChecked(gcfg[settingName])
  end)
  
  textFrame:SetScript("OnShow", function(self)
    --self:SetSize(textRegion:GetStringWidth()+50,textRegion:GetStringHeight()) 
    self:SetSize(textRegion:GetStringWidth()+1,textRegion:GetStringHeight())
  end)
  
  textFrame:SetScript("OnEnter", function(self) 
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(tooltipText or checkboxText, 1, 1, 1, nil, true)
    GameTooltip:Show() 
  end)
  
  textFrame:SetScript("OnLeave", function() 
    GameTooltip:Hide() 
  end)
  
  textFrame:SetScript("OnClick", function() 
    if checkbox:GetChecked() then
      checkbox:SetChecked(false)
    else
      checkbox:SetChecked(true)
    end
    gcfg[settingName] = checkbox:GetChecked() and true or false
    settingsFrame:UpdateLocalConfig()
  end)
end

f.settingsScrollFrame = settingsScrollFrame

-- создание опций аддона
function settingsFrame:CreateOptions()
  if settingsFrame.options then return end
  settingsFrame.options=true
  settingsFrame.optNum=0
  
  -- вроде отныне не говнокод для интерфейса настроек (27.1.25)
  -- [1] - settingName, [2] - checkboxText, [3] - tooltipText, [4] - значение по умолчанию, [5] - minValue, [6] - maxValue 
  for i,v in ipairs(options) do
    if v[4]~=nil then
      if type(v[4])=="boolean" then
        settingsFrame:CreateCheckbox(v[1], v[2], v[3], v[4], settingsFrame.optNum)
        if options[i+1] and type(options[i+1][4])=="number" then
          settingsFrame.optNum=settingsFrame.optNum+3
        else
          settingsFrame.optNum=settingsFrame.optNum+2
        end
      elseif type(v[4])=="number" then
        --settingsFrame:createEditBox(v[1], v[2], v[3], v[4], v[5], v[6], settingsFrame.optNum)
        if options[i+1] and type(options[i+1][4])=="boolean" then
          settingsFrame.optNum=settingsFrame.optNum+1.5
        else
          settingsFrame.optNum=settingsFrame.optNum+2
        end
      end
    end
  end
  
  -- old --
  -- do
    -- local num=0
    -- for _,v in ipairs(options) do
      -- -- settingName,checkboxText,tooltipText,defaultValue,optNum
      -- CreateOptionCheckbox(v[1],v[2],num)
      -- num=num+2
    -- end
  -- end
end

function settingsFrame:GetCharacterProfileKeyName()
  return UnitName("player").." ~ "..GetRealmName():gsub("%b[]", ""):gsub("%s+$", "")
end

-- инициализация конфига при загрузке адона
function settingsFrame:InitConfig()
  gcfg = AutoOpenBgRewards_Settings
  
  if not gcfg then
    _print("Инициализация конфига для аккаунта",true)
    gcfg = {}
    AutoOpenBgRewards_Settings = gcfg
  end
  
  local characterProfileKeyName = settingsFrame:GetCharacterProfileKeyName()

  if gcfg[characterProfileKeyName] == nil then
    _print("Инициализация конфига для персонажа",true)
    gcfg[characterProfileKeyName] = {}
    for k,v in pairs(gcfg) do
      if type(v)=="boolean" then
        gcfg[characterProfileKeyName][k] = v
        gcfg[k] = nil
        print("delete obsolete boolean")
      end
    end
  end
  
  gcfg = gcfg[characterProfileKeyName]
  
  for _,v in ipairs(options) do
    --print(gcfg[v[1]],v[1])
    if gcfg[v[1]]==nil then
      --print(type(v[2]))
      if type(v[2])=="table" then
        gcfg[v[1]]={}
        --print("table "..v[1].." created")
      else
        gcfg[v[1]]=v[4]
        _print(""..v[1]..":",tostring(gcfg[v[1]]),"новая опция, задан параметр по умолчанию",true)
      end
    end
  end

  settingsFrame:UpdateLocalConfig()
  
  settingsFrame:CreateOptions()
  
  _print("аддон загружен. Настройки: "..ChatLink("Настройки (кликабельно)","Settings").."")
end

settingsFrame:RegisterEvent("ADDON_LOADED")
settingsFrame:SetScript("onevent", function(_, event, ...) 
  if arg1~=ADDON_NAME then return end
  settingsFrame:InitConfig()
end)

-- диалоговые окна по центру с запросом на подтверждение авто открытия/удаления 
StaticPopupDialogs[""..ADDON_NAME.."_Confirm_Delete"] = {
  text      = ""..ADDON_NAME.."_Confirm_Delete",
  button1    = YES,
  button2    = CANCEL,
  button3    = YES.." + не спрашивать",
  --exclusive  = false,
  timeout   = 0,
  whileDead = false,
  notClosableByLogout = 0,
  showAlert = 1,
  hideOnEscape = true,
  --showAlertGear = 1,
  --closeButton = 1,
  --hideOnEscape = 1,
  OnHide = function(self)
    self:Hide()
  end,
  OnAccept = function(self)
    f:ScanBags(""..ADDON_NAME.."_Confirm_Delete",true)
    self:Hide()
  end,
  OnUpdate = function(self, elapsed)
    if not CanDelete() then
      self:Hide()
    else
      local info = StaticPopupDialogs[""..ADDON_NAME.."_Confirm_Delete"]
      if info and info.showAlert then
        local q=_G[self:GetName().."AlertIcon"]
        q:SetTexture("Interface\\AddOns\\"..ADDON_NAME.."\\pomoykawow.tga")
        q:SetSize(28,28)
      end
      if self.data and self.text:GetText()~=self.data then
        self.text:SetText(self.data)
        StaticPopup_Resize(self, ""..ADDON_NAME.."_Confirm_Delete")
      end
    end
  end,
  OnCancel = function(self, data, reason)
    self:Hide()
  end,
  OnAlt = function(self)
    cfg["auto_del_trash_confirm"]=false
    f:ScanBags(""..ADDON_NAME.."_Confirm_Delete",true)
    self:Hide()
  end,
}  

StaticPopupDialogs[""..ADDON_NAME.."_Confirm_Open"] = {
  text      = ""..ADDON_NAME.."_Confirm_Open",
  button1    = YES,
  button2    = CANCEL,
  button3    = YES.." + не спрашивать",
  --exclusive  = false,
  timeout   = 0,
  whileDead = false,
  notClosableByLogout = 0,
  showAlert = 1,
  hideOnEscape = true,
  --showAlertGear = 1,
  --closeButton = 1,
  --hideOnEscape = 1,
  OnHide = function(self)
    self:Hide()
  end,
  OnAccept = function(self)
    f:ScanBags(""..ADDON_NAME.."_Confirm_Open",nil,true)
    self:Hide()
  end,
  OnUpdate = function(self, elapsed)
    if not CanOpen() then
      self:Hide()
    else
      local info = StaticPopupDialogs[""..ADDON_NAME.."_Confirm_Delete"]
      if info and info.showAlert then
        local q=_G[self:GetName().."AlertIcon"]
        q:SetTexture("Interface\\AddOns\\"..ADDON_NAME.."\\cup.tga")
        q:SetSize(28,28)
      end
      if self.data and self.text:GetText()~=self.data then
        self.text:SetText(self.data)
        StaticPopup_Resize(self, ""..ADDON_NAME.."_Confirm_Delete")
        --_G[self:GetName().."AlertIcon"]:SetSize(20,20)
      end
    end
  end,
  OnCancel = function(self, data, reason)
    self:Hide()
  end,
  OnAlt = function(self)
    cfg["auto_open_confirm"]=false
    f:ScanBags(""..ADDON_NAME.."_Confirm_Open",nil,true)
    self:Hide()
  end,
}  

-- принудительно будем жать кнопки лута если автолут забагался и фрейм показывается больше чем надо
do
  local LootFrameAppearTime = 0
  LootFrame:HookScript("onshow",function()
    --print("LootFrame onshow")
    LootFrameAppearTime=GetTime()
  end)
  
  LootFrame:HookScript("onhide",function()
    --print("LootFrame onhide")
    LootFrameAppearTime=0
  end)

  local t=0
  local tryCount=0
  LootFrame:HookScript("onupdate",function(_,elapsed)
    t=t+elapsed
    if t<(0.1+select(3, GetNetStats())/1000) then return end
    t=0
    
    if not scanLaunched or (LootFrameAppearTime+0.1)>GetTime() then 
      return 
    end
    
    for i=1,LOOTFRAME_NUMBUTTONS do
      local butt=_G["LootButton"..i]
      if butt and butt:IsVisible() then
        _G["LootButton"..i]:Click()
        _print("force LootButton"..i..":Click()")
      else
        tryCount=tryCount+1
      end
    end
    
    if tryCount>5 then 
      tryCount=0
      _print("force CloseLoot()","tryCount>5")
      CloseLoot() 
    end
  end)
end
