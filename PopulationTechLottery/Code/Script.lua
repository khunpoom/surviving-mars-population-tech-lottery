-- Population Tech Lottery
-- Surviving Mars: Relaunched 1.1.x
-- Written by Grok (xAI). MIT License.
--
-- 1.1 research is GrantTech / ResearchTech / UnlockTech / GetTechState
-- (ModTools/Src/Lua/Tech.lua and CommonLua/Libs/Research/Research.lua).
-- SetTechResearched now forwards to UIPlayer:UIResearch(id, "force").

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
}

local last_roll_time = false
local hours_this_sol = 0
local ticker_on = false
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

local function PatchLoc()
	if loc_patched then
		return
	end
	local un = G("Untranslated")
	local fn = G("AppendTTranslate")
	local tags = G("IsTagsAndPunctuation")
	if not un or type(fn) ~= "function" then
		return
	end
	loc_patched = true
	local old = fn
	rawset(_G, "AppendTTranslate", function(text, ...)
		if type(text) == "string" and (not tags or not tags(text)) then
			text = un(text)
		end
		return old(text, ...)
	end)
	Log("patched debug infobar T() asserts")
end

local function GetColonistCount()
	local overview = G("GetCityResourceOverview")
	local city = G("UICity")
	if overview and city then
		local ok, obj = pcall(overview, city)
		if ok and obj and obj.GetColonistCount then
			local ok2, n = pcall(obj.GetColonistCount, obj)
			if ok2 and type(n) == "number" then
				return n
			end
		end
	end
	local colony = G("UIColony")
	if colony and colony.labels and colony.labels.Colonist then
		return #colony.labels.Colonist
	end
	if city and city.labels and city.labels.Colonist then
		return #city.labels.Colonist
	end
	return 0
end

local function TechState(tech_id)
	local fn = G("GetTechState")
	if fn then
		local ok, state = pcall(fn, tech_id)
		if ok then
			return state
		end
	end
	local ir = G("IsTechResearched")
	if ir then
		local ok, v = pcall(ir, tech_id)
		if ok and v then
			return "researched"
		end
	end
	local iu = G("IsTechUnlocked")
	if iu then
		local ok, v = pcall(iu, tech_id)
		if ok and v then
			return "enabled"
		end
	end
	return nil
end

local function IsBreakthroughTech(tech)
	if not tech then
		return false
	end
	if tech.group == "Breakthroughs" or tech.field == "Breakthroughs" then
		return true
	end
	return false
end

local function CollectCandidates(include_bt, include_locked)
	local list = {}
	local ForEachPreset = G("ForEachPreset")
	if not ForEachPreset then
		return list
	end
	pcall(ForEachPreset, "Tech", function(tech)
		if not tech or not tech.id then
			return
		end
		if (not include_bt) and IsBreakthroughTech(tech) then
			return
		end
		local state = TechState(tech.id)
		if state == "researched" then
			return
		end
		if include_locked or state == "enabled" then
			list[#list + 1] = tech.id
		end
	end)
	return list
end

local function Grant(tech_id)
	local RT = G("ResearchTech")
	if RT then
		pcall(RT, tech_id)
	else
		local GT = G("GrantTech")
		if GT then
			pcall(GT, tech_id)
		end
	end
	return TechState(tech_id) == "researched"
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

local function Rand(n)
	if n <= 1 then
		return 1
	end
	local r
	local ir = G("InteractionRand")
	if ir then
		r = ir(n, "PopTechLottery")
	end
	local ar = G("AsyncRand")
	if not r and ar then
		r = ar(n)
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
	PatchLoc()
	if not OptBool("Enabled", DEFAULTS.Enabled) then
		Log(reason or "?", "disabled")
		return
	end
	local colonists = GetColonistCount()
	local chance = ChancePercent(colonists)
	local include_bt = OptBool("IncludeBreakthroughs", DEFAULTS.IncludeBreakthroughs)
	local include_locked = OptBool("UnlockLockedTechs", DEFAULTS.UnlockLockedTechs)
	local cands = CollectCandidates(include_bt, include_locked)
	if #cands == 0 and not include_locked then
		include_locked = true
		cands = CollectCandidates(include_bt, true)
		Log(reason or "?", "enabled pool empty, using locked techs")
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
	if remainder > 0 and Rand(10000) <= math.floor(remainder * 100 + 0.5) then
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
		cands = CollectCandidates(include_bt, include_locked)
		if #cands == 0 then
			break
		end
		local tech_id = cands[Rand(#cands)]
		if Grant(tech_id) then
			done = done + 1
			Log("researched", tech_id)
		else
			Log("grant failed", tech_id, "state", tostring(TechState(tech_id)))
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
	if ticker_on then
		return
	end
	local create = G("CreateGameTimeThread")
	local SleepFn = G("Sleep")
	if not create or not SleepFn then
		Log("no game-time thread")
		return
	end
	ticker_on = true
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
	Log("ticker started")
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

function OnMsg.LoadGame()
	hours_this_sol = 0
	last_roll_time = false
	ticker_on = false
	PatchLoc()
	StartTicker()
end

function OnMsg.NewMapLoaded()
	PatchLoc()
	StartTicker()
end

function OnMsg.InGameInterfaceCreated()
	PatchLoc()
	StartTicker()
end

function OnMsg.ClassesPostprocess()
	PatchLoc()
end

rawset(_G, "PopTechLottery_Debug", function()
	PatchLoc()
	local cands = CollectCandidates(OptBool("IncludeBreakthroughs", false), OptBool("UnlockLockedTechs", false))
	Log("debug pop", GetColonistCount(), "chance", ChancePercent(GetColonistCount()), "cands", #cands, "queue", G("UIPlayer") and "yes" or "NO")
	TryRoll("manual")
end)

PatchLoc()
Log("loaded")
