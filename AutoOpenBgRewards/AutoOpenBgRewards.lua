-- 18.1.25

local ADDON_NAME = ...
local LOCALE = GetLocale()
local ADDON_NAME_LOCALE_SHORT = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"TitleS-ruRU") or GetAddOnMetadata(ADDON_NAME,"TitleShort")
local ADDON_NAME_LOCALE = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Title-ruRU") or GetAddOnMetadata(ADDON_NAME,"Title")
local ADDON_NOTES = LOCALE=="ruRU" and GetAddOnMetadata(ADDON_NAME,"Notes-ruRU") or GetAddOnMetadata(ADDON_NAME,"Notes")

local MIN_FREE_SLOTS_FOR_AUTO_OPEN = 5
local MAX_MONEY_FOR_AUTO_OPEN = 210 * 10000000 -- первое число(210) = голда в касарях, лимит выше которого не будем опенить автоматом

--SetCVar("autoLootDefault","1")
local f=CreateFrame("frame")
f.Tip = CreateFrame("GameTooltip",ADDON_NAME.."_ItemCheckTooltip",nil,"GameTooltipTemplate")
f.Tip:SetOwner(UIParent, "ANCHOR_NONE")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
--f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, ...) return self[event](self, ...) end)
local _,scanLaunched,bagsAreFull,InstanceType,curZone
local lockedBagSlot,openTryCount,cfg,trashItemsCount,containerItemsCount={},{},{},{},{}
local lastBagUpdTime=0
local AUCTION_ITEM_SUB_CATEGORY_PET = LOCALE=="ruRU" and "Питомцы" or "Pet"
local AUCTION_ITEM_SUB_CATEGORY_MOUNT = LOCALE=="ruRU" and "Верховые животные" or "Mount"
local BUG_CATEGORY13,ITEM_SOULBOUND,ITEM_SPELL_KNOWN = BUG_CATEGORY13,ITEM_SOULBOUND,ITEM_SPELL_KNOWN
local oldAutoLootState=GetCVar("autoLootDefault")
local ZONE_ULDUAR = LOCALE=="ruRU" and "Ульдуар" or "Ulduar"
local ZONE_AZSHARA_CRATER = LOCALE=="ruRU" and "Кратер Азшары" or "Azshara Crater"

local GetContainerNumFreeSlots,GetItemInfo,GetItemCount = GetContainerNumFreeSlots,GetItemInfo,GetItemCount
local GetContainerItemInfo,GetContainerNumSlots,GetContainerItemID = GetContainerItemInfo,GetContainerNumSlots,GetContainerItemID
local GetContainerItemLink = GetContainerItemLink

-- стремные функции, которые будут использоваться в коде. надеюсь все проверки правильно сделаю... 
local ClearCursor,PickupContainerItem,DeleteCursorItem,UseContainerItem=ClearCursor,PickupContainerItem,DeleteCursorItem,UseContainerItem

-- айди итемов-контейнеров которые будем опенить в авто-моде
local containerIDs =
{
  38165, -- ларец
  38702, -- красный
  10594, -- сундук наград с поля боя
  44816, -- скари лутбокс
  --44951, -- ящик бомб (на тест)
}

local function contains(table, element)
  for _, value in pairs(table) do
    if (value == element) then
      return true
    end
  end
  return false
end

local function rgbToHex(r, g, b)
  return string.format("%02x%02x%02x", math.floor(255 * r), math.floor(255 * g), math.floor(255 * b))
end

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

