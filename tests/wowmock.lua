-- Minimal World of Warcraft API mock for loading Lootline.lua outside the game (fengari / Lua 5.3).
-- Unknown widget methods and unknown globals are recorded so typos in API names show up.

__out = {}
function print(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	__out[#__out + 1] = table.concat(t, " ")
end

unpack = unpack or table.unpack
-- Lua 5.1's string.gsub/find behave the same for our purposes; 5.1 has no math.pow removal issues

__unknownMethods = {}
__unknownGlobals = {}
__allFrames = {}
__now = 1000
__timers = {}
__sounds = {}

function GetTime() return __now end

local function noop() end

-- widget object -------------------------------------------------------------
local Widget = {}
local WidgetMT = {}
WidgetMT.__index = function(t, k)
	local m = Widget[k]
	if m then return m end
	if type(k) == "string" and k:match("^[A-Z]") then
		__unknownMethods[(rawget(t, "__type") or "?") .. ":" .. k] = true
		return noop
	end
	return nil
end

local function NewObject(objType, parent, name)
	local o = setmetatable({
		__type = objType, __parent = parent, __points = {}, __scripts = {}, __shown = true,
		__alpha = 1, __width = 0, __height = 0, __scale = 1, __children = {}, __text = "",
		__mouse = false, __level = 1,
	}, WidgetMT)
	if parent and type(parent) == "table" and parent.__children then
		parent.__children[#parent.__children + 1] = o
	end
	if name then _G[name] = o end
	__allFrames[#__allFrames + 1] = o
	return o
end

-- frame-ish methods
function Widget:SetPoint(point, rel, relPoint, x, y)
	if type(rel) == "number" then x, y, rel, relPoint = rel, relPoint, nil, nil end
	self.__points[#self.__points + 1] = { point, rel, relPoint, x or 0, y or 0 }
end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:GetPoint(i)
	local p = self.__points[i or 1]
	if not p then return nil end
	return p[1], p[2], p[3] or p[1], p[4], p[5]
end
function Widget:GetNumPoints() return #self.__points end
function Widget:SetAllPoints(rel) self.__points = { { "ALL", rel } } end
function Widget:SetSize(w, h) self.__width, self.__height = w, h end
function Widget:SetWidth(w) self.__width = w end
function Widget:SetHeight(h) self.__height = h end
function Widget:GetWidth() return self.__width end
function Widget:GetHeight() return self.__height end
function Widget:GetSize() return self.__width, self.__height end
function Widget:Show()
	local was = self.__shown
	self.__shown = true
	if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end
end
function Widget:Hide()
	local was = self.__shown
	self.__shown = false
	if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Widget:SetShown(s) if s then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible()
	local o = self
	while o do
		if type(o) ~= "table" or not o.__shown then return o == nil end
		o = o.__parent
	end
	return true
end
function Widget:SetAlpha(a)
	assert(type(a) == "number", "SetAlpha needs a number")
	self.__alpha = math.max(0, math.min(1, a))
end
function Widget:GetAlpha() return self.__alpha end
function Widget:SetScale(s)
	assert(type(s) == "number" and s > 0, "SetScale needs a positive number")
	self.__scale = s
end
function Widget:GetScale() return self.__scale end
function Widget:GetEffectiveScale() return self.__scale end
-- like the game: setting one of these handlers turns mouse input on (EnableMouse(true))
local MOUSE_SCRIPTS = { OnEnter = true, OnLeave = true, OnMouseDown = true, OnMouseUp = true }
function Widget:SetScript(name, fn)
	self.__scripts[name] = fn
	if fn and MOUSE_SCRIPTS[name] then self.__mouse = true end
end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HookScript(name, fn)
	local old = self.__scripts[name]
	self.__scripts[name] = function(...) if old then old(...) end fn(...) end
	if MOUSE_SCRIPTS[name] then self.__mouse = true end
end
function Widget:RegisterEvent(ev) self.__events = self.__events or {}; self.__events[ev] = true end
function Widget:UnregisterEvent(ev) if self.__events then self.__events[ev] = nil end end
function Widget:IsEventRegistered(ev) return self.__events ~= nil and self.__events[ev] == true end
function Widget:RegisterForDrag() end
function Widget:RegisterForClicks() end
function Widget:EnableMouse(b) self.__mouse = not not b end
function Widget:IsMouseEnabled() return self.__mouse end
function Widget:IsMouseOver() return self.__mouseOver == true end
function Widget:SetMovable() end
function Widget:SetClampedToScreen() end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetFrameStrata() return self.__strata or "MEDIUM" end
function Widget:SetUserPlaced(b) self.__userPlaced = b end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameLevel() return self.__level end
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p) self.__parent = p end
function Widget:StartMoving() end
function Widget:StopMovingOrSizing() end
function Widget:GetName() return self.__name end
function Widget:GetObjectType() return self.__type end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self.__width end
function Widget:GetTop() return self.__height end
function Widget:GetBottom() return 0 end
function Widget:GetCenter()
	if self.__center then return self.__center[1], self.__center[2] end -- tests set it to fake a drag
	return self.__width / 2, self.__height / 2
end
function Widget:SetClipsChildren() end
function Widget:SetIgnoreParentAlpha() end
function Widget:SetIgnoreParentScale() end
-- backdrop
function Widget:SetBackdrop(b) self.__backdrop = b end
function Widget:SetBackdropColor(r, g, b, a) self.__bdColor = { r, g, b, a } end
function Widget:SetBackdropBorderColor(r, g, b, a) self.__bdBorder = { r, g, b, a } end
-- regions
function Widget:CreateTexture(name, layer)
	local t = NewObject("Texture", self, name)
	t.__layer = layer
	return t
end
function Widget:CreateFontString(name, layer, template)
	local f = NewObject("FontString", self, name)
	f.__layer = layer
	return f
end
function Widget:CreateMaskTexture(name, layer) return NewObject("MaskTexture", self, name) end
function Widget:CreateLine(name, layer) return NewObject("Line", self, name) end
-- texture
function Widget:SetTexture(tex) self.__tex = tex end
function Widget:GetTexture() return self.__tex end
function Widget:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a } end
function Widget:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a } end
function Widget:SetTexCoord(...) self.__texcoord = { ... } end
function Widget:SetDrawLayer() end
function Widget:SetBlendMode(m) self.__blend = m end
function Widget:SetDesaturated() end
function Widget:SetAtlas(a) self.__atlas = a end
function Widget:SetGradient() end
function Widget:SetRotation(r) self.__rotation = r end
function Widget:SetSnapToPixelGrid() end
function Widget:SetTexelSnappingBias() end
function Widget:AddMaskTexture() end
function Widget:SetHorizTile() end
function Widget:SetVertTile() end
-- fontstring
function Widget:SetText(t) self.__text = t == nil and "" or tostring(t) end
function Widget:GetText() return self.__text end
function Widget:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function Widget:SetFontObject(f) self.__fontObject = f end
function Widget:SetFont(path, size, flags)
	assert(type(path) == "string" and type(size) == "number", "SetFont(path, size, flags) bad args")
	self.__font = { path, size, flags }
	return true
end
function Widget:GetFont() if self.__font then return unpack(self.__font) end end
function Widget:SetJustifyH(j) self.__justifyH = j end
function Widget:SetJustifyV(j) self.__justifyV = j end
function Widget:SetWordWrap(w) self.__wrap = w end
function Widget:SetNonSpaceWrap() end
function Widget:SetMaxLines(n) self.__maxLines = n end
function Widget:SetSpacing() end
function Widget:SetShadowOffset() end
function Widget:SetShadowColor() end
function Widget:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a } end
function Widget:GetStringWidth()
	-- crude: strip colour/texture escapes, 6px per char
	local s = self.__text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "XX")
	return #s * 6
