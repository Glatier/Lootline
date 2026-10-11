-- Farm counter (window, minimap button, menu), bag space warning, Auctionator refresh,
-- price labels, profession skill-ups.
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
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "[tex]"):gsub("|H.-|h(.-)|h", "%1"))
end
local function bars()
	local list = {}
	for _, o in ipairs(__allFrames) do
		if o.__type == "Button" and o.__parent == LootlineAnchor and o.__shown and rawget(o, "icon") and rawget(o, "entry") then
			list[#list + 1] = { left = strip(o.left.__text), right = strip(o.right.__text), row = o, icon = o.icon.__tex }
		end
	end
	return list
end
local function bar(text)
	for _, b in ipairs(bars()) do if b.left:find(text, 1, true) then return b end end
end
local function count(text)
	local n = 0
	for _, b in ipairs(bars()) do if b.left:find(text, 1, true) then n = n + 1 end end
	return n
end
local function tipHas(text)
	for _, l in ipairs(GameTooltip.__lines or {}) do
		if strip(l):find(text, 1, true) then return true end
	end
end
local function printed(text)
	for _, line in ipairs(__out) do if strip(line):find(text, 1, true) then return true end end
end
local function lootChat(id, n)
	local msg = (n or 1) > 1 and LOOT_ITEM_SELF_MULTIPLE:format(__link(id), n) or LOOT_ITEM_SELF:format(__link(id))
	__fire("CHAT_MSG_LOOT", msg, "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
	__tick(0.05, 2)
end
local function money(copper) return strip(__ns.FormatPrice(copper)) end
local function txt(fs) return strip(fs.__text) end

-- Auctionator: prices by itemID, and the DB update callback it was given
__ah, __ahCallbacks = {}, {}
Auctionator = { API = { v1 = {
	GetAuctionPriceByItemLink = function(caller, link) return __ah[tonumber(link:match("item:(%d+)"))] end,
	RegisterForDBUpdate = function(caller, cb) __ahCallbacks[#__ahCallbacks + 1] = { caller, cb } end,
} } }
-- context menus: the last one opened
MenuUtil = { CreateContextMenu = function(owner, gen)
	local root = { items = {} }
	function root:CreateTitle(t) self.items[#self.items + 1] = { text = t, title = true } end
	function root:CreateButton(t, fn) self.items[#self.items + 1] = { text = t, fn = fn } end
	function root:CreateRadio(t, isSelected, fn) self.items[#self.items + 1] = { text = t, fn = fn, selected = isSelected } end
	gen(owner, root)
	__menu = root
end }
local function menuItem(text)
	for _, it in ipairs(__menu and __menu.items or {}) do if it.text == text then return it end end
end
-- skill lines (Character > Skills); by ID also when their header is collapsed
local SKINNING = { skillID = 393, name = "Skinning", isHeader = false, rank = 145, maxRank = 150, skillLineCategoryID = 11 }
local COOKING = { skillID = 185, name = "Cooking", isHeader = false, rank = 50, maxRank = 75, skillLineCategoryID = 9 }
local SWORDS = { skillID = 43, name = "Swords", isHeader = false, rank = 100, maxRank = 150, skillLineCategoryID = 6 }
-- the same profession listed again: a child line of it, and a same-named line without a parent;
-- their rank follows Skinning's
local SKINNING_CHILD = setmetatable({ skillID = 2564, parentSkillLineID = 393 }, { __index = SKINNING })
local SKINNING_TWIN = setmetatable({ skillID = 2999, parentSkillLineID = 0 }, { __index = SKINNING })
__skillLines = {
	{ skillID = 11, name = "Professions", isHeader = true, rank = 0, maxRank = 0, skillLineCategoryID = 11 },
	SKINNING_TWIN, SKINNING_CHILD, SKINNING, COOKING, SWORDS,
}
C_SkillInfo = {
	GetNumSkillLines = function() return #__skillLines end,
	GetSkillLineInfo = function(i) return __skillLines[i] end,
	GetSkillLineInfoByID = function(id)
		for _, s in ipairs({ SKINNING, COOKING, SWORDS }) do if s.skillID == id then return s end end
	end,
}

__fire("ADDON_LOADED", "Lootline")
__fire("PLAYER_ENTERING_WORLD", true, false)
local db = LootlineDB
local farm = LootlineFarm
local btn = LootlineMinimapButton

-- 1. minimap button and its short tooltip -------------------------------------------------
check(btn and btn:IsShown() and btn.__parent == Minimap, "minimap button on the minimap, shown by default")
local p = btn.__points[1]
check(p and p[1] == "CENTER" and math.abs(p[4] + 53.03) < 0.1 and math.abs(p[5] + 53.03) < 0.1,
	"placed on the minimap's edge at the default angle (225)")
btn.__scripts.OnEnter(btn)
check(GameTooltip:IsOwned(btn) and tipHas("not started") and tipHas("Left-click: farm window")
	and tipHas("Shift+Left-click: start the counter") and tipHas("Right-click: menu"), "tooltip: state and click hints")
check(#GameTooltip.__lines <= 9, "the tooltip stays short (" .. #GameTooltip.__lines .. " lines)")
btn.__scripts.OnLeave(btn)

-- 2. counting only while it runs (Shift+Left-click starts it) --------------------------------
lootChat(2589, 3)
__fire("CHAT_MSG_MONEY", "You loot 5 Silver")
check(next(farm.items) == nil and farm.money == 0, "nothing counted before the counter starts")
__shift = true
btn:Click("LeftButton")
__shift = nil
check(farm.running and printed("farm counter started") and not LootlineFarmWindow, "Shift+Left-click starts the counter (no window)")
local function iconInColour()
	return btn.icon.__desaturated ~= true and (btn.icon.__vertex == nil or btn.icon.__vertex[4] == nil or btn.icon.__vertex[4] == 1)
end
check(iconInColour(), "the minimap icon stays in colour while running")
lootChat(2589, 3)
lootChat(2770, 2)
__fire("CHAT_MSG_MONEY", "You loot 1 Gold, 2 Silver, 3 Copper")
__fire("CHAT_MSG_MONEY", "Your share of the loot is 5 Silver.")
__fire("CHAT_MSG_MONEY", "Bob loots 3 Gold.")
check(farm.money == 10703, "looted money and the group share counted, someone else's loot not (got " .. farm.money .. ")")
check(farm.items[2589].count == 3 and farm.items[2770].count == 2, "items counted once each (loot window + chat line dedup)")
__tick(1, 120)
local s = __ns.FarmSummary()
check(s.elapsed == 120 and s.count == 5 and s.vendor == 49 and s.ah == 0 and s.total == 10752
	and s.perHour == 10752 * 30, "summary: time, items, vendor value, total, per hour")

-- 3. the farm window (left-click) ------------------------------------------------------------
btn:Click("LeftButton")
local w = LootlineFarmWindow
check(w and w:IsShown() and txt(w.state) == "running" and txt(w.time) == "2m 00s", "left-click opens the farm window: state, time")
check(db.farmWindowStyle == "classic" and w.__backdrop.edgeFile == "Interface\\DialogFrame\\UI-DialogBox-Border"
	and w.header:IsShown() and txt(w.headerText) == "Lootline - Farm counter" and not w.title:IsShown(),
	"classic style by default: the game's dialog border, title on the header plate")
local cp = w.content.__points[1]
check(w.__width == 312 and w.__height == 398 and cp[4] == 6 and cp[5] == -6, "classic: the content moves in from the thick border")
local hp = w.header.__points[1]
check(hp[1] == "TOP" and hp[5] == 0 and w.__clampInsets[3] == 0, "classic: the header plate sits inside the window (nothing sticks out)")
check(w.header.__width == w.headerText:GetStringWidth() + 10 and w.headerL:IsShown() and w.headerR:IsShown()
	and w.headerL.__points[1][2] == w.header and w.headerR.__points[1][2] == w.header,
	"classic: the plate's middle stretches with the title, its two ends on either side")
check(not w.nine:IsShown() and not w.modernTitle:IsShown(), "classic: no modern pieces")
check(txt(w.money) == money(10703) and txt(w.items) == "5" and txt(w.vendor) == money(49) and txt(w.ah) == "-",
	"money, items, vendor value; no auction value yet")
check(txt(w.total) == money(10752) and txt(w.perHour) == money(10752 * 30), "total and per hour")
check(txt(w.rows[1].name) == "3x Linen Cloth" and txt(w.rows[1].value) == money(39) and txt(w.rows[2].name) == "2x Copper Ore"
	and not w.rows[3]:IsShown() and not w.empty:IsShown(), "best items: icon, name, value, most valuable first")
check(w.rows[1].icon.__tex == 134400, "item rows show the item icon")
w.rows[1].__scripts.OnEnter(w.rows[1])
check(GameTooltip.__link == __link(2589), "hovering an item row shows the item tooltip")
w.rows[1].__scripts.OnLeave(w.rows[1])
__ah[2589] = 100
__ah[10003] = 99999
lootChat(10003, 1)
check(txt(w.ah) == money(300) and txt(w.total) == money(10703 + 300 + 10 + 3), "new loot and Auctionator prices show at once")
check(txt(w.rows[3].name) == "1x Junk Bone" and txt(w.rows[3].value) == money(3), "grey items count at the vendor price only")
__tick(1, 2)
check(txt(w.time) == "2m 02s", "the window's clock runs")
check(w.toggle.__text == "Pause", "button: Pause while running")
w.toggle:Click()
check(not farm.running and w.toggle.__text == "Resume" and txt(w.state) == "paused", "Pause in the window")
check(iconInColour(), "the minimap icon stays in colour while paused too")
__tick(1, 30)
lootChat(2770, 1)
check(txt(w.time) == "2m 02s" and farm.items[2770].count == 2, "paused: the clock and the counting stop")
w.toggle:Click()
check(farm.running and printed("farm counter resumed"), "Resume in the window")
w.__scripts.OnDragStop(w)
check(db.farmWindowPoint ~= nil, "the window's position is saved when it is dragged")
btn:Click("LeftButton")
check(not w:IsShown(), "left-click again closes it")
SlashCmdList.LOOTLINE("farm")
check(w:IsShown(), "/lootline farm opens it too")
SlashCmdList.LOOTLINE("farm")

-- 4. logout ------------------------------------------------------------------------------------
__tick(1, 10)
__fire("PLAYER_LOGOUT")
check(farm.elapsed == 132 and farm.startedAt == nil and farm.running, "logout: the time so far is saved")
__now = __now + 5000 -- logged out for a while
__ns.InitFarm()
__tick(1, 5)
check(__ns.FarmSummary().elapsed == 137, "next login: running again, time logged out not counted")
btn.__scripts.OnEnter(btn)
check(tipHas("running") and tipHas("2m 17s") and tipHas("Shift+Left-click: pause the counter"), "tooltip follows the counter")
__tick(1, 2)
check(GameTooltip:IsOwned(btn) and tipHas("2m 19s"), "the hovered tooltip keeps its clock running")
btn.__scripts.OnLeave(btn)

-- 5. reset (in the window) ---------------------------------------------------------------------
SlashCmdList.LOOTLINE("farm")
w.reset:Click()
check(not farm.running and farm.money == 0 and next(farm.items) == nil and farm.elapsed == 0, "Reset in the window")
check(txt(w.state) == "not started" and w.empty:IsShown() and not w.rows[1]:IsShown() and w.toggle.__text == "Start",
	"the window shows an empty counter")
SlashCmdList.LOOTLINE("farm")

-- 6. right-click menu: Settings / Hide minimap button ------------------------------------------
btn:Click("RightButton")
check(menuItem("Settings") and menuItem("Hide minimap button"), "right-click: menu with Settings and Hide minimap button")
menuItem("Hide minimap button").fn()
check(db.minimap.hide and not btn:IsShown() and printed("minimap button hidden"), "Hide minimap button hides it and says how to get it back")
SlashCmdList.LOOTLINE("minimap")
check(not db.minimap.hide and btn:IsShown(), "/lootline minimap shows it again")
btn:Click("RightButton")
menuItem("Settings").fn()
local ui = __ns.optionsUI
check(ui and ui:IsVisible(), "Settings opens the options")
SlashCmdList.LOOTLINE("") -- close
local savedMenu = MenuUtil
MenuUtil = nil
btn:Click("RightButton")
check(ui:IsVisible(), "without a menu (e.g. gamepad interface): right-click opens the options")
MenuUtil = savedMenu
check(ui.tabs[7].__text == "Farm", "Farm tab")
ui.tabs[7]:Click()
local page = ui.pages[7]
local function pageChild(kind, text)
	for _, o in ipairs(page.__children) do
		if o.__type == kind and strip(o.__text):find(text, 1, true) then return o end
	end
end
check(pageChild("Button", "Farm window") and pageChild("Button", "Start") and pageChild("FontString", "not started"),
	"Farm page: Farm window / Start / Reset, state")
pageChild("Button", "Start"):Click()
check(farm.running and pageChild("Button", "Pause") and pageChild("FontString", "running"), "Start on the page")
pageChild("Button", "Reset"):Click()
-- window style
local style = pageChild("Button", "Classic")
check(style ~= nil, "Farm page: window style, Classic selected")
SlashCmdList.LOOTLINE("farm")
style:Click()
menuItem("Minimal").fn()
check(db.farmWindowStyle == "minimal" and w.__backdrop.edgeFile == "Interface\\Buttons\\WHITE8X8" and not w.header:IsShown()
	and w.title:IsShown() and w.__width == 300 and w.content.__points[1][4] == 0, "Minimal: the flat panel, applied to the open window")
-- Modern: without the game's nine-slice helper (as in this mock) it falls back to Minimal
style:Click()
menuItem("Modern").fn()
check(db.farmWindowStyle == "modern" and w.style == "minimal" and w.title:IsShown(), "Modern without nine-slice art: falls back to Minimal")
-- with it: the metal frame, flat background, title in the top band
local applied
NineSliceUtil = { ApplyLayoutByName = function(frame, name) applied = { frame, name } end }
w.modernTried = nil
__ns.ApplyFarmWindowStyle()
check(w.style == "modern" and applied and applied[1] == w.nine and applied[2] == "ButtonFrameTemplateNoPortrait",
	"Modern: the game's ButtonFrameTemplateNoPortrait metal frame")
check(w.nine:IsShown() and w.modernBg:IsShown() and w.modernTitle:IsShown() and txt(w.modernTitle) == "Lootline - Farm counter"
	and w.__backdrop == nil and not w.header:IsShown() and not w.headerL:IsShown() and not w.headerR:IsShown()
	and not w.title:IsShown() and w.__width == 300,
	"Modern: border, flat background and title shown; no backdrop, no header plate")
check(w.content:GetFrameLevel() > w.nine:GetFrameLevel() and w.close:GetFrameLevel() > w.content:GetFrameLevel(),
	"Modern: content and close button above the border pieces")
check(w.modernTitle.__parent == w.content and w.modernTitle.__points[1][2] == w,
	"Modern: the title is drawn above the border's top band, anchored to the window's top")
style:Click()
menuItem("Classic").fn()
check(db.farmWindowStyle == "classic" and w.header:IsShown() and w.__width == 312 and not w.nine:IsShown(), "and back to Classic")
-- gamepad interface style: no dropdown menu (the game's gamepad navigation fails on it);
-- the button steps through the styles like Grow direction does
InputUtil = { IsGamepadUIEnabled = function() return true end }
__menu = nil
style:Click("LeftButton")
check(db.farmWindowStyle == "modern" and __menu == nil and style.__text == "Modern", "gamepad: click steps to the next style, no menu")
style:Click("LeftButton")
check(db.farmWindowStyle == "minimal" and w.style == "minimal", "gamepad: next again (applied to the open window)")
style:Click("LeftButton")
check(db.farmWindowStyle == "classic", "gamepad: and round to the first")
style:Click("RightButton")
check(db.farmWindowStyle == "minimal" and __menu == nil, "gamepad: right-click steps back")
style:Click("RightButton")
style:Click("RightButton")
check(db.farmWindowStyle == "classic", "gamepad: back to Classic")
SlashCmdList.LOOTLINE("") -- close the options
check(not ui:IsVisible(), "options closed")
btn:Click("RightButton")
check(__menu == nil and ui:IsVisible(), "gamepad: minimap right-click opens the options instead of a menu")
InputUtil = nil
SlashCmdList.LOOTLINE("farm")
-- the minimap button's checkbox is on the Layout tab
ui.tabs[1]:Click()
local box
for _, o in ipairs(ui.pages[1].__children) do
	if o.__type == "CheckButton" and o.label.__text == "Show the Lootline button on the minimap" then box = o end
end
check(box and box:GetChecked(), "Layout tab: minimap button checkbox")
box:Click()
check(db.minimap.hide and not btn:IsShown(), "the checkbox hides the button")
box:Click()
check(not db.minimap.hide and btn:IsShown(), "and shows it")
SlashCmdList.LOOTLINE("") -- close

-- 7. dragging the button around the minimap -----------------------------------------------
btn.__scripts.OnDragStart(btn)
__cursor = { 70 + 100, 70 } -- east of the minimap's centre
btn.__scripts.OnUpdate(btn, 0.02)
btn.__scripts.OnDragStop(btn)
p = btn.__points[1]
check(db.minimap.angle == 0 and math.abs(p[4] - 75) < 0.1 and math.abs(p[5]) < 0.1, "drag: moves along the edge, angle saved")
__cursor = { 70, 70 - 100 }
btn.__scripts.OnUpdate(btn, 0.02)
check(db.minimap.angle == 0, "after the drag the button stays put")

-- 8. bag space warning: a chat message, no bar --------------------------------------------
__tick(1, 20)
check(db.bagWarn == true and db.bagWarnAt == 5, "bag warning on by default, at 5 free slots")
-- what Lootline printed for this bag change (nil when nothing)
local function bags(free)
	local n = #__out
	__freeSlots = free
	__fire("BAG_UPDATE_DELAYED")
	__tick(0.05, 6)
	local said
	for i = n + 1, #__out do said = (said and (said .. " / ") or "") .. strip(__out[i]) end
	return said
end
check(bags(6) == nil, "6 free: no warning")
local said = bags(5)
check(said == "Lootline: Bags almost full: 5 free slots left" and not bar("Bags"), "5 free: chat message, no bar (" .. tostring(said) .. ")")
check(bags(4) == "Lootline: Bags almost full: 4 free slots left", "fuller still: another message")
check(bags(1) == "Lootline: Bags almost full: 1 free slot left", "1 free: 'slot', not 'slots'")
check(bags(0) == "Lootline: Bags full!", "0 free: 'Bags full!'")
check(bags(0) == nil, "no change: no repeat")
check(bags(3) == nil, "more room again (sold, deleted): no message")
SlashCmdList.LOOTLINE("bagwarn")
check(db.bagWarn == false and bags(2) == nil, "/lootline bagwarn turns it off")
SlashCmdList.LOOTLINE("bagwarn")
SlashCmdList.LOOTLINE("bagwarn 10")
check(db.bagWarn and db.bagWarnAt == 10, "/lootline bagwarn 10 sets the level")
bags(16)
check(bags(9) == "Lootline: Bags almost full: 9 free slots left", "warns at the new level")

-- 9. Auctionator scan refreshes the bars on screen ------------------------------------------
check(#__ahCallbacks == 1 and __ahCallbacks[1][1] == "Lootline", "registered with Auctionator once, as Lootline")
db.showAH = 2
__ah[2770] = 200
lootChat(2770, 1)
__tick(0.05, 6)
local before = bar("Copper Ore").right
__ah[2770] = 4500
for _ = 1, 5 do __ahCallbacks[1][2]() end -- a scan reports several batches
__tick(0.05, 12)
local after = bar("Copper Ore").right
check(before:find(money(200), 1, true) and after:find(money(4500), 1, true), "after a scan the bar shows the new auction price")
__tick(1, 12)

-- 10. price labels (off by default) ---------------------------------------------------------
check(db.priceLabels == false, "price labels off by default")
lootChat(2589, 3)
__tick(0.05, 6)
check(not bar("Linen Cloth").right:find("vendor", 1, true), "off: plain prices")
SlashCmdList.LOOTLINE("labels")
local r = bar("Linen Cloth").right
check(db.priceLabels and r:find("AH  " .. money(100), 1, true) and r:find("vendor  " .. money(13), 1, true)
	and r:find("stack  " .. money(39), 1, true), "/lootline labels: AH / vendor / stack in front of the prices")
db.showAH = 3
__ns.Apply()
check(bar("Linen Cloth").right:find("AH stack  " .. money(300), 1, true), "auction stack price: 'AH stack'")
SlashCmdList.LOOTLINE("labels")
db.showAH = 1
__tick(1, 12)

-- 11. profession skill-ups (off by default) --------------------------------------------------
check(db.showSkills == false, "skill-ups off by default")
SKINNING.rank = 146
__fire("SKILL_LINES_CHANGED")
__tick(0.05, 6)
check(not bar("Skinning"), "off: no bar")
SlashCmdList.LOOTLINE("skills")
check(db.showSkills, "/lootline skills turns them on")
SKINNING.rank = 147
__fire("SKILL_LINES_CHANGED")
__tick(0.05, 6)
b = bar("Skinning")
check(b and b.left == "Skinning  +1" and b.right == "147 / 150" and b.icon == "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
	"Skinning +1  147 / 150, with the profession's icon")
check(count("Skinning") == 1, "one bar per profession, even when the game lists it more than once")
SKINNING.rank = 148
__fire("SKILL_LINES_CHANGED")
check(count("Skinning") == 1 and bar("Skinning").left == "Skinning  +2" and bar("Skinning").right == "148 / 150",
	"the next point merges into the same bar")
SWORDS.rank = 101
COOKING.rank = 51
__fire("SKILL_LINES_CHANGED")
__tick(0.05, 6)
check(not bar("Swords") and bar("Cooking") and bar("Cooking").right == "51 / 75", "weapon skills are left out, cooking counts")
__fire("SKILL_LINES_CHANGED")
check(bar("Skinning").left == "Skinning  +2", "no change, no new points")
__skillLines = { __skillLines[1] } -- Professions header collapsed
SKINNING.rank = 149
__fire("SKILL_LINES_CHANGED")
check(bar("Skinning").left == "Skinning  +3", "a collapsed header does not hide the skill-up")
__shift = true
bar("Skinning").row:Click("RightButton")
__shift = nil
check(db.blacklist["skill:393"] == "Skinning", "Shift+Right-click ignores that profession")
__tick(1, 12)
SKINNING.rank = 150
__fire("SKILL_LINES_CHANGED")
__tick(0.05, 6)
check(not bar("Skinning"), "an ignored profession shows no bar")

print(("RESULT: %d failure(s)"):format(failures))
