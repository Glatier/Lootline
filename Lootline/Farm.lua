-- Lootline farm counter: what you loot while it runs - money and items, valued at the vendor or
-- the Auctionator price - with its window and the minimap button that opens it.
-- The counter is kept per character (LootlineFarm) across /reload and logout; time spent logged
-- out does not count.

local ADDON_NAME, ns = ...

local floor, max, min = math.floor, math.max, math.min
local atan2 = math.atan2 or math.atan
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo

local ICON = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\icon"
local TOP_ITEMS = 5

local farm -- LootlineFarm
local button -- minimap button, made the first time it is shown

local function db() return ns.GetDB() end

---------------------------------------------------------------------------
-- Counter
---------------------------------------------------------------------------

local function Elapsed()
	local s = farm.elapsed
	if farm.running and farm.startedAt then s = s + max(0, time() - farm.startedAt) end
	return s
end

local function Changed()
	if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
	if ns.RefreshFarmPage then ns.RefreshFarmPage() end
	if ns.RefreshFarmWindow then ns.RefreshFarmWindow() end
end

local function Start()
	if farm.running then return end
	farm.running, farm.startedAt = true, time()
	ns.Print("farm counter " .. (farm.elapsed > 0 and "resumed" or "started"))
	Changed()
end

local function Pause()
	if not farm.running then return end
	farm.elapsed = Elapsed()
	farm.running, farm.startedAt = false, nil
	ns.Print("farm counter paused")
	Changed()
end

local function Reset()
	farm.running, farm.startedAt, farm.elapsed, farm.money = false, nil, 0, 0
	wipe(farm.items)
	ns.Print("farm counter reset")
	Changed()
end

local function Toggle()
	if farm.running then Pause() else Start() end
end

function ns.OnLootedItem(link, count)
	if not (farm and farm.running) then return end
	local id = tonumber(link:match("item:(%d+)"))
	if not id then return end
	local it = farm.items[id]
	if not it then
		it = { count = 0 }
		farm.items[id] = it
	end
	it.count = it.count + (count or 1)
	it.link = link
	Changed()
end

function ns.OnLootedMoney(copper)
	if not (farm and farm.running) then return end
	farm.money = farm.money + copper
	Changed()
end

-- prices are read when shown: a new Auctionator scan changes them
function ns.OnPricesChanged()
	Changed()
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------

local function Money(copper)
	local s = ns.FormatPrice(copper)
	return s ~= "" and s or "|cff8080800|r"
end

local function TimeText(s)
	s = floor(s)
	local h, m = floor(s / 3600), floor(s / 60) % 60
	if h > 0 then return ("%dh %02dm"):format(h, m) end
	return ("%dm %02ds"):format(m, s % 60)
end

-- vendor, auction and best value of a stack; grey items count at the vendor price only
local function ItemValue(link, count)
	local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
	local vendor = (sellPrice or 0) * count
	local ah = (quality or 0) > 0 and ns.GetAHPrice(link)
	ah = ah and ah * count or 0
	return vendor, ah, max(vendor, ah)
end

