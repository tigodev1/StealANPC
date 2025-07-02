local NPCManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local PathfindingService = game:GetService("PathfindingService")
local ContentProvider = game:GetService("ContentProvider")

local mainFolder = ReplicatedStorage:WaitForChild("MainFolder")
local modulesFolder = mainFolder:WaitForChild("Modules")
local CollisionManager = require(modulesFolder:WaitForChild("CollisionManager"))
local Raritys = require(modulesFolder:WaitForChild("Raritys"))
local rigsFolder = mainFolder:WaitForChild("Rigs")
local configFolder = mainFolder:WaitForChild("Config")
local rarityColoursFolder = mainFolder:WaitForChild("RarityColours")
local importantAssets = ServerScriptService:WaitForChild("MainHandler"):WaitForChild("Important")
local walkingOnPart = Workspace:WaitForChild("WalkingOn")

local rankGui = importantAssets:WaitForChild("Rank")
local actionButton = importantAssets:WaitForChild("ActionButton")
local startPart = Workspace:WaitForChild("Start")
local finishPoint = Workspace:WaitForChild("FinishPoint")

local spawnInterval = configFolder.SpawnInterval.Value
local walkSpeed = configFolder.WalkSpeed.Value
local maxNPCs = configFolder.MaxNPCs.Value

local startCollectionForStand, cleanupCollectionForStand, getBaseOwnedByPlayer, formatNumber, getProfileCache

local npcTemplateFolder = mainFolder:FindFirstChild("NPCTemplates") or Instance.new("Folder")
npcTemplateFolder.Name = "NPCTemplates"
npcTemplateFolder.Parent = mainFolder

local _rigsByRarity = {}
local npcComponentCache = {}
local activeNPCsCount = 0
local preloaded = false
local walkingToBaseFolder

local function preloadNpcTemplates()
	if preloaded then return end
	for _, rigFolder in ipairs(rigsFolder:GetChildren()) do
		if rigFolder:IsA("Folder") then
			local template = rigFolder:Clone()
			template.Parent = npcTemplateFolder
		end
	end
	preloaded = true
end

