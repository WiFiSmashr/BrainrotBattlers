--!strict
-- Tap-only selection state: the selected unit, up to two selected items, and the item whose details
-- are shown (UI-04). This is local UI state only (UI-01 allows drag previews and open menus); it is
-- never sent anywhere by itself.

local Signal = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Util.Signal)

local Selection = {
	unit = nil :: number?, -- selected unit uid; also the unit whose info card is open
	items = {} :: { number }, -- selected item uids, oldest first (two selected components can be combined)
	inspected = nil :: number?, -- the item whose effects the item panel shows
	changed = Signal.new() :: any,
}

-- Selects a unit (and opens its card), or clears the selection with nil.
function Selection.selectUnit(uid: number?)
	Selection.unit = uid
	Selection.changed:fire()
end

-- Selects or deselects an item and shows its details. At most two stay selected; the oldest drops out.
function Selection.toggleItem(uid: number)
	local i = table.find(Selection.items, uid)
	if i then
		table.remove(Selection.items, i)
	else
		table.insert(Selection.items, uid)
		if #Selection.items > 2 then
			table.remove(Selection.items, 1)
		end
	end
	Selection.inspected = uid
	Selection.changed:fire()
end

-- Shows an item's details without selecting it (used for items on a unit).
function Selection.inspectItem(uid: number?)
	Selection.inspected = uid
	Selection.changed:fire()
end

-- True if the item is selected.
function Selection.hasItem(uid: number): boolean
	return table.find(Selection.items, uid) ~= nil
end

-- Clears the item selection.
function Selection.clearItems()
	Selection.items = {}
	Selection.changed:fire()
end

-- Clears everything.
function Selection.clear()
	Selection.unit = nil
	Selection.items = {}
	Selection.inspected = nil
	Selection.changed:fire()
end

return Selection