local function Summarize()
	local s = { money = farm.money, vendor = 0, ah = 0, best = 0, count = 0, items = {} }
	for id, it in pairs(farm.items) do
		local vendor, ah, best = ItemValue(it.link, it.count)
		s.vendor, s.ah, s.best, s.count = s.vendor + vendor, s.ah + ah, s.best + best, s.count + it.count
		s.items[#s.items + 1] = { id = id, link = it.link, count = it.count, value = best }
	end
	table.sort(s.items, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	s.total = s.money + s.best
	s.elapsed = Elapsed()
	s.perHour = s.elapsed >= 60 and s.total * 3600 / s.elapsed or nil
	return s
end

local function StateText()
	if farm.running then return "|cff33ff33running|r" end
	if farm.elapsed > 0 or farm.money > 0 or next(farm.items) then return "|cffffd100paused|r" end
	return "|cff808080not started|r"
end

local function ToggleText()
	if farm.running then return "Pause" end
	return (farm.elapsed > 0 or farm.money > 0 or next(farm.items)) and "Resume" or "Start"
end

ns.FarmSummary = Summarize
ns.FarmState = StateText
ns.FarmToggleText = ToggleText
ns.FarmToggle = Toggle
ns.FarmReset = Reset

---------------------------------------------------------------------------
-- Farm window: left-click on the minimap button or /lootline farm
---------------------------------------------------------------------------

local WIN_W, WIN_H = 300, 386
local WHITE = "Interface\\Buttons\\WHITE8X8"
local win

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

local function Divider(parent, y)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", 14, y)
	t:SetPoint("TOPRIGHT", -14, y)
	t:SetHeight(1)
	t:SetColorTexture(1, 0.82, 0, 0.25)
end

-- "label ........ value"; returns the value's font string
local function StatRow(parent, y, label, labelFont, valueFont)
	local l = Text(parent, labelFont or "GameFontNormal")
	l:SetPoint("TOPLEFT", 16, y)
	l:SetText(label)
	local v = Text(parent, valueFont or "GameFontHighlight", "RIGHT")
	v:SetPoint("TOPRIGHT", -16, y)
	return v
end

local function ItemRow(parent, y)
	local r = CreateFrame("Button", nil, parent)
	r:SetPoint("TOPLEFT", 14, y)
	r:SetPoint("TOPRIGHT", -14, y)
	r:SetHeight(20)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(16, 16)
	r.icon:SetPoint("LEFT", 2, 0)
	r.value = Text(r, "GameFontHighlight", "RIGHT")
	r.value:SetPoint("RIGHT", -2, 0)
	r.name = Text(r, "GameFontHighlight")
	r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
	r.name:SetPoint("RIGHT", r, "RIGHT", -96, 0)
	r:SetScript("OnEnter", function(self)
		if not self.link then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(self.link)
		GameTooltip:Show()
	end)
	r:SetScript("OnLeave", function() GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self) -- Shift-click: link in chat
		if self.link and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end
	end)
	return r
end

-- "[Silk Cloth]" with its quality colour, without the brackets
local function ItemName(link)
	local color = link:match("^(|c%x%x%x%x%x%x%x%x)") or ""
	return color .. (link:match("|h%[(.-)%]|h") or link) .. "|r"
end

local function RefreshWindow()
	if not win or not win:IsShown() then return end
	local s = Summarize()
	win.state:SetText(StateText())
	win.time:SetText(TimeText(s.elapsed))
	win.money:SetText(Money(s.money))
	win.items:SetText(tostring(s.count))
	win.vendor:SetText(Money(s.vendor))
	win.ah:SetText(s.ah > 0 and Money(s.ah) or "|cff808080-|r")
	win.total:SetText(Money(s.total))
	win.perHour:SetText(s.perHour and Money(s.perHour) or "|cff808080-|r")
	for i, r in ipairs(win.rows) do
		local it = s.items[i]
		r.link = it and it.link
		if it then
			r.icon:SetTexture(select(10, GetItemInfo(it.link)) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)))
			r.name:SetText("|cffffffff" .. it.count .. "x|r " .. ItemName(it.link))
			r.value:SetText(Money(it.value))
		end
		r:SetShown(it ~= nil)
	end
	win.empty:SetShown(#s.items == 0)
	win.toggle:SetText(ToggleText())
end

-- Classic: the game's own dialog border (thick, gold-trimmed) with the title on a header plate.
-- Minimal: a flat dark panel with a 1px edge.
local CLASSIC_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileEdge = true, tileSize = 32, edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}
local MINIMAL_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
local CLASSIC_PAD = 6 -- the content moves in by this much, the window grows by it

-- Modern: the metal frame of today's game windows (DefaultPanelFlatTemplate's pieces, put together
-- here: the template itself brings focus / gamepad handling this window does not need).
local function BuildModern(w)
	if w.modernTried then return w.modernOK end
	w.modernTried = true
	if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then return false end
	w.modernOK = pcall(NineSliceUtil.ApplyLayoutByName, w.nine, "ButtonFrameTemplateNoPortrait")
	return w.modernOK
end

-- per style: content inset, extra size, clamp room above the frame (header plate / metal top)
local STYLE = {
	classic = { pad = CLASSIC_PAD, above = 0, close = { -5, -5 } },
	modern = { pad = 0, above = 2, close = { -2, 1 } },
	minimal = { pad = 0, above = 0, close = { -2, -2 } },
}