local function createPlatformNpc(npcName)
	local trimmedName = npcName:gsub("^%s*(.-)%s*$", "%1")
	local template = npcTemplateFolder:FindFirstChild(trimmedName)
	if not template then
		return nil
	end

	local clonedCharacterFolder = template:Clone()
	clonedCharacterFolder.Name = trimmedName
	local rig = clonedCharacterFolder:FindFirstChild("Rig")
	local charImportant = clonedCharacterFolder:FindFirstChild("Important")
	local humanoid = rig and (rig:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid", rig))
	if humanoid then humanoid.Name = "Humanoid" end

	npcComponentCache[clonedCharacterFolder] = { Rig = rig, Humanoid = humanoid, Important = charImportant }
	return clonedCharacterFolder
end

local function createNpcFromPool(npcName)
	local trimmedName = npcName:gsub("^%s*(.-)%s*$", "%1")
	local template = npcTemplateFolder:FindFirstChild(trimmedName)
	if not template then
		return nil
	end

	activeNPCsCount += 1
	local newNpc = template:Clone()
	newNpc.Name = trimmedName

	local rig = newNpc:FindFirstChild("Rig")
	local charImportant = newNpc:FindFirstChild("Important")
	local humanoid = rig and (rig:FindFirstChildOfClass("Humanoid") or Instance.new("Humanoid", rig))
	if humanoid then humanoid.Name = "Humanoid" end

	npcComponentCache[newNpc] = { Rig = rig, Humanoid = humanoid, Important = charImportant }
	return newNpc
end

local function destroyPooledNpc(npcFolder)
	if not npcFolder then return end
	npcComponentCache[npcFolder] = nil
	npcFolder:Destroy()
	activeNPCsCount = math.max(0, activeNPCsCount - 1)
end

local function followPath(humanoid, destination, contextFolder, onFinished)
	task.spawn(function()
		local rig = humanoid.Parent
		if not (rig and rig.Parent) then return end

		local path = PathfindingService:CreatePath({ AgentRadius = 3, AgentHeight = 6, AgentCanJump = false })
		local success, err = pcall(function()
			path:ComputeAsync(humanoid.RootPart.Position, destination)
		end)

		if not success or path.Status ~= Enum.PathStatus.Success then
			if onFinished then onFinished(false) end
			return
		end

		local waypoints = path:GetWaypoints()
		if #waypoints < 2 then
			if onFinished then onFinished(true) end
			return
		end

		local blockedConn
		local function cleanup()
			if blockedConn then
				blockedConn:Disconnect()
				blockedConn = nil
			end
		end

		blockedConn = path.Blocked:Connect(function()
			cleanup()
			followPath(humanoid, destination, contextFolder, onFinished)
		end)

		for i = 2, #waypoints do
			if not (humanoid.Parent and humanoid.Parent.Parent and humanoid.Parent.Parent.Parent == contextFolder) then
				cleanup()
				return
			end
			humanoid:MoveTo(waypoints[i].Position)
			if humanoid.MoveToFinished:Wait() == false then
				cleanup()
				followPath(humanoid, destination, contextFolder, onFinished)
				return
			end
		end
		cleanup()
		if onFinished then onFinished(true) end
	end)
end

local function setupNPC(npcFolder)
	local components = npcComponentCache[npcFolder]
	if not components then return nil end

	local rigModel, humanoid, important = components.Rig, components.Humanoid, components.Important
	local walkAnim = important:FindFirstChild("Walk")

	if not (walkAnim and walkAnim:IsA("Animation")) then
		destroyPooledNpc(npcFolder)
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	humanoid.AutoRotate = true
	humanoid.WalkSpeed = walkSpeed
	if rigModel.PrimaryPart then rigModel.PrimaryPart.Anchored = false end

	local walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack:Play(0.1)
	CollisionManager.setNpcCollisionGroup(rigModel)
	return humanoid
end

local function setupClonedNPC(npcFolder)
	local components = npcComponentCache[npcFolder]
	if not components then return nil end

	local rigModel, humanoid, important = components.Rig, components.Humanoid, components.Important
	local rootPart = rigModel:FindFirstChild("HumanoidRootPart")
	local idleAnim = important:FindFirstChild("Idle")

	if not (rootPart and idleAnim and idleAnim:IsA("Animation")) then
		npcFolder:Destroy()
		return nil
	end

	rootPart.Anchored = true
	humanoid.AutoRotate = false
	CollisionManager.setNpcCollisionGroup(rigModel)

	task.defer(function()
		if not rigModel.Parent then return end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
		animator:LoadAnimation(idleAnim):Play(0.1)
	end)
	return humanoid
end

local function addOverheadGuiToStandNPC(player, npcRig, characterImportantFolder, standModel)
	local head = npcRig:FindFirstChild("Head")
	local torso = npcRig:FindFirstChild("Torso")
	if not (head and torso) then return end

	local guiClone = rankGui:Clone()
	local nameLabel = guiClone:WaitForChild("Name")
	local rarityLabel = guiClone:WaitForChild("Rarity")
	local perSecLabel = guiClone:WaitForChild("PerSec")
	local priceLabel = guiClone:WaitForChild("Price")
	local nameValue = characterImportantFolder:FindFirstChild("Name")
	local rarityValue = characterImportantFolder:FindFirstChild("Rarity")
	local perSecValue = characterImportantFolder:FindFirstChild("PerSec")
	local priceValue = characterImportantFolder:FindFirstChild("Price")

	if nameValue then nameLabel.Text = nameValue.Value end

	if rarityValue then
		rarityLabel.Text = rarityValue.Value
		local gradient = rarityColoursFolder:FindFirstChild(rarityValue.Value)
		if gradient and gradient:IsA("UIGradient") then gradient:Clone().Parent = rarityLabel end
	end

	if perSecValue then perSecLabel.Text = perSecValue.Value .. "$/s" end

	if priceValue then
		local price = tonumber(priceValue.Value)
		if price then
			priceLabel.Text = formatNumber(price) .. "$"
			local sellPrompt = actionButton:Clone()
			sellPrompt.ActionText = "Sell"
			sellPrompt.ObjectText = (nameValue and nameValue.Value or "NPC") .. " - " .. formatNumber(price * 0.5) .. "$"
			sellPrompt.Parent = torso
			sellPrompt.Triggered:Once(function(triggeringPlayer)
				if triggeringPlayer.UserId == player.UserId then
					NPCManager.removeNPCOnStand(player, standModel)
				end
			end)
		end
	end
	guiClone.Parent = head
end

function NPCManager.addPurchaseGuiToWalkingNPC(npcFolder)
	local components = npcComponentCache[npcFolder]
	if not components then return end

	local npc, charImportant = components.Rig, components.Important
	local torso, head = npc:FindFirstChild("Torso"), npc:FindFirstChild("Head")
	if not (torso and head) then return end

	local guiClone = rankGui:Clone()
	local nameLabel = guiClone:WaitForChild("Name")
	local rarityLabel = guiClone:WaitForChild("Rarity")
	local perSecLabel = guiClone:WaitForChild("PerSec")
	local priceLabel = guiClone:WaitForChild("Price")
	local nameValue = charImportant:FindFirstChild("Name")
	local rarityValue = charImportant:FindFirstChild("Rarity")
	local perSecValue = charImportant:FindFirstChild("PerSec")
	local priceValue = charImportant:FindFirstChild("Price")

	if nameValue then nameLabel.Text = nameValue.Value end

	if rarityValue then
		rarityLabel.Text = rarityValue.Value
		local gradient = rarityColoursFolder:FindFirstChild(rarityValue.Value)
		if gradient and gradient:IsA("UIGradient") then gradient:Clone().Parent = rarityLabel end
	end

	if perSecValue then perSecLabel.Text = perSecValue.Value .. "$/s" end

	if priceValue then
		local price = tonumber(priceValue.Value)
		if price then
			priceLabel.Text = formatNumber(price) .. "$"
			local prompt = actionButton:Clone()
			prompt.ActionText = "Buy"
			prompt.ObjectText = (nameValue and nameValue.Value or "NPC") .. " - " .. formatNumber(price) .. "$"
			prompt.Parent = torso
			prompt.Triggered:Connect(function(player)
				NPCManager.purchaseAndPlaceNPC(player, npcFolder)
			end)
		end
	end
	guiClone.Parent = head
end

function NPCManager.removeNPCOnStand(player, standModel)
	if not (player and standModel) then return end
	cleanupCollectionForStand(standModel)

	local placeholder = standModel:FindFirstChild("PlaceHolder")
	if placeholder then
		local npcPlatform = placeholder:FindFirstChild("NPCPlatform")
		if npcPlatform then
			for _, npcFolder in ipairs(npcPlatform:GetChildren()) do
				npcComponentCache[npcFolder] = nil
				npcFolder:Destroy()
			end
		end
	end

	local importantFolder = standModel:FindFirstChild("Important")
	if importantFolder then
		local profile = getProfileCache()[player]
		local standNum = string.match(standModel.Name, "%d+")
		if profile and standNum and profile.Data.OwnedNPCs and profile.Data.OwnedNPCs[standNum] then
			profile.Data.Cash += (tonumber(profile.Data.OwnedNPCs[standNum].Price) or 0) * 0.5
			if player.leaderstats.Cash then player.leaderstats.Cash.Value = profile.Data.Cash end
			profile.Data.OwnedNPCs[standNum] = nil
		end
		importantFolder.Equipped.Value = false
		importantFolder.NPCName.Value = ""
	end
end

function NPCManager.setNPCOnStand(player, standModel, npcName, initialAmount)
	NPCManager.removeNPCOnStand(player, standModel)

	local npcFolder = createPlatformNpc(npcName)
	if not npcFolder then return end

	local components = npcComponentCache[npcFolder]
	if not components then npcFolder:Destroy() return end

	local rig = components.Rig
	local newHumanoid = setupClonedNPC(npcFolder)

	if newHumanoid then
		local targetPlaceHolder = standModel:FindFirstChild("PlaceHolder")
		if targetPlaceHolder then
			local npcPlatformFolder = targetPlaceHolder:FindFirstChild("NPCPlatform") or Instance.new("Folder", targetPlaceHolder)
			npcPlatformFolder.Name = "NPCPlatform"

			local rootPart = rig:FindFirstChild("HumanoidRootPart")
			if not rootPart then npcFolder:Destroy() return end

			npcFolder.Parent = Workspace
			rig.PrimaryPart = rootPart

			local _, modelSize = rig:GetBoundingBox()
			local modelBottomY = rig.PrimaryPart.Position.Y - (modelSize.Y / 2)
			local pivotToBottomOffset = rootPart.Position.Y - modelBottomY
			local platformTopPosition = targetPlaceHolder.Position + Vector3.new(0, targetPlaceHolder.Size.Y / 2, 0)
			local targetPivotPosition = platformTopPosition + Vector3.new(0, pivotToBottomOffset, 0)

			local rotationCFrame
			if standModel:GetPivot().Position.X < 0 then
				rotationCFrame = CFrame.Angles(0, math.rad(-90), 0)
			else
				rotationCFrame = CFrame.Angles(0, math.rad(90), 0)
			end

			local finalCFrame = CFrame.new(targetPivotPosition) * rotationCFrame
			rig:SetPrimaryPartCFrame(finalCFrame)
			npcFolder.Parent = npcPlatformFolder

			local standImportant = standModel:FindFirstChild("Important")
			if standImportant then
				standImportant.Equipped.Value = true
				standImportant.NPCName.Value = npcFolder.Name
			end

			local profile = getProfileCache()[player]
			local standNum = string.match(standModel.Name, "%d+")
			if profile and standNum then
				local important = components.Important
				profile.Data.OwnedNPCs = profile.Data.OwnedNPCs or {}
				profile.Data.OwnedNPCs[standNum] = {
					NPCType = npcFolder.Name,
					CollectedAmount = initialAmount or 0,
					PerSec = tonumber(important.PerSec.Value) or 0,
					LastUpdate = os.time(),
					OfflineCap = tonumber(important.OfflineCap.Value) or math.huge,
					Price = tonumber(important.Price.Value) or 0
				}
			end

			addOverheadGuiToStandNPC(player, rig, components.Important, standModel)
			startCollectionForStand(player, standModel, rig, components.Important, initialAmount or 0)
		else
			npcFolder:Destroy()
		end
	end
end

function NPCManager.purchaseAndPlaceNPC(purchasingPlayer, walkingNpcFolder)
	if walkingNpcFolder:GetAttribute("IsBeingPurchased") then return end
	walkingNpcFolder:SetAttribute("IsBeingPurchased", true)

	local profile = getProfileCache()[purchasingPlayer]
	local components = npcComponentCache[walkingNpcFolder]
	if not components then walkingNpcFolder:SetAttribute("IsBeingPurchased", nil) return end

	local charImportant = components.Important
	local price = tonumber(charImportant and charImportant:FindFirstChild("Price") and charImportant.Price.Value)

	if not (profile and price and profile.Data.Cash >= price) then
		walkingNpcFolder:SetAttribute("IsBeingPurchased", nil)
		return
	end

	local base = getBaseOwnedByPlayer(purchasingPlayer)
	if not base then walkingNpcFolder:SetAttribute("IsBeingPurchased", nil) return end

	local openStand
	local platforms = base:WaitForChild("Platforms"):GetChildren()
	table.sort(platforms, function(a, b) return a.Name < b.Name end)
	for _, stand in ipairs(platforms) do
		local important = stand:FindFirstChild("Important")
		if stand:IsA("Model") and important and not important.Equipped.Value and stand:GetAttribute("ReservedFor") == nil then
			openStand = stand
			break
		end
	end

	if not openStand then walkingNpcFolder:SetAttribute("IsBeingPurchased", nil) return end

	local rig = components.Rig
	local prompt = rig and rig:FindFirstChild("Torso") and rig.Torso:FindFirstChild("ActionButton")
	if prompt then prompt.Enabled = false end
	openStand:SetAttribute("ReservedFor", walkingNpcFolder.Name)

	profile.Data.Cash -= price
	if purchasingPlayer.leaderstats.Cash then purchasingPlayer.leaderstats.Cash.Value = profile.Data.Cash end
	walkingNpcFolder.Parent = walkingToBaseFolder

	local currentHumanoid = setupNPC(walkingNpcFolder)
	if not currentHumanoid then
		openStand:SetAttribute("ReservedFor", nil)
		if prompt then prompt.Enabled = true end
		profile.Data.Cash += price
		if purchasingPlayer.leaderstats.Cash then purchasingPlayer.leaderstats.Cash.Value = profile.Data.Cash end
		destroyPooledNpc(walkingNpcFolder)
		return
	end

	if prompt then prompt:Destroy() end
	local destination = base:WaitForChild("Signs"):WaitForChild("CollectZone").Position

	followPath(currentHumanoid, destination, walkingToBaseFolder, function(reached)
		openStand:SetAttribute("ReservedFor", nil)
		if reached then
			local npcTypeName = walkingNpcFolder.Name
			NPCManager.setNPCOnStand(purchasingPlayer, openStand, npcTypeName, 0)
			destroyPooledNpc(walkingNpcFolder)
		else
			profile.Data.Cash += price
			if purchasingPlayer.leaderstats.Cash then purchasingPlayer.leaderstats.Cash.Value = profile.Data.Cash end
			destroyPooledNpc(walkingNpcFolder)
		end
	end)
end

function NPCManager.spawnSpecificNPC(npcName)
	if activeNPCsCount >= maxNPCs then return end

	local npcFolder = createNpcFromPool(npcName)
	if not npcFolder then return end

	local components = npcComponentCache[npcFolder]
	if not components then destroyPooledNpc(npcFolder) return end

	local npc = components.Rig
	local humanoid = setupNPC(npcFolder)
	if not humanoid then return end

	npc:PivotTo(CFrame.lookAt(startPart.Position + Vector3.new(0, 5, 0), finishPoint.Position))
	npcFolder.Parent = walkingOnPart:WaitForChild("ActiveNPCs")
	if npc.PrimaryPart then npc.PrimaryPart:SetNetworkOwner(nil) end
	NPCManager.addPurchaseGuiToWalkingNPC(npcFolder)

	followPath(humanoid, finishPoint.Position, npcFolder.Parent, function(reached)
		destroyPooledNpc(npcFolder)
	end)
end

function NPCManager.spawnRandomNPC()
	if activeNPCsCount >= maxNPCs then return end
	local selectedRarity = Raritys.GetRandomRarity(_rigsByRarity)
	if not selectedRarity then return end
	local validRigs = _rigsByRarity[selectedRarity]
	if validRigs and #validRigs > 0 then
		local randomRigName = validRigs[math.random(#validRigs)]
		NPCManager.spawnSpecificNPC(randomRigName)
	end
end

function NPCManager.init(dependencies)
	startCollectionForStand = dependencies.startCollectionForStand
	cleanupCollectionForStand = dependencies.cleanupCollectionForStand
	getBaseOwnedByPlayer = dependencies.getBaseOwnedByPlayer
	formatNumber = dependencies.formatNumber
	getProfileCache = dependencies.getProfileCache

	walkingToBaseFolder = walkingOnPart:WaitForChild("WalkingToBase") or Instance.new("Folder", walkingOnPart)
	walkingToBaseFolder.Name = "WalkingToBase"

	for _, folder in ipairs(rigsFolder:GetChildren()) do
		if folder:IsA("Folder") then
			local important = folder:FindFirstChild("Important")
			local rarityValue = important and important:FindFirstChild("Rarity")
			if rarityValue and rarityValue:IsA("StringValue") then
				local rarity = rarityValue.Value
				if not _rigsByRarity[rarity] then _rigsByRarity[rarity] = {} end
				table.insert(_rigsByRarity[rarity], folder.Name)
			end
		end
	end

	task.spawn(function()
		local assetsToPreload = {rankGui, actionButton}
		for _, rig in ipairs(rigsFolder:GetChildren()) do table.insert(assetsToPreload, rig) end
		ContentProvider:PreloadAsync(assetsToPreload)
	end)

	preloadNpcTemplates()

	task.spawn(function()
		if #Players:GetPlayers() == 0 then
			Players.PlayerAdded:Wait()
		end

		task.wait(configFolder.SpawnDelay.Value)

		while task.wait(spawnInterval) do
			if #Players:GetPlayers() > 0 then
				NPCManager.spawnRandomNPC()
			end
		end
	end)
end

return NPCManager