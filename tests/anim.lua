-- Animation / layout / glow behaviour tests against the WeakAura spec.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. msg)
	else
		print("ok   " .. msg)
	end
end
local function near(a, b, eps) return a and b and math.abs(a - b) <= (eps or 0.01) end

local function strip(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "[tex]"):gsub("|A.-|a", "[atlas]"))
end

-- rows = visible Buttons parented to the anchor
local function rows()
	local list = {}
	for _, o in ipairs(__allFrames) do
		if o.__type == "Button" and o.__parent == LootlineAnchor and o.__shown then
			local p = o.__points[1]
			local left, right = "", ""
			-- first two OVERLAY fontstrings created are left/right texts
			local fs = {}
			for _, c in ipairs(o.__children) do if c.__type == "FontString" then fs[#fs + 1] = c end end
			list[#list + 1] = {
				frame = o, alpha = o.__alpha, x = p and p[4], y = p and p[5],
				left = strip(fs[1] and fs[1].__text), right = strip(fs[2] and fs[2].__text),
			}
		end
	end
	table.sort(list, function(a, b) return (a.y or 0) < (b.y or 0) end) -- bottom first
	return list
end
local function find(text)
	for _, r in ipairs(rows()) do
		if r.left:find(text, 1, true) then return r end
	end
end
local function dump(label)
	local r = rows()
	print(("-- %s: %d rows"):format(label, #r))
	for i, x in ipairs(r) do
		print(("   [%d] a=%.2f x=%.1f y=%.1f  %s  ||  %s"):format(i, x.alpha, x.x or -1, x.y or -1, x.left:gsub("\n", " / "), x.right:gsub("\n", " / ")))
	end
end
local function glowFrame(row)
	return row._LootlinePixelGlow
end
local function chatLoot(id, n)
	if n and n > 1 then
		__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF_MULTIPLE:format(__link(id), n), "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
	else
		__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(__link(id)), "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
	end
end

__fire("ADDON_LOADED", "Lootline")
__money = 5000000
__fire("PLAYER_ENTERING_WORLD", true, false)
local db = LootlineDB
check(db.width == 350 and db.grow == "down" and db.point[1] == "CENTER" and db.point[3] == -400 and db.point[4] == 95,
	"Lootline defaults: 350 wide, grows down, centre -400 / 95")
check(db.thresholds[1] == 10000 and db.thresholds[2] == 50000 and db.thresholds[3] == 100000, "default glow tiers 1g / 5g / 10g")
-- the rest of this file checks the WeakAura's behaviour, so use its layout and thresholds
SlashCmdList.LOOTLINE("width 400")
SlashCmdList.LOOTLINE("grow center")
SlashCmdList.LOOTLINE("threshold 20 200 1000")
check(db.showItemLevel == false, "item level under gear is off by default")
SlashCmdList.LOOTLINE("ilvl")
check(db.width == 400 and db.rowHeight == 40 and db.spacing == 5, "WA geometry 400x40, spacing 5")
check(db.grow == "center" and db.thresholds[1] == 200000 and db.thresholds[3] == 10000000, "centred stack, WA tiers (copper)")

-- 1. slide-in: immediately alpha 0 at +50px, linear to alpha 1 at 0px over 0.25s
chatLoot(2244) -- epic, vendor 185g -> tier 1 glow (>= 20g)
local r = find("Krol Blade")
check(r ~= nil, "epic item bar created")
check(r and near(r.alpha, 0) and near(r.x, 50), "starts at alpha 0, x +50 (got a=" .. tostring(r and r.alpha) .. " x=" .. tostring(r and r.x) .. ")")
check(r and near(r.y, 0), "single bar centred on anchor (y=0)")
__tick(0.125)
r = find("Krol Blade")
check(r and near(r.alpha, 0.5, 0.02) and near(r.x, 25, 1), "halfway: alpha 0.5, x 25 (got a=" .. tostring(r and r.alpha) .. " x=" .. tostring(r and r.x) .. ")")
__tick(0.15)
r = find("Krol Blade")
check(r and near(r.alpha, 1) and near(r.x, 0), "finished: alpha 1, x 0")
local g = glowFrame(r.frame)
check(g and g.__shown, "expensive item has a pixel glow")
check(g and #g.lines == 40, "glow uses 20 lines (40 textures incl. corner pieces)")
check(g and g.info.period == 20 and g.info.th == 0.55 and g.info.length == 20, "glow params: 20s/lap, thickness 0.55, length 20")
local c = g and g.lines[1].__vertex
check(c and near(c[1], 0.95) and near(c[2], 0.95) and near(c[3], 0.32), "tier 1 glow colour = LibCustomGlow default")

-- 2. second bar: stack re-centres, existing bar glides 0.2s; sort by prio (common below epic)
chatLoot(2589, 12) -- common
__tick(0.001)
local sword, cloth = find("Krol Blade"), find("Linen Cloth")
check(cloth and sword and cloth.y < sword.y, "common item sorted below epic (prio = quality)")
check(cloth and near(cloth.y, -22.5, 0.6), "new common bar placed directly in its slot (-22.5)")
check(sword and sword.y > 0 and sword.y < 22.5, "epic bar is gliding up (y=" .. tostring(sword and sword.y) .. ")")
__tick(0.1)
sword = find("Krol Blade")
check(sword and near(sword.y, 11.25, 1), "glide is linear: halfway at 0.1s (y=" .. tostring(sword and sword.y) .. ")")
__tick(0.11)
sword = find("Krol Blade")
check(sword and near(sword.y, 22.5), "glide finished at 0.2s (y=22.5)")
cloth = find("Linen Cloth")
check(cloth and cloth.left == "12x Linen Cloth", "count prefix '12x ' (got '" .. tostring(cloth and cloth.left) .. "')")
check(cloth and cloth.right == "13c \n1s 56c ", "unit price then stack total (got '" .. tostring(cloth and cloth.right) .. "')")
check(not (glowFrame(cloth.frame) and glowFrame(cloth.frame).__shown), "cheap item has no glow")

-- 3. money (prio -1) at the bottom, rep (prio 10) at the top, currency (9) below rep
__money = __money + 2000000 -- 200g -> tier 2
__fire("PLAYER_MONEY")
__fire("CHAT_MSG_CURRENCY", CURRENCY_GAINED_MULTIPLE:format("|cffffffff|Hcurrency:1166:0|h[Timewarped Badge]|h|r", 40))
__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", FACTION_STANDING_INCREASED:format("Iskaara Tuskarr", 80))
__tick(0.05, 12)
dump("five bars")
local rs = rows()
check(#rs == 5, "5 bars")
check(rs[1].left:find("Money", 1, true), "money is the bottom bar")
check(rs[5].left:find("Iskaara Tuskarr Rep", 1, true), "rep is the top bar")
check(rs[4].left:find("Timewarped Badge", 1, true), "currency just below rep")
check(near(rs[1].y, -90) and near(rs[5].y, 90), "5 bars centred: y from -90 to +90 step 45")
local money = find("Money")
check(money and money.right == "200g  0s  0c ", "money format '200g  0s  0c ' (got '" .. tostring(money and money.right) .. "')")
local mg = glowFrame(money.frame)
check(mg and mg.__shown and near(mg.lines[1].__vertex[2], 0.6), "200g money glows tier 2 (orange)")
local badge = find("Timewarped Badge")
check(badge and badge.left == "40x Timewarped Badge (2000)", "currency text (got '" .. tostring(badge and badge.left) .. "')")
local rep = find("Iskaara Tuskarr")
check(rep and rep.left == "+80 Iskaara Tuskarr Rep (80 / 3000)", "rep text (got '" .. tostring(rep and rep.left) .. "')")

-- 4. merge: same item again -> count adds up, no slide-in replay, timer restarts
local before = find("Linen Cloth")
chatLoot(2589, 3)
__tick(0.001)
cloth = find("Linen Cloth")
check(cloth and cloth.left == "15x Linen Cloth", "merged count 15x")
check(cloth and near(cloth.alpha, 1) and near(cloth.x, 0), "merge does not replay the slide-in")
check(#rows() == 5, "merge adds no bar")

-- 5. expiry: common lasts 5s; slide out to -50 over 0.25s keeping its slot, then others glide
-- poor 3 / common 5 / uncommon 10 / rare 15 / epic 20 / money 5 / rep 15 / currency 15
__tick(0.1, 49) -- ~4.9s after the merge
cloth = find("Linen Cloth")
check(cloth and near(cloth.alpha, 1), "still fully visible before its duration ends (no early fade)")
__tick(0.1, 2) -- past 5s
cloth = find("Linen Cloth")
check(cloth and cloth.alpha < 1 and cloth.x < 0, "exit animation started: sliding left and fading (a=" .. tostring(cloth and cloth.alpha) .. " x=" .. tostring(cloth and cloth.x) .. ")")
local clothY = cloth and cloth.y
__tick(0.05, 2)
cloth = find("Linen Cloth")
check(cloth == nil or near(cloth.y, clothY), "keeps its slot while leaving")
__tick(0.05, 4)
check(find("Linen Cloth") == nil, "gone after the 0.25s exit")
__tick(0.1, 3)
check(#rows() == 3, "money (5s) left too; 3 bars remain")

-- 6. row limit: 10 shown, the rest wait hidden (highest prio = top ones hidden)
SlashCmdList.LOOTLINE("clear")
for i = 1, 12 do
	__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", FACTION_STANDING_INCREASED:format("Faction" .. i, 10))
end
__tick(0.05, 6)
check(#rows() == 10, "only 10 bars shown (got " .. #rows() .. ")")
check(find("Faction12") == nil and find("Faction11") == nil, "newest equal-prio entries are the hidden ones (top of stack)")

-- 7. recycled rows drop their glow
SlashCmdList.LOOTLINE("clear")
chatLoot(2244)
__tick(0.05, 6)
local swordFrame = find("Krol Blade").frame
SlashCmdList.LOOTLINE("clear")
chatLoot(10003) -- poor junk, 3c
__tick(0.05, 6)
local junk = find("Junk Bone")
check(junk ~= nil, "junk bar shown")
local jg = junk and glowFrame(junk.frame)
check(not (jg and jg.__shown), "recycled row has no leftover glow")

-- 8. gear line and socket formatting
SlashCmdList.LOOTLINE("clear")
chatLoot(10002)
__tick(0.05, 6)
local chest = find("Damaged Chest")
check(chest and chest.left:find("ilvl: 425  Avoidance  [tex]Socket", 1, true), "gear line WA format (got '" .. tostring(chest and chest.left) .. "')")

-- 8b. bag count " (N)" appears once the bags update (polled every 0.2s)
SlashCmdList.LOOTLINE("clear")
__bags[2770] = 5
chatLoot(2770, 2)
__tick(0.01)
local ore = find("Copper Ore")
check(ore and ore.left == "2x Copper Ore (5) ", "bag count shown (got '" .. tostring(ore and ore.left) .. "')")
__bags[2770] = 7
__tick(0.05, 5)
ore = find("Copper Ore")
check(ore and ore.left == "2x Copper Ore (7) ", "bag count refreshed by polling (got '" .. tostring(ore and ore.left) .. "')")
SlashCmdList.LOOTLINE("clear")
chatLoot(10002)
__tick(0.05, 6)

-- 9. right-click dismiss plays the exit animation
local row = find("Damaged Chest").frame
row.__scripts.OnClick(row, "RightButton")
__tick(0.1)
local ch = find("Damaged Chest")
check(ch and ch.alpha < 1 and ch.x < 0, "right-click starts the slide-out")
__tick(0.1, 3)
check(find("Damaged Chest") == nil, "dismissed bar removed")

-- 10. /lb test works and uses every bar type
SlashCmdList.LOOTLINE("test")
__tick(0.05, 6)
dump("preview")
check(#rows() == 10, "preview shows 10 bars (got " .. #rows() .. ")")

local um, ug = {}, {}
for k in pairs(__unknownMethods) do um[#um + 1] = k end
for k in pairs(__unknownGlobals) do ug[#ug + 1] = k end
table.sort(um); table.sort(ug)
print("unknown widget methods used: " .. (#um > 0 and table.concat(um, ", ") or "none"))
print("unknown globals read: " .. (#ug > 0 and table.concat(ug, ", ") or "none"))
print(("RESULT: %d failure(s)"):format(failures))