end
function Widget:GetStringHeight() return 12 end
function Widget:GetUnboundedStringWidth() return self:GetStringWidth() end
function Widget:IsTruncated() return false end
-- buttons / check buttons
function Widget:SetChecked(c) self.__checked = not not c end
function Widget:GetChecked() return self.__checked == true end
function Widget:SetEnabled(e) self.__enabled = not not e end
function Widget:Enable() self.__enabled = true end
function Widget:Disable() self.__enabled = false end
function Widget:IsEnabled() return self.__enabled ~= false end
function Widget:LockHighlight() end
function Widget:UnlockHighlight() end
function Widget:SetHitRectInsets(...) self.__hitInsets = { ... } end
-- simulated mouse click; a CheckButton toggles before OnClick runs, like in the game
function Widget:Click(button)
	if self.__enabled == false then return end
	if self.__type == "CheckButton" then self.__checked = not self.__checked end
	local fn = self.__scripts.OnClick
	if fn then fn(self, button or "LeftButton", true) end
end
-- sliders
function Widget:SetOrientation(o) self.__orientation = o end
function Widget:SetThumbTexture(t) self.__thumb = t end
function Widget:SetMinMaxValues(lo, hi) self.__min, self.__max = lo, hi end
function Widget:GetMinMaxValues() return self.__min, self.__max end
function Widget:SetValueStep(s) self.__step = s end
function Widget:SetObeyStepOnDrag() end
function Widget:EnableMouseWheel(b) self.__wheel = b end
function Widget:SetValue(v)
	assert(type(v) == "number", "SetValue needs a number")
	if self.__min then v = math.max(self.__min, math.min(self.__max, v)) end
	local changed = self.__value ~= v
	self.__value = v
	if changed and self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, v, false) end