local function _print(msg,msg2,msg3)
  if cfg["show_addon_log_in_chat"] then
    print(""..ChatLink(ADDON_NAME_LOCALE_SHORT,"Settings","3399ff")..": "..msg, msg2 and "("..msg2..")" or "", msg3 and "("..msg3..")" or "")
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
      f:ScanBags("OnHyperlinkClick", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
    elseif arg2 == "Confirm_Open" then
      --f:ScanBags(""..ADDON_NAME.."_Confirm_Open",nil,true)
      f:ScanBags("OnHyperlinkClick", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
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

function f:BAG_UPDATE(...)
  if not cfg["enable_addon"] then return end
  --print("BAG_UPDATE")
  if lastBagUpdTime>=(GetTime()-0.1) then return end
  lastBagUpdTime=GetTime()
  --print("BAG_UPDATE (+)")
  f:ScanBags("BAG_UPDATE", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
  --f:ScanBags("BAG_UPDATE", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
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
  --print("PLAYER_ENTERING_WORLD")
  InstanceType = select(2,IsInInstance())
  curZone=GetZoneText()
  lockedBagSlot,bagsAreFull,openTryCount={},nil,{}
  oldAutoLootState=GetCVar("autoLootDefault")
  if not cfg["enable_addon"] then return end
  local t = not byCheckbox and GetTime()+1 or 0
  CreateFrame("frame"):SetScript("OnUpdate", function(self)
    if t<GetTime() then
      if not f:IsEventRegistered("BAG_UPDATE") then
        f:RegisterEvent("BAG_UPDATE")
        _print("RegisterEvent BAG_UPDATE")
      end
      --local forceAutoDelTrash=cfg["auto_del_trash_confirm"]==true and false or 1
      --local forceAutoOpen=cfg["auto_open_confirm"]==true and false or 1
      --print(forceAutoDelTrash,forceAutoOpen)
      f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
      --f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
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
  if InstanceType=="pvp" or InstanceType=="arena" or curZone==ZONE_ULDUAR or curZone==ZONE_AZSHARA_CRATER then
    return true
  end
  return false
end

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

local function CannotScan()
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
    UnitExists("npc") 
    or UnitIsDead("player") 
    or MerchantFrame:IsVisible() 
    or MailFrame:IsVisible()
    or TradeFrame:IsVisible()
    or BankFrame:IsVisible() 
    or (AuctionFrame and AuctionFrame:IsVisible())
    or (GuildBankFrame and GuildBankFrame:IsVisible())
    or inCrossZone()
    or InstanceType=="pvp" 
    or InstanceType=="arena" 
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
  if GetCursorInfo()==nil then
    return true
  end
  return false
end

function f:ScanBags(reason,forceAutoDelTrash,forceAutoOpen)
  --print("CanOpen()",CanOpen(),"CannotScan()",CannotScan(),"scanLaunched",scanLaunched)
  if CannotScan() then 
    --_print("|cffff0000CannotOpen()|r",reason)
    return 
  end
  
  --print("forceAutoDelTrash:",forceAutoDelTrash,"forceAutoOpen:",forceAutoOpen)

  --_print("|cff00ff00запуск скана итемов...|r", reason..", "..curZone..", "..tostring(inCrossZone())..", "..select(2,IsInInstance()).."")
  _print("|cff00ff00запуск скана итемов...|r", reason)
  scanLaunched=true
  local t=0
  
  f:SetScript("OnUpdate",function(_,elapsed)
    if not scanLaunched then
      _print("|cffff0000скан итемов отмененен по одной из причин: открытие окна вендора/трейда/гб/банка/аука/взаимодействие с нпц/смерть перса/нахождение на кросе/фул сумки/итем заблокирован/не открывается/автолут забагался/лимит голды на открытие в опциях/не открывать если меньше "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." слотов в сумках в опциях|r")
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
    if t<(0.05+select(3, GetNetStats())/1000) or LootFrame:IsVisible() then -- ожидание если фрейм лута открыт
      return 
    end
    --if t<0.01 or LootFrame:IsVisible() then return end

    -- сначала скан по очистке, удалять вроде как можно на кроссе
    if not forceAutoOpen and CanDelete() and not (reason and reason=="/opentest") then
      local _true
      for k,v in pairs(cfg) do
        if k:find("auto_delete") and v==true then
          --print(k)
          _true=true
          break
        end
      end

      if _true then --print("test3")
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

                  if countInBags>0 and quality and class and subclass then
                    if (itemID==43489 and cfg["auto_delete_mohawk_grenade"]) or
                       (itemID==33081 and cfg["auto_delete_voodoo_skull"]) or
                       (itemID==38577 and cfg["auto_delete_party_grenade"]) or
                       (itemID==40081 and cfg["auto_delete_pot_of_nightmares"]) or
                       (itemID==40087 and cfg["auto_delete_pot_powerful_rejuv"]) or
                       (itemID==46378 and cfg["auto_delete_flask_of_pure_mojo"]) or
                       (itemID==46779 and cfg["auto_delete_path_of_cenarius"]) or
                       (itemID==38233 and cfg["auto_delete_path_of_illidan"]) or
                       (itemID==33447 and cfg["auto_delete_runic_healing_potion"]) or
                       (itemID==33079 and cfg["auto_delete_murloc_costume_if_has"] and countFull > 1) or 
                       (itemID==38578 and cfg["auto_delete_flag_of_ownership_if_has"] and countFull > 1) or
                       (cfg["auto_delete_soulbound_already_known_mounts_pets"] and class==BUG_CATEGORY13 and (subclass==AUCTION_ITEM_SUB_CATEGORY_PET or subclass==AUCTION_ITEM_SUB_CATEGORY_MOUNT) and ItemIsSoulbound(bag,slot) and ItemIsAlreadyKnown(bag,slot)) or
                       (cfg["auto_delete_already_known_pets"] and class==BUG_CATEGORY13 and subclass==AUCTION_ITEM_SUB_CATEGORY_PET and ItemIsAlreadyKnown(bag,slot)) or
                       (cfg["auto_delete_all_commons_pets"] and class==BUG_CATEGORY13 and subclass==AUCTION_ITEM_SUB_CATEGORY_PET and quality==1) or 
                       (cfg["auto_delete_all_rare_epic_pets"] and class==BUG_CATEGORY13 and subclass==AUCTION_ITEM_SUB_CATEGORY_PET and (quality==3 or quality==4))
                       --or ((itemID==159 or itemID==1179 or itemID==1205 or itemID==1645 or itemID==1708 or itemID==2512 or itemID==12644 or itemID==41119) and cfg["auto_delete_test_159"]) -- test
                    then 
                      if not trashItemsCount[itemID] then
                        local countToDel=countInBags
                        if itemID==33079 or itemID==38578 then
                          countToDel=countInBank>0 and countInBags or countInBags-1
                        end
                        trashItemsCount[itemID]=countToDel
                      end

                      if forceAutoDelTrash then
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
    end
    
    -- потом по открытию. тут условия по жестче
    if not forceAutoDelTrash and cfg["auto_open_when_received"] then
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
                
                  if forceAutoOpen then
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
      end
    end
    
    if not (forceAutoDelTrash or forceAutoOpen) then
      --print("test2",tablelength(trashItemsCount))
      if cfg["auto_del_trash_confirm"] and tablelength(trashItemsCount)>0 and CanDelete() then
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
          popup.data = "|cff44aaeeВ сумках найден следующий мусор:|r\n\n"..allItemsText.."\n\n|cffff0000УДАЛИМ ЭТОТ ТРЭШ, БРО?|r"
          _print("\n"..popup.data.." "..ChatLink("Удалить трэш (кликабельно)","Confirm_Delete"))
        end
      end
      
      if cfg["auto_open_confirm"] and tablelength(containerItemsCount)>0 and CanOpen() then
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
    end

    _print("|cff00ff00скан итемов завершен успешно|r",reason)
    scanLaunched=nil
    bagsAreFull=nil
    lockedBagSlot,openTryCount,trashItemsCount,containerItemsCount={},{},{},{}
    
    if GetCVar("autoLootDefault")~=oldAutoLootState then
      SetCVar("autoLootDefault",oldAutoLootState)
    end
    
    f:SetScript("OnUpdate",nil)
    
    if forceAutoDelTrash then
      f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
    elseif forceAutoOpen then
      f:ScanBags("PLAYER_ENTERING_WORLD", cfg["auto_del_trash_confirm"]==false, cfg["auto_open_confirm"]==false)
    end
    
    return
  end)
end

SlashCmdList["opentestqweewq"] = function()
  f:ScanBags("/opentest") 
end
SLASH_opentestqweewq1 = "/opentest"

-- опции: параметр/описание/значение по умолчанию для дефолт конфига
local options =
{
  {"enable_addon","Включить аддон",true},
  {"show_addon_log_in_chat","Выводить лог работы кода в чат",true},
  {"auto_open_when_received","Открывать все боксы автоматически, при условии что не на кроссе",true},
  {"auto_open_confirm","Всегда запрашивать разрешение пользователя перед массовым открытием боксов",true},
  {"auto_del_trash_confirm","Всегда запрашивать разрешение пользователя перед массовым удалением мусора",true},
  {"show_bags_when_processing","Показывать инвентарь(сумки) в процессе авто-открытия/удаления",true},
  {"stop_if_less_then_X_free_bag_slots","Не открывать всё автоматом если меньше, чем "..MIN_FREE_SLOTS_FOR_AUTO_OPEN.." свободных слотов в сумках",true},
  {"stop_if_more_then_X_money","Не открывать всё автоматом если больше, чем "..(MAX_MONEY_FOR_AUTO_OPEN/10000000).."к голды в сумках",true},
  {"auto_delete_mohawk_grenade","|cffff0000Удалять мусор: Индейская граната",false},
  {"auto_delete_voodoo_skull","|cffff0000Удалять мусор: Череп вудуиста",false},
  {"auto_delete_party_grenade","|cffff0000Удалять мусор: П.Е.Т.А.Р.Д.А. для вечеринки",false},
  {"auto_delete_pot_of_nightmares","|cffff0000Удалять мусор: Зелье ночных кошмаров",false},
  {"auto_delete_pot_powerful_rejuv","|cffff0000Удалять мусор: Мощное зелье омоложения",false},
  {"auto_delete_flask_of_pure_mojo","|cffff0000Удалять мусор: Настой чистого колдунства",false},
  {"auto_delete_path_of_cenarius","|cffff0000Удалять мусор: Путь Кенария",false},
  {"auto_delete_path_of_illidan","|cffff0000Удалять мусор: Путь Иллидана",false},
  {"auto_delete_runic_healing_potion","|cffff0000Удалять мусор: Рунический флакон с лечебным зельем",false},
  {"auto_delete_murloc_costume_if_has","|cffff0000Удалять мусор: Костюм мурлока если такой уже имеется",false},
  {"auto_delete_flag_of_ownership_if_has","|cffff0000Удалять мусор: Знамя победителя если то уже имеется",false},
  {"auto_delete_soulbound_already_known_mounts_pets","|cffff0000Удалять мусор: персональные маунты/петы ("..ITEM_SOULBOUND..") если те уже изучены ("..ITEM_SPELL_KNOWN..")",false},
  {"auto_delete_already_known_pets","|cffff0000Удалять мусор: уже изученные ("..ITEM_SPELL_KNOWN..") петы",false},
  {"auto_delete_all_commons_pets","|cffff0000Удалять мусор: белые петы, даже если те НЕ изучены",false},
  {"auto_delete_all_rare_epic_pets","|cffff0000Удалять мусор: синие петы, даже если те НЕ изучены",false},
  --{"auto_delete_test_159","|cffff0000Удалять мусор: test",false},
}

-- опции\настройки\конфиг - создание фреймов
local width, height = 800, 500
local settingsScrollFrame = CreateFrame("ScrollFrame",ADDON_NAME.."SettingsScrollFrame",InterfaceOptionsFramePanelContainer,"UIPanelScrollFrameTemplate")
settingsScrollFrame.name = ADDON_NAME_LOCALE_SHORT -- Название во вкладке интерфейса
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

settingsFrame.TitleText = settingsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
settingsFrame.TitleText:SetPoint("TOPLEFT", 24, -16)
settingsFrame.TitleText:SetText(ADDON_NAME_LOCALE)

do
  local f = CreateFrame("button", nil, settingsFrame)
  f:SetPoint("center",settingsFrame.TitleText,"center")
  f:SetSize(settingsFrame.TitleText:GetStringWidth()+11,settingsFrame.TitleText:GetStringHeight()+1) 
  
  f:SetScript("OnEnter", function(self) 
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(""..ADDON_NAME_LOCALE.."\n\n"..ADDON_NOTES.."", nil, nil, nil, nil, true)
    GameTooltip:Show() 
  end)

  f:SetScript("OnLeave", function(self) 
    GameTooltip:Hide() 
  end)
end

-- функция по созданию чекбокса для конфига
local function CreateOptionCheckbox(optionName,optionDescription,num)
  local checkbox = CreateFrame("CheckButton", nil, settingsFrame, "UICheckButtonTemplate")
  checkbox:SetPoint("TOPLEFT", settingsFrame.TitleText, "BOTTOMLEFT", 0, -10-(num*10))

  local textFrame = CreateFrame("Button",nil,checkbox) 
  textFrame:SetPoint("LEFT", checkBox, "RIGHT", 0, 0)

  local textRegion = textFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  --textRegion:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  textRegion:SetText(optionDescription or "")
  
  textRegion:SetJustifyH("LEFT")
  textRegion:SetJustifyV("BOTTOM")
  
  textRegion:SetAllPoints(textFrame)
  
  textFrame:SetSize(textRegion:GetStringWidth()+50,textRegion:GetStringHeight()) 
  textFrame:SetPoint("LEFT", checkbox, "RIGHT", 0, 0)

  checkbox:SetScript("OnClick", function(self)
    cfg[optionName]=self:GetChecked() and true or false
    if optionName=="enable_addon" then
      f:PLAYER_ENTERING_WORLD(true)
    end
  end)

  checkbox:SetScript("onshow", function(self)
    self:SetChecked(cfg[optionName]==true and true or false)
  end)
  
  textFrame:SetScript("OnEnter", function(self) 
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(optionDescription, 1, 1, 1, nil, true)
    GameTooltip:Show() 
  end)
  
  textFrame:SetScript("OnLeave", function(self) 
    GameTooltip:Hide() 
  end)
  
  textFrame:SetScript("OnClick", function() 
    if checkbox:GetChecked() then
      checkbox:SetChecked(false)
    else
      checkbox:SetChecked(true)
    end
    cfg[optionName] = checkbox:GetChecked() and true or false
  end)
end

do
  local num=0
  for _,v in ipairs(options) do
    CreateOptionCheckbox(v[1],v[2],num)
    num=num+2
  end
  options=nil
end

f.settingsScrollFrame = settingsScrollFrame

-- инициализация конфига при загрузке адона
settingsFrame:RegisterEvent("ADDON_LOADED")
settingsFrame:SetScript("onevent", function(_, event, ...) 
  if arg1==ADDON_NAME then
    cfg=AutoOpenBgRewards_Settings or {}
    if AutoOpenBgRewards_Settings == nil then 
      AutoOpenBgRewards_Settings = {}
      cfg=AutoOpenBgRewards_Settings
      for _,v in ipairs(options) do
        cfg[v[1]]=v[3]
      end
      _print("создание дефолтного конфига")
    end
    _print("аддон загружен. Настройки: "..ChatLink("Настройки (кликабельно)","Settings").."")
  end
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

-- хук для лут фрейма если тот багается (лут не собирается/авто-лут забагался)
-- принудительно будем жать кнопки лута если фрейм показывается больше чем 1 секунду
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
    
    if not scanLaunched or (LootFrameAppearTime+1)>GetTime() or not LootFrame:IsVisible() then 
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
      _print("force CloseLoot()")
      CloseLoot() 
    end
  end)
end
