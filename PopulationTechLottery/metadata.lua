return PlaceObj("ModDef", {
	"title", "Population Tech Lottery",
	"description", [[Every 20 living colonists add +1% chance (once per Sol by default) to instantly research a random technology the colony has already unlocked.

This is an optional sandbox / high-tech playstyle. A normal colony does not need it.

HOW IT WORKS
• Chance = (colonists ÷ Colonists-per-1%) × Chance-per-group
• Default: 20 colonists → 1% per Sol, 200 → 10%, 2 000 → 100% (one tech per Sol)
• Chance over 100% becomes extra rolls (capped, default 5 techs per tick)
• Default pool: discovered / unlocked techs only, Breakthroughs excluded
• Turn on "Also roll locked techs" if you want the whole tree to open over time
• Switch interval to Hour if you want a much faster all-tech run (~25×)

INSTALL
Drop this folder into:
  %AppData%\Surviving Mars Relaunched\Mods\PopulationTechLottery
Enable it in the in-game Mod Manager, then restart the game.
Options: Game Options → Mod Options → Population Tech Lottery

Safe to add to an existing save. Removing it simply stops the rolls.
Does not require other mods. Written for Surviving Mars: Relaunched 1.1.x.

CREDITS
Written by Grok (xAI). MIT License.]],
	"short_description", "Every 20 colonists add +1% chance per Sol to instantly research a random already-unlocked tech.",
	"image", "preview.jpg",
	"last_changes", "1.0.1: fix debug-mode crash on undefined global (lottery never rolled); avoid T() text in console; roll on NewHour as well as NewDay.",
	"id", "PopTechLottery",
	"author", "Grok (xAI)",
	"version_major", 1,
	"version_minor", 0,
	"version", 2,
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
		Interval = "Sol",
		UnlockLockedTechs = false,
		IncludeBreakthroughs = false,
		MaxRollsPerTick = 5,
		ShowNotifications = true,
		LogToConsole = false,
	},
})
