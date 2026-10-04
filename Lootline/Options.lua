-- Lootline options: the Lootline page in Esc > Options > AddOns (/lootline). Uses only stock
-- templates that exist on every client (UIPanelButtonTemplate, UICheckButtonTemplate,
-- InputBoxTemplate, UIPanelCloseButton, BackdropTemplate); sliders are drawn by hand.

local ADDON_NAME, ns = ...

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local WIDTH, HEIGHT = 600, 560
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ui -- tabs, pages and buttons; shown on the Settings page or in the combat window
local panel -- canvas registered in Esc > Options > AddOns
local combatWindow
local controls = {}
local refreshing = false

local function db() return ns.GetDB() end

local function Changed(full)
	if full ~= false then ns.Apply() end
end

local function Label(parent, text, x, y, font)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	return fs
end

-- text: a string, or a function returning one (read each time the tooltip opens)
local function Tooltip(frame, title, text)
	if not text then return end
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title)
		GameTooltip:AddLine(type(text) == "function" and text() or text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Button(parent, text, w, h)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w or 120, h or 22)
	b:SetText(text)
	return b
end

local function Section(page, text, y)
	Label(page, text, 16, y, "GameFontNormal")
	local line = page:CreateTexture(nil, "ARTWORK")
	line:SetPoint("TOPLEFT", 16, y - 18)
	line:SetSize(WIDTH - 64, 1)
	line:SetColorTexture(1, 0.82, 0, 0.35)
end

local function Register(control)
	controls[#controls + 1] = control
	return control
end

local function Check(page, label, x, y, get, set, tip)
	local c = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	c:SetSize(26, 26)
	c:SetPoint("TOPLEFT", x, y + 5)
	c.label = Label(page, label, x + 30, y)
	-- clicking the text toggles too
	c:SetHitRectInsets(0, -(c.label:GetStringWidth() + 6), 0, 0)
	c:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
		Changed()
	end)
	Tooltip(c, label, tip)
	c.Refresh = function() c:SetChecked(get() and true or false) end
	return Register(c)
end

local function Round(v, step)
	return tonumber(format("%.4f", floor(v / step + 0.5) * step))
end

local function Slider(page, label, x, y, minV, maxV, step, get, set, fmt, tip, light)
	fmt = fmt or tostring
	local s = CreateFrame("Slider", nil, page, "BackdropTemplate")
	s.label = Label(page, label, x, y)
	s:SetOrientation("HORIZONTAL")
	s:SetPoint("TOPLEFT", x + 160, y + 1)
	s:SetSize(240, 14)
	s:SetHitRectInsets(0, 0, -4, -4)
	s:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	s:SetBackdropColor(0.16, 0.16, 0.18, 1)
	s:SetBackdropBorderColor(0, 0, 0, 1)
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	thumb:SetSize(32, 32)
	s:SetThumbTexture(thumb)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
	s:EnableMouse(true)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(self:GetValue() + delta * step)
	end)
	local value = Label(page, "", x + 412, y)
	s:SetScript("OnValueChanged", function(_, v)
		v = Round(v, step)
		value:SetText(fmt(v))
		if refreshing then return end
		if v ~= get() then
			set(v)
			Changed(not light)
		end
	end)
	Tooltip(s, label, tip)
	s.Refresh = function()
		local v = get()
		s:SetValue(v)
		value:SetText(fmt(v))
	end
	return Register(s)
end

-- With the game's gamepad interface style, opening any dropdown menu makes Blizzard's
-- SmartNavigation remember a button it later fails on (SmartNavigation.lua: attempt to index
-- field 'activeInfo'). Its menu hook returns early for mouse & keyboard, so menus are safe there.
local function GamepadUI()
	if not (InputUtil and InputUtil.IsGamepadUIEnabled) then return false end
	local ok, on = pcall(InputUtil.IsGamepadUIEnabled)
	return not ok or on == true -- when unsure, stay on the safe side (no menu)
end