local function ApplyStyle(w)
	local style = db().farmWindowStyle
	if not STYLE[style] then style = "classic" end
	if style == "modern" and not BuildModern(w) then style = "minimal" end -- no nine-slice art in this client
	local s = STYLE[style]
	w:SetSize(WIN_W + 2 * s.pad, WIN_H + 2 * s.pad)
	-- the window stays on screen together with what sticks out above it
	w:SetClampRectInsets(0, 0, s.above, 0)
	w.content:ClearAllPoints()
	w.content:SetPoint("TOPLEFT", s.pad, -s.pad)
	if style == "classic" then
		w:SetBackdrop(CLASSIC_BACKDROP)
		w:SetBackdropColor(1, 1, 1, 1)
		w:SetBackdropBorderColor(1, 1, 1, 1)
	elseif style == "minimal" then
		w:SetBackdrop(MINIMAL_BACKDROP)
		w:SetBackdropColor(0.06, 0.06, 0.07, 0.95)
		w:SetBackdropBorderColor(0, 0, 0, 1)
	else
		w:SetBackdrop(nil)
	end
	w.nine:SetShown(style == "modern")
	w.modernBg:SetShown(style == "modern")
	w.modernTitle:SetShown(style == "modern")
	w.header:SetShown(style == "classic")
	w.headerL:SetShown(style == "classic")
	w.headerR:SetShown(style == "classic")
	if style == "classic" then w.header:SetWidth(w.headerText:GetStringWidth() + 10) end -- fonts load late
	w.headerText:SetShown(style == "classic")
	w.icon:SetShown(style == "minimal")
	w.title:SetShown(style == "minimal")
	w.close:ClearAllPoints()
	w.close:SetPoint("TOPRIGHT", s.close[1], s.close[2])
	w.style = style
end

function ns.ApplyFarmWindowStyle()
	if win then ApplyStyle(win) end
end

