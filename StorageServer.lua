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
	print("[DEBUG][SERVER] getPlayerPlot called for", player.Name, "Looking for:", plotName)
	local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(plotName)
	if plot then
		print("[DEBUG][SERVER] Found player plot:", plot)
	else
		warn("[DEBUG][SERVER] Player plot not found:", plotName)
	end
	return plot
end

-- Find shelf instance by StorageId under player's plot
local function getShelfByStorageId(player, storageId)
	print("[DEBUG][SERVER] getShelfByStorageId called for player:", player.Name, "storageId:", storageId)
	local plot = getPlayerPlot(player)
	if not plot then
		warn("[DEBUG][SERVER] Plot not found for player:", player.Name)
		return nil
	end
	local objects = plot:FindFirstChild("Objects")
	if not objects then
		warn("[DEBUG][SERVER] Objects folder not found in plot for player:", player.Name)
		return nil
	end
	for _, shelf in ipairs(objects:GetChildren()) do
		local shelfStorageId = shelf:GetAttribute("StorageId")
		print("[DEBUG][SERVER] Checking shelf:", shelf, "StorageId:", shelfStorageId)
		if shelfStorageId == storageId then
			print("[DEBUG][SERVER] Shelf found for StorageId:", storageId)
			return shelf
		end
	end
	warn("[DEBUG][SERVER] No shelf found with StorageId:", storageId)
	return nil
end

-- Open shelf request from client
Signal.ListenRemote("Storage:Open", function(player, storageId)
	print("[DEBUG][SERVER] Storage:Open received from", player.Name, "with StorageId:", storageId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf then
		warn("[DEBUG][SERVER] Storage:Open failed: shelf not found for StorageId:", storageId)
		return
	end

	-- Create storage data if missing
	if not ShelfData[storageId] then
		print("[DEBUG][SERVER] ShelfData missing for StorageId:", storageId, "Creating new entry.")
		ShelfData[storageId] = {
			Items = {},
			MaxStacks = 8,
			Owner = player,
			ShelfInstance = shelf,
		}
	else
		print("[DEBUG][SERVER] ShelfData exists for StorageId:", storageId)
	end
	if ShelfData[storageId].Owner ~= player then
		warn("[DEBUG][SERVER] Shelf owner mismatch. Expected:", ShelfData[storageId].Owner, "Got:", player)
		return
	end

	print("[DEBUG][SERVER] Firing Storage:Open to client. Data:", ShelfData[storageId])
	Signal.FireClient(player, "Storage:Open", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
end)

-- Deposit stack from inventory to shelf
Signal.ListenRemote("Storage:Deposit", function(player, storageId, stackId)
	print("[DEBUG][SERVER] Storage:Deposit received from", player.Name, "storageId:", storageId, "stackId:", stackId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf then
		warn("[DEBUG][SERVER] Deposit failed: shelf not found for StorageId:", storageId)
		return
	end
	if not ShelfData[storageId] then
		warn("[DEBUG][SERVER] Deposit failed: ShelfData missing for StorageId:", storageId)
		return
	end
	if ShelfData[storageId].Owner ~= player then
		warn("[DEBUG][SERVER] Deposit failed: Owner mismatch. Owner:", ShelfData[storageId].Owner, "Player:", player)
		return
	end

	local inv = InventoryServer.AllInventories[player]
	if not inv then
		warn("[DEBUG][SERVER] Deposit failed: Inventory not found for player:", player.Name)
		return
	end

	-- Find stack in inventory
	local stackIdx, stackData
	for i, stack in ipairs(inv.Inventory) do
		if stack.StackId == stackId then
			stackIdx = i
			stackData = stack
			break
		end
	end
	if not stackIdx then
		warn("[DEBUG][SERVER] Deposit failed: StackId not found in inventory:", stackId)
		return
	end

	-- Check shelf capacity
	if #ShelfData[storageId].Items >= ShelfData[storageId].MaxStacks then
		warn("[DEBUG][SERVER] Deposit failed: Shelf is full")
		Signal.FireClient(player, "Storage:Error", "Shelf is full!")
		return
	end

	print("[DEBUG][SERVER] Inserting stack into shelf. StackId:", stackId)
	table.insert(ShelfData[storageId].Items, stackData)
	table.remove(inv.Inventory, stackIdx)

	print("[DEBUG][SERVER] Firing Storage:Update to client after deposit.")
	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Withdraw stack from shelf to inventory
Signal.ListenRemote("Storage:Withdraw", function(player, storageId, stackId)
	print("[DEBUG][SERVER] Storage:Withdraw received from", player.Name, "storageId:", storageId, "stackId:", stackId)
	local shelf = getShelfByStorageId(player, storageId)
	if not shelf then
		warn("[DEBUG][SERVER] Withdraw failed: shelf not found for StorageId:", storageId)
		return
	end
	if not ShelfData[storageId] then
		warn("[DEBUG][SERVER] Withdraw failed: ShelfData missing for StorageId:", storageId)
		return
	end
	if ShelfData[storageId].Owner ~= player then
		warn("[DEBUG][SERVER] Withdraw failed: Owner mismatch. Owner:", ShelfData[storageId].Owner, "Player:", player)
		return
	end

	local inv = InventoryServer.AllInventories[player]
	if not inv then
		warn("[DEBUG][SERVER] Withdraw failed: Inventory not found for player:", player.Name)
		return
	end

	-- Check inventory stack capacity
	if #inv.Inventory >= InventoryServer.MaxStacks then
		warn("[DEBUG][SERVER] Withdraw failed: Inventory is full")
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
	if not stackIdx then
		warn("[DEBUG][SERVER] Withdraw failed: StackId not found in shelf items:", stackId)
		return
	end

	print("[DEBUG][SERVER] Moving stack from shelf to inventory. StackId:", stackId)
	table.insert(inv.Inventory, stackData)
	table.remove(ShelfData[storageId].Items, stackIdx)

	print("[DEBUG][SERVER] Firing Storage:Update and InventoryClient:Update to client after withdraw.")
	Signal.FireClient(player, "Storage:Update", storageId, ShelfData[storageId].Items, ShelfData[storageId].MaxStacks)
	Signal.FireClient(player, "InventoryClient:Update", inv)
end)

-- Cleanup storage data when player leaves
Players.PlayerRemoving:Connect(function(player)
	print("[DEBUG][SERVER] PlayerRemoving for", player.Name, "Cleaning up storage data.")
	for storageId, data in pairs(ShelfData) do
		if data.Owner == player then
			print("[DEBUG][SERVER] Removing ShelfData for StorageId:", storageId)
			ShelfData[storageId] = nil
		end
	end
end)

return ShelfData