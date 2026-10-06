-- Faster auto loot: all loot at once without the game's loot window, unless the player is needed.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. msg)
	else
		print("ok   " .. msg)
	end
end

local function strip(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "[tex]"):gsub("|A.-|a", "[atlas]"))
end
local function rows()
	local list = {}
	for _, o in ipairs(__allFrames) do
		if o.__type == "Button" and o.__parent == LootlineAnchor and o.__shown and rawget(o, "icon") then
			local fs = {}
			for _, c in ipairs(o.__children) do if c.__type == "FontString" then fs[#fs + 1] = c end end
			list[#list + 1] = { frame = o, left = strip(fs[1] and fs[1].__text) }
		end
	end
	return list
end
local function count(text)
	local n = 0
	for _, r in ipairs(rows()) do if r.left:find(text, 1, true) then n = n + 1 end end
	return n
end
local function item(id, n, extra)
	local s = { link = __link(id), quantity = n or 1 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end
local function settle() __tick(0.05, 20) end -- 1s
local function closeWindow() CloseLoot(); settle() end
local function printed(text)
	for _, line in ipairs(__out) do if line:find(text, 1, true) then return true end end
end

__fire("ADDON_LOADED", "Lootline")
__fire("PLAYER_ENTERING_WORLD", true, false)
local db = LootlineDB

-- 1. off by default: nothing changes -------------------------------------------
check(db.fastLoot == false, "Faster auto loot is off by default")
__openLoot({ item(2589, 3), item(2770, 2) }, "Creature-1")
check(__lootWindowShows == 1 and LootFrame:IsShown() and #__lootSlotCalls == 0, "off: the game's loot window opens, Lootline takes nothing")
closeWindow()
check(not LootFrame:IsShown(), "window closed")

-- 2. on: everything at once, no window -----------------------------------------
db.fastLoot = true
local shows, closesBefore = __lootWindowShows, __closeLootCalls
__openLoot({ item(2589, 3), item(2770, 2), { money = true, quantity = 1 } }, "Creature-2")
check(__lootWindowShows == shows and not LootFrame:IsShown(), "on: no loot window")
check(#__lootSlotCalls == 3, "every slot is taken at once (got " .. #__lootSlotCalls .. ")")
check(not LootFrame:IsEventRegistered("LOOT_OPENED"), "the window's LOOT_OPENED is switched off for this loot")
__fire("LOOT_READY", false) -- the client can repeat LOOT_READY within one loot
check(#__lootSlotCalls == 3, "a repeated LOOT_READY does not request the slots again")
settle()
check(LootFrame:IsEventRegistered("LOOT_OPENED"), "and switched back on when the loot closed")
check(count("3x Linen Cloth") == 1 and count("2x Copper Ore") == 1, "one bar per item (loot event and chat line counted once)")
check(__closeLootCalls == closesBefore, "the empty loot closed by itself (Lootline did not have to close it)")

-- 3. Auto Loot key held: the usual window ---------------------------------------
__modifiers.AUTOLOOTTOGGLE = true
shows = __lootWindowShows
__openLoot({ item(2589, 1) }, "Creature-3")
check(__lootWindowShows == shows + 1 and #__lootSlotCalls == 0, "Shift (Auto Loot key) held: the usual loot window")
__modifiers.AUTOLOOTTOGGLE = nil
closeWindow()

-- 4. cases where the game needs the player: the normal window, nothing taken ------
local function expectWindow(slots, why)
	shows = __lootWindowShows
	__openLoot(slots, "Creature-x")
	check(__lootWindowShows == shows + 1 and #__lootSlotCalls == 0 and LootFrame:IsEventRegistered("LOOT_OPENED"), why)
	closeWindow()
end
__items[19019][8] = 1
expectWindow({ item(2589, 1), item(19019, 1) }, "Bind on Pickup item: normal window (the game asks first)")
__items[19019][8] = nil
expectWindow({ item(2589, 1), item(2770, 1, { locked = true }) }, "locked slot (roll / master loot): normal window")
__inGroup = true
expectWindow({ item(10002, 1) }, "in a group, an item at the loot threshold: normal window")
shows = __lootWindowShows
__openLoot({ item(2589, 2) }, "Creature-g")
check(__lootWindowShows == shows and #__lootSlotCalls == 1, "in a group, items below the threshold are still taken at once")
settle()
__inGroup = nil
__freeSlots = 0
expectWindow({ item(2589, 1) }, "no free bag space: normal window")
shows = __lootWindowShows
__openLoot({ { money = true, quantity = 1 } }, "Creature-m")
check(__lootWindowShows == shows and #__lootSlotCalls == 1, "no bag space but only money: still taken at once")
settle()
__freeSlots = 16
__uncached[2770] = true
expectWindow({ item(2770, 1) }, "item the client has not loaded yet: normal window")
__uncached[2770] = nil

-- 5. something fails after all: say so, end the loot, the next loot shows the window
shows = __lootWindowShows
local closes = __closeLootCalls
__openLoot({ item(2589, 1), item(2770, 1, { fail = ERR_INV_FULL }) }, "Creature-9")
check(__lootWindowShows == shows, "looks takeable: no window")
settle()
check(__closeLootCalls == closes + 1 and LootFrame:IsEventRegistered("LOOT_OPENED"), "a slot that could not be taken ends the hidden loot")
check(printed("could not take everything") and printed("Copper Ore") and printed("Loot again"), "and Lootline says what was left")
check(count("Linen Cloth") == 1, "what could be taken still shows its bar")
shows = __lootWindowShows
__openLoot({ item(2770, 1, { fail = ERR_INV_FULL }) }, "Creature-9")
check(__lootWindowShows == shows + 1 and #__lootSlotCalls == 0, "looting that corpse again opens the window")
closeWindow()
shows = __lootWindowShows
__openLoot({ item(2589, 1) }, "Creature-10")
check(__lootWindowShows == shows, "the next corpse is fast again")
settle()

-- 6. the window was already open (LOOT_OPENED came first): leave it, still take everything
LootFrame:Show()
__lootSlots, __lootSlotCalls = { item(2589, 1) }, {}
__fire("LOOT_READY", false)
check(LootFrame:IsEventRegistered("LOOT_OPENED") and #__lootSlotCalls == 1, "window already open: not touched, loot still taken at once")
settle()

-- 7. turning the option off during a loot gives the window back at once ------------
SlashCmdList.LOOTLINE("") -- no Settings API in this test: the stand-alone window
local ui = __ns.optionsUI
check(ui and #ui.tabs == 6 and ui.tabs[6].__text == "Looting", "Looting tab")
local box
for _, o in ipairs(__allFrames) do
	if o.__type == "CheckButton" and rawget(o, "label") and o.label.__text == "Take all loot at once, without the loot window" then box = o end
end
check(box and box:GetChecked(), "checkbox shows the setting")
__openLoot({ item(2589, 1, { fail = ERR_INV_FULL }) }, "Creature-11")
check(not LootFrame:IsEventRegistered("LOOT_OPENED"), "hidden loot in progress")
box:Click()
check(db.fastLoot == false and LootFrame:IsEventRegistered("LOOT_OPENED"), "unticking gives the loot window back right away")
closeWindow()
SlashCmdList.LOOTLINE("fastloot")
check(db.fastLoot == true and box:GetChecked(), "/lootline fastloot turns it on (checkbox follows)")
__openLoot({ item(2589, 1, { fail = ERR_INV_FULL }) }, "Creature-12")
SlashCmdList.LOOTLINE("fastloot")
check(db.fastLoot == false and LootFrame:IsEventRegistered("LOOT_OPENED"), "and off again, giving the window back mid-loot")
closeWindow()

-- 8. an empty loot (corpse clicked again before the client saw it emptied): no empty window
db.fastLoot = true
shows, closes = __lootWindowShows, __closeLootCalls
__openLoot({}, "Creature-13")
check(__lootWindowShows == shows and not LootFrame:IsShown(), "empty loot: no empty loot window")
settle()
check(__closeLootCalls == closes + 1 and LootFrame:IsEventRegistered("LOOT_OPENED"), "the empty loot is closed and the window given back")
LootFrame:Show()
__lootSlots, __lootSlotCalls = {}, {}
__fire("LOOT_READY", false)
settle()
check(not LootFrame:IsShown() and LootFrame:IsEventRegistered("LOOT_OPENED"), "empty window already open (LOOT_OPENED came first): closed")
db.fastLoot = false
shows = __lootWindowShows
__openLoot({}, "Creature-14")
check(__lootWindowShows == shows + 1, "off: an empty loot opens the window as before")
closeWindow()

print(("RESULT: %d failure(s)"):format(failures))
