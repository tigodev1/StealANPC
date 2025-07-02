local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MainFolder = ReplicatedStorage:WaitForChild("MainFolder")
local ModulesFolder = MainFolder:WaitForChild("Modules")
local CollisionManager = require(ModulesFolder:WaitForChild("CollisionManager"))
local NPCManager = require(ModulesFolder:WaitForChild("NPCManager"))

local CONFIG = {
	LASER_TRANSPARENCY_LOCKED = 0.3,
	LASER_TRANSPARENCY_UNLOCKED = 1,
}

local remotes = MainFolder:WaitForChild("Remotes")
local baseAssignedRemote = remotes:WaitForChild("BaseAssigned")
local lockBaseRemote = remotes:WaitForChild("LockBase")

local playerConnections = {}

local function EnsureInstanceValue(folder, valueType, name, defaultValue)
	local value = folder:FindFirstChild(name)
	if not value then
		value = Instance.new(valueType)
		value.Name = name
		value.Parent = folder
		if defaultValue ~= nil then
			value.Value = defaultValue
		end
	end
	return value
end

local function RetrieveBases()
	local basesFolder = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Bases")
	if not basesFolder then return {} end

	local bases = {}
	for _, base in ipairs(basesFolder:GetChildren()) do
		if base:IsA("Folder") and base.Name:match("^Base%d+") then
			table.insert(bases, base)
		end
	end
	return bases
end

local function FindPlayerOwnedBase(player)
	for _, base in ipairs(RetrieveBases()) do
		local importantFolder = base:FindFirstChild("Important")
		if importantFolder then
			local owner = importantFolder:FindFirstChild("Owner")
			local isOwned = importantFolder:FindFirstChild("Owned")
			if owner and isOwned and isOwned.Value and owner.Value == player.Name then
				return base
			end
		end
	end
	return nil
end

local function TeleportPlayerToBaseSpawn(player, base)
	local spawnFolder = base:FindFirstChild("Spawn")
	if spawnFolder then
		local spawnPoint = spawnFolder:FindFirstChild("SpawnPoint")
		if spawnPoint and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			player.Character.HumanoidRootPart.CFrame = spawnPoint.CFrame + Vector3.new(0, 3, 0)
		end
	end
end

local function UpdateBaseSignage(base, player)
	local signsFolder = base:WaitForChild("Signs")
	local signsPartFolder = signsFolder:WaitForChild("SignsPart")
	local nameBase = signsPartFolder:WaitForChild("PlayerNameBase")
	local surfaceGui = nameBase:WaitForChild("SurfaceGui")
	local textLabel = surfaceGui:WaitForChild("TextLabel")
	local thumbnailLabel = surfaceGui:WaitForChild("Thumbnail")

	if textLabel then
		textLabel.Text = (player.DisplayName or player.Name) .. "'s Base"
	end

	if thumbnailLabel and thumbnailLabel:IsA("ImageLabel") then
		local content, isReady = Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.AvatarThumbnail, Enum.ThumbnailSize.Size420x420)
		if isReady then
			thumbnailLabel.Image = content
		end
	end
	surfaceGui.Enabled = true
end

local function UpdateBarrierState(base, isLocked)
	local mainBarrier = base:FindFirstChild("Barriers", true) and base.Barriers:FindFirstChild("Main", true) and base.Barriers.Main:FindFirstChild("MainBarrier")
	if not mainBarrier then return end

	mainBarrier.CanCollide = isLocked

	local lazersFolder = base:FindFirstChild("Barriers", true) and base.Barriers.Main:FindFirstChild("Lazers")
	if not lazersFolder then return end

	for _, part in ipairs(lazersFolder:GetChildren()) do
		if part:IsA("BasePart") and part.Name == "Laser" then
			part.Transparency = isLocked and CONFIG.LASER_TRANSPARENCY_LOCKED or CONFIG.LASER_TRANSPARENCY_UNLOCKED
		end
	end
end

local function ResetBaseSignage(base)
	local signsFolder = base:FindFirstChild("Signs", true)
	if not signsFolder then return end

	local signsPartFolder = signsFolder:FindFirstChild("SignsPart", true)
	if not signsPartFolder then return end

	local nameBase = signsPartFolder:FindFirstChild("PlayerNameBase", true)
	if not nameBase then return end

	local surfaceGui = nameBase:FindFirstChild("SurfaceGui", true)
	if not surfaceGui then return end

	surfaceGui.Enabled = false

	local textLabel = surfaceGui:FindFirstChild("TextLabel")
	if textLabel then
		textLabel.Text = "No-one's Base"
	end

	local thumbnailLabel = surfaceGui:FindFirstChild("Thumbnail")
	if thumbnailLabel then
		thumbnailLabel.Image = ""
	end
end

