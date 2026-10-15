--!strict

-- Discord: ianfinity 728976729590464554
-- Roblox: ianfinity01

local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Get ReplicatedStorage
local RunService = game:GetService("RunService") -- Get RunService for RenderStepped
local Players = game:GetService("Players") -- Get Players
local REMOTES = ReplicatedStorage.BoardRemotes -- Get the Remote Event that will be used for data updates
local GUI = script.Parent -- Get the gui that will be updated
local UPDATER_GUI = GUI.Parent.Updater -- Get the GUI where the user can send and remove entries

local ENTRY_TEMPLATE = GUI.EntryTemplate -- Get the template for entries on the leaderboard
local BOARD_VALUE_SUFFIX = " pts" -- The suffix for board values
local TOP_SCROLL = GUI.Top.ScrollingFrame -- The scrolling frame for the top entires on the leaderboard
local AROUND_SCROLL = GUI.Around.ScrollingFrame -- The scrolling frame for entries around the player on the leaderboard
local REFRESH_TIMER = GUI.Refresh -- The text label that shows the time until the leaderboard refreshes
local TOP_ERR = TOP_SCROLL.ERROR -- The error label for the top scrolling frame
local AROUND_ERR = AROUND_SCROLL.ERROR -- The error label for the around the player scrolling frame
local AROUND_NF = AROUND_SCROLL.NOTFOUND -- The label for the not found error

-- main code
local refresh_target: number? = nil -- The timestamp at which the next leaderboard refresh will occur
local board_size: number? = nil -- The total number of entries (displayed or not) on the leaderboard
local top_entries: {TextButton} = {} -- The entries in the top scrolling frame
local around_entries: {TextButton} = {} -- The entries in the around scrolling frame
local name_cache: {[number]: string} = {} -- A cache of user-id to username
local profile_cache: {[number]: string} = {} -- A cache of user-id to profile picture
local out_of_bounds_frame: typeof(ENTRY_TEMPLATE)? = nil -- A frame to display when the player is out of the bounds of the leaderboard

-- Called when the player clicks on a leaderboard entry
function on_click(id: number)
	-- Update the entry-updater gui to allow the user to edit the entry
	UPDATER_GUI.SEND.ID.Text = tostring(id) -- Update the entry-updating text box to display the id of the entry you clicked on
	UPDATER_GUI.REMOVE.ID.Text = tostring(id) -- Update the entry-removal text box to display the id of the entry you clicked on
end

-- Loads the username and profile picture onto an entry frame by their user-id
function load_entry_name_profile(id: number, frame: typeof(ENTRY_TEMPLATE))
	if name_cache[id] then -- Check if the username of the id is cached
		frame.Left.User.Text = name_cache[id] -- If so, update the entry's username label to show their username
	else -- Otherwise
		task.spawn(function()	-- Spawn a new thread to retrieve the username and cache it without hanging anything up
			local name = Players:GetNameFromUserIdAsync(id) -- Get the player's username from their id
			name_cache[id] = name -- Cache it for later use
			
			if not frame.Parent then -- Make sure the entry still exists and wasn't lost while we were requesting the username
				return -- If it doesn't exist anymore, exit because there's nothing to update
			end
			
			frame.Left.User.Text = name -- Update the entry's username label to show their newly-found username
		end)
	end -- Please don't tell me I have to come up with a comment for this line too
		-- Or this one (it's empty)
	-- Basically the same logic as above (yayyy I have to write all these comments again, thanks HD)
	if profile_cache[id] then -- Check if the profile picture of the id is cached
		frame.Right.Profile.Image = profile_cache[id] -- If so, update the entry's profile picture image to show the cached pfp
	else -- Otherwise
		task.spawn(function()  -- Spawn a new thread to retrieve the profile picture and cache it without hanging anything up
			local image = Players:GetUserThumbnailAsync(id, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100) -- Get the player's headshot 100x100 profile picture
			profile_cache[id] = image -- Cache it for later use
			
			if not frame.Parent then -- Make sure the entry still exists and wasn't lost while we were requesting the profile picture
				return -- If it doesn't exist anymore, exit because there's nothing to update
			end
			
			frame.Right.Profile.Image = image -- Update the entry's profile picture image to show the newly-found profile picture
		end)
	end
end

-- Displays the frame that appears when the player is out of the bounds of the leaderboard
function display_out_of_bounds_frame()
	local frame = ENTRY_TEMPLATE:Clone() -- Clone the entry template
	frame.Visible = true -- Make the entry visible
	frame.Parent = AROUND_SCROLL -- Set the entry's parent to the around scrolling frame so it displays
	frame.Name = "FAIL" -- Give the frame an appropriate name (not entirely necessary)

	frame.Left.Rank.Text = `>{board_size}` -- Set the rank label to be greater than the board size, indicating that the player's rank is greater than the number of users on the board (they're not qualified to be on the board)
	frame.Left.User.Text = "--" -- Placeholder text for the username while it loads in the load_entry_name_profile function
	frame.Right.Value.Visible = false -- Hide the value label because it's not applicable (considering the player isn't on the board)
	
	frame.Activated:Connect(function() -- Whenever this entry is clicked
		on_click(Players.LocalPlayer.UserId) -- Activate the on click function for the player's entry
	end)

	load_entry_name_profile(Players.LocalPlayer.UserId, frame) -- Load the player's username and profile picture onto the entry (may not be immediate)

	out_of_bounds_frame = frame -- Set the out_of_bounds_frame to reflect that this is the out of bounds entry
	table.insert(around_entries, frame) -- Add the frame to the around entries list so it will be properly cleaned up
