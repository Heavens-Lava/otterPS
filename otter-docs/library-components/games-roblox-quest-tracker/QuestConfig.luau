--!strict
export type QuestReward = {
	xp: number,
	gold: number,
}

export type QuestDefinition = {
	id: string,
	title: string,
	objectiveType: string,
	targetCount: number,
	reward: QuestReward,
}

local Quests: { [string]: QuestDefinition } = {
	slime_hunt = {
		id = "slime_hunt",
		title = "Clear the Meadow",
		objectiveType = "defeat_slime",
		targetCount = 5,
		reward = { xp = 120, gold = 50 },
	},
	herb_gather = {
		id = "herb_gather",
		title = "Alchemist's Request",
		objectiveType = "collect_herb",
		targetCount = 3,
		reward = { xp = 80, gold = 35 },
	},
}

return table.freeze(Quests)
