return PlaceObj("ModDef", {
	"title", "Population Tech Lottery",
	"description", [[Every 20 living colonists add +1% chance (once per Sol by default) to instantly research a random technology the colony has already unlocked.

This is an optional sandbox / high-tech playstyle. A normal colony does not need it.

HOW IT WORKS
• Chance = (colonists ÷ Colonists-per-1%) × Chance-per-group
• Default: 20 colonists → 1% per Sol, 2000 → 100%
• Techs-per-success controls how many techs each success grants
• Turn on Also roll locked techs for the all-tech playstyle

After load, the first roll happens in about 1 in-game Hour so you can confirm it works.
Look for [PopTechLottery] lines in the debug log.

CREDITS
Written by Grok (xAI). MIT License.]],
	"short_description", "Every 20 colonists add +1% chance per Sol to instantly research a random already-unlocked tech.",
	"image", "preview.jpg",
	"last_changes", "1.0.3: silence vanilla debug infobar 'v' assert; independent game-time ticker; first roll ~1 Hour after load so you can see it work.",
	"id", "PopTechLottery",
	"author", "Grok (xAI)",
	"version_major", 1,
	"version_minor", 0,
	"version", 4,
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
