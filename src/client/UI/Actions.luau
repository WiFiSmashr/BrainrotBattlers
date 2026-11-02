--!strict
-- The only way the UI changes the game: send an intent to the server (UI-01, ARCH-01). The server
-- answers { ok, reason } and also pushes a Toast for rejections, so there is nothing to decide here.

local StateStore = require(script.Parent.Parent.StateStore)

local Actions = {}

local remote: RemoteFunction? = nil

-- Gives the module the Action RemoteFunction.
function Actions.init(action: RemoteFunction)
	remote = action
end

-- Sends an intent without blocking the UI. A failed call (not a rejection) shows a network toast.
function Actions.send(name: string, args: { [string]: any }?)
	task.spawn(function()
		local ok = pcall(function()
			return (remote :: RemoteFunction):InvokeServer(name, args or {})
		end)
		if not ok then
			StateStore.toast:fire("NetworkError")
		end
	end)
end

-- Menu actions (outside the GDD): queue for a match and return to the menu.
function Actions.joinQueue()
	Actions.send("JoinQueue")
end

function Actions.leaveQueue()
	Actions.send("LeaveQueue")
end

-- Tells the server which plot the camera is over, so it can stream it (D-89).
function Actions.scoutPlot(seat: number?)
	Actions.send("ScoutPlot", { seat = seat })
end

function Actions.backToMenu()
	Actions.send("BackToMenu")
end

-- Convenience wrappers named after the GDD 3.5 actions.
function Actions.buyUnit(slot: number)
	Actions.send("BuyUnit", { slot = slot })
end

function Actions.rerollShop()
	Actions.send("RerollShop")
end

function Actions.buyXp()
	Actions.send("BuyXP")
end

function Actions.toggleLock()
	Actions.send("ToggleLock")
end

function Actions.moveToBench(unitUid: number, index: number)
	Actions.send("MoveUnit", { unitUid = unitUid, dest = { kind = "bench", index = index } })
end

function Actions.moveToBoard(unitUid: number, col: number, row: number)
	Actions.send("MoveUnit", { unitUid = unitUid, dest = { kind = "board", col = col, row = row } })
end

function Actions.sellUnit(unitUid: number)
	Actions.send("SellUnit", { unitUid = unitUid })
end

function Actions.equipItem(itemUid: number, unitUid: number)
	Actions.send("EquipItem", { itemUid = itemUid, unitUid = unitUid })
end

function Actions.unequipItem(itemUid: number)
	Actions.send("UnequipItem", { itemUid = itemUid })
end

function Actions.combineItems(itemUidA: number, itemUidB: number)
	Actions.send("CombineItems", { itemUidA = itemUidA, itemUidB = itemUidB })
end

function Actions.pickAugment(index: number)
	Actions.send("PickAugment", { index = index })
end

function Actions.rerollAugment()
	Actions.send("RerollAugment")
end

function Actions.pickCarousel(index: number)
	Actions.send("PickCarousel", { index = index })
end

return Actions
