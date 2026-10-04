-- Lootline: shows what you just looted as a stack of bars.
-- A standalone recreation of the "Loot Frame" WeakAura (wago.io/-IWPKK1il): same layout,
-- texts, sort order, slide animations, animated group reflow and pixel-glow highlights.

local ADDON_NAME, ns = ...
ns = ns or {} -- shared with Options.lua

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local format, tonumber, tostring = string.format, tonumber, tostring
local tinsert, tremove = table.insert, table.remove

-- API shims (Mainline moved most item functions into C_Item)
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or _G.GetItemInfo
local GetItemStats = (C_Item and C_Item.GetItemStats) or _G.GetItemStats
local GetDetailedItemLevelInfo = (C_Item and C_Item.GetDetailedItemLevelInfo) or _G.GetDetailedItemLevelInfo
local GetItemQualityColor = (C_Item and C_Item.GetItemQualityColor) or _G.GetItemQualityColor
local GetItemCount = (C_Item and C_Item.GetItemCount) or _G.GetItemCount

local function IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

local function Print(msg)
	print("|cff33ff99Lootline|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local DB_VERSION = 3

-- Defaults mostly follow the WeakAura's exported settings.
local DEFAULTS = {
	version = DB_VERSION,
	point = { "CENTER", "CENTER", -400, 95 }, -- bars' centre from the screen's centre, UIParent pixels
	width = 350,
	rowHeight = 40,
	spacing = 5,
	scale = 1,
	maxRows = 10,
	grow = "down", -- down, up, center (the WeakAura's centred vertical stack)
	fontSize = 12,
	mouse = true,
	minQuality = 0,
	questAlways = true, -- quest items ignore the quality / value filters
	minValue = 0, -- copper; hide items whose (vendor or auction) value x count is lower, 0 = off
	merge = true,
	showMoney = true,
	showCurrency = true,
	showRep = true,
	showPushed = true, -- quest rewards, purchases ("You receive item: ...")
	showCreated = true, -- crafted items ("You create: ...")
	showAH = 1, -- 1 off, 2 unit AH price, 3 stack AH price
	showJunkAH = true,
	showStackPrice = 1, -- 1 unit + stack total, 2 unit only, 3 stack total only
	dispCopSilv = true,
	invCount = true,
	showItemLevel = false, -- "ilvl: N" under gear (Classic tooltips do not show it either)
	fastLoot = false, -- take all loot at once without the loot window (see Faster auto loot)
	maxLength = 35,
	highlight = true,
	thresholds = { 10000, 50000, 100000 }, -- copper (1g / 5g / 10g), compared with the per-unit price
	sound = false,
	durations = {
		poor = 3, common = 5, uncommon = 10, rare = 15, epic = 20, legendary = 40,
		artifact = 15, heirloom = 15, quest = 15, money = 5, rep = 15, currency = 15,
	},
	blacklist = {},
}

local db

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local QUALITY_KEY = { [0] = "poor", "common", "uncommon", "rare", "epic", "legendary", "artifact", "heirloom", "heirloom" }

local BG_COLOR = { 0.074509803921569, 0.070588235294118, 0.047058823529412, 0.66423577070236 }
local GLOW_COLORS = {
	{ 0.95, 0.95, 0.32, 1 }, -- LibCustomGlow default (tier 1 has no colour of its own)
	{ 1, 0.60000002384186, 0, 1 },
	{ 1, 0.0039215688593686, 0.0039215688593686, 1 },
}
local SOUND_FILE = "Interface\\AddOns\\" .. tostring(ADDON_NAME) .. "\\Media\\wilhelm.ogg"
local TEXT_FONT = "Fonts\\2002.TTF"
local BADGE_FONT = "Fonts\\FRIZQT__.TTF"

local ICON_REP = 236681
local ICON_UNKNOWN = 134400

-- animation timings from the WeakAuras presets (slideright / slideleft) and dynamic group reflow
local START_DUR, FINISH_DUR, MOVE_DUR, SLIDE = 0.25, 0.25, 0.2, 50

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function QualityHex(q)
	if q and GetItemQualityColor then
		local _, _, _, hex = GetItemQualityColor(q)
		if type(hex) == "string" then return hex end
	end
	return "ffffffff"
end

local function StripCodes(s)
	return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "x"):gsub("|A.-|a", "x"))
end

-- Cuts a name to n characters (UTF-8 aware) and adds "..."; maxLength 0 keeps the name as is.
-- At least MIN_NAME characters stay, even when the appended text uses up the whole limit.
local MIN_NAME = 5

local function Truncate(s, n)
	if not db or db.maxLength <= 0 then return s end
	n = max(n, MIN_NAME)
	local count, i, len = 0, 1, #s
	while i <= len do
		local c = s:byte(i)
		local step = (c < 0x80 and 1) or (c < 0xE0 and 2) or (c < 0xF0 and 3) or 4
		count = count + 1
		if count > n then return s:sub(1, i - 1) .. "..." end
		i = i + step
	end
	return s
end

-- Money as the WeakAura prints it: white numbers, coloured g/s/c each followed by a space,
-- single digits padded with a space when a bigger unit is shown.
local G_TXT, S_TXT, C_TXT = "|cffffff00g |r", "|cffb0b0b0s |r", "|cffd17c4bc |r"

local function FormatPrice(copper)
	copper = floor((copper or 0) + 0.5)
	if copper <= 0 then return "" end
	local cv, sv, gv = copper % 100, floor(copper / 100) % 100, floor(copper / 10000)
	if gv > 0 then
		if not db.dispCopSilv then return gv .. G_TXT end
		return gv .. G_TXT .. (sv < 10 and " " or "") .. sv .. S_TXT .. (cv < 10 and " " or "") .. cv .. C_TXT
	end
	if not db.dispCopSilv then return "" end
	if sv > 0 then
		return sv .. S_TXT .. (cv < 10 and " " or "") .. cv .. C_TXT
	end
	return cv .. C_TXT
end

