-- Options window tests: every control writes its setting, the filters really hide bars,
-- and the window follows changes made elsewhere (slash commands, dragging, defaults).
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

-- a control found by the text of its label
local function control(text, objType)
	for _, o in ipairs(__allFrames) do
		if rawget(o, "label") and (not objType or o.__type == objType) and strip(o.label.__text) == text then return o end
	end
end
-- first visible button with this text
local function button(text)
	for _, o in ipairs(__allFrames) do
		if o.__type == "Button" and strip(o.__text) == text and o:IsVisible() then return o end
	end
end
-- visible font string under `parent` containing `needle`
local function textOn(parent, needle)
	for _, c in ipairs(parent.__children) do
		if c.__type == "FontString" and c:IsVisible() and strip(c.__text):find(needle, 1, true) then return c end
	end
end
local function typeInto(box, text)
	box:SetFocus()
	box:SetText(text)
	box.__scripts.OnEnterPressed(box)
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
local function find(text)
	for _, r in ipairs(rows()) do
		if r.left:find(text, 1, true) then return r end
	end
end
local function chatLoot(id, n)
	if n and n > 1 then
		__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF_MULTIPLE:format(__link(id), n), "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
	else
		__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(__link(id)), "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
	end
end
local CURRENCY_MSG = CURRENCY_GAINED_MULTIPLE:format("|cffffffff|Hcurrency:1166:0|h[Timewarped Badge]|h|r", 40)
local REP_MSG = FACTION_STANDING_INCREASED:format("Iskaara Tuskarr", 80)
local function clear() SlashCmdList.LOOTLINE("clear") end
local function settle() __tick(0.05, 10) end

-- Fake game Options window (SettingsPanel) and Settings API that treat a canvas page like
-- Blizzard's: OpenToCategory parents the page to the canvas, shows it and calls OnRefresh;
-- closing the window hides the page.
local registered = {}
local canvas = CreateFrame("Frame", nil, UIParent) -- SettingsPanel.Container.SettingsCanvas
SettingsPanel = { shown = false, closed = 0 }
function SettingsPanel:IsShown() return self.shown end
function SettingsPanel:Close()
	self.shown = false
	self.closed = self.closed + 1
	registered.frame:Hide()
end
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		registered.frame, registered.name = frame, name
		return { name = name, GetID = function() return 42 end }
	end,
	RegisterAddOnCategory = function(cat) registered.category = cat end,
	OpenToCategory = function(id)
		registered.opened = id
		SettingsPanel.shown = true
		local f = registered.frame
		f:SetParent(canvas)
		f:ClearAllPoints()
		f:SetAllPoints(canvas)
		f:Show()
		if f.OnRefresh then f:OnRefresh() end
	end,
}

__fire("ADDON_LOADED", "Lootline")
__money = 1000000
__fire("PLAYER_ENTERING_WORLD", true, false)
local db = LootlineDB
check(db.minValue == 0 and db.questAlways == true, "new settings get their defaults")
check(registered.name == "Lootline" and registered.category ~= nil and __ns.settingsCategory == registered.category,
	"Lootline page registered in Esc > Options > AddOns")
check(not registered.frame:IsShown(), "the page stays hidden until it is picked")
check(__ns.optionsUI == nil and LootlineOptions == nil, "controls are built lazily")
check(SLASH_LOOTLINE1 == "/lootline" and SLASH_LOOTLINE2 == nil, "only /lootline, no /lb alias")