local function ConfigureBaseLockMechanism(base, player)
	local lockPart = base:WaitForChild("Platforms", true):WaitForChild("Lock")
	local textFrame = lockPart:WaitForChild("TextHolder", true):WaitForChild("TextFrame")

	local lockTextLabel = textFrame:WaitForChild("LockText")
	local timerLabel = textFrame:WaitForChild("Timer")

	local importantFolder = base:FindFirstChild("Important")
	importantFolder.Name = "Important"
	local lockStatus = EnsureInstanceValue(importantFolder, "BoolValue", "LockStatus", true)
	local timerValue = EnsureInstanceValue(importantFolder, "StringValue", "Timer", "20")

	local connectionsForPlayer = {
		timer = nil,
		touch = nil,
		remote = nil
	}
	playerConnections[player.UserId] = connectionsForPlayer

	local function StartUnlockTimer()
		if connectionsForPlayer.timer and connectionsForPlayer.timer.Connected then
			connectionsForPlayer.timer:Disconnect()
		end

		local timeRemaining = tonumber(timerValue.Value) or 20
		connectionsForPlayer.timer = RunService.Heartbeat:Connect(function(deltaTime)
			timeRemaining = timeRemaining - deltaTime
			local timeText = tostring(math.ceil(timeRemaining))
			timerValue.Value = timeText
			timerLabel.Text = timeText
			if timeRemaining <= 0 then
				if connectionsForPlayer.timer and connectionsForPlayer.timer.Connected then
					connectionsForPlayer.timer:Disconnect()
				end
				lockStatus.Value = false
				timerValue.Value = "0"
				lockTextLabel.Text = "Lock base"
				timerLabel.Visible = false
				UpdateBarrierState(base, false)
			end
		end)
	end

	local function activateLock()
		if not lockStatus.Value then
			lockStatus.Value = true
			timerValue.Value = "20"
			lockTextLabel.Text = "Unlocks in:"
			timerLabel.Visible = true
			timerLabel.Text = timerValue.Value
			UpdateBarrierState(base, true)
			StartUnlockTimer()
		end
	end

	connectionsForPlayer.touch = lockPart.Touched:Connect(function(touchedPart)
		local character = touchedPart.Parent
		local touchingPlayer = Players:GetPlayerFromCharacter(character)
		if touchingPlayer and touchingPlayer == player then
			activateLock()
		end
	end)

	connectionsForPlayer.remote = lockBaseRemote.OnServerEvent:Connect(function(requestingPlayer)
		if requestingPlayer == player then
			activateLock()
		end
	end)

	activateLock()
end

local function AssignBaseToPlayer(player)
	if FindPlayerOwnedBase(player) then return end

	for _, base in ipairs(RetrieveBases()) do
		local importantFolder = base:FindFirstChild("Important")
		importantFolder.Name = "Important"
		local ownerValue = EnsureInstanceValue(importantFolder, "StringValue", "Owner", "N/A")
		local isOwnedValue = EnsureInstanceValue(importantFolder, "BoolValue", "Owned", false)

		if not isOwnedValue.Value then
			ownerValue.Value = player.Name
			isOwnedValue.Value = true

			UpdateBaseSignage(base, player)
			CollisionManager.setupPlayerBaseCollisions(player, base)
			ConfigureBaseLockMechanism(base, player)
			baseAssignedRemote:FireClient(player, base.Name)
			TeleportPlayerToBaseSpawn(player, base)
			return
		end
	end
end

local function ReleasePlayerBase(player)
	local base = FindPlayerOwnedBase(player)
	if not base then return end

	local connections = playerConnections[player.UserId]
	if connections then
		for _, conn in pairs(connections) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		playerConnections[player.UserId] = nil
	end

	local importantFolder = base:FindFirstChild("Important")
	if importantFolder then
		EnsureInstanceValue(importantFolder, "StringValue", "Owner", "N/A").Value = "N/A"
		EnsureInstanceValue(importantFolder, "BoolValue", "Owned", false).Value = false
		EnsureInstanceValue(importantFolder, "BoolValue", "LockStatus", false).Value = false
		EnsureInstanceValue(importantFolder, "StringValue", "Timer", "0").Value = "0"
		UpdateBarrierState(base, false)
		CollisionManager.cleanupPlayerBaseCollisions(player)
	end

	ResetBaseSignage(base)

	local standsFolder = base:FindFirstChild("Stands")
	if standsFolder then
		for _, stand in ipairs(standsFolder:GetChildren()) do
			local placeHolder = stand:FindFirstChild("PlaceHolder")
			if placeHolder then
				local npcPlatform = placeHolder:FindFirstChild("NPCPlatform")
				if npcPlatform then
					for _, npc in ipairs(npcPlatform:GetChildren()) do
						if npc:IsA("Model") then
							npc:Destroy()
						end
					end
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid").WalkSpeed = 28

		local base = FindPlayerOwnedBase(player)
		if base then
			TeleportPlayerToBaseSpawn(player, base)
			UpdateBaseSignage(base, player)
			CollisionManager.setupPlayerBaseCollisions(player, base)
			ConfigureBaseLockMechanism(base, player)
		else
			AssignBaseToPlayer(player)
		end
	end)
	if player.Character then
		player.Character:WaitForChild("Humanoid").WalkSpeed = 28
		local base = FindPlayerOwnedBase(player)
		if base then
			TeleportPlayerToBaseSpawn(player, base)
			UpdateBaseSignage(base, player)
			CollisionManager.setupPlayerBaseCollisions(player, base)
			ConfigureBaseLockMechanism(base, player)
		else
			AssignBaseToPlayer(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ReleasePlayerBase(player)
end)