--!nolint
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local CollisionManager = {}

CollisionManager.NPC_GROUP = "NonCollidableNPCs"
CollisionManager.PLAYER_GROUP = "Players"

-- A helper function to safely register and configure collision groups.
local function registerAndConfigureGroup(groupName, collidesWith)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	for otherGroup, doesCollide in pairs(collidesWith) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(groupName, otherGroup, doesCollide)
		end)
	end
end

-- Initial setup for the main collision groups
registerAndConfigureGroup(CollisionManager.NPC_GROUP, {
	[CollisionManager.PLAYER_GROUP] = false,
	["Default"] = true,
})

registerAndConfigureGroup(CollisionManager.PLAYER_GROUP, {
	[CollisionManager.PLAYER_GROUP] = true,
	["Default"] = true,
})

function CollisionManager.setupPlayerBaseCollisions(player, base)
	if not player or not base then return end

	local playerCharacter = player.Character
	if not playerCharacter then return end

	local barrierPart = base:FindFirstChild("Barriers", true) and base.Barriers:FindFirstChild("Main", true) and base.Barriers.Main:FindFirstChild("MainBarrier")
	if not barrierPart then
		warn("Could not find MainBarrier for base:", base.Name)
		return
	end

	local ownerGroupName = "Owner_" .. player.UserId
	local barrierGroupName = "Barrier_" .. player.UserId

	registerAndConfigureGroup(ownerGroupName, {})
	registerAndConfigureGroup(barrierGroupName, {})

	PhysicsService:CollisionGroupSetCollidable(ownerGroupName, barrierGroupName, false)
	PhysicsService:CollisionGroupSetCollidable(ownerGroupName, CollisionManager.NPC_GROUP, false)
	PhysicsService:CollisionGroupSetCollidable(CollisionManager.PLAYER_GROUP, barrierGroupName, true)
	PhysicsService:CollisionGroupSetCollidable("Default", barrierGroupName, true)

	for _, part in ipairs(playerCharacter:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = ownerGroupName
		end
	end

	barrierPart.CollisionGroup = barrierGroupName
end

function CollisionManager.cleanupPlayerBaseCollisions(player)
	if not player then return end

	local ownerGroupName = "Owner_" .. player.UserId
	local barrierGroupName = "Barrier_" .. player.UserId

	pcall(function()
		PhysicsService:UnregisterCollisionGroup(ownerGroupName)
		PhysicsService:UnregisterCollisionGroup(barrierGroupName)
	end)
end

function CollisionManager.setNpcCollisionGroup(npcRig)
	for _, part in ipairs(npcRig:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				part.CollisionGroup = CollisionManager.NPC_GROUP
			end)
		end
	end
end

function CollisionManager.setPlayerToDefaultGroup(player)
	local character = player.Character
	if character then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function()
					part.CollisionGroup = CollisionManager.PLAYER_GROUP
				end)
			end
		end
	end
end

-- Handle existing and new players
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.1) -- Wait for character parts to be fully loaded
		CollisionManager.setPlayerToDefaultGroup(player)
	end)
	if player.Character then
		CollisionManager.setPlayerToDefaultGroup(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	CollisionManager.setPlayerToDefaultGroup(player)
end

return CollisionManager