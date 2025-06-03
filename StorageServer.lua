-- Place this in ServerScriptService

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Types = require(ReplicatedStorage.Modules.Types)
local Signal = require(ReplicatedStorage.Modules.Signal)
local ServerScriptService = game:GetService("ServerScriptService")
local InventoryServer = require(ServerScriptService.Server.InventoryServer)

-- Storage shelves data, keyed by StorageId (string)
local ShelfData = {} -- [storageId] = { Items, MaxStacks, Owner, ShelfInstance }

-- Find the player's plot model
local function getPlayerPlot(player)
	local plotName = player.Name .. "'s" ..  " Plot"
	local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(plotName)
	return plot
end

-- Find shelf instance by StorageId under player's plot
local function getShelfByStorageId(player, storageId)
	local plot = getPlayerPlot(player)
	if not plot then
		return nil
	end
	local objects = plot:FindFirstChild("Objects")
	if not objects then
		return nil
	end
	for _, shelf in ipairs(objects:GetChildren()) do
		local shelfStorageId = shelf:GetAttribute("StorageId")
		if shelfStorageId == storageId then
			return shelf
		end
	end
	return nil
end

-- Open shelf request from client
Signal.ListenRemote("Storage:Open", function(player, storageId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf then
		return
	end

	-- Create storage data if missing
	if not ShelfData[storageId] then
		ShelfData[storageId] = {
			Items = {},
			MaxStacks = 8,
			Owner = player,
			ShelfInstance = shelf,
		}
	end
	if ShelfData[storageId].Owner ~= player then
		return
	end

	Signal.FireClient(player, "Storage:Open", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
end)

-- Deposit stack from inventory to shelf
Signal.ListenRemote("Storage:Deposit", function(player, storageId, stackId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf or not ShelfData[storageId] or ShelfData[storageId].Owner ~= player then
		return
	end

	local inv = InventoryServer.AllInventories[player]
	if not inv then return end

	-- Find stack in inventory
	local stackIdx, stackData
	for i, stack in ipairs(inv.Inventory) do
		if stack.StackId == stackId then
			stackIdx = i
			stackData = stack
			break
		end
	end
	if not stackIdx then return end

	-- Check shelf capacity
	if #ShelfData[storageId].Items >= ShelfData[storageId].MaxStacks then
		Signal.FireClient(player, "Storage:Error", "Shelf is full!")
		return
	end

	table.insert(ShelfData[storageId].Items, stackData)
	table.remove(inv.Inventory, stackIdx)

	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Withdraw stack from shelf to inventory
Signal.ListenRemote("Storage:Withdraw", function(player, storageId, stackId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf or not ShelfData[storageId] or ShelfData[storageId].Owner ~= player then
		return
	end

	local inv = InventoryServer.AllInventories[player]
	if not inv then return end

	if #inv.Inventory >= InventoryServer.MaxStacks then
		Signal.FireClient(player, "Storage:Error", "Inventory is full!")
		return
	end

	-- Find stack in shelf
	local stackIdx, stackData
	for i, stack in ipairs(ShelfData[storageId].Items) do
		if stack.StackId == stackId then
			stackIdx = i
			stackData = stack
			break
		end
	end
	if not stackIdx then return end

	table.insert(inv.Inventory, stackData)
	table.remove(ShelfData[storageId].Items, stackIdx)

	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Cleanup storage data when player leaves
Players.PlayerRemoving:Connect(function(player)
	for storageId, data in pairs(ShelfData) do
		if data.Owner == player then
			ShelfData[storageId] = nil
		end
	end
end)

return ShelfData