-- options = { {value, "Label"}, ... }. Mouse & keyboard: click opens a dropdown menu.
-- Gamepad interface style (or no menu API): click steps to the next option.
-- Right-click always steps back.
local function Choice(page, label, x, y, options, get, set, tip)
	local b = Button(page, "", 180, 22)
	b.label = Label(page, label, x, y)
	b:SetPoint("TOPLEFT", x + 160, y + 4)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b.Refresh = function()
		local current = get()
		for _, o in ipairs(options) do
			if o[1] == current then b:SetText(o[2]) return end
		end
		b:SetText(tostring(current))
	end
	local function pick(v)
		set(v)
		Changed()
		b.Refresh()
	end
	local function canMenu()
		return MenuUtil and MenuUtil.CreateContextMenu and not GamepadUI()
	end
	b:SetScript("OnClick", function(self, button)
		if button ~= "RightButton" and canMenu() then
			MenuUtil.CreateContextMenu(self, function(_, root)
				for _, o in ipairs(options) do
					root:CreateRadio(o[2], function() return get() == o[1] end, function() pick(o[1]) end)
				end
			end)
			return
		end
		local current, idx = get(), 0
		for i, o in ipairs(options) do if o[1] == current then idx = i end end
		local step = button == "RightButton" and -1 or 1
		pick(options[(idx - 1 + step) % #options + 1][1])
	end)
	local names = {}
	for _, o in ipairs(options) do names[#names + 1] = o[2] end
	Tooltip(b, label, function()
		local how = canMenu() and "Click: choose from the list   Right-click: previous"
			or ("Click: next   Right-click: previous\n" .. table.concat(names, "|cff808080  >  |r"))
		return (tip and (tip .. "\n\n") or "") .. how
	end)
	return Register(b)
end

local function NumberBox(page, label, x, y, get, set, tip, suffix, allowNegative)
	local e = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	e.label = Label(page, label, x, y)
	e:SetSize(80, 20)
	e:SetPoint("TOPLEFT", x + 166, y + 4)
	e:SetAutoFocus(false)
	e:SetMaxLetters(8)
	if suffix then Label(page, suffix, x + 252, y) end
	local function commit(self)
		local v = tonumber(self:GetText())
		if v and (allowNegative or v >= 0) and v ~= get() then
			set(v)
			Changed()
		end
		self.Refresh()
	end
	e:SetScript("OnEnterPressed", function(self)
		commit(self)
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", commit)
	e:SetScript("OnEscapePressed", function(self)
		self.Refresh()
		self:ClearFocus()
	end)
	Tooltip(e, label, tip)
	e.Refresh = function() e:SetText(tostring(get())) end
	return Register(e)
end

-- Gold + silver boxes for an amount stored in copper (copper itself is kept as it was).
local function MoneyBox(page, label, x, y, get, set, tip)
	local function Box(width, left)
		local e = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
		e:SetSize(width, 20)
		e:SetPoint("TOPLEFT", left, y + 4)
		e:SetAutoFocus(false)
		e:SetNumeric(true)
		e:SetMaxLetters(width > 40 and 7 or 2)
		Tooltip(e, label, tip)
		return e
	end
	local gold = Box(60, x + 166)
	gold.label = Label(page, label, x, y)
	Label(page, "|cffffd700g|r", x + 230, y)
	local silver = Box(30, x + 248)
	Label(page, "|cffc7c7cfs|r", x + 282, y)
	gold.silver = silver
	local function amount(box)
		local text = box:GetText()
		if text == "" then return 0 end
		return tonumber(text)
	end
	local function commit()
		local g, s = amount(gold), amount(silver)
		if g and s and g >= 0 and s >= 0 then
			local v = floor(g) * 10000 + floor(s) * 100 + get() % 100
			if v ~= get() then
				set(v)
				Changed()
			end
		end
		gold.Refresh()
	end
	for _, box in ipairs({ gold, silver }) do
		box:SetScript("OnEnterPressed", function(self)
			commit()
			self:ClearFocus()
		end)
		box:SetScript("OnEditFocusLost", commit)
		box:SetScript("OnEscapePressed", function(self)
			gold.Refresh()
			self:ClearFocus()
		end)
	end
	gold:SetScript("OnTabPressed", function() silver:SetFocus() end)
	silver:SetScript("OnTabPressed", function() gold:SetFocus() end)
	gold.Refresh = function()
		local v = get()
		gold:SetText(tostring(floor(v / 10000)))
		silver:SetText(tostring(floor(v / 100) % 100))
	end
	return Register(gold)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------

local function Getter(key) return function() return db()[key] end end
local function Setter(key) return function(v) db()[key] = v end end
local function DurGet(key) return function() return db().durations[key] end end
local function DurSet(key) return function(v) db().durations[key] = v end end
local function Seconds(v) return v == 0 and "|cffff6060hidden|r" or (v .. " s") end

local function BuildLayoutPage(p)
	Section(p, "Position", -10)
	local move = Button(p, "Move bars", 140, 24)
	move:SetPoint("TOPLEFT", 16, -36)
	move:SetScript("OnClick", function()
		if ns.IsLocked() then ns.StartMove() else ns.SetLocked(true) end
		move.Refresh()
	end)
	move.Refresh = function() move:SetText(ns.IsLocked() and "Move bars" or "Lock bars") end
	Tooltip(move, "Move bars", "Closes the Options window and shows sample bars with a green box. Drag the box, "
		.. "then click Lock next to it to come back here.")
	Register(move)
	local reset = Button(p, "Reset position", 140, 24)
	reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
	reset:SetScript("OnClick", function()
		ns.ResetPosition()
		ns.RefreshOptions()
	end)
	local offsetTip = "Distance of the bars from the centre of the screen (negative = left / down). "
		.. "Dragging the bars changes it too. Press Enter to apply."
	NumberBox(p, "Horizontal offset (X)", 16, -72,
		function() return (ns.GetOffset()) end,
		function(v) local _, y = ns.GetOffset(); ns.SetOffset(v, y) end,
		offsetTip, "px", true)
	NumberBox(p, "Vertical offset (Y)", 16, -100,
		function() return select(2, ns.GetOffset()) end,
		function(v) local x = ns.GetOffset(); ns.SetOffset(x, v) end,
		offsetTip, "px", true)
	Choice(p, "Grow direction", 16, -132, {
		{ "down", "Downwards" }, { "up", "Upwards" }, { "center", "Centred" },
	}, Getter("grow"), Setter("grow"), "Centred: the stack grows both ways from its middle.")

	Section(p, "Size", -170)
	Slider(p, "Scale", 16, -198, 0.5, 2, 0.05, Getter("scale"), Setter("scale"),
		function(v) return format("%.2f", v) end)
	Slider(p, "Bar width", 16, -226, 200, 800, 10, Getter("width"), Setter("width"))
	Slider(p, "Bar height", 16, -254, 20, 80, 1, Getter("rowHeight"), Setter("rowHeight"))
	Slider(p, "Spacing", 16, -282, 0, 30, 1, Getter("spacing"), Setter("spacing"))
	Slider(p, "Font size", 16, -310, 8, 24, 1, Getter("fontSize"), Setter("fontSize"))
	Slider(p, "Max bars", 16, -338, 1, 20, 1, Getter("maxRows"), Setter("maxRows"), nil,
		"Extra bars wait hidden until a slot frees up.")

	Section(p, "Mouse", -374)
	Check(p, "Show tooltips and allow clicks (off = click-through)", 16, -400, Getter("mouse"), Setter("mouse"),
		"Right-click a bar to dismiss it, Shift+Right-click to ignore that item.")
end

local QUALITIES = {
	{ 0, "|cff9d9d9dPoor|r (show all)" }, { 1, "Common" }, { 2, "|cff1eff00Uncommon|r" },
	{ 3, "|cff0070ddRare|r" }, { 4, "|cffa335eeEpic|r" }, { 5, "|cffff8000Legendary|r" },
}

local function BuildFilterPage(p)
	Section(p, "Show these (untick to hide)", -10)
	Check(p, "Money", 16, -36, Getter("showMoney"), Setter("showMoney"),
		"Any gold you gain: looting, quests, selling.")
	Check(p, "Currencies", 16, -62, Getter("showCurrency"), Setter("showCurrency"))
	Check(p, "Reputation", 16, -88, Getter("showRep"), Setter("showRep"))
	Check(p, "Quest rewards and purchases", 16, -114, Getter("showPushed"), Setter("showPushed"))
	Check(p, "Crafted items", 16, -140, Getter("showCreated"), Setter("showCreated"))

	Section(p, "Item filters", -178)
	Choice(p, "Minimum quality", 16, -206, QUALITIES, Getter("minQuality"), Setter("minQuality"),
		"Items below this quality are hidden. Rare hides grey, white and green items.")
	MoneyBox(p, "Hide items worth less than", 16, -238, Getter("minValue"), Setter("minValue"),
		"Vendor price, or the auction price when Auctionator knows it (the higher one), "
		.. "times the stack size. Items with no known price (e.g. soulbound mounts) are always shown. "
		.. "0 = off. Press Enter to apply.")
	Check(p, "Always show quest items", 16, -270, Getter("questAlways"), Setter("questAlways"),
		"Quest items ignore the two filters above.")

	Section(p, "Item text", -308)
	Check(p, "Merge repeated loot of the same item into one bar", 16, -334, Getter("merge"), Setter("merge"))
	Check(p, "Show how many you have in your bags, e.g. (27)", 16, -360, Getter("invCount"), Setter("invCount"))
	Check(p, "Show the item level under gear, e.g. ilvl: 66", 16, -386, Getter("showItemLevel"), Setter("showItemLevel"))
	Slider(p, "Max name length", 16, -420, 0, 100, 1, Getter("maxLength"), Setter("maxLength"),
		function(v) return v == 0 and "off" or tostring(v) end, "Longer names are cut with '...'.")
end

local function BuildDurationsPage(p)
	Section(p, "How long each bar stays (0 = hide that type)", -10)
	local rows = {
		{ "poor", "|cff9d9d9dPoor|r" }, { "common", "Common" }, { "uncommon", "|cff1eff00Uncommon|r" },
		{ "rare", "|cff0070ddRare|r" }, { "epic", "|cffa335eeEpic|r" }, { "legendary", "|cffff8000Legendary|r" },
		{ "artifact", "|cffe6cc80Artifact|r" }, { "heirloom", "|cff00ccffHeirloom|r" }, { "quest", "Quest items" },
		{ "money", "|cffffff00Money|r" }, { "currency", "|cffe6cc80Currency|r" }, { "rep", "|cff00ccffReputation|r" },
	}
	for i, r in ipairs(rows) do
		Slider(p, r[2], 16, -10 - i * 30, 0, 60, 1, DurGet(r[1]), DurSet(r[1]), Seconds, nil, true)
	end
end

local function BuildPricesPage(p)
	Section(p, "Prices", -10)
	Choice(p, "Vendor price", 16, -38, {
		{ 1, "Unit + stack total" }, { 2, "Unit price only" }, { 3, "Stack total only" },
	}, Getter("showStackPrice"), Setter("showStackPrice"))
	Choice(p, "Auction price", 16, -70, {
		{ 1, "Off" }, { 2, "Unit price" }, { 3, "Stack price" },
	}, Getter("showAH"), Setter("showAH"), "Needs Auctionator, after it has scanned the auction house.")
	Check(p, "Show silver and copper", 16, -104, Getter("dispCopSilv"), Setter("dispCopSilv"))

	Section(p, "Highlight expensive loot", -142)
	Check(p, "Animated glow around expensive bars", 16, -168, Getter("highlight"), Setter("highlight"),
		"Compares the price of ONE item (or the money total) with the thresholds below.")
	local tiers = { "|cfff2f251Tier 1 (yellow)|r", "|cffff9900Tier 2 (orange)|r", "|cffff2020Tier 3 (red)|r" }
	for i = 1, 3 do
		MoneyBox(p, tiers[i], 16, -174 - i * 32,
			function() return db().thresholds[i] end,
			function(v) db().thresholds[i] = v end,
			"Price of one item (vendor or auction) from which the bar glows in this colour. Press Enter to apply.")
	end
	Check(p, "Play a sound for tier 3 (Wilhelm scream)", 16, -310, Getter("sound"), Setter("sound"))
end

local function BuildLootingPage(p)
	Section(p, "Faster auto loot", -10)
	Check(p, "Take all loot at once, without the loot window", 16, -36, Getter("fastLoot"), function(v)
		db().fastLoot = v
		if not v then ns.RestoreLootFrame() end
	end, "Right-click a corpse and everything goes straight into your bags. "
		.. "The game's own Auto Loot setting does not have to be on.")
	local notes = Label(p, "Hold your Auto Loot key (Shift by default) while looting to get the loot window as usual.\n\n"
		.. "The window still opens whenever the game needs you: Bind on Pickup items, group rolls, "
		.. "master loot, locked slots or no free bag space.\n\n"
		.. "If something cannot be taken after all, Lootline tells you what was left, and looting "
		.. "that corpse again opens the window.", 46, -66, "GameFontHighlightSmall")
	notes:SetWidth(500)
	notes:SetWordWrap(true)
	notes:SetSpacing(3)
end

local KIND_LABEL = { item = "Item", cur = "Currency", rep = "Reputation" }

local function IgnoredEntries()
	local list = {}
	for key, name in pairs(db().blacklist) do
		local kind, id = tostring(key):match("^(%a+):(.*)$")
		list[#list + 1] = {
			key = key, name = tostring(name), kind = KIND_LABEL[kind] or "?",
			id = (kind == "item" or kind == "cur") and id or nil,
		}
	end
	table.sort(list, function(a, b)
		if a.kind ~= b.kind then return a.kind < b.kind end
		return a.name:lower() < b.name:lower()
	end)
	return list
end

local function BuildIgnorePage(p)
	local ROWS = 10
	local offset = 0
	local view = {}
	Section(p, "Ignored items, currencies and factions", -10)
	Label(p, "Shift+Right-click a bar to add it here.", 16, -34, "GameFontDisableSmall")
	local empty = Label(p, "Nothing is ignored.", 16, -60, "GameFontDisable")
	local lines = {}
	for i = 1, ROWS do
		local y = -58 - (i - 1) * 26
		local line = { text = Label(p, "", 16, y) }
		line.text:SetWidth(410)
		line.text:SetWordWrap(false)
		line.button = Button(p, "Remove", 90, 20)
		line.button:SetPoint("TOPLEFT", 440, y + 3)
		line.button:SetScript("OnClick", function()
			if line.key then db().blacklist[line.key] = nil end
			view.Refresh()
		end)
		lines[i] = line
	end
	local prev = Button(p, "<", 30, 22)
	prev:SetPoint("TOPLEFT", 16, -324)
	local pageText = Label(p, "", 54, -328)
	local nextPage = Button(p, ">", 30, 22)
	nextPage:SetPoint("TOPLEFT", 120, -324)
	prev:SetScript("OnClick", function() offset = max(0, offset - ROWS); view.Refresh() end)
	nextPage:SetScript("OnClick", function() offset = offset + ROWS; view.Refresh() end)

	Label(p, "Ignore an item by ID:", 16, -370)
	local box = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
	box:SetSize(80, 20)
	box:SetPoint("TOPLEFT", 182, -366)
	box:SetAutoFocus(false)
	box:SetMaxLetters(10)
	local add = Button(p, "Add", 70, 22)
	add:SetPoint("LEFT", box, "RIGHT", 8, 0)
	local function addItem()
		local id = tonumber(box:GetText())
		if id then
			ns.Print("ignoring " .. ns.IgnoreItem(id))
			box:SetText("")
		end
		box:ClearFocus()
		view.Refresh()
	end
	add:SetScript("OnClick", addItem)
	box:SetScript("OnEnterPressed", addItem)
	box:SetScript("OnEscapePressed", box.ClearFocus)
	local clear = Button(p, "Clear list", 100, 22)
	clear:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -366)
	clear:SetScript("OnClick", function()
		wipe(db().blacklist)
		ns.Print("ignore list cleared")
		view.Refresh()
	end)

	view.Refresh = function()
		local list = IgnoredEntries()
		local pages = max(1, ceil(#list / ROWS))
		offset = min(offset, (pages - 1) * ROWS)
		for i, line in ipairs(lines) do
			local entry = list[offset + i]
			line.key = entry and entry.key
			if entry then
				line.text:SetText(("|cffaaaaaa%s:|r %s%s"):format(entry.kind, entry.name,
					entry.id and ("  |cff777777(" .. entry.id .. ")|r") or ""))
			end
			line.text:SetShown(entry ~= nil)
			line.button:SetShown(entry ~= nil)
		end
		empty:SetShown(#list == 0)
		local paged = pages > 1
		prev:SetShown(paged)
		nextPage:SetShown(paged)
		pageText:SetShown(paged)
		pageText:SetText(("%d / %d"):format(offset / ROWS + 1, pages))
		prev:SetEnabled(offset > 0)
		nextPage:SetEnabled(offset + ROWS < #list)
	end
	Register(view)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local PAGES = {
	{ "Layout", BuildLayoutPage },
	{ "Show / Hide", BuildFilterPage },
	{ "Durations", BuildDurationsPage },
	{ "Prices", BuildPricesPage },
	{ "Ignored", BuildIgnorePage },
	{ "Looting", BuildLootingPage },
}

local function RefreshAll()
	refreshing = true
	for _, c in ipairs(controls) do c.Refresh() end
	refreshing = false
end
ns.RefreshOptions = RefreshAll

local function SelectPage(index)
	for i, page in ipairs(ui.pages) do
		page:SetShown(i == index)
		ui.tabs[i]:SetEnabled(i ~= index)
	end
	ui.selected = index
end

local function BuildUI()
	ui = CreateFrame("Frame", nil, UIParent)
	ns.optionsUI = ui
	-- Keep the page out of the game's gamepad navigation (it is active with a mouse too):
	-- otherwise it can remember one of these buttons and fail on it later (activeInfo nil).
	ui.smartNavigationIgnored = true
	Label(ui, "Lootline", 16, -14, "GameFontNormalLarge")
	local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = getMeta and getMeta(ADDON_NAME, "Version")
	ui.version = Label(ui, (version and ("v" .. version .. "  -  ") or "")
		.. "by Lastern  -  /lootline  -  inspired by the Loot Frame WeakAura by Hypocrit", 110, -18, "GameFontDisableSmall")

	ui.tabs, ui.pages = {}, {}
	for i, def in ipairs(PAGES) do
		local tab = Button(ui, def[1], 90, 24)
		tab:SetPoint("TOPLEFT", 16 + (i - 1) * 96, -44)
		tab:SetScript("OnClick", function() SelectPage(i) end)
		ui.tabs[i] = tab
		local page = CreateFrame("Frame", nil, ui)
		page:SetPoint("TOPLEFT", 8, -78)
		page:SetPoint("BOTTOMRIGHT", -8, 44)
		page:Hide()
		def[2](page)
		ui.pages[i] = page
	end

	local test = Button(ui, "Show test bars", 130, 24)
	test:SetPoint("BOTTOMLEFT", 16, 12)
	test:SetScript("OnClick", function()
		ns.RunTest()
		ns.SetPreviewMode(true) -- drawn above the Options window until they expire or are cleared
	end)
	Tooltip(test, "Show test bars", "Sample bars on top of this window, so you can see your changes. "
		.. "Clicks go through them to the settings underneath.")
	local clear = Button(ui, "Clear bars", 100, 24)
	clear:SetPoint("LEFT", test, "RIGHT", 8, 0)
	clear:SetScript("OnClick", function() ns.ClearAll() end)
	local defaults = Button(ui, "Defaults", 100, 24)
	defaults:SetPoint("BOTTOMRIGHT", -16, 12)
	defaults:SetScript("OnClick", function()
		ns.ResetDefaults()
		RefreshAll()
	end)
	Tooltip(defaults, "Defaults", "Resets every setting to its default (the ignore list is kept).")
	SelectPage(1)
end

local moving -- "Move bars" is closing the Options window on purpose
local reopenAfterMove

-- Puts the controls into `host` (the Settings page or the combat window).
local function Attach(host)
	if not ui then BuildUI() end
	if host ~= combatWindow and combatWindow and combatWindow:IsShown() then combatWindow:Hide() end
	ui:SetParent(host)
	ui:ClearAllPoints()
	ui:SetAllPoints(host)
	ui:Show()
	RefreshAll()
end

-- `host` was hidden: another Settings page was picked, Options or the window was closed.
local function Detach(host)
	if not ui or ui:GetParent() ~= host or moving then return end
	ns.SetPreviewMode(false)
	if not ns.IsLocked() then ns.SetLocked(true) end
end

-- Like the game's Edit Mode: the Options window covers the middle of the screen, so it closes
-- while the bars are moved; Lock next to the green box brings it back.
function ns.StartMove()
	local fromOptions = panel and panel:IsVisible() and SettingsPanel and SettingsPanel:IsShown()
	ns.SetLocked(false)
	ns.EnsurePreview()
	if fromOptions then
		reopenAfterMove = true
		moving = true
		SettingsPanel:Close(true)
		moving = false
	end
end

-- Lock button next to the green box
function ns.FinishMove()
	local reopen = reopenAfterMove
	ns.SetLocked(true)
	if reopen and not (panel and panel:IsVisible()) then ns.OpenOptions() end
end

-- any lock (button, /lootline lock, closing Options) ends the move started from Options
function ns.OnLockChanged(locked)
	if locked then reopenAfterMove = false end
end

-- Addons may not open the game's Options window in combat; this window stands in for it there.
local function BuildCombatWindow()
	local w = CreateFrame("Frame", "LootlineOptions", UIParent, "BackdropTemplate")
	w:SetSize(WIDTH, HEIGHT)
	-- off-centre by default: the bars sit near the middle of the screen
	local p = db().optionsPoint or { "TOPLEFT", "TOPLEFT", 40, -80 }
	w:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	w:SetFrameStrata("DIALOG")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false) -- the position lives in LootlineDB, not in the layout cache
		local point, _, relPoint, x, y = self:GetPoint()
		db().optionsPoint = { point, relPoint, floor(x + 0.5), floor(y + 0.5) }
	end)
	w:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	w:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
	w:SetBackdropBorderColor(0, 0, 0, 1)
	tinsert(UISpecialFrames, "LootlineOptions") -- Escape closes it
	local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	close:SetFrameLevel(w:GetFrameLevel() + 20) -- above the controls moved in later
	w:SetScript("OnShow", Attach)
	w:SetScript("OnHide", Detach)
	return w
end

-- /lootline: opens the Lootline page in Esc > Options > AddOns, or closes it when it is open.
function ns.OpenOptions()
	local category = ns.settingsCategory
	if InCombatLockdown() or not (category and Settings and Settings.OpenToCategory) then
		if panel and panel:IsVisible() then return end -- already on screen in the Options window
		if not combatWindow then
			combatWindow = BuildCombatWindow()
			Attach(combatWindow) -- OnShow does not fire for a frame that is created shown
		else
			combatWindow:SetShown(not combatWindow:IsShown())
		end
		return
	end
	if combatWindow and combatWindow:IsShown() then combatWindow:Hide() end
	if SettingsPanel and SettingsPanel:IsShown() and panel and panel:IsVisible() then
		-- Close() commits (or asks about) pending changes; a plain HideUIPanel would drop them
		SettingsPanel:Close(true)
		return
	end
	Settings.OpenToCategory(category:GetID())
end

-- the Lootline page in Esc > Options > AddOns; the controls are built the first time it shows
function ns.RegisterSettingsPage()
	panel = CreateFrame("Frame")
	panel:Hide() -- the Options window shows it when the Lootline page is picked
	panel:SetScript("OnShow", Attach)
	panel:SetScript("OnHide", Detach)
	-- canvas callbacks of the Options window; every change already applies at once
	panel.OnRefresh = function() RefreshAll() end
	panel.OnDefault = function()
		ns.ResetDefaults()
		RefreshAll()
	end
	panel.OnCommit = function() end
	if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
		local category = Settings.RegisterCanvasLayoutCategory(panel, "Lootline")
		Settings.RegisterAddOnCategory(category)
		ns.settingsCategory = category -- numeric category:GetID() is what Settings.OpenToCategory takes
	elseif InterfaceOptions_AddCategory then
		panel.name = "Lootline"
		panel.refresh, panel.default = panel.OnRefresh, panel.OnDefault
		InterfaceOptions_AddCategory(panel)
	end
end
