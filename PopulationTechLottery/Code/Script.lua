-- Population Tech Lottery
-- Surviving Mars: Relaunched
-- Written by Grok (xAI). MIT License.

local MOD_TAG = "[PopTechLottery]"

local DEFAULTS = {
	Enabled = true,
	ColonistsPerPercent = 20,
	ChancePerGroup = 1,
	TechsPerSuccess = 1,
	Interval = "Sol",
	IncludeBreakthroughs = false,
	UnlockLockedTechs = false,
	ShowNotifications = true,
	MaxRollsPerTick = 5,
	LogToConsole = true,
}

local last_roll_time = false
local hours_this_sol = 0
local ticker_id = false
local loc_patched = false

local function G(name)
	return rawget(_G, name)
end

local function OptRaw(name)
	local opts = G("CurrentModOptions")
	if not opts then
		return nil
	end
	if opts.GetProperty then
		local ok, v = pcall(opts.GetProperty, opts, name)
		if ok then
			return v
		end
	end
	return opts[name]
end

local function OptBool(name, default)
	local v = OptRaw(name)
	if v == nil then
		return default
	end
	if v == true or v == 1 or v == "true" or v == "True" or v == "1" then
		return true
	end
	if v == false or v == 0 or v == "false" or v == "False" or v == "0" then
		return false
	end
	return not not v
end

local function OptNum(name, default)
	local v = tonumber(OptRaw(name))
	if not v then
		return default
	end
	return v
end

local function OptStr(name, default)
	local v = OptRaw(name)
	if type(v) ~= "string" or v == "" then
		return default
	end
	return v
end

local function Log(...)
	print(MOD_TAG, ...)
end

local function PatchPlainTextLoc()
	if loc_patched then
		return
	end
	local un = G("Untranslated")
	local fn = G("AppendTTranslate")
	if not un or type(fn) ~= "function" then
		return
	end
	loc_patched = true
	local old = fn
	rawset(_G, "AppendTTranslate", function(text, ...)
		local t = type(text)
		if t == "string" or t == "number" then
			text = un(tostring(text))
		end
		return old(text, ...)
	end)
	Log("patched AppendTTranslate for debug infobar asserts")
end

local function GetColony()
	local colony = G("UIColony")
	if colony and colony.SetTechResearched then
		return colony
	end
	local city = G("UICity")
	if city then
		if city.colony and city.colony.SetTechResearched then
			return city.colony
		end
		if city.SetTechResearched then
			return city
		end
	end
	local main = G("MainCity")
	if main then
		if main.colony and main.colony.SetTechResearched then
			return main.colony
		end
		if main.SetTechResearched then
			return main
		end
	end
	return nil
end

local function GetColonistCount()
	local colony = G("UIColony")
	if colony then
		local labels = colony.labels
		if (not labels or not labels.Colonist) and colony.city_labels then
			labels = colony.city_labels.labels
		end
		if labels and labels.Colonist then
			return #labels.Colonist
		end
	end
	local n = 0
	local cities = G("Cities")
	if type(cities) == "table" then
		for _, city in ipairs(cities) do
			local list = city.labels and city.labels.Colonist
			if list then
				n = n + #list
			end
		end
	end
	local city = G("UICity")
	if n == 0 and city and city.labels and city.labels.Colonist then
		n = #city.labels.Colonist
	end
	return n
end

local function Rand(colony, n)
	if n <= 1 then
		return 1
	end
	local r
	if colony and colony.Random then
		local ok, v = pcall(colony.Random, colony, n)
		if ok and type(v) == "number" then
			r = v
		end
	end
	local ir = G("InteractionRand")
	if not r and ir then
		r = ir(n, "PopTechLottery")
	end
	r = r or 0
	if r < 1 then
		return r + 1
	end
	if r > n then
		return (r % n) + 1
	end
	return r
end

local function IsBreakthrough(tech_id, status)
	local td = G("TechDef")
	local def = td and td[tech_id]
	if def and (def.group == "Breakthroughs" or def.field == "Breakthroughs") then
		return true
	end
	if status and status.field == "Breakthroughs" then
		return true
	end
	return false
end

