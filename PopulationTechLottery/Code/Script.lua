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

-- File-scope locals only. Debug mode asserts on undefined globals.
local last_roll_time = false
local hours_this_sol = 0

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
	if OptBool("LogToConsole", DEFAULTS.LogToConsole) then
		print(MOD_TAG, ...)
	end
end

local function HasTechStatus(obj)
	return obj and type(obj) == "table" and obj.tech_status and obj.SetTechResearched
end

local function GetResearch()
	local colony = G("UIColony")
	local city = G("UICity")
	local main = G("MainCity")
	local list = {
		colony,
		colony and colony.research,
		city,
		city and city.colony,
		city and city.colony and city.colony.research,
		main,
		main and main.colony,
	}
	for i = 1, #list do
		if HasTechStatus(list[i]) then
			return list[i]
		end
	end
	for i = 1, #list do
		local obj = list[i]
		if obj and obj.SetTechResearched then
			return obj
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
		if colony.GetLabels then
			local ok, list = pcall(colony.GetLabels, colony, "Colonist")
			if ok and type(list) == "table" then
				return #list
			end
		end
	end
	local city = G("UICity")
	if city and city.labels and city.labels.Colonist then
		return #city.labels.Colonist
	end
	local n = 0
	local cities = G("Cities")
	if cities then
		for _, c in ipairs(cities) do
			local list = c.labels and c.labels.Colonist
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
	local ir = G("InteractionRand")
	if not r and ir then
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

local function IsBreakthrough(tech_id, status, def)
	if def and (def.group == "Breakthroughs" or def.field == "Breakthroughs") then
		return true
	end
	if status and status.field == "Breakthroughs" then
		return true
	end
	return false
end

local function IsResearched(research, tech_id, status)
	if research.IsTechResearched then
		local ok, v = pcall(research.IsTechResearched, research, tech_id)
		if ok then
			return not not v
		end
	end
	return status and not not status.researched
end

local function IsUnlocked(research, tech_id, status)
	if research.IsTechResearchable then
		local ok, v = pcall(research.IsTechResearchable, research, tech_id)
		if ok and v then
			return true
		end
	end
	if research.IsTechDiscovered then
		local ok, v = pcall(research.IsTechDiscovered, research, tech_id)
		if ok then
			return not not v
		end
	end
	return status and not not status.discovered
end

local function EachTechId(research, fn)
	local seen = {}
	local function hit(tech_id)
		if type(tech_id) == "string" and not seen[tech_id] then
			seen[tech_id] = true
			fn(tech_id)
		end
	end
	if research.tech_status then
		for tech_id in pairs(research.tech_status) do
			hit(tech_id)
		end
	end
	if research.tech_field then
		for _, field_list in pairs(research.tech_field) do
			if type(field_list) == "table" then
				for i = 1, #field_list do
					hit(field_list[i])
				end
			end
		end
	end
	local techdef = G("TechDef")
	if techdef then
		pcall(function()
			for tech_id in pairs(techdef) do
				hit(tech_id)
			end
		end)
	end
end

local function CollectCandidates(research, include_bt, include_locked)
	local list = {}
	local techdef = G("TechDef")
	EachTechId(research, function(tech_id)
		local status = research.tech_status and research.tech_status[tech_id]
		local def = techdef and techdef[tech_id]
		if IsResearched(research, tech_id, status) then
			local repeatable = false
			if research.IsTechRepeatable then
				local ok, v = pcall(research.IsTechRepeatable, research, tech_id)
				repeatable = ok and v
			end
			if not repeatable then
				return
			end
		end
		if (not include_bt) and IsBreakthrough(tech_id, status, def) then
			return
		end
		if include_locked or IsUnlocked(research, tech_id, status) then
			list[#list + 1] = tech_id
		end
	end)
	return list
end

local function ResearchOne(research, tech_id, include_locked)
	if include_locked and research.SetTechDiscovered then
		pcall(research.SetTechDiscovered, research, tech_id)
	end
	local ok, result = pcall(research.SetTechResearched, research, tech_id)
	if ok and result then
		return true
	end
	local status = research.tech_status and research.tech_status[tech_id]
	if IsResearched(research, tech_id, status) then
		return true
	end
	if ok and status then
		status.discovered = status.discovered or 1
		status.researched = status.researched or 1
		local techdef = G("TechDef")
		local def = techdef and techdef[tech_id]
		if def and def.EffectsApply then
			pcall(def.EffectsApply, def, research)
		end
		pcall(Msg, "TechResearched", tech_id, research, true)
		return true
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
	if not un then
		return
	end
	pcall(function()
		local add = G("AddCustomOnScreenNotification")
		if add then
			add("PopTechLottery", un("Population Tech Lottery"), un(text), nil)
		end
	end)
end

function PopTechLottery_TryRoll(reason)
	if not OptBool("Enabled", DEFAULTS.Enabled) then
		return
	end
	local research = GetResearch()
	if not research then
		Log("no research object, lottery cannot run")
		return
	end
	local colonists = GetColonistCount()
	if colonists < 1 then
		Log("no colonists")
		return
	end
	local chance = ChancePercent(colonists)
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
	if threshold > 0 and Rand(research, 10000) <= threshold then
		successes = successes + 1
	end
	if successes < 1 then
		Log(reason or "?", "pop", colonists, "chance", chance, "miss")
		return
	end
	local want = successes * per_success
	if want > max_techs then
		want = max_techs
	end

	local include_bt = OptBool("IncludeBreakthroughs", DEFAULTS.IncludeBreakthroughs)
	local include_locked = OptBool("UnlockLockedTechs", DEFAULTS.UnlockLockedTechs)
	local candidates = CollectCandidates(research, include_bt, include_locked)
	if #candidates == 0 and not include_locked then
		Log("unlocked pool empty, trying locked techs this tick")
		include_locked = true
		candidates = CollectCandidates(research, include_bt, true)
	end
	if #candidates == 0 then
		Log("no candidate techs remaining")
		return
	end

	local done = 0
	for _ = 1, want do
		candidates = CollectCandidates(research, include_bt, include_locked)
		if #candidates == 0 then
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
		Toast("Granted " .. tostring(done) .. " tech(s). Colonists: " .. tostring(colonists))
	else
		Log("wanted", want, "but SetTechResearched granted 0")
	end
end

local function DebouncedRoll(reason)
	local t = G("GameTime") and G("GameTime")() or 0
	local c = G("const")
	local min_gap = (c and c.MinuteDuration and (10 * c.MinuteDuration)) or 1
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
	local c = G("const")
	local hours_per_sol = (c and c.HoursPerDay) or 24
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

function PopTechLottery_Debug()
	local research = GetResearch()
	local colonists = GetColonistCount()
	local cands = research and CollectCandidates(research, OptBool("IncludeBreakthroughs", false), OptBool("UnlockLockedTechs", false)) or {}
	print(MOD_TAG, "debug pop", colonists, "chance", ChancePercent(colonists), "research", research and "yes" or "NO", "candidates", #cands)
end

print(MOD_TAG, "loaded")