-- 1. /lootline opens the Lootline page in the game's Options window --------------
SlashCmdList.LOOTLINE("")
local w = __ns.optionsUI
check(registered.opened == 42 and SettingsPanel.shown, "/lootline opens Options on the Lootline page (numeric ID)")
check(w ~= nil and w:GetParent() == registered.frame and w:IsVisible(), "the controls are on that page")
check(#w.tabs == 6, "6 tabs")
check(w.version and strip(w.version.__text):find("v9.9.9", 1, true) == 1, "the page shows the addon version from the .toc")
check(strip(w.version.__text):find("by Lastern", 1, true) and strip(w.version.__text):find("WeakAura by Hypocrit", 1, true)
	and not w.version.__text:find("#", 1, true), "credits: author Lastern, WeakAura by Hypocrit (no BattleTag)")
check(w.pages[1]:IsShown() and not w.pages[2]:IsShown(), "first tab selected")
local mouseless = {}
for _, o in ipairs(__allFrames) do
	if rawget(o, "label") and o.__type ~= "Frame" and o.__type ~= "FontString" and not o:IsMouseEnabled() then
		mouseless[#mouseless + 1] = o.__type .. " " .. strip(o.label.__text)
	end
end
check(#mouseless == 0, "every control takes mouse clicks (not: " .. table.concat(mouseless, ", ") .. ")")
SlashCmdList.LOOTLINE("")
check(not SettingsPanel.shown and SettingsPanel.closed == 1, "/lootline again closes Options through its Close()")
SlashCmdList.LOOTLINE("settings")
check(SettingsPanel.shown and w:IsVisible(), "/lootline settings opens it too")
db.width = 300
registered.frame:OnDefault()
check(db.width == 350 and control("Bar width", "Slider"):GetValue() == 350, "the Options window's Defaults button resets Lootline")
-- in combat addons may not open the game's Options window: a stand-alone window instead
SlashCmdList.LOOTLINE("")
InCombatLockdown = function() return true end
registered.opened = nil
SlashCmdList.LOOTLINE("")
local cw = LootlineOptions
check(registered.opened == nil and cw ~= nil and cw:IsShown() and w:GetParent() == cw and w:IsVisible(),
	"in combat: the controls open in the Lootline window")
check(tContains(UISpecialFrames, "LootlineOptions"), "Escape closes that window (UISpecialFrames)")
local wp = cw.__points[1]
check(wp and wp[1] == "TOPLEFT" and wp[4] == 40 and wp[5] == -80, "it opens off-centre (the bars are near the middle)")
cw.__points = { { "TOPLEFT", UIParent, "TOPLEFT", 120.4, -60.6 } }
cw.__scripts.OnDragStop(cw)
local op = db.optionsPoint
check(op and op[1] == "TOPLEFT" and op[3] == 120 and op[4] == -61 and cw.__userPlaced == false,
	"window position saved in LootlineDB")
SlashCmdList.LOOTLINE("")
check(not cw:IsShown(), "/lootline again closes it")
SlashCmdList.LOOTLINE("")
InCombatLockdown = function() return false end
SlashCmdList.LOOTLINE("")
check(not cw:IsShown() and SettingsPanel.shown and w:GetParent() == registered.frame and w:IsVisible(),
	"after combat: window closed, controls back on the Options page")

-- 2. Show / Hide: currencies, reputation, money -------------------------------
w.tabs[2]:Click()
check(w.pages[2]:IsShown() and not w.pages[1]:IsShown(), "tab switch")
check(not w.tabs[2]:IsEnabled() and w.tabs[1]:IsEnabled(), "selected tab is disabled, others enabled")
local cur, rep, money = control("Currencies", "CheckButton"), control("Reputation", "CheckButton"), control("Money", "CheckButton")
check(cur and rep and money, "Money / Currencies / Reputation checkboxes exist")
check(cur:GetChecked() and rep:GetChecked() and money:GetChecked(), "all ticked by default")
cur:Click(); rep:Click(); money:Click()
check(db.showCurrency == false and db.showRep == false and db.showMoney == false, "unticking writes the settings")
__fire("CHAT_MSG_CURRENCY", CURRENCY_MSG)
__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", REP_MSG)
__money = __money + 50000
__fire("PLAYER_MONEY")
settle()
check(#rows() == 0, "hidden: no currency, reputation or money bar (got " .. #rows() .. ")")
cur:Click(); rep:Click(); money:Click()
__fire("CHAT_MSG_CURRENCY", CURRENCY_MSG)
__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", REP_MSG)
__money = __money + 50000
__fire("PLAYER_MONEY")
settle()
check(find("Timewarped Badge") and find("Iskaara Tuskarr") and find("Money"), "ticked again: all three show")
check(cur.__hitInsets and cur.__hitInsets[2] < 0, "the label text is clickable too")
clear()

-- 3. minimum quality (e.g. hide everything below Rare/blue) -------------------
local q = control("Minimum quality", "Button")
check(q and strip(q.__text) == "Poor (show all)", "quality button shows Poor (got '" .. strip(q and q.__text) .. "')")
-- fake game menu API; and the interface style (gamepad: menus would trip Blizzard's SmartNavigation)
local gamepad = true
InputUtil = { IsGamepadUIEnabled = function() return gamepad end }
local menu
MenuUtil = { CreateContextMenu = function(owner, generator)
	menu = { owner = owner, radios = {} }
	local root = {}
	function root:CreateRadio(text, isSelected, setSelected)
		menu.radios[#menu.radios + 1] = { text = strip(text), isSelected = isSelected, setSelected = setSelected }
	end
	generator(owner, root)
end }
q:Click(); q:Click(); q:Click()
check(db.minQuality == 3 and strip(q.__text) == "Rare", "gamepad style: three clicks step to Rare (got " .. tostring(db.minQuality) .. ")")
check(menu == nil, "gamepad style: no dropdown menu is opened")
q:Click("RightButton")
check(db.minQuality == 2, "right-click steps back (Uncommon)")
q:Click()
check(db.minQuality == 3, "and click forward again (Rare)")
gamepad = false
q:Click()
check(menu and menu.owner == q and #menu.radios == 6 and menu.radios[4].text == "Rare",
	"mouse & keyboard: click opens a dropdown with the 6 qualities")
check(menu.radios[4].isSelected() and not menu.radios[1].isSelected(), "the current choice (Rare) is ticked")
menu.radios[5].setSelected()
check(db.minQuality == 4 and strip(q.__text) == "Epic", "picking Epic from the list")
menu.radios[4].setSelected()
check(db.minQuality == 3, "back to Rare from the list")
menu = nil
q:Click("RightButton")
check(db.minQuality == 2 and menu == nil, "mouse & keyboard: right-click still steps back, no menu")
q:Click("RightButton"); q:Click() -- (opens the menu again, nothing picked)
menu.radios[4].setSelected()
check(db.minQuality == 3, "Rare again")
InputUtil.IsGamepadUIEnabled = function() error("no interface style") end
menu = nil
q:Click()
check(menu == nil and db.minQuality == 4, "interface style unknown: steps instead of opening a menu")
q:Click("RightButton")
InputUtil.IsGamepadUIEnabled = function() return gamepad end
gamepad = true -- the rest of the file steps with clicks
chatLoot(10002) -- uncommon chest
chatLoot(2589, 5) -- common cloth
chatLoot(10003) -- poor junk
chatLoot(10001) -- rare hat
chatLoot(2244) -- epic blade
chatLoot(10004) -- quest item (common)
settle()
check(not find("Damaged Chest") and not find("Linen Cloth") and not find("Junk Bone"), "below Rare hidden")
check(find("Metal Hat") and find("Krol Blade"), "Rare and Epic shown")
check(find("Quest Thing"), "quest items still shown")
local questAlways = control("Always show quest items", "CheckButton")
questAlways:Click()
check(db.questAlways == false, "'Always show quest items' off")
clear()
chatLoot(10004)
settle()
check(not find("Quest Thing"), "quest item filtered when 'always show' is off")
questAlways:Click()
q:Click("RightButton"); q:Click("RightButton"); q:Click("RightButton")
check(db.minQuality == 0 and strip(q.__text) == "Poor (show all)", "three right-clicks: back to Poor")
q:Click("RightButton")
check(db.minQuality == 5, "right-click on the first option wraps to the last (Legendary)")
q:Click()
check(db.minQuality == 0, "click on the last wraps to the first")

-- 4. minimum value ------------------------------------------------------------
local mv = control("Hide items worth less than", "EditBox")
check(mv and mv.__text == "0" and mv.silver and mv.silver.__text == "0", "value boxes show 0 g 0 s")
typeInto(mv.silver, "50")
check(db.minValue == 5000, "50 silver = 5000 copper (got " .. tostring(db.minValue) .. ")")
typeInto(mv, "1")
check(db.minValue == 15000 and mv.__text == "1" and mv.silver.__text == "50", "1 g 50 s")
typeInto(mv.silver, "0")
check(db.minValue == 10000, "value filter set to 1 gold")
clear()
chatLoot(2770, 3) -- 3 x 5c
chatLoot(2589, 12) -- 12 x 13c
chatLoot(2244) -- 185g
chatLoot(10004) -- quest item, no price
settle()
check(not find("Copper Ore") and not find("Linen Cloth"), "cheap stacks hidden")
check(find("Krol Blade") and find("Quest Thing"), "valuable item and quest item shown")
chatLoot(2589, 800) -- 800 x 13c = 1g 4s
settle()
check(find("Linen Cloth"), "stack value counts (800 x 13c >= 1g)")
chatLoot(2589, 20) -- 20 x 13c: too cheap on its own
settle()
local linen = find("Linen Cloth")
check(linen and linen.left == "820x Linen Cloth", "...but it merges into the bar already shown (got '" .. tostring(linen and linen.left) .. "')")
chatLoot(6948) -- Hearthstone: no vendor price, no auction price
settle()
check(find("Hearthstone"), "items without a known price are not hidden by the value filter")
typeInto(mv, "abc")
check(db.minValue == 10000 and mv.__text == "1", "text input ignored, box reset")
typeInto(mv, "-5")
check(db.minValue == 10000 and mv.__text == "1", "negative value ignored")
typeInto(mv.silver, "250")
check(db.minValue == 35000 and mv.__text == "3" and mv.silver.__text == "50", "250 silver carries over: 3 g 50 s")
typeInto(mv, "1")
typeInto(mv.silver, "0")
Auctionator = { API = { v1 = { GetAuctionPriceByItemLink = function(_, link)
	if link:find("item:2770:", 1, true) then return 50000 end
end } } }
clear()
chatLoot(2770)
settle()
check(find("Copper Ore"), "auction price (5g) counts toward the value filter")
Auctionator = nil
typeInto(mv, "0")
check(db.minValue == 0, "value filter off")

-- 5. Layout: sliders, offsets, move -------------------------------------------
w.tabs[1]:Click()
local width = control("Bar width", "Slider")
check(width and width:GetValue() == 350, "width slider shows 350")
width:SetValue(503)
check(db.width == 500 and LootlineAnchor.__width == 500, "slider snaps to its step and applies (" .. db.width .. ")")
width.__scripts.OnMouseWheel(width, 1)
check(db.width == 510, "mouse wheel steps the slider")
local scale = control("Scale", "Slider")
scale:SetValue(1.2300001)
check(db.scale == 1.25 and LootlineAnchor.__scale == 1.25, "scale snaps to 0.05 (" .. tostring(db.scale) .. ")")
local xbox, ybox = control("Horizontal offset (X)", "EditBox"), control("Vertical offset (Y)", "EditBox")
check(xbox.__text == "-400" and ybox.__text == "95", "offset boxes show the default -400 / 95")
local p = LootlineAnchor.__points[1]
check(p[1] == "CENTER" and p[3] == "CENTER" and p[4] == -400 / 1.25 and p[5] == 95 / 1.25,
	"anchored to the screen centre; offsets divided by the bar scale")
typeInto(xbox, "-250")
typeInto(ybox, "100")
p = LootlineAnchor.__points[1]
check(db.point[3] == -250 and db.point[4] == 100 and p[4] == -250 / 1.25 and p[5] == 100 / 1.25, "offset boxes move the bars")
button("Reset position"):Click()
check(db.point[3] == -400 and db.point[4] == 95 and xbox.__text == "-400", "reset position, boxes follow")
db.width = 900 -- outside the slider range
__ns.RefreshOptions()
check(db.width == 900, "refreshing never writes a clamped value back")
db.width = 350

local function clickable()
	local n = 0
	for _, r in ipairs(rows()) do if r.frame:IsMouseEnabled() then n = n + 1 end end
	return n
end
check(w.smartNavigationIgnored == true, "the page is kept out of the game's gamepad navigation")
SlashCmdList.LOOTLINE("test")
settle()
check(LootlineAnchor:GetFrameStrata() == "BACKGROUND" and clickable() == #rows() and #rows() > 0,
	"with Options open, bars stay behind it (nothing drawn over the settings)")
clear()
-- Show test bars: on top of the Options window, click-through, until they are gone
button("Show test bars"):Click()
check(#rows() == 10 and LootlineAnchor:GetFrameStrata() == "FULLSCREEN_DIALOG" and clickable() == 0,
	"Show test bars: sample bars on top of the Options window, click-through")
local tf = find("Thunderfury")
check(tf and tf.left:find("Thunderfury, Blessed Blade of the W...", 1, true) and tf.frame.entry.link ~= nil,
	"the preview shows Classic items read from the game (Thunderfury with its link, name cut at 35)")
check(find("20x Runecloth") and find("Argent Dawn"), "stacks and a Classic faction")
local favor = find("Merchant's Favor")
check(favor and favor.left == "5x Merchant's Favor (17)", "a Forever currency read from the game: +5, 12 owned (got '"
	.. tostring(favor and favor.left) .. "')")
local function previewText()
	local all = ""
	for _, r in ipairs(rows()) do all = all .. r.left .. "\n" end
	return all
end
local text = previewText()
check(not text:find("Leech", 1, true) and not text:find("Indestructible", 1, true) and not text:find("Socket", 1, true),
	"no retail-only stats (Leech, Indestructible, sockets) in the preview")
check(not text:find("ilvl", 1, true), "no item level by default")
local ilvlBox = control("Show the item level under gear, e.g. ilvl: 66", "CheckButton")
ilvlBox:Click()
check(db.showItemLevel and previewText():find("ilvl: 80", 1, true) and not previewText():find("Runecloth\nilvl", 1, true),
	"item level option: gear shows ilvl (Thunderfury 80) right away, trade goods do not")
ilvlBox:Click()
check(not previewText():find("ilvl", 1, true), "and it goes away again")
button("Clear bars"):Click()
check(#rows() == 0 and LootlineAnchor:GetFrameStrata() == "BACKGROUND", "Clear bars ends the preview")
__uncached[19019] = true -- the client does not have Thunderfury yet
button("Show test bars"):Click()
check(#rows() == 9 and not find("Thunderfury"), "an item the client is still loading is not shown yet")
__tick(0.25, 10)
tf = find("Thunderfury")
check(tf and tf.frame.entry.link == nil and tf.left:find("Thunderfury", 1, true), "after 2s it is shown with the built-in fallback")
__uncached[19019] = nil
button("Clear bars"):Click()
button("Show test bars"):Click()
__tick(0.1, 450) -- 45s: every sample bar has expired
check(#rows() == 0 and LootlineAnchor:GetFrameStrata() == "BACKGROUND", "the preview ends when the last sample bar expires")
button("Show test bars"):Click()
SlashCmdList.LOOTLINE("")
check(LootlineAnchor:GetFrameStrata() == "BACKGROUND" and clickable() == #rows(), "closing Options ends the preview")
SlashCmdList.LOOTLINE("")
clear()
-- Move bars works like Edit Mode: Options closes, Lock next to the box brings it back
local move = button("Move bars")
local closedBefore = SettingsPanel.closed
move:Click()
check(not SettingsPanel.shown and SettingsPanel.closed == closedBefore + 1, "Move bars closes the Options window")
check(not __ns.IsLocked() and LootlineAnchor.bg.__shown, "and unlocks the bars")
check(#rows() == 10, "sample bars appear while moving (got " .. #rows() .. ")")
check(clickable() == 0 and LootlineAnchor:IsMouseEnabled(), "unlocked: bars are click-through, the green box takes the mouse")
check(LootlineAnchor:GetFrameStrata() == "FULLSCREEN_DIALOG", "unlocked: bars drawn above every window")
check(LootlineAnchor.lock:IsShown(), "a Lock button sits next to the green box")
-- dragged so that the centre (in the bars' own scale 1.25) ends up 300.4 right / 200.6 below the screen centre
LootlineAnchor.__center = { (960 + 300.4) / 1.25, (540 - 200.6) / 1.25 }
LootlineAnchor.__points = { { "TOPLEFT", UIParent, "TOPLEFT", 1, 1 } }
LootlineAnchor.__scripts.OnDragStop(LootlineAnchor)
LootlineAnchor.__center = nil
p = LootlineAnchor.__points[1]
check(db.point[1] == "CENTER" and db.point[3] == 300 and db.point[4] == -201, "drag stores the centre offset, rounded")
check(p[1] == "CENTER" and p[4] == 300 / 1.25, "and re-anchors to the screen centre")
check(xbox.__text == "300" and ybox.__text == "-201", "offset boxes follow the drag")
registered.opened = nil
LootlineAnchor.lock:Click()
check(__ns.IsLocked() and not LootlineAnchor.bg.__shown and not LootlineAnchor.lock:IsShown(), "Lock button locks the bars")
check(registered.opened == 42 and SettingsPanel.shown and w:IsVisible(), "and reopens Options on the Lootline page")
check(move.__text == "Move bars", "Move bars button text follows")
check(LootlineAnchor:GetFrameStrata() == "BACKGROUND" and clickable() == #rows(), "locked: bars back in BACKGROUND, clickable")
move:Click()
SlashCmdList.LOOTLINE("lock")
registered.opened = nil
SlashCmdList.LOOTLINE("unlock")
LootlineAnchor.lock:Click()
check(__ns.IsLocked() and registered.opened == nil, "a move ended elsewhere (/lootline lock) does not reopen Options later")
SlashCmdList.LOOTLINE("")
check(w:IsVisible() and move.__text == "Move bars", "reopened, button text refreshed")
SlashCmdList.LOOTLINE("reset")

local grow = control("Grow direction", "Button")
check(db.grow == "down" and grow.__text == "Downwards", "grows downwards by default")
grow:Click()
check(db.grow == "up" and grow.__text == "Upwards", "grow direction cycles to Upwards")
grow:Click()
check(db.grow == "center" and grow.__text == "Centred", "then Centred (no WeakAura note)")
grow:Click()
check(db.grow == "down", "and back to Downwards")

-- 6. Durations: 0 hides a type ------------------------------------------------
w.tabs[3]:Click()
local poor = control("Poor", "Slider")
poor:SetValue(0)
check(db.durations.poor == 0, "poor duration 0")
clear()
chatLoot(10003)
settle()
check(not find("Junk Bone"), "duration 0 hides poor items")
poor:SetValue(3)

-- 7. Prices: thresholds ---------------------------------------------------------
w.tabs[4]:Click()
local t1 = control("Tier 1 (yellow)", "EditBox")
local t3 = control("Tier 3 (red)", "EditBox")
check(t1.__text == "1" and t1.silver.__text == "0" and t3.__text == "10", "tiers show 1 g / ... / 10 g")
check(not control("TSM price source"), "no TradeSkillMaster option")
typeInto(t1.silver, "75")
check(db.thresholds[1] == 17500, "tier 1 = 1 g 75 s")
typeInto(t1, "0")
check(db.thresholds[1] == 7500, "tier 1 = 75 s")
clear()
chatLoot(2589) -- Linen Cloth, 13c: below 75s
chatLoot(10002) -- Damaged Chest, 2g 46s 90c: tier 1 (75s .. 5g)
settle()
local chest = find("Damaged Chest")
local cg = chest and chest.frame._LootlinePixelGlow
check(cg and cg.__shown and math.abs(cg.lines[1].__vertex[2] - 0.95) < 0.01, "2g 46s item glows tier 1 (yellow)")
local cloth = find("Linen Cloth")
check(cloth and not (cloth.frame._LootlinePixelGlow and cloth.frame._LootlinePixelGlow.__shown), "13c item does not glow")
typeInto(t1, "1")
typeInto(t1.silver, "0")
local ah = control("Auction price", "Button")
ah:Click()
check(db.showAH == 2 and ah.__text == "Unit price", "auction price choice")
ah:Click(); ah:Click()
check(db.showAH == 1, "auction price back to Off")

-- 8. Ignore list ---------------------------------------------------------------
w.tabs[5]:Click()
local page = w.pages[5]
check(textOn(page, "Nothing is ignored."), "empty list message")
clear()
chatLoot(10001) -- Metal Hat: gear, keyed by its full item string
settle()
local hat = find("Metal Hat")
__shift = true
hat.frame.__scripts.OnClick(hat.frame, "RightButton")
__shift = false
check(db.blacklist["item:10001"] ~= nil, "Shift+Right-click on gear ignores its itemID")
settle()
chatLoot(10001)
settle()
check(not find("Metal Hat"), "ignored gear is not shown again")
check(textOn(page, "Item: Metal Hat"), "ignored item listed in the window")
check(not textOn(page, "Nothing is ignored."), "empty message hidden")
__fire("CHAT_MSG_CURRENCY", CURRENCY_MSG)
settle()
local badge = find("Timewarped Badge")
__shift = true
badge.frame.__scripts.OnClick(badge.frame, "RightButton")
__shift = false
check(db.blacklist["cur:1166"] ~= nil and textOn(page, "Currency: Timewarped Badge"), "currency ignored and listed")
button("Remove"):Click() -- list is sorted: Currency before Item
check(db.blacklist["cur:1166"] == nil and db.blacklist["item:10001"] ~= nil, "Remove deletes that entry only")
local idBox
for _, c in ipairs(page.__children) do if c.__type == "EditBox" then idBox = c end end
typeInto(idBox, "2770")
check(db.blacklist["item:2770"] == "Copper Ore" and textOn(page, "Item: Copper Ore"), "add by item ID")
__uncached[10003] = true
typeInto(idBox, "10003")
check(db.blacklist["item:10003"] == "item 10003" and textOn(page, "Item: item 10003"), "item not cached yet: placeholder first")
__uncached[10003] = nil
__tick(0.25)
check(db.blacklist["item:10003"] == "Junk Bone" and textOn(page, "Item: Junk Bone"), "renamed once the client has the item")
__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", REP_MSG)
settle()
local repBar = find("Iskaara Tuskarr")
__shift = true
repBar.frame.__scripts.OnClick(repBar.frame, "RightButton")
__shift = false
check(db.blacklist["rep:Iskaara Tuskarr"] ~= nil, "reputation ignored")
SlashCmdList.LOOTLINE("unignore rep:Iskaara Tuskarr")
check(db.blacklist["rep:Iskaara Tuskarr"] == nil and not textOn(page, "Reputation:"), "/lootline unignore handles keys with spaces")
SlashCmdList.LOOTLINE("unignore rep:Nobody Here")
check(tostring(__out[#__out]):find("not in the ignore list", 1, true), "unknown key reported instead of 'removed'")
for i = 1, 25 do db.blacklist["item:" .. (50000 + i)] = "Test " .. i end
__ns.RefreshOptions()
check(textOn(page, "1 / 3"), "27 entries: 3 pages")
button(">"):Click()
check(textOn(page, "2 / 3"), "next page")
button("Clear list"):Click()
check(next(db.blacklist) == nil and textOn(page, "Nothing is ignored.") and not textOn(page, "/ 3"), "clear list")

-- 9. Defaults, slash commands keep the window in sync --------------------------
db.blacklist["item:1"] = "keep me"
db.width = 300
db.showRep = false
button("Defaults"):Click()
check(db.width == 350 and db.showRep == true, "Defaults resets settings")
check(db.blacklist["item:1"] == "keep me", "Defaults keeps the ignore list")
check(rep:GetChecked() and width:GetValue() == 350, "controls show the defaults")
SlashCmdList.LOOTLINE("minvalue 7")
check(db.minValue == 70000 and mv.__text == "7", "/lootline minvalue updates the window")
SlashCmdList.LOOTLINE("minvalue 1g 50s")
check(db.minValue == 15000 and mv.__text == "1" and mv.silver.__text == "50", "/lootline minvalue 1g 50s")
SlashCmdList.LOOTLINE("threshold 2 75s 1g50s")
check(db.thresholds[1] == 20000 and db.thresholds[2] == 7500 and db.thresholds[3] == 15000, "/lootline threshold takes gold or g/s amounts")
SlashCmdList.LOOTLINE("rep")
check(db.showRep == false and not rep:GetChecked(), "/lootline rep updates the checkbox")
SlashCmdList.LOOTLINE("defaults")
check(db.minValue == 0 and rep:GetChecked(), "/lootline defaults updates the window")

-- 10. the tier-3 sound is for loot, not for setting changes ------------------------
clear()
db.sound = true
local sounds = #__sounds
__money = __money + 10000000 -- 1000g: tier 3
__fire("PLAYER_MONEY")
settle()
check(#__sounds == sounds + 1, "1000g money plays the tier 3 sound once")
w.tabs[4]:Click()
local glow = control("Animated glow around expensive bars", "CheckButton")
glow:Click(); glow:Click()
check(db.highlight == true and #__sounds == sounds + 1, "toggling the glow does not replay it")
db.sound = false

-- 11. a short name limit still keeps part of the name -----------------------------
db.maxLength = 15
clear()
__fire("CHAT_MSG_CURRENCY", CURRENCY_GAINED_MULTIPLE:format("|cffffffff|Hcurrency:1792:0|h[Honor]|h|r", 500))
settle()
local honor = find("Honor")
check(honor and honor.left == "500x Honor (15000 / 15000)", "capped currency keeps its name (got '" .. tostring(honor and honor.left) .. "')")
db.maxLength = 35

local um, ug = {}, {}
for k in pairs(__unknownMethods) do um[#um + 1] = k end
for k in pairs(__unknownGlobals) do ug[#ug + 1] = k end
table.sort(um); table.sort(ug)
print("unknown widget methods used: " .. (#um > 0 and table.concat(um, ", ") or "none"))
print("unknown globals read: " .. (#ug > 0 and table.concat(ug, ", ") or "none"))
print(("RESULT: %d failure(s)"):format(failures))