local function CreateWindow()
	local w = CreateFrame("Frame", "LootlineFarmWindow", UIParent, "BackdropTemplate")
	w:SetSize(WIN_W, WIN_H)
	local p = db().farmWindowPoint or { "RIGHT", "RIGHT", -240, 80 }
	w:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:EnableMouse(true)
	w:SetMovable(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", w.StartMoving)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false) -- the position lives in LootlineDB
		local point, _, relPoint, x, y = self:GetPoint()
		db().farmWindowPoint = { point, relPoint, floor(x + 0.5), floor(y + 0.5) }
	end)
	tinsert(UISpecialFrames, "LootlineFarmWindow") -- Escape closes it
	w.close = CreateFrame("Button", nil, w, "UIPanelCloseButton")

	-- Minimal style: icon + title in the corner
	w.icon = w:CreateTexture(nil, "ARTWORK")
	w.icon:SetSize(20, 20)
	w.icon:SetTexture(ICON)
	w.icon:SetPoint("TOPLEFT", 14, -12)
	w.title = Text(w, "GameFontNormalLarge")
	w.title:SetPoint("LEFT", w.icon, "RIGHT", 6, 0)
	w.title:SetText("Farm counter")
	-- Classic style: the title on the dialog header plate, cut into its two ends and a middle that
	-- stretches with the title (the plate drawn whole is narrower than the title)
	local function HeaderPiece(left, right)
		local t = w:CreateTexture(nil, "ARTWORK")
		t:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
		t:SetTexCoord(left, right, 0, 0.63)
		t:SetHeight(40)
		return t
	end
	w.header = HeaderPiece(0.31, 0.67)
	w.header:SetPoint("TOP", 0, 0) -- flush with the top edge: nothing sticks out of the window
	w.headerL = HeaderPiece(0.21, 0.31)
	w.headerL:SetWidth(30)
	w.headerL:SetPoint("RIGHT", w.header, "LEFT")
	w.headerR = HeaderPiece(0.67, 0.77)
	w.headerR:SetWidth(30)
	w.headerR:SetPoint("LEFT", w.header, "RIGHT")
	w.headerText = Text(w, "GameFontNormal", "CENTER")
	w.headerText:SetPoint("TOP", w.header, "TOP", 0, -14)
	w.headerText:SetText("Lootline - Farm counter")
	w.header:SetWidth(w.headerText:GetStringWidth() + 10)
	-- Modern style: metal border, flat dark background, title in the frame's top band
	w.nine = CreateFrame("Frame", nil, w)
	w.nine:SetAllPoints()
	w.modernBg = w:CreateTexture(nil, "BACKGROUND")
	w.modernBg:SetPoint("TOPLEFT", 6, -20)
	w.modernBg:SetPoint("BOTTOMRIGHT", -2, 2)
	local bg = PANEL_BACKGROUND_COLOR
	if bg and bg.GetRGBA then
		w.modernBg:SetColorTexture(bg:GetRGBA())
	else
		w.modernBg:SetColorTexture(0.08, 0.08, 0.09, 0.97)
	end

	-- everything else sits in `c`, which the classic style moves in from its thick border
	local c = CreateFrame("Frame", nil, w)
	w.content = c
	c:SetFrameLevel(w:GetFrameLevel() + 5) -- above the modern border pieces
	w.close:SetFrameLevel(w:GetFrameLevel() + 10)
	c:SetSize(WIN_W, WIN_H)
	-- on `c` as well: the border's top band is drawn above anything on the window itself
	w.modernTitle = Text(c, "GameFontNormal", "CENTER")
	w.modernTitle:SetPoint("TOP", w, "TOP", 0, -5)
	w.modernTitle:SetText("Lootline - Farm counter")

	w.state = Text(c, "GameFontHighlight")
	w.state:SetPoint("TOPLEFT", 16, -46)
	w.time = Text(c, "GameFontHighlightLarge", "RIGHT")
	w.time:SetPoint("TOPRIGHT", -16, -44)

	Divider(c, -68)
	w.money = StatRow(c, -78, "Money looted")
	w.items = StatRow(c, -98, "Items looted")
	w.vendor = StatRow(c, -118, "   Vendor value")
	w.ah = StatRow(c, -138, "   Auction value")
	Divider(c, -160)
	w.total = StatRow(c, -170, "Total", "GameFontNormalLarge", "GameFontHighlightLarge")
	w.perHour = StatRow(c, -194, "Per hour", "GameFontNormal")
	Divider(c, -216)
	local best = Text(c, "GameFontNormalSmall")
	best:SetPoint("TOPLEFT", 16, -226)
	best:SetText("Best items")
	w.rows = {}
	for i = 1, TOP_ITEMS do w.rows[i] = ItemRow(c, -242 - (i - 1) * 20) end
	w.empty = Text(c, "GameFontDisable")
	w.empty:SetPoint("TOPLEFT", 16, -248)
	w.empty:SetText("Nothing looted yet.")

	w.toggle = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
	w.toggle:SetSize(132, 24)
	w.toggle:SetPoint("BOTTOMLEFT", 14, 12)
	w.toggle:SetScript("OnClick", Toggle)
	local reset = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
	reset:SetSize(132, 24)
	reset:SetPoint("BOTTOMRIGHT", -14, 12)
	reset:SetText("Reset")
	reset:SetScript("OnClick", Reset)
	w.reset = reset
	ApplyStyle(w)

	-- the clock keeps running while the window is open
	local since = 0
	w:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since >= 1 then
			since = 0
			RefreshWindow()
		end
	end)
	w:SetScript("OnShow", RefreshWindow)
	return w
end

ns.RefreshFarmWindow = RefreshWindow

function ns.ToggleFarmWindow()
	if not farm then return end
	if not win then
		win = CreateWindow()
		RefreshWindow() -- a frame created shown gets no OnShow
		return
	end
	win:SetShown(not win:IsShown())
end

function ns.FarmCommand(arg)
	if arg == "start" or arg == "resume" then
		Start()
	elseif arg == "stop" or arg == "pause" then
		Pause()
	elseif arg == "reset" then
		Reset()
	else
		ns.ToggleFarmWindow()
	end
end

