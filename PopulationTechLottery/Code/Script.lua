-- Population Tech Lottery
-- Surviving Mars: Relaunched
-- Every N colonists add +X% chance each Sol (or Hour) to instantly
-- research a random already-unlocked technology.
--
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
	local v = OptRaw(name)
	v = tonumber(v)
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
	if UIColony and UIColony.tech_status then
		return UIColony
	end
	if UICity then
		if UICity.colony and UICity.colony.tech_status then
			return UICity.colony
		end
		if UICity.tech_status then
			return UICity
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
		if UIColony.ForEachLabelObject then
			local n = 0
			pcall(function()
				UIColony:ForEachLabelObject("Colonist", function()
					n = n + 1
				end)
			end)
			if n > 0 then
				return n
			end
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
	if def then
		if def.group == "Breakthroughs" then
			return true
		end
		if def.field == "Breakthroughs" then
			return true
		end
	end
	if status and status.field == "Breakthroughs" then
		return true
	end
	return false
end

local function CollectCandidates(research, include_bt, include_locked)
	local list = {}
	local seen = {}

	local function consider(tech_id)
		if type(tech_id) ~= "string" or seen[tech_id] then
			return
		end
		seen[tech_id] = true
		local status = research.tech_status and research.tech_status[tech_id]
		if not status then
			return
		end
		if research.IsTechResearched and research:IsTechResearched(tech_id) then
			if not (research.IsTechRepeatable and research:IsTechRepeatable(tech_id)) then
				return
			end
		elseif status.researched then
			return
		end
		if IsBreakthrough(tech_id, status) and not include_bt then
			return
		end
		local discovered = status.discovered
		if research.IsTechDiscovered then
			discovered = research:IsTechDiscovered(tech_id)
		end
		if not discovered and not include_locked then
			return
		end
		list[#list + 1] = tech_id
	end

	if research.tech_field then
		for field_id, field_list in pairs(research.tech_field) do
			local field = TechFields and TechFields[field_id]
			local discoverable = not field or field.discoverable
			if discoverable or include_bt or include_locked then
				if type(field_list) == "table" then
					for i = 1, #field_list do
						consider(field_list[i])
					end
				end
			end
		end
	end

	if #list == 0 and research.tech_status then
		for tech_id in pairs(research.tech_status) do
			consider(tech_id)
		end
	end

	return list
end

local function TechName(tech_id)
	local def = TechDef and TechDef[tech_id]
	if def and def.display_name then
		return def.display_name
	end
	return tech_id
end

local function NotifyResearched(tech_id)
	if not OptBool("ShowNotifications", DEFAULTS.ShowNotifications) then
		return
	end
	local def = TechDef and TechDef[tech_id]
	if not def then
		return
	end
	pcall(function()
		AddOnScreenNotification("ResearchComplete", OpenResearchDialog, {
			name = def.display_name,
			context = def,
			rollover_title = def.display_name,
			rollover_text = def.description,
		})
	end)
end

local function ResearchOne(research, tech_id, include_locked)
	if include_locked and research.SetTechDiscovered then
		pcall(research.SetTechDiscovered, research, tech_id)
	end
	local ok, result = pcall(research.SetTechResearched, research, tech_id, "notify")
	if ok and result then
		return true
	end
	ok, result = pcall(research.SetTechResearched, research, tech_id)
	if ok and result then
		NotifyResearched(tech_id)
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

function PopTechLottery_TryRoll(reason)
	if not OptBool("Enabled", DEFAULTS.Enabled) then
		return
	end
	local research = GetResearch()
	if not research or not research.SetTechResearched then
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
		Log(reason, "pop", colonists, "chance", chance, "% miss")
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
			Log("no remaining candidate techs")
			break
		end
		local tech_id = candidates[Rand(research, #candidates)]
		if ResearchOne(research, tech_id, include_locked) then
			done = done + 1
			Log("researched", tech_id, TechName(tech_id))
		end
	end
	if done > 0 then
		print(MOD_TAG, "pop", colonists, "chance", string.format("%.2f", chance) .. "%", "granted", done, "tech(s) on", reason or "?")
	end
end

local function SolRoll(reason)
	local t = GameTime and GameTime() or 0
	if PopTechLottery_LastSolTime == t then
		return
	end
	PopTechLottery_LastSolTime = t
	PopTechLottery_TryRoll(reason)
end

function OnMsg.NewDay()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		return
	end
	SolRoll("sol")
end

function OnMsg.NewHour()
	if OptStr("Interval", DEFAULTS.Interval) ~= "Hour" then
		return
	end
	PopTechLottery_TryRoll("hour")
end

function OnMsg.NewSol()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		return
	end
	SolRoll("sol")
end

function OnMsg.ApplyModOptions(mod_id)
	if CurrentModId and mod_id ~= CurrentModId then
		return
	end
	Log("options applied")
end

print(MOD_TAG, "loaded")