local function EachTechId(colony, fn)
	local seen = {}
	local function hit(tech_id)
		if type(tech_id) == "string" and tech_id ~= "" and not seen[tech_id] then
			seen[tech_id] = true
			fn(tech_id)
		end
	end
	if colony.tech_status then
		pcall(function()
			for tech_id in pairs(colony.tech_status) do
				hit(tech_id)
			end
		end)
	end
	if colony.tech_field then
		pcall(function()
			for _, field_list in pairs(colony.tech_field) do
				if type(field_list) == "table" then
					for i = 1, #field_list do
						hit(field_list[i])
					end
				end
			end
		end)
	end
	local ForEachPreset = G("ForEachPreset")
	if ForEachPreset then
		pcall(ForEachPreset, "TechPreset", function(preset)
			if preset and preset.id then
				hit(preset.id)
			end
		end)
	end
end

local function CollectCandidates(colony, include_bt, include_locked)
	local list = {}
	EachTechId(colony, function(tech_id)
		local status = colony.tech_status and colony.tech_status[tech_id]
		local researched = false
		if colony.IsTechResearched then
			local ok, v = pcall(colony.IsTechResearched, colony, tech_id)
			researched = ok and v
		elseif status then
			researched = not not status.researched
		end
		if researched then
			return
		end
		if (not include_bt) and IsBreakthrough(tech_id, status) then
			return
		end
		local unlocked = false
		if colony.IsTechDiscovered then
			local ok, v = pcall(colony.IsTechDiscovered, colony, tech_id)
			unlocked = ok and v
		elseif colony.IsTechResearchable then
			local ok, v = pcall(colony.IsTechResearchable, colony, tech_id)
			unlocked = ok and v
		elseif status then
			unlocked = not not status.discovered
		end
		if include_locked or unlocked then
			list[#list + 1] = tech_id
		end
	end)
	return list
end

local function ResearchOne(colony, tech_id)
	if colony.SetTechDiscovered then
		pcall(colony.SetTechDiscovered, colony, tech_id)
	end
	local ok, result = pcall(colony.SetTechResearched, colony, tech_id)
	if not ok then
		Log("SetTechResearched error", tech_id, tostring(result))
		return false
	end
	if result then
		return true
	end
	if colony.IsTechResearched then
		local ok2, v = pcall(colony.IsTechResearched, colony, tech_id)
		if ok2 and v then
			return true
		end
	end
	return false
end

local function ChancePercent(colonists)
	local per = OptNum("ColonistsPerPercent", DEFAULTS.ColonistsPerPercent)
	local add = OptNum("ChancePerGroup", DEFAULTS.ChancePerGroup)
	if per < 1 then
		per = 1
	end
	if add < 0 then
		add = 0
	end
	return (colonists / per) * add
end

local function Toast(text)
	if not OptBool("ShowNotifications", DEFAULTS.ShowNotifications) then
		return
	end
	local un = G("Untranslated")
	local add = G("AddCustomOnScreenNotification")
	if un and add then
		pcall(add, "PopTechLottery", un("Population Tech Lottery"), un(text), nil)
	end
end

local function TryRoll(reason)
	PatchPlainTextLoc()
	if not OptBool("Enabled", DEFAULTS.Enabled) then
		Log(reason or "?", "disabled")
		return
	end
	local colony = GetColony()
	if not colony then
		Log(reason or "?", "NO colony/research object")
		return
	end
	local colonists = GetColonistCount()
	local chance = ChancePercent(colonists)
	local include_bt = OptBool("IncludeBreakthroughs", DEFAULTS.IncludeBreakthroughs)
	local include_locked = OptBool("UnlockLockedTechs", DEFAULTS.UnlockLockedTechs)
	local cands = CollectCandidates(colony, include_bt, include_locked)
	if #cands == 0 and not include_locked then
		include_locked = true
		cands = CollectCandidates(colony, include_bt, true)
		Log(reason or "?", "unlocked pool empty, using locked techs")
	end
	Log(reason or "?", "pop", colonists, "chance", chance, "cands", #cands)

	if colonists < 1 then
		return
	end
	local per_success = math.floor(OptNum("TechsPerSuccess", DEFAULTS.TechsPerSuccess) + 0.5)
	if per_success < 1 then
		per_success = 1
	end
	local max_techs = math.floor(OptNum("MaxRollsPerTick", DEFAULTS.MaxRollsPerTick) + 0.5)
	if max_techs < 1 then
		max_techs = 1
	end
	local guaranteed = math.floor(chance / 100)
	local remainder = chance - guaranteed * 100
	local successes = guaranteed
	local threshold = math.floor(remainder * 100 + 0.5)
	if threshold > 0 and Rand(colony, 10000) <= threshold then
		successes = successes + 1
	end
	if successes < 1 then
		Log(reason or "?", "miss")
		return
	end
	local want = successes * per_success
	if want > max_techs then
		want = max_techs
	end
	if #cands == 0 then
		Log(reason or "?", "no candidate techs")
		return
	end

	local done = 0
	for _ = 1, want do
		cands = CollectCandidates(colony, include_bt, include_locked)
		if #cands == 0 then
			break
		end
		local tech_id = cands[Rand(colony, #cands)]
		if ResearchOne(colony, tech_id) then
			done = done + 1
			Log("researched", tech_id)
		end
	end
	if done > 0 then
		Log("granted", done, "on", reason or "?")
		Toast("Granted " .. tostring(done) .. " tech(s). Pop " .. tostring(colonists))
	else
		Log("wanted", want, "granted 0")
	end
end

rawset(_G, "PopTechLottery_TryRoll", TryRoll)

local function Debounced(reason)
	local gt = G("GameTime")
	local t = gt and gt() or 0
	local c = G("const")
	local min_gap = (c and c.MinuteDuration and (5 * c.MinuteDuration)) or 1
	if last_roll_time and (t - last_roll_time) < min_gap then
		return
	end
	last_roll_time = t
	TryRoll(reason)
end

local function HourWait()
	local c = G("const")
	if c and c.HourDuration then
		return c.HourDuration
	end
	return 60000
end

local function StartTicker()
	if ticker_id then
		return
	end
	local create = G("CreateGameTimeThread")
	local SleepFn = G("Sleep")
	if not create or not SleepFn then
		Log("no CreateGameTimeThread, falling back to NewHour only")
		return
	end
	ticker_id = true
	create(function()
		SleepFn(HourWait())
		TryRoll("boot")
		while true do
			SleepFn(HourWait())
			if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
				TryRoll("hour-thread")
			else
				hours_this_sol = hours_this_sol + 1
				local c = G("const")
				local need = (c and c.HoursPerDay) or 24
				if hours_this_sol >= need then
					hours_this_sol = 0
					Debounced("sol-thread")
				end
			end
		end
	end)
	Log("game-time ticker started")
end

function OnMsg.NewHour()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		TryRoll("hour-msg")
		return
	end
	hours_this_sol = hours_this_sol + 1
	local c = G("const")
	local need = (c and c.HoursPerDay) or 24
	if hours_this_sol >= need then
		hours_this_sol = 0
		Debounced("sol-msg")
	end
end

function OnMsg.NewDay()
	if OptStr("Interval", DEFAULTS.Interval) ~= "Hour" then
		hours_this_sol = 0
		Debounced("sol-day")
	end
end

function OnMsg.NewSol()
	if OptStr("Interval", DEFAULTS.Interval) ~= "Hour" then
		hours_this_sol = 0
		Debounced("sol-sol")
	end
end

function OnMsg.LoadGame()
	hours_this_sol = 0
	last_roll_time = false
	ticker_id = false
	PatchPlainTextLoc()
	StartTicker()
end

function OnMsg.NewMapLoaded()
	PatchPlainTextLoc()
	StartTicker()
end

function OnMsg.InGameInterfaceCreated()
	PatchPlainTextLoc()
	StartTicker()
end

function OnMsg.ClassesPostprocess()
	PatchPlainTextLoc()
end

rawset(_G, "PopTechLottery_Debug", function()
	PatchPlainTextLoc()
	local colony = GetColony()
	local colonists = GetColonistCount()
	local cands = colony and CollectCandidates(colony, OptBool("IncludeBreakthroughs", false), OptBool("UnlockLockedTechs", false)) or {}
	Log("debug pop", colonists, "chance", ChancePercent(colonists), "colony", colony and "yes" or "NO", "cands", #cands)
	TryRoll("manual")
end)

PatchPlainTextLoc()
Log("loaded")
