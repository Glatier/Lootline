-- Settings saved by 1.2/1.3 (version 2): values still at the old defaults take the new defaults,
-- money moves from gold to copper, the TradeSkillMaster setting goes away.
local failures = 0
local function check(cond, msg)
	if not cond then
		failures = failures + 1
		print("FAIL: " .. msg)
	else
		print("ok   " .. msg)
	end
end

LootlineDB = {
	version = 2,
	point = { "LEFT", "TOP", -200, -364 },
	width = 400,
	grow = "center",
	thresholds = { 20, 200, 1000 },
	minValue = 1.5,
	tsmSource = "DBMarket",
	spacing = 8,
	blacklist = { ["item:1"] = "keep me" },
}
__fire("ADDON_LOADED", "Lootline")
local db = LootlineDB
check(db.version == 3, "version 3")
check(db.point[1] == "CENTER" and db.point[2] == "CENTER" and db.point[3] == -400 and db.point[4] == 95, "old default position -> new default")
check(db.width == 350 and db.grow == "down", "old default width / grow -> 350 / down")
check(db.thresholds[1] == 10000 and db.thresholds[2] == 50000 and db.thresholds[3] == 100000, "old default tiers -> 1g / 5g / 10g")
check(db.minValue == 15000, "1.5 gold -> 15000 copper (got " .. tostring(db.minValue) .. ")")
check(db.tsmSource == nil, "TSM setting removed")
check(db.spacing == 8 and db.blacklist["item:1"] == "keep me", "other settings and the ignore list kept")
print(("RESULT: %d failure(s)"):format(failures))
