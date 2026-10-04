-- Implementation-agnostic smoke test: load, fire events, advance time, report visible bars.
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
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn.-:", ""):gsub("|r", ""):gsub("|T.-|t", "[tex]"))
end

-- every visible Button under the bar anchor = a bar; returns list of {texts, alpha, frame}
local function bars()
	local list = {}
	for _, o in ipairs(__allFrames) do
		if o.__type == "Button" and o.__parent == LootlineAnchor and o:IsVisible() then
			local texts = {}
			for _, c in ipairs(o.__children) do
				if c.__type == "FontString" and c.__shown and c.__text ~= "" then texts[#texts + 1] = strip(c.__text) end
			end
			list[#list + 1] = { text = table.concat(texts, " | "), alpha = o.__alpha, frame = o }
		end
	end
	return list
end

local function dump(label)
	local b = bars()
	print(("-- %s: %d visible bars"):format(label, #b))
	for i, x in ipairs(b) do
		local p = x.frame.__points[1]
		print(("   [%d] a=%.2f pt=%s y=%s  %s"):format(i, x.alpha, p and tostring(p[1]) or "-", p and tostring(p[5]) or "-", x.text))
	end
	return b
end

__fire("ADDON_LOADED", "Lootline")
__fire("PLAYER_LOGIN")
__fire("PLAYER_ENTERING_WORLD", true, false)
check(type(LootlineDB) == "table", "SavedVariables table created")
check(SlashCmdList.LOOTLINE ~= nil, "slash command registered")

-- loot via chat
__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(__link(2244)), "Tester", "", "", "Tester", "", 0, 0, "", 0, 1, UnitGUID("player"))
__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF_MULTIPLE:format(__link(2589), 12), "Tester", "", "", "Tester", "", 0, 0, "", 0, 2, UnitGUID("player"))
__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(__link(10001)), "Tester", "", "", "Tester", "", 0, 0, "", 0, 3, UnitGUID("player"))
__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF:format(__link(10002)), "Tester", "", "", "Tester", "", 0, 0, "", 0, 4, UnitGUID("player"))
-- someone else's loot must be ignored
__fire("CHAT_MSG_LOOT", LOOT_ITEM:format("Bob", __link(2770)), "Bob", "", "", "Bob", "", 0, 0, "", 0, 5, "Player-1-00000002")
__money = 1000000
__fire("PLAYER_ENTERING_WORLD", true, false)
__money = __money + 12345
__fire("PLAYER_MONEY")
__fire("CHAT_MSG_CURRENCY", CURRENCY_GAINED_MULTIPLE:format("|cffffffff|Hcurrency:1166:0|h[Timewarped Badge]|h|r", 40))
__fire("CHAT_MSG_COMBAT_FACTION_CHANGE", FACTION_STANDING_INCREASED:format("Iskaara Tuskarr", 80))
__tick(0.05, 20) -- 1s

local b = dump("after 1s")
check(#b >= 6, "at least 6 bars visible (got " .. #b .. ")")
local all = ""
for _, x in ipairs(b) do all = all .. "\n" .. x.text end
check(all:find("Krol Blade", 1, true) ~= nil, "epic weapon shown")
check(all:find("12x", 1, true) ~= nil, "stack count shown")
check(all:find("Indestructible", 1, true) ~= nil, "tertiary stat shown")
check(all:find("Socket", 1, true) ~= nil, "socket shown")
check(all:find("Copper Ore", 1, true) == nil, "other player's loot ignored")
check(all:find("Timewarped Badge", 1, true) ~= nil, "currency shown")
check(all:find("Iskaara Tuskarr", 1, true) ~= nil, "reputation shown")
check(all:find("Money | 1g 23s 45c", 1, true) ~= nil, "money gain shown (PLAYER_MONEY delta)")

-- loot window path + dedup with chat
__lootSlots = { { link = __link(2770), quantity = 3 } }
__fire("LOOT_READY", true)
__fire("LOOT_SLOT_CLEARED", 1)
__fire("CHAT_MSG_LOOT", LOOT_ITEM_SELF_MULTIPLE:format(__link(2770), 3), "Tester", "", "", "Tester", "", 0, 0, "", 0, 6, UnitGUID("player"))
__fire("LOOT_CLOSED")
__tick(0.05, 10)
b = dump("after loot window")
local ores = 0
for _, x in ipairs(b) do if x.text:find("Copper Ore", 1, true) then ores = ores + 1 end end
check(ores == 1, "loot window + chat produce exactly one bar (got " .. ores .. ")")

-- secret chat text must not error
__fire("CHAT_MSG_LOOT", __SECRET, "Tester")
__fire("CHAT_MSG_MONEY", __SECRET)
check(true, "secret values do not error")

-- slash commands
SlashCmdList.LOOTLINE("test")
__tick(0.05, 10)
SlashCmdList.LOOTLINE("unlock")
SlashCmdList.LOOTLINE("lock")
SlashCmdList.LOOTLINE("help")
SlashCmdList.LOOTLINE("")
check(LootlineOptions ~= nil and LootlineOptions:IsShown(), "/lootline opens the options window")
SlashCmdList.LOOTLINE("")
check(LootlineOptions ~= nil and not LootlineOptions:IsShown(), "/lootline again closes it")
check(true, "slash commands run")

-- everything expires
__tick(0.1, 700) -- 70s
b = dump("after 70s")
check(#b == 0, "all bars expire (got " .. #b .. ")")

-- report unknown API usage
local um, ug = {}, {}
for k in pairs(__unknownMethods) do um[#um + 1] = k end
for k in pairs(__unknownGlobals) do ug[#ug + 1] = k end
table.sort(um); table.sort(ug)
print("unknown widget methods used: " .. (#um > 0 and table.concat(um, ", ") or "none"))
print("unknown globals read: " .. (#ug > 0 and table.concat(ug, ", ") or "none"))
print(("RESULT: %d failure(s)"):format(failures))
