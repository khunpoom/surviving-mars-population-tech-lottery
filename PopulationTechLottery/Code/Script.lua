-- Population Tech Lottery
-- Surviving Mars: Relaunched 1.1.x
-- Written by Grok (xAI). MIT License.
--
-- 1.1 research is GrantTech / ResearchTech / UnlockTech / GetTechState
-- (ModTools/Src/Lua/Tech.lua and CommonLua/Libs/Research/Research.lua).

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
	return tech.group == "Breakthroughs" or tech.field == "Breakthroughs"
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

local function TechDisplayName(tech_id)
	local Techs = G("Techs")
	local tech = Techs and Techs[tech_id]
	if not tech then
		return tech_id
	end
	local t = tech.DisplayName or tech.display_name
	local eng = G("TDevModeGetEnglishText")
	if eng and t then
		local ok, s = pcall(eng, t, false, true)
		if ok and type(s) == "string" and s ~= "" and s ~= "DisplayName" then
			return s
		end
	end
	local tr = G("_InternalTranslate")
	if tr and t then
		local ok, s = pcall(tr, t)
		if ok and type(s) == "string" and s ~= "" then
			return s
		end
	end
	return tech_id
end

local function Toast(tech_ids)
	if not OptBool("ShowNotifications", DEFAULTS.ShowNotifications) then
		return
	end
	tech_ids = tech_ids or {}
	if #tech_ids == 0 then
		return
	end
	local names = {}
	for i = 1, #tech_ids do
		names[#names + 1] = TechDisplayName(tech_ids[i])
	end
	local un = G("Untranslated")
	local add = G("AddNotification")
	if not un or not add then
		return
	end
	pcall(add, "StoryBit", {
		Title = un("Population Tech Lottery"),
		Text = un(table.concat(names, "\n")),
		Dismissable = true,
		CloseOnRead = true,
		Expiration = 60000,
		Image = "UI/IconsRemaster/Notifications/research.png",
		PressAction = "dismiss",
	})
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
	local granted_ids = {}
	for _ = 1, want do
		cands = CollectCandidates(include_bt, include_locked)
		if #cands == 0 then
			break
		end
		local tech_id = cands[Rand(#cands)]
		if Grant(tech_id) then
			done = done + 1
			granted_ids[#granted_ids + 1] = tech_id
			Log("researched", tech_id)
		else
			Log("grant failed", tech_id, "state", tostring(TechState(tech_id)))
		end
	end
	if done > 0 then
		Log("granted", done, "on", reason or "?")
		Toast(granted_ids)
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

function OnMsg.NewHour()
	if OptStr("Interval", DEFAULTS.Interval) == "Hour" then
		Debounced("hour")
	end
end

function OnMsg.NewDay()
	if OptStr("Interval", DEFAULTS.Interval) ~= "Hour" then
		Debounced("sol")
	end
end

function OnMsg.LoadGame()
	last_roll_time = false
	PatchLoc()
end

function OnMsg.NewMapLoaded()
	PatchLoc()
end

function OnMsg.InGameInterfaceCreated()
	PatchLoc()
end

function OnMsg.ClassesPostprocess()
	PatchLoc()
end

rawset(_G, "PopTechLottery_Debug", function()
	PatchLoc()
	local cands = CollectCandidates(OptBool("IncludeBreakthroughs", false), OptBool("UnlockLockedTechs", false))
	Log("debug pop", GetColonistCount(), "chance", ChancePercent(GetColonistCount()), "cands", #cands)
	TryRoll("manual")
end)

PatchLoc()
Log("loaded")
