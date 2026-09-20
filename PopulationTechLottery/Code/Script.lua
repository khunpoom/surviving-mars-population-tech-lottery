-- Population Tech Lottery
-- Surviving Mars: Relaunched
-- Written by Grok (xAI). MIT License.

local MOD_TAG = "[PopTechLottery]"

local DEFAULTS = {
	Enabled = true,
	ColonistsPerPercent = 20,
	ChancePerGroup = 1,
	Interval = "Sol",
	IncludeBreakthroughs = false,
	UnlockLockedTechs = false,
	ShowNotifications = true,
	MaxRollsPerTick = 5,
	LogToConsole = false,
}

-- File-scope locals only. Debug/dev mode asserts on undefined globals.
local last_roll_time = false
local hours_this_sol = 0

local function OptRaw(name)
	local opts = CurrentModOptions
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
	if OptBool("LogToConsole", DEFAULTS.LogToConsole) then
		print(MOD_TAG, ...)
	end
end

local function GetResearch()
	local objs = {
		UIColony,
		UIColony and UIColony.research,
		MainCity,
		UICity,
		UICity and UICity.colony,
		UICity and UICity.colony and UICity.colony.research,
	}
	for i = 1, #objs do
		local obj = objs[i]
		if obj and obj.tech_status and obj.SetTechResearched then
			return obj
		end
	end
	return nil
end

local function GetColonistCount()
	if UIColony then
		local labels = UIColony.labels
		if (not labels or not labels.Colonist) and UIColony.city_labels then
			labels = UIColony.city_labels.labels
		end
		if labels and labels.Colonist then
			return #labels.Colonist
		end
	end
	if UICity and UICity.labels and UICity.labels.Colonist then
		return #UICity.labels.Colonist
	end
	local n = 0
	if Cities then
		for _, city in ipairs(Cities) do
			local list = city.labels and city.labels.Colonist
			if list then
				n = n + #list
			end
		end
	end
	return n
end

local function Rand(research, n)
	if n <= 1 then
		return 1
	end
	local r
	if research and research.Random then
		local ok, v = pcall(research.Random, research, n)
		if ok and type(v) == "number" then
			r = v
		end
	end
	if not r and InteractionRand then
		r = InteractionRand(n, "PopTechLottery")
	end
	if not r and AsyncRand then
		r = AsyncRand(n)
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
	local def = TechDef and TechDef[tech_id]
	if def and (def.group == "Breakthroughs" or def.field == "Breakthroughs") then
		return true
	end
	if status and status.field == "Breakthroughs" then
		return true
	end
	return false
end

local function CollectCandidates(research, include_bt, include_locked)
	local list = {}
	if not research or not research.tech_status then
		return list
	end
	for tech_id, status in pairs(research.tech_status) do
		if type(tech_id) == "string" and status then
			local researched = status.researched
			if research.IsTechResearched then
				researched = research:IsTechResearched(tech_id)
			end
			local repeatable = false
			if researched and research.IsTechRepeatable then
				repeatable = research:IsTechRepeatable(tech_id)
			end
			if (not researched or repeatable) and (include_bt or not IsBreakthrough(tech_id, status)) then
				local unlocked = status.discovered
				if research.IsTechResearchable then
					unlocked = research:IsTechResearchable(tech_id)
				elseif research.IsTechDiscovered then
					unlocked = research:IsTechDiscovered(tech_id)
				end
				if unlocked or include_locked then
					list[#list + 1] = tech_id
				end
			end
		end
	end
	return list
end

local function ResearchOne(research, tech_id, include_locked)
	if include_locked and research.SetTechDiscovered then
		pcall(research.SetTechDiscovered, research, tech_id)
	end
	local ok, result = pcall(research.SetTechResearched, research, tech_id)
	return ok and result and true or false
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

function PopTechLottery_TryRoll(reason)
	if not OptBool("Enabled", DEFAULTS.Enabled) then
		return
	end
	local research = GetResearch()
	if not research then
		Log("no research object")
		return
	end
	local colonists = GetColonistCount()
	if colonists < 1 then
		return
	end
	local chance = ChancePercent(colonists)
	local max_rolls = math.floor(OptNum("MaxRollsPerTick", DEFAULTS.MaxRollsPerTick) + 0.5)
	if max_rolls < 1 then
		max_rolls = 1
	end
	local guaranteed = math.floor(chance / 100)
	local remainder = chance - guaranteed * 100
	local rolls = guaranteed
	local threshold = math.floor(remainder * 100 + 0.5)
	if threshold > 0 and Rand(research, 10000) <= threshold then
		rolls = rolls + 1
	end
	if rolls < 1 then
		Log(reason or "?", "pop", colonists, "chance", chance, "miss")
		return
	end
	if rolls > max_rolls then
		rolls = max_rolls
	end

	local include_bt = OptBool("IncludeBreakthroughs", DEFAULTS.IncludeBreakthroughs)
	local include_locked = OptBool("UnlockLockedTechs", DEFAULTS.UnlockLockedTechs)
	local done = 0
	for _ = 1, rolls do
		local candidates = CollectCandidates(research, include_bt, include_locked)
		if #candidates == 0 then
			Log("no candidate techs remaining")
			break
		end
		local tech_id = candidates[Rand(research, #candidates)]
		if ResearchOne(research, tech_id, include_locked) then
			done = done + 1
			Log("researched", tech_id)
		end
	end
	if done > 0 then
		print(MOD_TAG, "pop", colonists, "granted", done, "on", reason or "?")
	end
end

local function DebouncedRoll(reason)
	local t = GameTime and GameTime() or 0
	local min_gap = (const and const.MinuteDuration and (10 * const.MinuteDuration)) or 1
	if last_roll_time and (t - last_roll_time) < min_gap then
		return
	end
	last_roll_time = t
	PopTechLottery_TryRoll(reason)
end

function OnMsg.NewHour()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		PopTechLottery_TryRoll("hour")
		return
	end
	hours_this_sol = hours_this_sol + 1
	local hours_per_sol = (const and const.HoursPerDay) or 24
	if hours_this_sol >= hours_per_sol then
		hours_this_sol = 0
		DebouncedRoll("sol")
	end
end

function OnMsg.NewDay()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		return
	end
	hours_this_sol = 0
	DebouncedRoll("sol")
end

function OnMsg.NewSol()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		return
	end
	hours_this_sol = 0
	DebouncedRoll("sol")
end

function OnMsg.LoadGame()
	hours_this_sol = 0
	last_roll_time = false
end

print(MOD_TAG, "loaded")