---------------------------------------------------------------------------
-- Minimap button (no library: a plain button on the minimap's edge, dragged around it)
---------------------------------------------------------------------------

local function UpdatePosition()
	local angle = math.rad(db().minimap.angle or 225)
	local x, y = math.cos(angle), math.sin(angle)
	local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		-- square minimaps: slide along the edge instead of the circle
		local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
		x, y = max(-w, min(x * dw, w)), max(-h, min(y * dh, h))
	else
		x, y = x * w, y * h
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local GREY = 0.6

local function ShowTooltip(self)
	local s = Summarize()
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:ClearLines()
	GameTooltip:AddDoubleLine("Lootline", StateText())
	GameTooltip:AddDoubleLine("Time", TimeText(s.elapsed), 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Total", Money(s.total), 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddDoubleLine("Per hour", s.perHour and Money(s.perHour) or "-", 0.8, 0.8, 0.8, 1, 1, 1)
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click: farm window", GREY, GREY, GREY)
	GameTooltip:AddLine("Shift+Left-click: " .. ToggleText():lower() .. " the counter", GREY, GREY, GREY)
	GameTooltip:AddLine("Right-click: menu   Drag: move", GREY, GREY, GREY)
	GameTooltip:Show()
end

local function HideButton()
	db().minimap.hide = true
	ns.UpdateMinimapButton()
	ns.Print("minimap button hidden - /lootline minimap or Options > Farm brings it back")
	if ns.RefreshOptions then ns.RefreshOptions() end
end

-- Settings / Hide minimap button. Without a menu (gamepad interface style): the options.
local function ShowMenu(owner)
	if not (ns.CanShowMenu and ns.CanShowMenu()) then
		ns.OpenOptions()
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle("Lootline")
		root:CreateButton("Settings", function() ns.OpenOptions() end)
		root:CreateButton("Hide minimap button", HideButton)
	end)
end

local function OnUpdate(self, elapsed)
	if self.dragging then
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		db().minimap.angle = math.deg(atan2(py / scale - my, px / scale - mx)) % 360
		UpdatePosition()
		return
	end
	-- the hovered tooltip keeps its clock running
	self.sinceTip = (self.sinceTip or 0) + elapsed
	if self.sinceTip >= 1 and GameTooltip:IsOwned(self) then
		self.sinceTip = 0
		ShowTooltip(self)
	end
end

local function CreateButton()
	local b = CreateFrame("Button", "LootlineMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	b:SetScript("OnClick", function(self, mouse)
		if mouse == "RightButton" then
			GameTooltip:Hide()
			ShowMenu(self)
			return
		end
		if IsShiftKeyDown() then Toggle() else ns.ToggleFarmWindow() end
		if GameTooltip:IsOwned(self) then ShowTooltip(self) end
	end)
	b:SetScript("OnEnter", function(self)
		if self.dragging then return end
		self.sinceTip = 0
		ShowTooltip(self)
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", function(self)
		self.dragging = true
		GameTooltip:Hide()
	end)
	b:SetScript("OnDragStop", function(self) self.dragging = false end)
	b:SetScript("OnUpdate", OnUpdate)
	return b
end

-- shows / hides / refreshes the button after a setting or the counter changed
function ns.UpdateMinimapButton()
	if not farm or not Minimap then return end
	local hide = db().minimap.hide
	if hide and not button then return end
	if not button then button = CreateButton() end
	button:SetShown(not hide)
	UpdatePosition()
end

---------------------------------------------------------------------------
-- Init (from Lootline.lua's ADDON_LOADED, once LootlineDB is ready)
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	-- logging out or /reload: the clock stops here and starts again at the next login
	if farm and farm.running and farm.startedAt then
		farm.elapsed = Elapsed()
		farm.startedAt = nil
	end
end)

function ns.InitFarm()
	LootlineFarm = type(LootlineFarm) == "table" and LootlineFarm or {}
	farm = LootlineFarm
	farm.elapsed = tonumber(farm.elapsed) or 0
	farm.money = tonumber(farm.money) or 0
	if type(farm.items) ~= "table" then farm.items = {} end
	if farm.running and not farm.startedAt then farm.startedAt = time() end
	events:RegisterEvent("PLAYER_LOGOUT")
	ns.UpdateMinimapButton()
end
