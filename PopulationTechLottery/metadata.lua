return PlaceObj("ModDef", {
	"title", "Population Tech Lottery",
	"description", [[Every 20 living colonists add +1% chance (once per Sol by default) to instantly research a random technology.

Written against Surviving Mars: Relaunched 1.1 ModTools APIs:
GrantTech / ResearchTech / UnlockTech / GetTechState.

After load, the first roll happens in about 1 in-game Hour.
Look for [PopTechLottery] lines in the debug log.

CREDITS
Written by Grok (xAI). MIT License.]],
	"short_description", "Every 20 colonists add +1% chance per Sol to instantly research a random tech.",
	"image", "preview.jpg",
	"last_changes", "1.0.4: use Relaunched 1.1 ResearchTech/UnlockTech/GetTechState (ModTools). First roll ~1 Hour after load.",
	"id", "PopTechLottery",
	"author", "Grok (xAI)",
	"version_major", 1,
	"version_minor", 0,
	"version", 5,
	"lua_revision", 350453,
	"saved_with_revision", 403908,
	"optional_mod", true,
	"TagGameplay", true,
	"code", {
		"Code/Script.lua",
	},
	"default_options", {
		Enabled = true,
		ColonistsPerPercent = 20,
		ChancePerGroup = 1,
		TechsPerSuccess = 1,
		Interval = "Sol",
		UnlockLockedTechs = false,
		IncludeBreakthroughs = false,
		MaxRollsPerTick = 5,
		ShowNotifications = true,
		LogToConsole = true,
	},
})