end
-- All these comments are excruciating
REMOTES.TopUpdate.OnClientEvent:Connect(function(entries) -- When the server notifies of an update to the top entries of the leaderboard
	-- Remove all existing entries so that we can populate the board with the new ones
	for _, entry in top_entries do -- For every entry in the current top entries list
		entry:Destroy() -- Delete the entry
	end -- Help
	
	table.clear(top_entries) -- Clear the list to reflect that the entries in it have been destroyed
	
	if not entries then -- Check if entries is not provided, which will occur iff the board encountered an error
		TOP_ERR.Visible = true -- Display the error message
		return -- Stop the code since the rest relies on the server having provided entries to display
	end
	
	TOP_ERR.Visible = false -- Hide the error message (in case it was displaying earlier)
	
	for _, entry in entries do -- For every entry in the list of new top entries
		local frame = ENTRY_TEMPLATE:Clone() -- Copy the template entry to use as a starting point
		frame.Visible = true -- Make the entry visible
		frame.Parent = TOP_SCROLL -- Put the entry into the scrolling frame for top entries
		frame.Name = entry.rank -- Give it a reasonable name (not completely necessary)
		
		local rank = entry.rank -- Retrieve the rank of the entry from the data provided by the server
		local id = entry.entry.key -- Retrieve the user id of the entry from the data provided by the server
		local points = entry.entry.points -- Retrieve the user's points from the entry from the data provided by the server
		
		frame.LayoutOrder = rank -- Make sure the entries display in order of their ranks
		frame.Left.Rank.Text = `#{rank}` -- Display the rank of the entry
		frame.Left.User.Text = "--" -- Put a placeholder for their username while load_entry_name_profile loads it
		frame.Right.Value.Text = `{points}{BOARD_VALUE_SUFFIX}` -- Display the user's points with the points suffix
		
		frame.Activated:Connect(function() -- Whenever this entry is clicked
			on_click(id) -- Activate the on click function for the player's entry
		end)
		
		load_entry_name_profile(id, frame) -- Load the player's username and profile picture onto the entry (may not be immediate)
		
		table.insert(top_entries, frame) -- Add the frame to the top entries list so it will be properly cleaned up
	end
end)
-- Oh god help me I'm barely half way done
REMOTES.AroundUpdate.OnClientEvent:Connect(function(cached, data) -- When the server notifies of an update to the entries around you on the leaderboard
	-- Remove all existing entries so that we can populate the board with the new ones
	for _, entry in around_entries do -- For every entry in the current around entries list
		entry:Destroy() -- Delete the entry
	end
	
	out_of_bounds_frame = nil -- Clear the out_of_bounds_frame variable so that its non-existance is clear after it was destroyed in the above lines

	table.clear(around_entries) -- Clear the list to reflect that the entries in it have been destroyed

	if not cached then -- If the server did not send us cached data, this means it errored
		AROUND_ERR.Visible = true -- Display an error message
		return -- Exit since there's no data to work with for the rest of the function
	end

	AROUND_ERR.Visible = false -- Make the error message not visible (since it didn't error)
	AROUND_NF.Visible = false -- Make the not-found error not visible (may be overwritten in a moment)
	
	if not data then -- If there is no data (the server sent nil) then you are not on the board (out of bounds)
		if not board_size then -- If the board size is not known
			AROUND_NF.Visible = true -- Just display an error message
		else -- Otherwise
			display_out_of_bounds_frame() -- Display the frame showing that your rank is greater than the number of people currently on the board (you are ranked below them all)
		end
		
		return -- There's no data to work with, so exit
	end
	
	local display_entries = data.surrounding_entries or {data} -- Either display the surrounding entries of the player, or just display the player's data if its not available
	for _, entry in display_entries do -- Iterate through all entries to display
		local frame = ENTRY_TEMPLATE:Clone() -- Clone the template to have something to start with
		frame.Visible = true -- Make the entry visible
		frame.Parent = AROUND_SCROLL -- Put the frame in the scrolling frame so it displays
		frame.Name = entry.rank -- Give the frank an appropriate name (not strictly necessary)

		local rank = entry.rank -- Get the rank of the entry from the data provided by the server
		local id = entry.entry.key -- Get the user id of the entry from the data provided by the server
		local points = entry.entry.points -- Get the user's points of the entry from the data provided by the server

		frame.LayoutOrder = rank -- Make sure that the entries in the frame are ordered by rank
		frame.Left.Rank.Text = `#{rank}` -- Display the rank of the entry
		frame.Left.User.Text = "--" -- Put a placeholder for their username while load_entry_name_profile loads it
		frame.Right.Value.Text = `{points}{BOARD_VALUE_SUFFIX}` -- Display the user's points with the points suffix
		
		frame.Activated:Connect(function() -- Whenever this entry is clicked
			on_click(id) -- Activate the on click function for the player's entry
		end)
		
		if id == Players.LocalPlayer.UserId then -- Check if you are the player on this entry
			frame.Left.User.FontFace = Font.new(frame.Left.User.FontFace.Family, Enum.FontWeight.Bold) -- If so, make your name bold so it's easier to spot
		end

		load_entry_name_profile(id, frame) -- Load the player's username and profile picture onto the entry (may not be immediate)

		table.insert(around_entries, frame) -- Add the entry to the list of entries around the player so it will be properly cleaned up
	end
end)

REMOTES.RefreshUpdate.OnClientEvent:Connect(function(target_time, size) -- When the server provides new board info, including a board size and the time of the next update
	board_size = size -- Store the board size for later

	if out_of_bounds_frame then -- If the out of bounds frame is being currently displayed
		out_of_bounds_frame.Left.Rank.Text = `>{board_size}` -- Update the rank text to reflect the new board size
	elseif AROUND_NF.Visible then -- If the not found error is currently displayed
		AROUND_NF.Visible = false -- Hide it, since we now have a board size, and can display a more detailed out-of-bounds frame instead
		display_out_of_bounds_frame() -- Display the out of bounds frame
	end
	
	refresh_target = target_time -- Update the timestamp of the next update
end)

RunService.RenderStepped:Connect(function() -- Every frame
	if not refresh_target then -- If there isn't a known time for the next update
		REFRESH_TIMER.Text = "" -- Hide the refresh timer
		return -- Don't do anything else
	end
	
	local delta = math.max(refresh_target - workspace:GetServerTimeNow(), 0) -- Calculate the number of seconds until the timestamp of the next update (and don't allow it to be negative)
	local seconds = math.floor(delta%60) -- Take the portion of the total seconds that isn't minutes
	local minutes = math.floor(delta/60) -- Take the minutes out of the seconds
	
	REFRESH_TIMER.Text = string.format("REFRESH IN %02i:%02i", minutes, seconds) -- Display the new time information
end)