-- Turns a Blizzard format string (e.g. LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.")
-- into a Lua pattern, remembering the argument order for positional specifiers ("%1$s").
local function ToPattern(fmt, anchored)
	if type(fmt) ~= "string" then return end
	local out, order, auto, i = {}, {}, 0, 1
	while i <= #fmt do
		local c = fmt:sub(i, i)
		if c == "%" then
			local s, e, pos, dollar, spec = fmt:find("^%%(%d*)(%$?)[%d%.]*([sdf%%])", i)
			if not s then return end
			if spec == "%" then
				out[#out + 1] = "%%"
			else
				auto = auto + 1
				order[#order + 1] = (dollar ~= "" and tonumber(pos)) or auto
				if spec == "s" then
					out[#out + 1] = "(.-)"
				elseif spec == "d" then
					out[#out + 1] = "(%d+)"
				else
					out[#out + 1] = "([%d%.,]+)"
				end
			end
			i = e + 1
		else
			if c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then c = "%" .. c end
			out[#out + 1] = c
			i = i + 1
		end
	end
	local pat = table.concat(out)
	if anchored then pat = "^" .. pat .. "$" end
	return { pat = pat, order = order }
end

local function Match(msg, p)
	local caps = { msg:match(p.pat) }
	if #caps == 0 then return end
	local res = {}
	for i, pos in ipairs(p.order) do res[pos] = caps[i] end
	return res
end

---------------------------------------------------------------------------
-- Pixel glow: animated "marching lines" border, behaviour-compatible with
-- LibCustomGlow-1.0 PixelGlow_Start/_Stop (that library: MIT, (c) 2022 Benjamin Staneck).
-- Independent maskless rewrite: each moving line is drawn with at most two textures
-- (it can wrap only one corner because length <= min(width, height)).
---------------------------------------------------------------------------

local PG_KEY = "_LootlinePixelGlow"
local PG_WHITE = "Interface\\Buttons\\WHITE8X8"

local function PG_Round(v) return floor(v + 0.5) end

local function PG_NewTex(f, subLevel)
	local t = f:CreateTexture(nil, "ARTWORK", nil, subLevel)
	t:SetTexture(PG_WHITE)
	t:SetTexCoord(0, 1, 0, 1)
	return t
end

-- Draws the perimeter interval [u1, u2] lying on edge e as a th-thick strip.
-- u runs clockwise from the bottom-left corner:
-- e=1 left (bottom->top), 2 top (left->right), 3 right (top->bottom), 4 bottom (right->left).
-- Local coords: x right, y DOWN, origin = glow frame TOPLEFT. Corner squares belong to the
-- horizontal edges so a corner-wrapping line never double-blends.
local function PG_Strip(f, t, e, u1, u2, w, h, P, th)
	local x1, x2, y1, y2
	if e == 1 then
		x1, x2, y1, y2 = 0, th, max(PG_Round(h - u2), th), min(PG_Round(h - u1), h - th)
	elseif e == 2 then
		x1, x2, y1, y2 = max(PG_Round(u1 - h), 0), min(PG_Round(u2 - h), w), 0, th
	elseif e == 3 then
		x1, x2, y1, y2 = w - th, w, max(PG_Round(u1 - h - w), th), min(PG_Round(u2 - h - w), h - th)
	else
		x1, x2, y1, y2 = max(PG_Round(P - u2), 0), min(PG_Round(P - u1), w), h - th, h
	end
	if x2 <= x1 or y2 <= y1 then
		t:Hide()
		return
	end
	t:SetPoint("TOPLEFT", f, "TOPLEFT", x1, -y1)
	t:SetPoint("BOTTOMRIGHT", f, "TOPLEFT", x2, -y2)
	t:Show()
end

local function PG_OnUpdate(f, elapsed)
	local info = f.info
	f.timer = f.timer + elapsed / info.period
	if f.timer > 1 or f.timer < -1 then f.timer = f.timer % 1 end
	local w, h = f:GetSize() -- read every frame: follows resizes
	if not (w and h and w > 0 and h > 0) then return end
	local N, th, P = info.N, info.th, 2 * (w + h)
	local L = min(info.length or floor((w + h) * (2 / N - 0.1)), w, h)
	local e1, e2, e3 = h, h + w, 2 * h + w
	for k = 1, N do
		-- line k is centred on progress*P, progress = (timer + (k-1)/N) % 1
		local a = ((f.timer + (k - 1) / N) % 1) * P - L / 2
		if a < 0 then a = a + P end
		local b = a + L
		local e, eEnd
		if a < e1 then
			e, eEnd = 1, e1
		elseif a < e2 then
			e, eEnd = 2, e2
		elseif a < e3 then
			e, eEnd = 3, e3
		else
			e, eEnd = 4, P
		end
		local t1, t2 = f.lines[2 * k - 1], f.lines[2 * k]
		if b <= eEnd then
			PG_Strip(f, t1, e, a, b, w, h, P, th)
			t2:Hide()
		else -- wraps exactly one corner
			PG_Strip(f, t1, e, a, eEnd, w, h, P, th)
			if e == 4 then
				PG_Strip(f, t2, 1, 0, b - P, w, h, P, th)
			else
				PG_Strip(f, t2, e + 1, eEnd, b, w, h, P, th)
			end
		end
	end
end

-- frequency = laps per second (period = 1/frequency). border ~= false draws a dark
-- (0.1,0.1,0.1,0.8) band thickness+1 wide under the lines, like LibCustomGlow.
local function PixelGlowStart(frame, r, g, b, a, N, frequency, length, th, xOff, yOff, border)
	if not frame then return end
	if not r then r, g, b, a = 0.95, 0.95, 0.32, 1 end
	if not (N and N > 0) then N = 8 end
	local period = 4
	if frequency and (frequency > 0 or frequency < 0) then period = 1 / frequency end
	th, xOff, yOff = th or 1, xOff or 0, yOff or 0

	local f = frame[PG_KEY]
	if not f then
		f = CreateFrame("Frame", nil, frame)
		f.lines, f.bg, f.info, f.timer = {}, {}, {}, 0
		frame[PG_KEY] = f
	end
	f:SetFrameLevel(frame:GetFrameLevel() + 8) -- above icon/text/border of the row
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", frame, "TOPLEFT", -xOff + 0.05, yOff + 0.05)
	f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", xOff, -yOff + 0.05)

	for i = 1, 2 * N do
		f.lines[i] = f.lines[i] or PG_NewTex(f, 7)
		f.lines[i]:SetVertexColor(r, g, b, a or 1)
	end
	for i = 2 * N + 1, #f.lines do f.lines[i]:Hide() end

	if border ~= false then
		local bw = th + 1
		for i = 1, 4 do
			f.bg[i] = f.bg[i] or PG_NewTex(f, 6)
			f.bg[i]:ClearAllPoints()
			f.bg[i]:SetVertexColor(0.1, 0.1, 0.1, 0.8)
			f.bg[i]:Show()
		end
		f.bg[1]:SetPoint("TOPLEFT", f, "TOPLEFT")
		f.bg[1]:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, -bw)
		f.bg[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
		f.bg[2]:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, bw)
		f.bg[3]:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -bw)
		f.bg[3]:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", bw, bw)
		f.bg[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -bw)
		f.bg[4]:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", -bw, bw)
	else
		for i = 1, #f.bg do f.bg[i]:Hide() end
	end

	local info = f.info
	info.N, info.period, info.th, info.length = N, period, th, length
	f:Show() -- restart keeps f.timer (no phase jump)
	f:SetScript("OnUpdate", PG_OnUpdate)
	PG_OnUpdate(f, 0)
end

local function PixelGlowStop(frame)
	local f = frame and frame[PG_KEY]
	if not f then return false end
	f:SetScript("OnUpdate", nil)
	f:Hide()
	f.timer = 0 -- LibCustomGlow frees the frame: the next Start begins at progress 0
	return true
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local anchor = CreateFrame("Frame", "LootlineAnchor", UIParent)
anchor:SetFrameStrata("BACKGROUND")
anchor:SetMovable(true)
anchor:SetClampedToScreen(true)
anchor:RegisterForDrag("LeftButton")
anchor:EnableMouse(false)
anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
anchor.bg:SetAllPoints()
anchor.bg:SetColorTexture(0, 0.6, 0.2, 0.5)
anchor.bg:Hide()
anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
anchor.label:SetPoint("CENTER")
anchor.label:SetText("Lootline - drag me")
anchor.label:Hide()
-- right of the box, so the bars never cover it
anchor.lock = CreateFrame("Button", nil, anchor, "UIPanelButtonTemplate")
anchor.lock:SetSize(70, 22)
anchor.lock:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
anchor.lock:SetText("Lock")
anchor.lock:Hide()

local textFont = CreateFont("LootlineFontText")
local badgeFont = CreateFont("LootlineFontBadge")

local function SetFontSafe(fontObj, path, size, flags)
	fontObj:SetFont(path, size, flags)
	if not fontObj:GetFont() then fontObj:SetFont(STANDARD_TEXT_FONT, size, flags) end
	fontObj:SetTextColor(1, 1, 1, 1)
	fontObj:SetShadowColor(0, 0, 0, 1)
	fontObj:SetShadowOffset(1, -1)
end

local function ApplyFonts()
	SetFontSafe(textFont, TEXT_FONT, db.fontSize, "OUTLINE")
	SetFontSafe(badgeFont, BADGE_FONT, db.fontSize, "")
end

-- db.point offsets are UIParent pixels, so the bars stay put when their scale changes
-- (SetPoint offsets are in the scaled frame's own units).
local function ApplyPosition()
	local p = db.point
	anchor:SetScale(db.scale)
	anchor:ClearAllPoints()
	anchor:SetPoint(p[1], UIParent, p[2], p[3] / db.scale, p[4] / db.scale)
	anchor:SetSize(db.width, db.rowHeight)
end

local active = {} -- live entries (including ones playing their exit animation)
local pool = {}
local seqCounter = 0
local isLocked = true
local previewing = false -- "Show test bars" pressed while the options are open

-- Bars take the mouse only in normal play: unlocked they must not cover the drag box, and
-- during a preview they must not catch clicks meant for the options under them.
local function RowMouse(row)
	row:EnableMouse(db.mouse and isLocked and not previewing)
end

-- Unlocked or previewing, the stack is drawn above every window (the game's Options too).
local function UpdateLayer()
	anchor:SetFrameStrata((isLocked and not previewing) and "BACKGROUND" or "FULLSCREEN_DIALOG")
	for _, e in ipairs(active) do
		if e.row then RowMouse(e.row) end
	end
	for _, row in ipairs(pool) do RowMouse(row) end
end

local function SetLocked(locked)
	isLocked = locked and true or false
	anchor:EnableMouse(not isLocked)
	anchor.bg:SetShown(not isLocked)
	anchor.label:SetShown(not isLocked)
	anchor.lock:SetShown(not isLocked)
	UpdateLayer()
	if ns.OnLockChanged then ns.OnLockChanged(isLocked) end
end

-- Ends by itself once the last bar is gone (see the OnUpdate below) or the options close.
local function SetPreviewMode(on)
	previewing = on and true or false
	UpdateLayer()
end

anchor.lock:SetScript("OnClick", function()
	if ns.FinishMove then ns.FinishMove() else SetLocked(true) end
	if ns.RefreshOptions then ns.RefreshOptions() end
end)

anchor:SetScript("OnDragStart", anchor.StartMoving)
anchor:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	-- store the centre relative to the screen centre (the game re-anchors to whatever is nearest)
	local cx, cy = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	local s = self:GetScale()
	db.point = { "CENTER", "CENTER", floor(cx * s - ux + 0.5), floor(cy * s - uy + 0.5) }
	ApplyPosition()
	if ns.RefreshOptions then ns.RefreshOptions() end
end)

local function ApplyRowGeometry(row)
	local w, h = db.width, db.rowHeight
	row:SetSize(w, h)
	-- icon: full height square flush left, WA zoom 0.3 => texcoords 0.075..0.925
	row.icon:ClearAllPoints()
	row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
	row.icon:SetSize(h, h)
	-- flat background only behind the bar part (right of the icon)
	row.bg:ClearAllPoints()
	row.bg:SetPoint("TOPLEFT", row, "TOPLEFT", h, 0)
	row.bg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	-- 1px black outline around the whole row (icon included)
	local e = row.edges
	for i = 1, 4 do e[i]:ClearAllPoints() end
	e[1]:SetPoint("TOPLEFT", row, "TOPLEFT")
	e[1]:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, -1)
	e[2]:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
	e[2]:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT", 0, 1)
	e[3]:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
	e[3]:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", 1, 1)
	e[4]:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
	e[4]:SetPoint("BOTTOMLEFT", row, "BOTTOMRIGHT", -1, 1)
	-- texts: INNER_LEFT / INNER_RIGHT of the bar part, 2px padding
	row.left:ClearAllPoints()
	row.left:SetPoint("LEFT", row, "LEFT", h + 2, 0)
	row.right:ClearAllPoints()
	row.right:SetPoint("RIGHT", row, "RIGHT", -2, 0)
	row.badge:ClearAllPoints()
	row.badge:SetPoint("TOPLEFT", row.icon, "TOPLEFT", 0, 0)
	RowMouse(row)
end

local BeginExit -- forward declaration (used by the click handler)

local function Row_OnEnter(self)
	local e = self.entry
	if not e or not e.link then return end
	GameTooltip:SetOwner(self, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("LEFT", self, "RIGHT")
	GameTooltip:SetHyperlink(e.link)
	GameTooltip:Show()
end

local function Row_OnLeave()
	GameTooltip:Hide()
end

local function Row_OnClick(self, button)
	local e = self.entry
	if not e then return end
	if button == "RightButton" then
		if IsShiftKeyDown() and e.kind ~= "money" and not e.preview then
			-- gear bars are keyed by their full item string, the ignore list by itemID
			local key = e.ignoreKey or e.key
			db.blacklist[key] = e.plain or key
			Print("Ignoring " .. (e.plain or key) .. " (/lootline ignorelist)")
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
		BeginExit(e)
	elseif e.link and IsModifiedClick() and HandleModifiedItemClick then
		HandleModifiedItemClick(e.link)
	end
end

local function CreateRow()
	local row = CreateFrame("Button", nil, anchor)
	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetColorTexture(BG_COLOR[1], BG_COLOR[2], BG_COLOR[3], BG_COLOR[4])
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetTexCoord(0.075, 0.925, 0.075, 0.925)
	row.edges = {}
	for i = 1, 4 do
		local t = row:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetColorTexture(0, 0, 0, 1)
		row.edges[i] = t
	end
	row.left = row:CreateFontString(nil, "OVERLAY")
	row.left:SetFontObject(textFont)
	row.left:SetJustifyH("LEFT")
	row.right = row:CreateFontString(nil, "OVERLAY")
	row.right:SetFontObject(textFont)
	row.right:SetJustifyH("RIGHT")
	row.badge = row:CreateFontString(nil, "OVERLAY")
	row.badge:SetFontObject(badgeFont)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)
	row:SetScript("OnClick", Row_OnClick)
	ApplyRowGeometry(row)
	return row
end

local function AcquireRow()
	local row = tremove(pool) or CreateRow()
	ApplyRowGeometry(row)
	row:SetAlpha(0)
	return row
end

---------------------------------------------------------------------------
-- Entries, layout and animation
--
-- An entry plays: "in" (slide in from +50px, alpha 0->1, 0.25s), "shown", then after its
-- duration "out" (slide to -50px, alpha 1->0, 0.25s) while keeping its slot. When it is gone
-- the stack re-sorts and every bar whose slot changed glides there in 0.2s.
---------------------------------------------------------------------------

local function SortEntries(a, b)
	if a.prio ~= b.prio then return a.prio < b.prio end
	return a.seq < b.seq
end

local function SlotY(i, n)
	local h, sp = db.rowHeight, db.spacing
	if db.grow == "up" then
		return (i - 1) * (h + sp)
	elseif db.grow == "down" then
		return -(i - 1) * (h + sp)
	end
	local total = n * h + (n - 1) * sp
	return -total / 2 + h / 2 + (i - 1) * (h + sp)
end

local function MoveOffset(e)
	if e.moveDelta == 0 then return 0 end
	return e.moveDelta * (1 - min(e.moveT / MOVE_DUR, 1))
end

local function UpdateVisual(e)
	local alpha, slide = 1, 0
	if e.state == "in" then
		local p = min(e.animT / START_DUR, 1)
		alpha, slide = p, SLIDE * (1 - p)
	elseif e.state == "out" then
		local p = min(e.animT / FINISH_DUR, 1)
		alpha, slide = 1 - p, -SLIDE * p
	end
	local row = e.row
	row:SetAlpha(alpha)
	row:ClearAllPoints()
	row:SetPoint("LEFT", anchor, "LEFT", slide, e.slotY + MoveOffset(e))
end

local function Reflow()
	table.sort(active, SortEntries)
	local n = min(#active, db.maxRows)
	for i, e in ipairs(active) do
		if i <= n then
			local y = SlotY(i, n)
			if e.slotY then
				if abs(e.slotY - y) > 0.01 then
					-- glide from where the bar is drawn right now to its new slot
					e.moveDelta = e.slotY + MoveOffset(e) - y
					e.moveT = 0
				end
			else
				-- new bars (and bars coming back from overflow) appear directly in their slot
				e.moveDelta, e.moveT = 0, 0
			end
			e.slotY = y
			e.row:Show()
			UpdateVisual(e)
		else
			-- beyond the limit: hidden but alive, like the WA group limit
			e.slotY = nil
			e.moveDelta, e.moveT = 0, 0
			e.row:Hide()
		end
	end
end

local function ReleaseAt(i)
	local e = tremove(active, i)
	if not e then return end
	local row = e.row
	PixelGlowStop(row)
	row:Hide()
	row.entry = nil
	if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
	pool[#pool + 1] = row
	e.row = nil
	e.dead = true
end

local function RemoveEntry(e)
	for i, a in ipairs(active) do
		if a == e then
			ReleaseAt(i)
			return true
		end
	end
end

function BeginExit(e)
	if e.dead or e.state == "out" then return end
	if e.slotY then
		e.state, e.animT = "out", 0
	else
		RemoveEntry(e)
		Reflow()
	end
end

-- live entry with this key that can still be merged into (not leaving)
local function FindLive(key)
	for _, e in ipairs(active) do
		if e.key == key and e.state ~= "out" then return e end
	end
end

local function RenderRow(e)
	local row = e.row
	if not row then return end
	row.entry = e
	row.icon:SetTexture(e.icon or ICON_UNKNOWN)
	row.left:SetText(e.left or "")
	row.right:SetText(e.right or "")
	row.badge:SetText(e.badge or "")
	local c = db.highlight and e.tier and GLOW_COLORS[e.tier]
	if c then
		PixelGlowStart(row, c[1], c[2], c[3], c[4], 20, 0.05, 20, 0.55, 0, 0, true)
	else
		PixelGlowStop(row)
	end
end

local function TierFor(unitPrice, ahUnit)
	if not db.highlight then return nil end
	unitPrice = unitPrice or 0
	for i = #db.thresholds, 1, -1 do
		local thresh = tonumber(db.thresholds[i]) or 0
		if unitPrice >= thresh or (ahUnit and ahUnit >= thresh) then return i end
	end
end

-- Recomputes texts/tier and redraws; plays the sound when the bar reaches tier 3
-- (not when only a setting changed: silent).
local function Rebuild(e, silent)
	local oldTier = e.tier or 0
	e.build(e)
	if not silent and db.sound and (e.tier or 0) >= 3 and oldTier < 3 then
		PlaySoundFile(SOUND_FILE, "Master")
	end
	RenderRow(e)
end

-- Adds a new entry (plays the slide-in) or, when a live entry has the same key, merges into it
-- through e.merge(existing) and restarts its timer without any animation.
local function Push(e)
	if not e.duration or e.duration <= 0 then return end
	-- money, currency and reputation always merge; the merge option is about items
	local live = (db.merge or e.kind ~= "item") and FindLive(e.key)
	if live then
		if live.merge then live:merge(e) end
		live.duration = e.duration
		live.expires = GetTime() + e.duration
		Rebuild(live)
		return live
	end
	seqCounter = seqCounter + 1
	e.seq = seqCounter
	e.state, e.animT = "in", 0
	e.moveDelta, e.moveT = 0, 0
	e.expires = GetTime() + e.duration
	e.row = AcquireRow()
	tinsert(active, e)
	Rebuild(e)
	Reflow() -- also applies alpha 0 / +50px right away, so there is no one-frame flash
	return e
end

local function ClearAll()
	for i = #active, 1, -1 do ReleaseAt(i) end
	if previewing then SetPreviewMode(false) end
end

local function RebuildAll()
	ApplyFonts()
	ApplyPosition()
	for _, e in ipairs(active) do
		ApplyRowGeometry(e.row)
		Rebuild(e, true)
	end
	for _, row in ipairs(pool) do ApplyRowGeometry(row) end
	Reflow()
end

anchor:SetScript("OnUpdate", function(_, elapsed)
	if #active == 0 then return end
	local now = GetTime()
	local removed = false
	for i = #active, 1, -1 do
		local e = active[i]
		local drop = false
		if e.state ~= "out" and now >= e.expires then
			if e.slotY then
				e.state, e.animT = "out", 0
			else
				drop = true -- hidden by the row limit: nothing to animate
			end
		end
		if not drop then
			if e.state == "in" then
				e.animT = e.animT + elapsed
				if e.animT >= START_DUR then e.state = "shown" end
			elseif e.state == "out" then
				e.animT = e.animT + elapsed
				if e.animT >= FINISH_DUR then drop = true end
			end
			if e.moveDelta ~= 0 then
				e.moveT = e.moveT + elapsed
				if e.moveT >= MOVE_DUR then e.moveDelta, e.moveT = 0, 0 end
			end
		end
		if drop then
			ReleaseAt(i)
			removed = true
		elseif e.slotY then
			UpdateVisual(e)
		end
	end
	if removed then Reflow() end
	if previewing and #active == 0 then SetPreviewMode(false) end
end)

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

local TERTIARY = { -- WA order
	{ "ITEM_MOD_CR_AVOIDANCE_SHORT", "Avoidance" },
	{ "ITEM_MOD_CR_LIFESTEAL_SHORT", "Leech" },
	{ "ITEM_MOD_CR_SPEED_SHORT", "Speed" },
	{ "ITEM_MOD_CR_STURDINESS_SHORT", "Indestructible" },
}

local SOCKETS = { -- WA order and icons
	{ "EMPTY_SOCKET_META", 136257 },
	{ "EMPTY_SOCKET_RED", 136258 },
	{ "EMPTY_SOCKET_YELLOW", 136259 },
	{ "EMPTY_SOCKET_BLUE", 136256 },
	{ "EMPTY_SOCKET_PRISMATIC", 458977 },
}

-- Auction price from Auctionator's public API (it knows prices once it has scanned the AH).
local function GetAHPrice(link)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemLink then
		local ok, v = pcall(api.GetAuctionPriceByItemLink, ADDON_NAME, link)
		if ok and type(v) == "number" and v > 0 then return v end
	end
end

local function IsGear(classID, equipLoc)
	return (classID == 2 or classID == 4) and equipLoc ~= nil and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE"
end

-- "ilvl: N  Leech  <socket icons>Socket" - same pieces and spacing as the WA
local function GearLine(link, isGear)
	local tert, sock = "", ""
	local stats = GetItemStats and GetItemStats(link)
	if type(stats) == "table" then
		for _, t in ipairs(TERTIARY) do
			if stats[t[1]] then tert = tert .. " |cFF00FFFF" .. (_G[t[1]] or t[2]) .. "|r" end
		end
		local icons, known = "", {}
		for _, s in ipairs(SOCKETS) do
			known[s[1]] = true
			for _ = 1, (tonumber(stats[s[1]]) or 0) do icons = icons .. "|T" .. s[2] .. ":0|t" end
		end
		for k, v in pairs(stats) do -- newer socket types get the prismatic icon
			if type(k) == "string" and not known[k] and k:find("^EMPTY_SOCKET_") then
				for _ = 1, (tonumber(v) or 1) do icons = icons .. "|T458977:0|t" end
			end
		end
		if icons ~= "" then sock = " " .. icons .. "|cFFFF00FFSocket|r" end
	end
	local ilvl = db.showItemLevel and isGear and GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
	if sock == "" and tert == "" and not ilvl then return nil end
	return (ilvl and ("|rilvl: " .. ilvl .. " ") or "|r") .. tert .. (sock ~= "" and (" " .. sock) or "")
end

-- crafting quality badge at the icon's top-left (WA %pQuality)
local function QualityBadge(link)
	if not CreateAtlasMarkup then return nil end
	local tier = link:match("Professions%-ChatIcon%-Quality%-Tier(%d)")
	if tier then return CreateAtlasMarkup("professions-icon-quality-tier" .. tier .. "-inv", 32, 32) end
	local t12 = link:match("Professions%-ChatIcon%-Quality%-12%-Tier(%d)")
	if t12 then
		local atlas = "professions-icon-quality-12-tier" .. t12 .. "-inv"
		if C_Texture and C_Texture.GetAtlasInfo and not C_Texture.GetAtlasInfo(atlas) then
			atlas = "professions-icon-quality-tier" .. t12 .. "-inv"
		end
		return CreateAtlasMarkup(atlas, 32, 32)
	end
end

local function InvText(e)
	if not db.invCount or e.isGear or not GetItemCount then return nil, 0 end
	local ok, n = pcall(GetItemCount, e.link)
	if ok and type(n) == "number" and n > 1 then
		return " |r(" .. n .. ") ", #tostring(n) + 2
	end
	return nil, 0
end

local function BuildItem(e)
	if e.link then e.gearLine = GearLine(e.link, e.isGear) end -- follows the item level option
	local append, appendLen = "", 0
	if e.inv then append, appendLen = e.inv, e.invLen end
	e.left = (e.count > 1 and (e.count .. "x ") or "") .. "|c" .. QualityHex(e.rarity)
		.. Truncate(e.plain, db.maxLength - appendLen) .. append
		.. (e.gearLine and ("\n" .. e.gearLine) or "")

	local price = ""
	local function add(s)
		if s and s ~= "" then price = price .. (price ~= "" and "\n" or "") .. s end
	end
	e.ah = nil
	if db.showAH ~= 1 and e.link and (db.showJunkAH or e.rarity > 0) then
		e.ah = GetAHPrice(e.link)
		if e.ah then add(FormatPrice((db.showAH == 3 and e.count > 1) and e.ah * e.count or e.ah)) end
	end
	if db.showStackPrice ~= 3 or e.count == 1 then add(FormatPrice(e.sellPrice)) end
	if e.count > 1 and e.sellPrice > 0 and db.showStackPrice ~= 2 then add(FormatPrice(e.count * e.sellPrice)) end
	e.right = price
	e.tier = TierFor(e.sellPrice, e.rarity > 0 and e.ah or nil)
end

local function MergeItem(self, other)
	self.count = self.count + other.count
end

-- The bag count updates a moment after the loot message: poll a few times (WA does the same).
local function PollInventory(e)
	if not db.invCount or e.isGear then return end
	local token = {}
	e.invToken = token
	local first = e.inv or ""
	local tries = 0
	local function poll()
		if e.dead or e.invToken ~= token then return end
		tries = tries + 1
		e.inv, e.invLen = InvText(e)
		if (e.inv or "") ~= first then
			Rebuild(e)
		elseif tries < 6 then
			C_Timer.After(0.2, poll)
		end
	end
	C_Timer.After(0.2, poll)
end

local function ItemDuration(rarity, isQuest)
	local d = db.durations
	if isQuest then return d.quest end
	return d[QUALITY_KEY[rarity] or "common"] or d.common
end

local function ResolveItem(link, cb)
	if GetItemInfo(link) then return cb() end
	if Item and Item.CreateFromItemLink then
		local item = Item:CreateFromItemLink(link)
		if not item:IsItemEmpty() then
			item:ContinueOnItemLoad(cb)
			return
		end
	end
	local tries = 0
	local function retry()
		tries = tries + 1
		if GetItemInfo(link) or tries >= 10 then cb() else C_Timer.After(0.2, retry) end
	end
	C_Timer.After(0.2, retry)
end

local function AddItem(link, count, force)
	local itemID = tonumber(link:match("item:(%d+)"))
	if not itemID then return end
	if not force and db.blacklist["item:" .. itemID] then return end
	ResolveItem(link, function()
		local name, _, quality, _, _, _, _, _, equipLoc, icon, sellPrice, classID = GetItemInfo(link)
		name = name or link:match("%[(.-)%]") or ("item:" .. itemID)
		quality = quality or 1
		local isQuest = classID == 12
		local isGear = IsGear(classID, equipLoc)
		-- gear merges by its exact item string (different ilvl = different bar), the rest by itemID
		local key = "item:" .. itemID
		if isGear then key = link:match("|H(item:[^|]+)|h") or key end
		-- a pickup that merges into a bar already on screen skips the filters, so its count stays right
		local merging = db.merge and FindLive(key)
		if not force and not merging and not (isQuest and db.questAlways) then
			if quality < db.minQuality then return end
			if (db.minValue or 0) > 0 then
				local unit = sellPrice or 0
				local ah = GetAHPrice(link)
				if ah and ah > unit then unit = ah end
				-- no known price (soulbound mounts, toys, tokens...) is not the same as worthless
				if unit > 0 and unit * count < db.minValue then return end
			end
		end
		local rarity = isQuest and 7 or quality
		local e = {
			kind = "item", key = key, ignoreKey = "item:" .. itemID, link = link, plain = name, count = count,
			rarity = rarity, prio = rarity, isGear = isGear,
			icon = icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)),
			sellPrice = sellPrice or 0,
			badge = QualityBadge(link),
			duration = ItemDuration(quality, isQuest),
			build = BuildItem, merge = MergeItem,
		}
		e.inv, e.invLen = InvText(e)
		local shown = Push(e)
		if shown then PollInventory(shown) end
	end)
end

---------------------------------------------------------------------------
-- Money (PLAYER_MONEY delta, like the WA: any income shows, spending lowers the total)
---------------------------------------------------------------------------

local trackMoney

local function BuildMoney(e)
	e.left = "|cffffffff" .. (MONEY or "Money")
	e.right = FormatPrice(e.total)
	e.icon = (e.total < 100 and 133788) or (e.total < 10000 and 133786) or 133784
	e.tier = TierFor(e.total)
end

local function OnMoneyChanged()
	local now = GetMoney()
	if not trackMoney then
		trackMoney = now
		return
	end
	local delta = now - trackMoney
	trackMoney = now
	if not db.showMoney or delta == 0 then return end
	local live = FindLive("money")
	local total = delta + (live and live.total or 0)
	if total <= 0 then return end
	if live then
		live.total = total
		live.expires = GetTime() + db.durations.money
		Rebuild(live)
	else
		Push({ kind = "money", key = "money", prio = -1, total = total, plain = MONEY or "Money",
			duration = db.durations.money, build = BuildMoney })
	end
end

---------------------------------------------------------------------------
-- Currency
---------------------------------------------------------------------------

local function BuildCurrency(e)
	local append, capped
	if e.useEarned and e.max > 0 then
		capped = e.earned >= e.max
		append = " |r|cffffffff|r" .. e.qty .. (capped and "|cffFF0000" or "") .. " (" .. e.earned .. " / " .. e.max
			.. (capped and "|r" or "") .. "|cffffffff)|r"
	else
		capped = e.max > 0 and e.qty >= e.max
		append = " |r|cffffffff(|r" .. (capped and "|cffFF0000" or "") .. e.qty .. (e.max ~= 0 and (" / " .. e.max) or "")
			.. (capped and "|r" or "") .. "|cffffffff)|r"
	end
	e.left = (e.count > 1 and (e.count .. "x ") or "") .. "|c" .. QualityHex(6)
		.. Truncate(e.plain, db.maxLength - #StripCodes(append)) .. append
	e.right = ""
	e.tier = TierFor(0)
end

local function ReadCurrency(e, info)
	e.qty = info.quantity or 0
	e.max = info.maxQuantity or 0
	e.earned = info.totalEarned or 0
	e.useEarned = info.useTotalEarnedForMaxQty and true or false
end

local function AddCurrency(currencyID, change, link)
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
	if not info or not info.name or info.name == "" or info.isTypeUnused then return end
	local key = "cur:" .. currencyID
	if db.blacklist[key] then return end
	local e = {
		kind = "currency", key = key, currencyID = currencyID, link = link, plain = info.name,
		icon = info.iconFileID, count = change, prio = 9, duration = db.durations.currency,
		build = BuildCurrency,
		merge = function(self, other)
			self.count = self.count + other.count
			self.qty, self.max, self.earned, self.useEarned = other.qty, other.max, other.earned, other.useEarned
		end,
	}
	ReadCurrency(e, info)
	local shown = Push(e)
	-- the chat line can arrive before the total is updated
	if shown then
		C_Timer.After(0.3, function()
			local fresh = C_CurrencyInfo.GetCurrencyInfo(currencyID)
			if fresh and not shown.dead then
				ReadCurrency(shown, fresh)
				Rebuild(shown)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------

local function FindFactionID(name)
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, C_Reputation.GetNumFactions() do
			local d = C_Reputation.GetFactionDataByIndex(i)
			if d and d.name == name then return d.factionID end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local fname, _, _, _, _, _, _, _, _, _, _, _, _, factionID = GetFactionInfo(i)
			if fname == name then return factionID end
		end
	end
end

-- Returns progress inside the current standing and an optional level suffix:
-- current, max, " R: <renown/friendship rank>" or " P: <paragon level>"
local function FactionProgress(id)
	if not id then return end
	if C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(id)
		and C_Reputation.GetFactionParagonInfo then
		local cur, threshold, _, hasReward = C_Reputation.GetFactionParagonInfo(id)
		if cur and threshold and threshold > 0 then
			local level = floor(cur / threshold) - (hasReward and 1 or 0)
			return cur - level * threshold, threshold, " P: " .. level
		end
	end
	if C_Reputation and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id)
		and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
		local m = C_MajorFactions.GetMajorFactionData(id)
		if m and m.renownLevelThreshold then
			return m.renownReputationEarned, m.renownLevelThreshold, m.renownLevel and (" R: " .. m.renownLevel) or nil
		end
	end
	if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
		local f = C_GossipInfo.GetFriendshipReputation(id)
		if f and f.friendshipFactionID and f.friendshipFactionID > 0 then
			local suffix = f.reaction and (" R: " .. f.reaction) or nil
			if f.nextThreshold then
				return f.standing - f.reactionThreshold, f.nextThreshold - f.reactionThreshold, suffix
			end
			return nil, nil, suffix
		end
	end
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local d = C_Reputation.GetFactionDataByID(id)
		if d and d.nextReactionThreshold and d.nextReactionThreshold > d.currentReactionThreshold then
			return d.currentStanding - d.currentReactionThreshold, d.nextReactionThreshold - d.currentReactionThreshold
		end
	elseif GetFactionInfoByID then
		local _, _, _, barMin, barMax, barValue = GetFactionInfoByID(id)
		if barMax and barMax > barMin then return barValue - barMin, barMax - barMin end
	end
end

local function BuildRep(e)
	local n = e.count
	local prefix = n >= 0 and ("+" .. n .. " ") or ("|cffFF0000" .. n .. "|r ")
	local append = ""
	if e.cur and e.maxRep then append = " |r(" .. e.cur .. " / " .. e.maxRep .. ")" end
	if e.suffix then append = append .. e.suffix end
	e.left = prefix .. "|c" .. QualityHex(7) .. Truncate(e.plain .. " Rep", db.maxLength - #StripCodes(append)) .. append
	e.right = ""
	e.tier = TierFor(0)
end

local function AddRep(faction, amount)
	local key = "rep:" .. faction
	if db.blacklist[key] then return end
	local e = Push({
		kind = "rep", key = key, plain = faction, icon = ICON_REP, count = amount, prio = 10,
		duration = db.durations.rep, build = BuildRep,
		merge = function(self, other) self.count = self.count + other.count end,
	})
	if not e then return end
	-- standings update a moment after the chat message
	C_Timer.After(0.3, function()
		if e.dead then return end
		e.cur, e.maxRep, e.suffix = FactionProgress(FindFactionID(faction))
		Rebuild(e)
	end)
end

---------------------------------------------------------------------------
-- Chat parsing
---------------------------------------------------------------------------

local LOOT_PATTERNS, REP_PATTERNS, CURRENCY_PATTERNS = {}, {}, {}

local function AddPatterns(list, names, anchored, extra)
	for _, name in ipairs(names) do
		local p = ToPattern(_G[name], anchored)
		if p then
			if extra then extra(p, name) end
			list[#list + 1] = p
		end
	end
end

local function BuildPatterns()
	AddPatterns(LOOT_PATTERNS, {
		"LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
		"LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_SELF",
	}, true, function(p) p.kind = "loot" end)
	AddPatterns(LOOT_PATTERNS, {
		"LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
		"LOOT_ITEM_REFUND_MULTIPLE", "LOOT_ITEM_REFUND",
	}, true, function(p) p.kind = "pushed" end)
	AddPatterns(LOOT_PATTERNS, {
		"LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF",
	}, true, function(p) p.kind = "created" end)

	AddPatterns(REP_PATTERNS, {
		"FACTION_STANDING_INCREASED_DOUBLE_BONUS",
		"FACTION_STANDING_INCREASED_ACH_BONUS",
		"FACTION_STANDING_INCREASED_BONUS",
		"FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
		"FACTION_STANDING_INCREASED",
	}, true, function(p) p.sign = 1 end)
	AddPatterns(REP_PATTERNS, {
		"FACTION_STANDING_DECREASED_ACCOUNT_WIDE",
		"FACTION_STANDING_DECREASED",
	}, true, function(p) p.sign = -1 end)

	AddPatterns(CURRENCY_PATTERNS, {
		"CURRENCY_GAINED_MULTIPLE_OVERFLOW",
		"CURRENCY_GAINED_MULTIPLE_BONUS",
		"CURRENCY_GAINED_MULTIPLE",
		"CURRENCY_GAINED",
	}, true)
end

---------------------------------------------------------------------------
-- Loot window capture + chat backstop
---------------------------------------------------------------------------

-- The loot window and the chat line both report the same pickup. Each source moves a
-- balance in opposite directions; we only show the loot when the balance moves away from 0,
-- so whichever arrives first wins and the other is swallowed.
local dedup = {}
local lootCapture, lootSessionOpen = {}, false

local function ClaimLoot(link, quantity, fromChat)
	local key = (link:match("item:(%d+)") or link) .. "\1" .. tostring(quantity)
	local now = GetTime()
	local t = dedup[key]
	if not t or t.expires <= now then
		t = { balance = 0 }
		dedup[key] = t
	end
	t.expires = now + 5
	local before = t.balance
	t.balance = before + (fromChat and -1 or 1)
	return abs(t.balance) > abs(before)
end

local function NotifyLoot(link, quantity, fromChat)
	if link and link:find("|Hitem:") and ClaimLoot(link, quantity, fromChat) then
		AddItem(link, quantity)
	end
end

local function CaptureLootWindow()
	if not lootSessionOpen then
		wipe(lootCapture)
		lootSessionOpen = true
	end
	for slot = 1, GetNumLootItems() do
		if not lootCapture[slot] then
			local link = GetLootSlotLink(slot)
			if link and not IsSecret(link) then
				local _, _, quantity = GetLootSlotInfo(slot)
				lootCapture[slot] = { link = link, quantity = quantity or 1 }
			end
		end
	end
end

---------------------------------------------------------------------------
-- Faster auto loot: when every slot can simply be taken, take them all at once and keep the
-- game's loot window from opening for that loot. The window's own LOOT_OPENED event is switched
-- off for that one loot only (a plain widget call, so none of Blizzard's loot window code runs
-- from here). Anything that needs the player - Bind on Pickup, rolls, master loot, locked slots,
-- full bags, items the client has not loaded - leaves the loot to the normal window.
---------------------------------------------------------------------------

local FL = { owned = false, session = 0, lastClear = 0, failed = false, src = nil, skipSrc = nil, skipUntil = 0 }

-- loot errors that mean a slot stays on the corpse
local LOOT_ERRORS = {}
for _, name in ipairs({ "ERR_INV_FULL", "ERR_ITEM_MAX_COUNT", "ERR_LOOT_ROLL_PENDING", "ERR_LOOT_CANT_LOOT_THAT",
	"ERR_LOOT_CANT_LOOT_THAT_NOW", "ERR_TOO_MUCH_GOLD" }) do
	if type(_G[name]) == "string" then LOOT_ERRORS[_G[name]] = true end
end

-- only undoes what Lootline did
local function RestoreLootFrame()
	if not FL.owned then return end
	FL.owned = false
	if LootFrame and LootFrame.IsEventRegistered and not LootFrame:IsEventRegistered("LOOT_OPENED") then
		LootFrame:RegisterEvent("LOOT_OPENED")
	end
end

local function FreeBagSlots()
	if not (C_Container and C_Container.GetContainerNumFreeSlots) then return nil end
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, family = C_Container.GetContainerNumFreeSlots(bag)
		if type(n) == "number" and (family == 0 or family == nil) then free = free + n end
	end
	return free
end

-- "money" / "item" when the slot can be taken without asking the player, nil otherwise
local function SlotKind(slot, inGroup)
	local slotType = GetLootSlotType and GetLootSlotType(slot)
	if slotType == nil or IsSecret(slotType) then return nil end
	local LST = Enum and Enum.LootSlotType or { None = 0, Item = 1, Money = 2, Currency = 3 }
	if slotType == LST.None then return "empty" end
	local _, _, _, _, quality, locked = GetLootSlotInfo(slot)
	if IsSecret(locked) or IsSecret(quality) or locked then return nil end -- roll, master loot, not yours
	if slotType == LST.Money or slotType == LST.Currency then return "money" end
	if inGroup and GetLootThreshold and (quality or 0) >= GetLootThreshold() then return nil end
	local link = GetLootSlotLink(slot)
	if not link or IsSecret(link) then return nil end
	local bindType = select(14, GetItemInfo(link))
	if bindType == nil or bindType == 1 then return nil end -- not loaded yet, or Bind on Pickup: the game asks first
	return "item"
end

local function LeftBehind()
	local left = {}
	for slot = 1, GetNumLootItems() do
		if LootSlotHasItem(slot) then
			local link = GetLootSlotLink(slot)
			if link and not IsSecret(link) then left[#left + 1] = link end
		end
	end
	RestoreLootFrame()
	FL.skipSrc, FL.skipUntil = FL.src, GetTime() + 30 -- next loot of this corpse opens the window
	CloseLoot()
	Print("could not take everything" .. (#left > 0 and (": " .. table.concat(left, ", ")) or "")
		.. ". Loot again to open the loot window.")
end

-- The client closes the loot by itself once it is empty; this only steps in when it does not.
local function Watch(session)
	C_Timer.After(0.5, function()
		if session ~= FL.session or not FL.owned then return end
		local left = false
		for slot = 1, GetNumLootItems() do
			if LootSlotHasItem(slot) then left = true break end
		end
		local idle = GetTime() - FL.lastClear
		if not left then
			if idle > 2 then CloseLoot() else Watch(session) end
		elseif idle > (FL.failed and 0.4 or 1.5) then
			LeftBehind()
		else
			Watch(session)
		end
	end)
end

-- first LOOT_READY of a loot
local function FastLoot()
	FL.session = FL.session + 1
	FL.failed, FL.lastClear = false, GetTime()
	local src = GetLootSourceInfo and GetLootSourceInfo(1)
	FL.src = (src and not IsSecret(src)) and src or nil
	if not db.fastLoot or IsModifiedClick("AUTOLOOTTOGGLE") then return end -- Shift: the usual window
	local n = GetNumLootItems()
	if not n or IsSecret(n) or n == 0 then return end
	if GetTime() < FL.skipUntil and (FL.skipSrc == nil or FL.skipSrc == FL.src) then
		FL.skipSrc, FL.skipUntil = nil, 0
		return
	end
	local inGroup = IsInGroup and IsInGroup()
	local items = 0
	for slot = 1, n do
		local kind = SlotKind(slot, inGroup)
		if not kind then return end
		if kind == "item" then items = items + 1 end
	end
	if items > 0 and FreeBagSlots() == 0 then return end
	local frame = LootFrame
	if frame and frame.IsEventRegistered and frame:IsEventRegistered("LOOT_OPENED") and not frame:IsShown() then
		frame:UnregisterEvent("LOOT_OPENED")
		FL.owned = true
		if IsFishingLoot and IsFishingLoot() and SOUNDKIT and SOUNDKIT.FISHING_REEL_IN then
			PlaySound(SOUNDKIT.FISHING_REEL_IN) -- the hidden window would have played it
		end
	end
	for slot = n, 1, -1 do LootSlot(slot) end
	if FL.owned then Watch(FL.session) end
end

ns.RestoreLootFrame = RestoreLootFrame

local H = {}

function H.CHAT_MSG_LOOT(msg, _, _, _, _, _, _, _, _, _, _, guid)
	if IsSecret(msg) or type(msg) ~= "string" then return end
	local playerGUID = UnitGUID("player")
	if guid and guid ~= "" and not IsSecret(guid) and not IsSecret(playerGUID) and guid ~= playerGUID then return end
	for _, p in ipairs(LOOT_PATTERNS) do
		local r = Match(msg, p)
		if r then
			if (p.kind == "pushed" and not db.showPushed) or (p.kind == "created" and not db.showCreated) then return end
			local count = tonumber(r[2]) or 1
			if p.kind == "loot" then
				NotifyLoot(r[1], count, true)
			elseif r[1] and r[1]:find("|Hitem:") then
				AddItem(r[1], count) -- pushed / created items never come from the loot window
			end
			return
		end
	end
end

function H.LOOT_READY()
	local newLoot = not lootSessionOpen
	CaptureLootWindow() -- always before any LootSlot
	if newLoot then FastLoot() end -- LOOT_READY can repeat within one loot: decide once
end

function H.LOOT_OPENED()
	CaptureLootWindow()
end

function H.LOOT_SLOT_CLEARED(slot)
	FL.lastClear = GetTime()
	if IsSecret(slot) then return end
	local data = lootCapture[slot]
	if not data then
		-- something emptied this slot before we saw the window; grab what is left
		CaptureLootWindow()
		data = lootCapture[slot]
	end
	if data then
		lootCapture[slot] = nil
		NotifyLoot(data.link, data.quantity, false)
	end
end

function H.LOOT_CLOSED()
	RestoreLootFrame()
	FL.session = FL.session + 1 -- stops a pending Watch
	lootSessionOpen = false
	wipe(lootCapture)
	local now = GetTime()
	for key, t in pairs(dedup) do
		if t.expires <= now then dedup[key] = nil end
	end
end

function H.LOOT_ITEM_ROLL_WON(link, quantity)
	if link and not IsSecret(link) then NotifyLoot(link, quantity or 1, false) end
end

function H.PLAYER_MONEY()
	OnMoneyChanged()
end

function H.PLAYER_ENTERING_WORLD()
	trackMoney = GetMoney()
	RestoreLootFrame()
end

function H.UI_ERROR_MESSAGE(_, msg)
	if FL.owned and type(msg) == "string" and not IsSecret(msg) and LOOT_ERRORS[msg] then
		FL.failed = true -- Watch hands the rest over once nothing more arrives
	end
end

function H.CHAT_MSG_CURRENCY(msg)
	if not db.showCurrency or IsSecret(msg) or type(msg) ~= "string" then return end
	for _, p in ipairs(CURRENCY_PATTERNS) do
		local r = Match(msg, p)
		if r and r[1] then
			local id = tonumber(r[1]:match("|Hcurrency:(%d+)"))
			if id then
				local link = r[1]:match("(|c.-|r)") or r[1]
				AddCurrency(id, tonumber(r[2]) or 1, link)
			end
			return
		end
	end
end

function H.CHAT_MSG_COMBAT_FACTION_CHANGE(msg)
	if not db.showRep or IsSecret(msg) or type(msg) ~= "string" then return end
	for _, p in ipairs(REP_PATTERNS) do
		local r = Match(msg, p)
		if r and r[1] and tonumber(r[2]) then
			AddRep(r[1], p.sign * tonumber(r[2]))
			return
		end
	end
end

---------------------------------------------------------------------------
-- Preview (/lootline test): well-known Classic items. Name, quality, icon and vendor price come
-- from the game itself; the values here are only used if the client cannot load an item.
---------------------------------------------------------------------------

-- { itemID, count, fallback name, quality, icon, vendor price in copper }
-- Values from the Forever 1.60.1.70170 item tables; all of them ship in the client's local item data.
local PREVIEW_ITEMS = {
	{ 19019, 1, "Thunderfury, Blessed Blade of the Windseeker", 5, "Interface\\Icons\\INV_Sword_39", 255355 },
	{ 17073, 1, "Earthshaker", 4, "Interface\\Icons\\INV_Hammer_04", 113631 },
	{ 12640, 1, "Lionheart Helm", 4, "Interface\\Icons\\INV_Helmet_36", 21894 },
	{ 12784, 1, "Arcanite Reaper", 3, "Interface\\Icons\\INV_Axe_09", 73036 },
	{ 13468, 2, "Black Lotus", 2, "Interface\\Icons\\INV_Misc_Herb_BlackLotus", 1000 },
	{ 14047, 20, "Runecloth", 1, "Interface\\Icons\\INV_Fabric_PurpleFire_01", 400 },
	{ 7073, 3, "Broken Fang", 0, "Interface\\Icons\\INV_Misc_Bone_08", 6 },
}
local PREVIEW_CURRENCY = { 3402, 5, "Merchant's Favor", 135725 } -- currencyID, gained, fallback name, icon
local PREVIEW_FACTION = "Argent Dawn"

local function PreviewItem(def)
	local id, count = def[1], def[2]
	local done = false
	local function push()
		if done then return end
		done = true
		local name, link, quality, _, _, _, _, _, equipLoc, icon, sellPrice, classID = GetItemInfo(id)
		local rarity = quality or def[4]
		Push({
			kind = "item", key = "test:" .. id, preview = true, link = link, plain = name or def[3],
			rarity = rarity, prio = rarity, isGear = name and IsGear(classID, equipLoc) or false,
			icon = icon or def[5], count = count, sellPrice = sellPrice or def[6],
			badge = link and QualityBadge(link) or nil,
			duration = ItemDuration(rarity), build = BuildItem, merge = MergeItem,
		})
	end
	if GetItemInfo(id) then return push() end
	if Item and Item.CreateFromItemID then
		local item = Item:CreateFromItemID(id)
		if not item:IsItemEmpty() then item:ContinueOnItemLoad(push) end
	end
	-- also polls (clients without ItemMixin) and gives up after 2s with the fallback values
	local tries = 0
	local function retry()
		if done then return end
		tries = tries + 1
		if GetItemInfo(id) or tries >= 10 then push() else C_Timer.After(0.2, retry) end
	end
	C_Timer.After(0.2, retry)
end

local function PreviewCurrency(def)
	local id, count = def[1], def[2]
	local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
	if not (info and info.name and info.name ~= "") then info = nil end
	local icon = info and info.iconFileID
	Push({
		kind = "currency", key = "test:cur" .. id, preview = true, plain = info and info.name or def[3],
		icon = (icon and icon ~= 0) and icon or def[4], count = count,
		qty = (info and info.quantity or 0) + count, max = info and info.maxQuantity or 0, earned = 0,
		prio = 9, duration = db.durations.currency, build = BuildCurrency,
	})
end

local function RunTest()
	for _, def in ipairs(PREVIEW_ITEMS) do PreviewItem(def) end
	PreviewCurrency(PREVIEW_CURRENCY)
	Push({ kind = "money", key = "test:money", preview = true, prio = -1, total = 123456, plain = MONEY or "Money",
		duration = db.durations.money, build = BuildMoney })
	Push({ kind = "rep", key = "test:rep", preview = true, plain = PREVIEW_FACTION, icon = ICON_REP, count = 50,
		cur = 1250, maxRep = 6000, prio = 10, duration = db.durations.rep, build = BuildRep })
end

---------------------------------------------------------------------------
-- API for Options.lua
---------------------------------------------------------------------------

local function ResetPosition()
	db.point = { unpack(DEFAULTS.point) }
	ApplyPosition()
end

local function ResetDefaults()
	local blacklist = db.blacklist
	wipe(db)
	CopyDefaults(DEFAULTS, db)
	db.blacklist = blacklist
	RebuildAll()
end

-- Ignores an itemID. Items not in the client cache are stored as "item <id>" and renamed
-- once the client has loaded them.
local function IgnoreItem(id)
	id = tonumber(id)
	if not id then return end
	local key = "item:" .. id
	local name = GetItemInfo(id)
	if name then
		db.blacklist[key] = name
		return name
	end
	local placeholder = "item " .. id
	db.blacklist[key] = placeholder
	local function rename()
		local loaded = GetItemInfo(id)
		if loaded and db.blacklist[key] == placeholder then
			db.blacklist[key] = loaded
			if ns.RefreshOptions then ns.RefreshOptions() end
		end
		return loaded
	end
	if Item and Item.CreateFromItemID then
		local item = Item:CreateFromItemID(id)
		if not item:IsItemEmpty() then item:ContinueOnItemLoad(rename) end
	else
		local tries = 0
		local function retry()
			tries = tries + 1
			if not rename() and tries < 10 then C_Timer.After(0.2, retry) end
		end
		C_Timer.After(0.2, retry)
	end
	return placeholder
end

ns.Print = Print
ns.GetDB = function() return db end
ns.Apply = RebuildAll
ns.IsLocked = function() return isLocked end
ns.SetLocked = SetLocked
ns.SetPreviewMode = SetPreviewMode
ns.ResetPosition = ResetPosition
ns.ResetDefaults = ResetDefaults
ns.GetOffset = function() return db.point[3], db.point[4] end
ns.SetOffset = function(x, y)
	db.point[3], db.point[4] = x, y
	ApplyPosition()
end
ns.RunTest = RunTest
ns.ClearAll = ClearAll
-- something to look at while moving or resizing the bars
ns.EnsurePreview = function()
	if #active == 0 then RunTest() end
end
ns.IgnoreItem = IgnoreItem

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local DURATION_KEYS = "poor, common, uncommon, rare, epic, legendary, artifact, heirloom, quest, money, rep, currency"

local function Toggle(field, label)
	db[field] = not db[field]
	Print(label .. ": " .. (db[field] and "|cff33ff33on|r" or "|cffff3333off|r"))
end

local function Help()
	Print("commands (/lootline <command>):")
	print("  /lootline  - options (Esc > Options > AddOns > Lootline)  |  /lootline help  - this list")
	print("  unlock | lock  - move the frame")
	print("  test  - show the sample bars")
	print("  clear  - remove all bars")
	print("  reset  - reset position | defaults - reset every setting")
	print("  grow down|up|center  - stack layout")
	print("  scale <n> | width <n> | height <n> | spacing <n> | font <n> | max <n>")
	print("  minq <0-5>  - minimum item quality (0 poor ... 5 legendary)")
	print("  minvalue <money>  - hide items worth less (0 = off)  |  questalways  - toggle")
	print("  duration <type> <sec>  - types: " .. DURATION_KEYS .. " (0 = hide)")
	print("  money | currency | rep | pushed | created  - toggle sources")
	print("  merge | highlight | sound | invcount | ilvl | coppersilver | mouse  - toggle options")
	print("  fastloot  - Faster auto loot: everything at once, without the loot window")
	print("  ah off|unit|stack  - auction price line (Auctionator)")
	print("  stackprice both|unit|stack  - vendor price lines")
	print("  threshold <m1> <m2> <m3>  - highlight thresholds (per unit)")
	print("  maxlen <n>  - name length limit (0 = off)")
	print("  ignore <itemID>  |  unignore <itemID or key>  |  ignorelist")
	print("  <money>: 2 = 2 gold, or 1g50s, 75s")
	print("  Right-click a bar: dismiss  -  Shift+Right-click: ignore")
end

-- "2" / "2.5" = gold; "1g50s", "75s", "3c" also work. Returns copper, nil when unreadable.
local function ParseMoney(s)
	if not s or s == "" then return end
	s = s:lower():gsub("%s+", "")
	local n = tonumber(s)
	if n then return n >= 0 and floor(n * 10000 + 0.5) or nil end
	if s:gsub("%d+%.?%d*[gsc]", "") ~= "" then return end
	local copper, unit = 0, { g = 10000, s = 100, c = 1 }
	for num, u in s:gmatch("(%d+%.?%d*)([gsc])") do copper = copper + tonumber(num) * unit[u] end
	return floor(copper + 0.5)
end

local function MoneyText(copper)
	local g, s, c = floor(copper / 10000), floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

local AH_MODES = { off = 1, unit = 2, stack = 3 }
local STACK_MODES = { both = 1, unit = 2, stack = 3 }

SLASH_LOOTLINE1 = "/lootline" -- no short alias: "/lb" is taken by too many addons
SlashCmdList.LOOTLINE = function(input)
	local args = {}
	for w in (input or ""):gmatch("%S+") do args[#args + 1] = w end
	local cmd = (args[1] or ""):lower()
	local arg2 = args[2] and args[2]:lower()
	local n = tonumber(args[2])

	if cmd == "" or cmd == "config" or cmd == "options" or cmd == "settings" then
		if ns.OpenOptions then ns.OpenOptions() else Help() end
		return
	elseif cmd == "unlock" then
		SetLocked(false)
		Print("unlocked - drag the green box")
	elseif cmd == "lock" then
		SetLocked(true)
		Print("locked")
	elseif cmd == "test" then
		RunTest()
	elseif cmd == "clear" then
		ClearAll()
	elseif cmd == "reset" then
		ResetPosition()
	elseif cmd == "defaults" then
		ResetDefaults()
		Print("settings reset")
	elseif cmd == "grow" and (arg2 == "center" or arg2 == "up" or arg2 == "down") then
		db.grow = arg2
		Reflow()
	elseif cmd == "scale" and n and n > 0 then
		db.scale = n
		RebuildAll()
	elseif cmd == "width" and n and n > 0 then
		db.width = n
		RebuildAll()
	elseif cmd == "height" and n and n > 0 then
		db.rowHeight = n
		RebuildAll()
	elseif cmd == "spacing" and n then
		db.spacing = n
		RebuildAll()
	elseif cmd == "font" and n and n > 0 then
		db.fontSize = n
		RebuildAll()
	elseif cmd == "max" and n and n > 0 then
		db.maxRows = floor(n)
		Reflow()
	elseif cmd == "minq" and n then
		db.minQuality = n
		Print("minimum quality: " .. n)
	elseif cmd == "minvalue" and ParseMoney((input or ""):match("^%s*%S+%s+(.-)%s*$")) then
		db.minValue = ParseMoney((input or ""):match("^%s*%S+%s+(.-)%s*$"))
		Print("hide items worth less than: " .. (db.minValue > 0 and MoneyText(db.minValue) or "off"))
	elseif cmd == "questalways" then
		Toggle("questAlways", "always show quest items")
	elseif cmd == "duration" and arg2 and db.durations[arg2] and tonumber(args[3]) then
		db.durations[arg2] = tonumber(args[3])
		Print(arg2 .. " duration: " .. args[3] .. "s")
	elseif cmd == "money" then
		Toggle("showMoney", "money")
	elseif cmd == "currency" then
		Toggle("showCurrency", "currency")
	elseif cmd == "rep" then
		Toggle("showRep", "reputation")
	elseif cmd == "pushed" then
		Toggle("showPushed", "quest rewards / purchases")
	elseif cmd == "created" then
		Toggle("showCreated", "crafted items")
	elseif cmd == "merge" then
		Toggle("merge", "merge same items")
	elseif cmd == "highlight" then
		Toggle("highlight", "highlight expensive items")
		RebuildAll()
	elseif cmd == "sound" then
		Toggle("sound", "sound on tier 3 highlight")
	elseif cmd == "invcount" then
		Toggle("invCount", "bag count")
	elseif cmd == "ilvl" then
		Toggle("showItemLevel", "item level under gear")
		RebuildAll()
	elseif cmd == "fastloot" then
		Toggle("fastLoot", "faster auto loot")
		if not db.fastLoot then RestoreLootFrame() end
	elseif cmd == "coppersilver" then
		Toggle("dispCopSilv", "show copper/silver")
		RebuildAll()
	elseif cmd == "mouse" then
		Toggle("mouse", "mouse interaction (off = click-through)")
		RebuildAll()
	elseif cmd == "ah" and arg2 and AH_MODES[arg2] then
		db.showAH = AH_MODES[arg2]
		Print("AH price: " .. arg2)
		RebuildAll()
	elseif cmd == "stackprice" and arg2 and STACK_MODES[arg2] then
		db.showStackPrice = STACK_MODES[arg2]
		Print("vendor price: " .. arg2)
		RebuildAll()
	elseif cmd == "threshold" and ParseMoney(args[2]) and ParseMoney(args[3]) and ParseMoney(args[4]) then
		db.thresholds = { ParseMoney(args[2]), ParseMoney(args[3]), ParseMoney(args[4]) }
		Print(format("highlight thresholds: %s / %s / %s",
			MoneyText(db.thresholds[1]), MoneyText(db.thresholds[2]), MoneyText(db.thresholds[3])))
		RebuildAll()
	elseif cmd == "maxlen" and n then
		db.maxLength = floor(n)
		RebuildAll()
	elseif cmd == "ignore" and args[2] then
		local id = tonumber(args[2]) or tonumber((input or ""):match("item:(%d+)"))
		if id then
			Print("ignoring " .. IgnoreItem(id))
		end
	elseif cmd == "unignore" and args[2] then
		-- the rest of the line: faction keys contain spaces ("rep:Iskaara Tuskarr")
		local rest = (input or ""):match("^%s*%S+%s+(.-)%s*$")
		local key = tonumber(rest) and ("item:" .. rest) or rest
		if db.blacklist[key] ~= nil then
			db.blacklist[key] = nil
			Print("removed " .. key)
		else
			Print(key .. " is not in the ignore list (/lootline ignorelist)")
		end
	elseif cmd == "ignorelist" then
		Print("ignored:")
		for k, v in pairs(db.blacklist) do print("  " .. k .. "  " .. tostring(v)) end
	else
		Help()
		return
	end
	if ns.RefreshOptions then ns.RefreshOptions() end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

-- Brings saved settings up to DB_VERSION. Values still at an old default take the new default.
local function Migrate(saved)
	local version = saved.version or 1
	if version < 2 then
		-- 1.0 defaults differed from the WeakAura; start fresh but keep the ignore list
		return { blacklist = saved.blacklist }
	end
	if version < 3 then
		-- money settings are stored in copper now (they were gold)
		if type(saved.minValue) == "number" then saved.minValue = floor(saved.minValue * 10000 + 0.5) end
		local t = saved.thresholds
		if type(t) == "table" then
			if t[1] == 20 and t[2] == 200 and t[3] == 1000 then
				saved.thresholds = nil
			else
				for i = 1, 3 do t[i] = floor((tonumber(t[i]) or 0) * 10000 + 0.5) end
			end
		end
		if saved.grow == "center" then saved.grow = nil end
		if saved.width == 400 then saved.width = nil end
		local p = saved.point
		if type(p) == "table" and p[1] == "LEFT" and p[2] == "TOP" and p[3] == -200 and p[4] == -364 then
			saved.point = nil
		end
		saved.tsmSource = nil -- TradeSkillMaster support was dropped
	end
	return saved
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		if ... ~= ADDON_NAME then return end
		self:UnregisterEvent("ADDON_LOADED")
		local saved = Migrate(LootlineDB or {})
		LootlineDB = CopyDefaults(DEFAULTS, saved)
		db = LootlineDB
		db.version = DB_VERSION
		BuildPatterns()
		ApplyFonts()
		ApplyPosition()
		SetLocked(true)
		for ev in pairs(H) do pcall(self.RegisterEvent, self, ev) end
		if ns.RegisterSettingsPage then
			local ok, err = pcall(ns.RegisterSettingsPage)
			if not ok then Print("could not add the Settings entry: " .. tostring(err)) end
		end
		return
	end
	local handler = H[event]
	if handler then handler(...) end
end)
