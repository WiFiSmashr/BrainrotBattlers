--!strict
-- Looking at another player's board (D-79). Clicking a name in the top bar moves the camera over that
-- player's plot and shows their board and bench units (read-only: stars and items, no selection or dragging).
-- A banner names whose board it is and returns to your own. Models are local to this client, like
-- PlotView's; the boards come from the public scoreboard in the snapshot.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Index = require(Shared.Util.Index)
local ModelRegistry = require(Shared.Util.ModelRegistry)
local ArenaLayout = require(Shared.Util.ArenaLayout)
local ModelFactory = require(Shared.Visual.ModelFactory)
local UnitAnimator = require(Shared.Visual.UnitAnimator)
local Theme = require(script.Parent.Parent.UI.Theme)
local Components = require(script.Parent.Parent.UI.Components)
local ItemIcon = require(script.Parent.Parent.UI.ItemIcon)
local StateStore = require(script.Parent.Parent.StateStore)

local ScoutView = {}

export type View = {
	render: (snapshot: { [string]: any }?) -> (), -- draws the scouted board, or clears it
	target: (snapshot: { [string]: any }?) -> { [string]: any }?, -- the scoreboard entry being scouted, if any
	view: (snapshot: { [string]: any }?) -> (Vector3?, boolean?), -- where the camera goes to watch them (D-89)
}

-- Builds the view; `parent` receives the banner.
function ScoutView.build(parent: Instance): View
	local folder = Instance.new("Folder")
	folder.Name = "ScoutView"
	folder.Parent = workspace

	local banner = Components.panel({
		Name = "ScoutBanner", Size = UDim2.fromOffset(560, 56), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108),
		stroke = Theme.colors.accent, radius = 12, Visible = false, ZIndex = 30, Parent = parent,
	})
	local text = Components.label({ Size = UDim2.new(1, -190, 1, 0), Position = UDim2.fromOffset(16, 0), TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31, Parent = banner })
	Components.button({
		Size = UDim2.fromOffset(170, 40), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Text = "My board", TextSize = 24,
		BackgroundColor3 = Theme.colors.good, TextColor3 = Color3.new(0, 0, 0), ZIndex = 31, Parent = banner,
		onTap = function()
			StateStore.setScouting(nil)
		end,
	})

	local entries: { any } = {}
	local drawn = "" -- signature of what is on screen

	local function clear()
		for _, entry in entries do
			entry.animator:destroy()
			entry.visual:destroy()
		end
		table.clear(entries)
		drawn = ""
	end

	local latest: { [string]: any }? = nil
	local render

	-- Where the scouted player is shown (D-89): on their own plot, or - while they are fighting - on the plot
	-- that hosts the fight, from behind their side of it. `live` is true then: the real fight is on screen.
	local function placement(who: { [string]: any }, snapshot: { [string]: any }): (Vector3, boolean, boolean)
		if StateStore.phase.name == "Combat" and who.host then
			for _, p in snapshot.players do
				if p.id == who.host then
					return ArenaLayout.plotOrigin(p.seat), who.host == who.id, true
				end
			end
		end
		return ArenaLayout.plotOrigin(who.seat), true, false
	end

	local function target(snapshot: { [string]: any }?): { [string]: any }?
		local id = StateStore.scouting
		if not id or not snapshot then
			return nil
		end
		for _, p in snapshot.players do
			if p.id == id then
				return p
			end
		end
		return nil
	end

	function render(snapshot: { [string]: any }?)
		latest = snapshot
		local who = target(snapshot)
		banner.Visible = who ~= nil
		if not who then
			clear()
			return
		end
		text.Text = ("%s's board and bench"):format(who.n)

		-- Redraw only when their board changed.
		local origin, homeSide, live = placement(who, snapshot :: { [string]: any })
		local parts = { who.id, tostring(live), tostring(homeSide), tostring(origin) }
		for _, u in who.board do
			table.insert(parts, ("%s:%d:%s:%s:%s:%s"):format(u.d, u.s, tostring(u.c), tostring(u.r), tostring(u.b), table.concat(u.i, ",")))
		end
		local signature = table.concat(parts, "|")
		if signature == drawn then
			return
		end
		clear()
		drawn = signature

		for _, u in who.board do
			local def = Index.unit(u.d) :: any
			if def and (u.b or not live) then
				local modelId = ModelRegistry.modelIdOf(def)
				local visual = ModelFactory.create(modelId, { tint = def.tint })
				visual.model.Name = "ScoutUnit"
				visual.model.Parent = folder
				local position = if u.b then ArenaLayout.benchPosition(origin, u.b, homeSide) else ArenaLayout.cellPosition(origin, u.c, u.r)
				visual:place(position, position + Vector3.new(0, 0, if homeSide then 10 else -10)) -- each side faces the far half

				local gui = Instance.new("BillboardGui")
				gui.Size = UDim2.fromOffset(110, 40)
				gui.StudsOffsetWorldSpace = Vector3.new(0, visual.height + 0.8, 0)
				gui.AlwaysOnTop = true
				gui.LightInfluence = 0
				gui.Adornee = visual.primary
				gui.Parent = visual.primary
				Components.label({
					Size = UDim2.new(1, 0, 0, 20), Text = string.rep("★", u.s), TextSize = 20, TextColor3 = Theme.colors.accent,
					TextStrokeTransparency = 0.3, Parent = gui,
				})
				local row = Components.create("Frame", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 20), BackgroundTransparency = 1, Parent = gui })
				Components.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 2), Parent = row })
				for _, itemId in u.i do
					ItemIcon.mini(row, itemId)
				end
				table.insert(entries, { visual = visual, animator = UnitAnimator.new(visual, ModelRegistry.animationsFor(modelId)) })
			end
		end
	end

	-- The plot and side the camera should look from for a scouted player, or nil when not scouting.
	local function view(snapshot: { [string]: any }?): (Vector3?, boolean?)
		local who = target(snapshot)
		if not who or not snapshot then
			return nil, nil
		end
		local origin, homeSide = placement(who, snapshot)
		return origin, homeSide
	end

	return { render = render, target = target, view = view }
end

return ScoutView
