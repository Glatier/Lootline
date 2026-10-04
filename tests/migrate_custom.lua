-- Settings saved by 1.2/1.3 (version 2) that the player changed are kept; gold amounts become copper.
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
	point = { "CENTER", "CENTER", 450, -120 },
	width = 380,
	grow = "up",
	thresholds = { 5, 50.5, 500 },
	minValue = 0,
	blacklist = {},
}
__fire("ADDON_LOADED", "Lootline")
local db = LootlineDB
check(db.point[3] == 450 and db.point[4] == -120, "moved position kept")
check(db.width == 380 and db.grow == "up", "chosen width / grow kept")
check(db.thresholds[1] == 50000 and db.thresholds[2] == 505000 and db.thresholds[3] == 5000000,
	"chosen tiers converted to copper (5g / 50g 50s / 500g)")
check(db.minValue == 0, "value filter still off")
local p = LootlineAnchor.__points[1]
check(p and p[1] == "CENTER" and p[4] == 450 and p[5] == -120, "bars placed at the saved position")
print(("RESULT: %d failure(s)"):format(failures))