end
function Widget:GetValue() return self.__value or 0 end
-- edit boxes
function Widget:SetAutoFocus() end
function Widget:SetMaxLetters() end
function Widget:SetNumeric() end
function Widget:SetFocus() self.__focus = true end
function Widget:HasFocus() return self.__focus == true end
function Widget:ClearFocus()
	local had = self.__focus
	self.__focus = false
	if had and self.__scripts.OnEditFocusLost then self.__scripts.OnEditFocusLost(self) end
end
-- tooltip
function Widget:SetOwner(owner) self.__owner = owner end
function Widget:IsOwned(f) return self.__owner == f end
function Widget:SetHyperlink(l) self.__link = l end
function Widget:SetCurrencyByID() end
function Widget:AddLine() end
function Widget:AddDoubleLine() end
function Widget:ClearLines() end
-- animation groups
function Widget:CreateAnimationGroup(name)
	local g = NewObject("AnimationGroup", self, name)
	g.__anims = {}
	g.__playing = false
	return g
end
function Widget:CreateAnimation(animType, name)
	local a = NewObject("Animation:" .. tostring(animType), self, name)
	self.__anims = self.__anims or {}
	self.__anims[#self.__anims + 1] = a
	return a
end
function Widget:Play() self.__playing = true; self.__played = (self.__played or 0) + 1 end
function Widget:Stop()
	local was = self.__playing
	self.__playing = false
	if was and self.__scripts.OnStop then self.__scripts.OnStop(self) end
end
function Widget:Pause() end
function Widget:Restart() self.__playing = true end
function Widget:Finish() self:__finish() end
function Widget:IsPlaying() return self.__playing end
function Widget:SetLooping(l) self.__looping = l end
function Widget:SetToFinalAlpha() end
function Widget:SetDuration(d) self.__duration = d end
function Widget:GetDuration() return self.__duration or 0 end
function Widget:SetOffset(x, y) self.__offset = { x, y } end
function Widget:SetFromAlpha(a) self.__fromAlpha = a end
function Widget:SetToAlpha(a) self.__toAlpha = a end
function Widget:SetSmoothing(s) self.__smoothing = s end
function Widget:SetStartDelay(d) self.__delay = d end
function Widget:SetOrder(o) self.__order = o end
function Widget:SetScaleFrom() end
function Widget:SetScaleTo() end
function Widget:SetOrigin() end
function Widget:SetTarget() end
function Widget:SetChildKey() end
function Widget:GetProgress() return 0 end
function Widget:__finish()
	if self.__playing then
		self.__playing = false
		if self.__scripts.OnFinished then self.__scripts.OnFinished(self) end
	end
end
function __finishAllAnimations()
	for _, o in ipairs(__allFrames) do
		if o.__type == "AnimationGroup" and o.__playing then o:__finish() end
	end
end

-- fonts
function CreateFont(name)
	local f = NewObject("Font", nil, name)
	return f
end

-- frame types that take mouse clicks from the start; plain Frames and Sliders do not
local MOUSE_BY_DEFAULT = { Button = true, CheckButton = true, EditBox = true }

function CreateFrame(frameType, name, parent, template)
	local f = NewObject(frameType or "Frame", parent, name)
	f.__template = template
	f.__name = name
	f.__mouse = MOUSE_BY_DEFAULT[frameType] == true
	if template and tostring(template):find("BackdropTemplate") then f.__backdropTemplate = true end
	return f
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
-- the game's loot window: opens on LOOT_OPENED, closes on LOOT_CLOSED; __lootWindowShows counts openings
__lootWindowShows = 0
LootFrame = CreateFrame("Frame", "LootFrame", UIParent)
LootFrame:Hide()
LootFrame:RegisterEvent("LOOT_OPENED")
LootFrame:RegisterEvent("LOOT_CLOSED")
LootFrame:SetScript("OnEvent", function(self, event)
	if event == "LOOT_OPENED" then
		__lootWindowShows = __lootWindowShows + 1
		self:Show()
	else
		self:Hide()
	end
end)

-- events -------------------------------------------------------------------
function __fire(event, ...)
	for _, o in ipairs(__allFrames) do
		if o.__events and o.__events[event] and o.__scripts.OnEvent then
			o.__scripts.OnEvent(o, event, ...)
		end
	end
end

function __tick(elapsed, steps)
	steps = steps or 1
	for _ = 1, steps do
		__now = __now + elapsed
		-- timers
		local due = {}
		for i = #__timers, 1, -1 do
			if __timers[i].at <= __now then
				due[#due + 1] = table.remove(__timers, i)
			end
		end
		table.sort(due, function(a, b) return a.at < b.at end)
		for _, t in ipairs(due) do t.fn() end
		-- OnUpdate on visible frames
		for _, o in ipairs(__allFrames) do
			local fn = o.__scripts.OnUpdate
			if fn and o:IsVisible() then fn(o, elapsed) end
		end
	end
end

C_Timer = {
	After = function(d, fn)
		assert(type(fn) == "function", "C_Timer.After needs a function")
		__timers[#__timers + 1] = { at = __now + d, fn = fn }
	end,
	NewTicker = function(d, fn) return { Cancel = noop } end,
	NewTimer = function(d, fn) __timers[#__timers + 1] = { at = __now + d, fn = fn }; return { Cancel = noop } end,
}

-- data ---------------------------------------------------------------------
__items = {
	[2589] = { "Linen Cloth", 1, 5, "", 134400, 13, 7 },
	[2770] = { "Copper Ore", 1, 1, "", 134566, 5, 7 },
	[6948] = { "Hearthstone", 1, 1, "", 134414, 0, 15 },
	[2244] = { "Krol Blade", 4, 63, "INVTYPE_WEAPONMAINHAND", 135349, 1858517, 2 },
	[10001] = { "Metal Hat", 3, 315, "INVTYPE_HEAD", 133071, 74070, 4 },
	[10002] = { "Damaged Chest", 2, 425, "INVTYPE_CHEST", 132624, 24690, 4 },
	[10003] = { "Junk Bone", 0, 1, "", 133718, 3, 15 },
	[10004] = { "Quest Thing", 1, 1, "", 134939, 0, 12 },
	-- Classic items used by the preview (/lootline test)
	[19019] = { "Thunderfury, Blessed Blade of the Windseeker", 5, 80, "INVTYPE_WEAPON", 135349, 255355, 2 },
	[17073] = { "Earthshaker", 4, 66, "INVTYPE_2HWEAPON", 133045, 113631, 2 },
	[12640] = { "Lionheart Helm", 4, 61, "INVTYPE_HEAD", 133126, 21894, 4 },
	[12784] = { "Arcanite Reaper", 3, 63, "INVTYPE_2HWEAPON", 132400, 73036, 2 },
	[13468] = { "Black Lotus", 2, 60, "", 134202, 1000, 7 },
	[14047] = { "Runecloth", 1, 50, "", 132903, 400, 7 },
	[10620] = { "Thorium Ore", 1, 40, "", 134579, 250, 7 },
	[7073] = { "Broken Fang", 0, 1, "", 133725, 6, 15 },
}
__uncached = {}

local qualityHex = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80", "ff00ccff", "ff00ccff" }

function __link(id, name)
	local d = __items[id]
	local q = d and d[2] or 1
	return string.format("|c%s|Hitem:%d::::::::80:::::|h[%s]|h|r", qualityHex[q], id, name or (d and d[1]) or "?")
end

local function itemInfo(item)
	local id
	if type(item) == "number" then id = item else id = tonumber(tostring(item):match("item:(%d+)")) end
	local d = id and __items[id]
	if not d or __uncached[id] then return nil end
	-- name, link, quality, ilvl, minLevel, type, subType, stack, equipLoc, icon, sellPrice, classID, subclassID, bindType
	return d[1], __link(id), d[2], d[3], 1, "Type", "Sub", 20, d[4], d[5], d[6], d[7], 0, d[8] or 0
end

C_Item = {
	GetItemInfo = itemInfo,
	GetItemIconByID = function(id) return __items[id] and __items[id][5] end,
	GetDetailedItemLevelInfo = function(link)
		local id = tonumber(tostring(link):match("item:(%d+)"))
		return id and __items[id] and __items[id][3]
	end,
	GetItemStats = function(link)
		local id = tonumber(tostring(link):match("item:(%d+)"))
		if id == 10001 then return { ITEM_MOD_CR_STURDINESS_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 10 } end
		if id == 10002 then return { ITEM_MOD_CR_AVOIDANCE_SHORT = 5, EMPTY_SOCKET_PRISMATIC = 1 } end
		if id == 2244 then return { ITEM_MOD_CR_LIFESTEAL_SHORT = 5 } end
		return {}
	end,
	GetItemQualityColor = function(q)
		local hex = qualityHex[q] or "ffffffff"
		return 1, 1, 1, hex
	end,
	RequestLoadItemDataByID = noop,
	GetItemCount = function(link)
		local id = tonumber(tostring(link):match("item:(%d+)"))
		return id and __bags[id] or 0
	end,
}
__bags = {}

C_CurrencyInfo = {
	GetCurrencyInfo = function(id)
		if id == 1166 then
			return { name = "Timewarped Badge", iconFileID = 1129674, quantity = 2000, maxQuantity = 0, quality = 1 }
		elseif id == 1792 then
			return { name = "Honor", iconFileID = 1455894, quantity = 15000, maxQuantity = 15000, quality = 1 }
		elseif id == 3402 then
			return { name = "Merchant's Favor", iconFileID = 135725, quantity = 12, maxQuantity = 0, quality = 1 }
		end
	end,
	GetCurrencyListSize = function() return 1 end,
	GetCurrencyListInfo = function() return { isHeader = false, currencyID = 1166, name = "Timewarped Badge" } end,
	GetCoinTextureString = function(c) return tostring(c) end,
}

C_Reputation = {
	GetNumFactions = function() return 1 end,
	GetFactionDataByIndex = function(i)
		return { name = "Iskaara Tuskarr", factionID = 2511 }
	end,
	GetFactionDataByID = function(id)
		return { factionID = id, name = "Iskaara Tuskarr", currentStanding = 3080, currentReactionThreshold = 3000, nextReactionThreshold = 6000 }
	end,
	IsMajorFaction = function() return false end,
	IsFactionParagon = function() return false end,
}
C_GossipInfo = { GetFriendshipReputation = function() return { friendshipFactionID = 0 } end }

function GetItemQualityColor(q) return C_Item.GetItemQualityColor(q) end
function UnitGUID(u) return "Player-1-00000001" end
function UnitName(u) return "Tester" end
function BreakUpLargeNumbers(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end
function IsShiftKeyDown() return __shift == true end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
__modifiers = {} -- e.g. __modifiers.AUTOLOOTTOGGLE = true while "Shift" is held
function IsModifiedClick(action) return __modifiers[action] == true end
function HandleModifiedItemClick() return false end
function PlaySoundFile(path, channel) __sounds[#__sounds + 1] = path; return true, 1 end
function PlaySound(id, channel) __sounds[#__sounds + 1] = id; return true, 1 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
format = string.format
tinsert, tremove = table.insert, table.remove
UISpecialFrames = {}
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
-- loot: __lootSlots = { { link = ..., quantity = n, money = true, locked = true, fail = ERR_..., quality = q }, ... }
function GetNumLootItems() return #(__lootSlots or {}) end
local function lootSlot(i) return __lootSlots and __lootSlots[i] end
function GetLootSlotLink(i) local s = lootSlot(i); return s and not s.looted and s.link or nil end
function GetLootSlotInfo(i)
	local s = lootSlot(i)
	if s and not s.looted then
		local q = s.quality
		if not q and s.link then local id = tonumber(s.link:match("item:(%d+)")); q = id and __items[id] and __items[id][2] end
		return 134400, "x", s.quantity, nil, q or 1, s.locked or false
	end
end
function GetLootSlotType(i)
	local s = lootSlot(i)
	if not s or s.looted then return 0 end
	return s.money and 2 or 1
end
function LootSlotHasItem(i) local s = lootSlot(i); return s ~= nil and not s.looted end
function GetLootSourceInfo(i) return __lootSource end
function IsFishingLoot() return false end
function GetLootThreshold() return 2 end
function IsInGroup() return __inGroup == true end
__lootSlotCalls, __closeLootCalls = {}, 0
-- the server answers a moment later: the slot empties (LOOT_SLOT_CLEARED + chat line) or an error
-- comes back; once everything is gone the client closes the loot by itself
function LootSlot(i)
	__lootSlotCalls[#__lootSlotCalls + 1] = i
	local s = lootSlot(i)
	if not s or s.looted or s.pending then return end
	s.pending = true
	C_Timer.After(0.05, function()
		s.pending = nil
		if s.fail then __fire("UI_ERROR_MESSAGE", 2, s.fail) return end
		s.looted = true
		__fire("LOOT_SLOT_CLEARED", i)
		if s.link then
			local msg = (s.quantity or 1) > 1 and LOOT_ITEM_SELF_MULTIPLE:format(s.link, s.quantity) or LOOT_ITEM_SELF:format(s.link)
			__fire("CHAT_MSG_LOOT", msg, "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
		end
		for _, x in ipairs(__lootSlots) do if not x.looted then return end end
		__fire("LOOT_CLOSED")
	end)
end
function CloseLoot()
	__closeLootCalls = __closeLootCalls + 1
	C_Timer.After(0, function() __fire("LOOT_CLOSED") end)
end
-- right-click on a corpse: what the client fires
function __openLoot(slots, source)
	__lootSlots, __lootSource, __lootSlotCalls = slots, source, {}
	__fire("LOOT_READY", false)
	__fire("LOOT_OPENED", false, false)
end
NUM_BAG_SLOTS = 4
__freeSlots = 16
C_Container = {
	GetContainerNumFreeSlots = function(bag) if bag == 0 then return __freeSlots, 0 end return 0, 0 end,
}
ERR_INV_FULL = "Inventory is full."
ERR_ITEM_MAX_COUNT = "You can't carry any more of those items."
ERR_LOOT_ROLL_PENDING = "That item is still being rolled for"
ERR_LOOT_CANT_LOOT_THAT = "You can't loot that item now."
ERR_LOOT_CANT_LOOT_THAT_NOW = "You can't loot that item now."
ERR_TOO_MUCH_GOLD = "At gold limit"
function GetMoney() return __money or 0 end
function InCombatLockdown() return false end
function GetBuildInfo() return "1.60.1", "12345", "Oct 1 2026", 16001 end
__tocVersion = "9.9.9" -- what the mock reports as ## Version from the .toc
C_AddOns = {
	GetAddOnMetadata = function(addon, field)
		if addon == "Lootline" and field == "Version" then return __tocVersion end
	end,
}
function issecretvalue(v) return v == __SECRET end
__SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function hooksecurefunc() end
function securecall(fn, ...) return fn(...) end
SlashCmdList = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
Item = nil -- exercise the retry fallback path

-- global strings (WoW Forever enUS) ------------------------------------------
COPPER_AMOUNT = "%d Copper"
SILVER_AMOUNT = "%d Silver"
GOLD_AMOUNT = "%d Gold"
CURRENCY_GAINED = "You receive currency: %s"
CURRENCY_GAINED_MULTIPLE = "You receive currency: %sx%d"
CURRENCY_GAINED_MULTIPLE_BONUS = "You receive currency: %sx%d (Bonus Objective)"
CURRENCY_GAINED_MULTIPLE_OVERFLOW = "You receive currency: %sx%d (You've earned the maximum amount of %s)"
LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s"
LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d"
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s"
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d"
LOOT_ITEM_REFUND = "You are refunded: %s."
LOOT_ITEM_REFUND_MULTIPLE = "You are refunded: %sx%d."
LOOT_ITEM_SELF = "You receive loot: %s"
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d"
LOOT_ITEM = "%s receives loot: %s."
LOOT_MONEY = "%s loots %s."
LOOT_MONEY_SPLIT = "Your share of the loot is %s."
LOOT_MONEY_SPLIT_GUILD = "Your share of the loot is %s. (%s deposited to guild bank)"
LOOT_MONEY_SPLIT_MOD = "Your share of the loot is %s (+%s)"
YOU_LOOT_MONEY = "You loot %s"
YOU_LOOT_MONEY_GUILD = "You loot %s (%s deposited to guild bank)"
FACTION_STANDING_INCREASED = "Your %s reputation has increased by %d."
FACTION_STANDING_INCREASED_ACH_BONUS = "Your %s reputation has increased by %d. (+%.1f bonus)"
FACTION_STANDING_INCREASED_BONUS = "Your %s reputation has increased by %d. (+%.1f Recruit A Friend bonus)"
FACTION_STANDING_INCREASED_DOUBLE_BONUS = "Your %s reputation has increased by %d. (+%.1f bonus +%.1f Recruit A Friend bonus)"
FACTION_STANDING_INCREASED_GENERIC = "Reputation with %s increased."
COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (%d Honor Points)"
COMBATLOG_HONORAWARD = "You have been awarded %d honor points."
COMBATLOG_HONORGAIN_NO_RANK = "%s dies, honorable kill (%d Honor Points)"
MONEY = "Money"
HONOR = "Honor"
REPUTATION = "Reputation"
ITEM_LEVEL_ABBR = "iLvl"
ITEM_MOD_CR_LIFESTEAL_SHORT = "Leech"
ITEM_MOD_CR_AVOIDANCE_SHORT = "Avoidance"
ITEM_MOD_CR_SPEED_SHORT = "Speed"
ITEM_MOD_CR_STURDINESS_SHORT = "Indestructible"
EMPTY_SOCKET_PRISMATIC = "Prismatic Socket"
ITEM_QUALITY_COLORS = {}
for q = 0, 8 do ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|c" .. qualityHex[q] } end
Enum = { ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Artifact = 6, Heirloom = 7, WoWToken = 8 }, ItemClass = { Questitem = 12, Weapon = 2, Armor = 4 } }
COPPER_PER_SILVER = 100
COPPER_PER_GOLD = 10000

-- record unknown global reads from here on
setmetatable(_G, {
	__index = function(t, k)
		__unknownGlobals[k] = true
		return nil
	end,
})
