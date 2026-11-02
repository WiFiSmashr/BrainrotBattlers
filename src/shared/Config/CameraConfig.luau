--!strict
-- The fixed, angled combat camera (a TFT-style view of your own arena). Every value is [CONFIG] and
-- can be tuned while playing. The camera sits behind the viewer's own side, looking across the
-- arena at the opponents; for the away player in a PvP fight that means the far end of the plot.

local CameraConfig = {
	fieldOfView = 70, -- degrees, vertical
	distance = 50, -- studs from the arena centre to the camera
	pitchDegrees = 40, -- how far the camera looks down
	lookHeight = 2, -- height of the point the camera aims at (the tile tops are at y = 1)
	-- Panels cover the bottom of the screen, so the camera is tilted down this much to show the arena in
	-- the free area between the top bar and the bench.
	uiShiftDegrees = 14.5,
	transitionSeconds = 0.55,
}

return CameraConfig
