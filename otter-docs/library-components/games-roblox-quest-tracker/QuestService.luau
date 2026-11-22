--!strict
local QuestConfig = require(script.Parent.QuestConfig)

export type PlayerQuestState = {
	questId: string,
	progress: number,
	completed: boolean,
}

local QuestService = {}
local playerStates: { [number]: { [string]: PlayerQuestState } } = {}

function QuestService.AcceptQuest(userId: number, questId: string): boolean
	local def = QuestConfig[questId]
	if not def then
		return false
	end
	playerStates[userId] = playerStates[userId] or {}
	if playerStates[userId][questId] then
		return false
	end
	playerStates[userId][questId] = {
		questId = questId,
		progress = 0,
		completed = false,
	}
	return true
end

function QuestService.RecordProgress(
	userId: number,
	objectiveType: string,
	delta: number,
	onCompleted: ((userId: number, def: QuestConfig.QuestDefinition) -> ())?
): number
	if delta <= 0 then
		return 0
	end
	local active = playerStates[userId]
	if not active then
		return 0
	end
	local completedNow = 0
	for questId, state in active do
		if state.completed then
			continue
		end
		local def = QuestConfig[questId]
		if def and def.objectiveType == objectiveType then
			state.progress = math.min(def.targetCount, state.progress + delta)
			if state.progress >= def.targetCount then
				state.completed = true
				completedNow += 1
				if onCompleted then
					onCompleted(userId, def)
				end
			end
		end
	end
	return completedNow
end

function QuestService.ClearPlayer(userId: number)
	playerStates[userId] = nil
end

return QuestService
