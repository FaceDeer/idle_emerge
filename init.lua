local areas_to_emerge = {}

local mapgen_chunksize = tonumber(minetest.get_mapgen_setting("chunksize"))
local mapblock_size = mapgen_chunksize * 16

local delay_between_emerge_calls = tonumber(minetest.settings:get("idle_emerge_delay")) or 0.0
local check_for_non_admin_players = minetest.settings:get_bool("idle_emerge_admin_check", true)
local delete_time_multiplier = 10 -- In theory, the game will spend 1/delete_time_multiplier of its time running deletion
local average_delete_dtime_over = 10 -- how many delete times to keep track of when calculating an average
local update_user_timer = 30 -- if a user has a task running, send him an update every this many seconds

-- adapted from https://stackoverflow.com/questions/398299/looping-in-a-spiral with much modification
local spiral_pos_iterator = function(pos1, pos2, size, skip_to_index)
	local minp = vector.divide({x = math.min(pos1.x, pos2.x), y = math.min(pos1.y, pos2.y), z = math.min(pos1.z, pos2.z)}, size)
	local maxp = vector.divide({x = math.max(pos1.x, pos2.x), y = math.max(pos1.y, pos2.y), z = math.max(pos1.z, pos2.z)}, size)
	local width = maxp.x-minp.x
	local depth = maxp.z-minp.z
	local min_y = math.ceil(minp.y)
	local max_y = math.floor(maxp.y)

    local x = 0
	local y = min_y-1
	local z = 0
    local dx = 0
    local dz = -1
	local width_half = width/2
	local depth_half = depth/2
	local i = 0
	local max_iter = math.max(width, depth)^2
	
	local iterator = function()
		if y < max_y then
			y = y + 1
			return {x=(x+width_half+minp.x)*size, y=y*size, z=(z+depth_half+minp.z)*size}
		else
			y = min_y
		end
		local ret = nil
		while ret == nil do
			if i > max_iter then
				return
			end
			if x == z or (x < 0 and x == -z) or (x > 0 and x == 1-z) then
				dx, dz = -dz, dx
			end
			x, z = x+dx, z+dz
			i = i + 1
			if (-width_half < x) and (x <= width_half) and (-depth_half < z) and (z <= depth_half) then
				ret = true
			end	
		end
		return {x=(x+width_half+minp.x)*size, y=y*size, z=(z+depth_half+minp.z)*size}
	end
	
	if skip_to_index and skip_to_index > 0 then
		-- Probably not the most efficient thing in the world to just plough through the iterator's outputs
		-- to catch up to the desired index, but unlikely to come up often and unlikely to have bugs.
		for i = 1, skip_to_index do
			iterator()
		end
	end
	
	return iterator
end

-- Loading and saving data
local filename = minetest.get_worldpath() .. "/idle_emerge_queue.lua"

local load_data = function()
	local f, e = loadfile(filename)
	if f then
		areas_to_emerge = f()
		for _, area in ipairs(areas_to_emerge) do
			area.iterator = spiral_pos_iterator(area.pos1, area.pos2, mapblock_size, area.index)
		end
	end
end

local save_data = function()
	local data = {}
	for i, area in ipairs(areas_to_emerge) do
		local new_area = {}
		for k, v in pairs(area) do
			if k ~= "iterator" then
				new_area[k] = v
			end
		end
		data[i] = new_area
	end
	local file, e = io.open(filename, "w");
	if not file then
		return error(e);
	end
	file:write(minetest.serialize(data))
	file:close()
end

load_data()

-- Testing whether non-admin players are present whenever that might have changed
local non_admin_players_present = false
if check_for_non_admin_players then
	local check_players = function(exclude_player)
		local players = minetest.get_connected_players()
		for _, player in ipairs(players) do
			local player_name = player:get_player_name()
			if exclude_player ~= player_name and not minetest.get_player_privs(player_name).server then
				non_admin_players_present = true
				return
			end
		end
		non_admin_players_present = false
	end

	minetest.register_on_joinplayer(function(obj)
		check_players()
	end)
	minetest.register_on_leaveplayer(function(obj, timed_out)
		check_players(obj:get_player_name())
	end)
	minetest.register_on_priv_grant(function(name, granter, priv)
		if priv == "server" then
			check_players()
		end
	end)
	minetest.register_on_priv_revoke(function(name, revoker, priv)
		if priv == "server" then
			check_players(name)
		end		
	end)
end

-- Chat command
local get_queue_display_string = function()
	if #areas_to_emerge == 0 then
		return "No idle_emerge tasks currently running."
	end
	local outstring = {"Queued idle_emerge tasks:"}
	for i, task in ipairs(areas_to_emerge) do
		outstring[#outstring+1] = tostring(i) .. ":\t" .. minetest.pos_to_string(task.pos1) .. " "
			.. minetest.pos_to_string(task.pos2) .. " queued by " .. task.name
		if task.index > 0 then
			outstring[#outstring] = outstring[#outstring] .. " and currently running index "
				.. task.index
		end
	end
	return table.concat(outstring, "\n")
end

local function parse_range_str(player_name, str)
	local p1, p2
	local args = str:split(" ")
	if args[1] == nil then
		return false, get_queue_display_string()
	elseif args[1] == "clear" then
		if args[2] then
			local index = tonumber(args[2])
			if index then
				if table.remove(areas_to_emerge, index) then
					return false, "Cleared queued emerge task " .. args[2]
				else
					return false, "Non-existent queue index " .. args[2]
				end
			else
				return false, "Expected an integer index into the queue of tasks"
			end
		else
			areas_to_emerge = {}
			return false, "Cleared all queued emerge tasks"
		end
	elseif args[1] == "here" then
		p1, p2 = minetest.get_player_radius_area(player_name, tonumber(args[2]))
		if p1 == nil then
			return false, "Unable to get player " .. player_name .. " position"
		end
		p1 = vector.round(p1)
		p2 = vector.round(p2)
	else
		p1, p2 = minetest.string_to_area(str)
		if p1 == nil then
			return false, "Incorrect area format. Expected: (x1,y1,z1) (x2,y2,z2)"
		end
	end
	return p1, p2
end

local get_max_index = function(p1, p2)
	local test_iterator = spiral_pos_iterator(p1, p2, mapblock_size)
	local i = 0
	while test_iterator() do
		i = i + 1
	end
	return i
end

minetest.register_chatcommand("idle_emerge", {
	params = "() | (here [<radius>]) | (<pos1> <pos2>) | (\"clear\" [<index>])",
	description = "Slowly load (or, if nonexistent, generate) map blocks "
		.. "contained in area pos1 to pos2 (<pos1> and <pos2> must be in parentheses)",
	privs = {server=true},
	func = function(name, param)
		local p1, p2 = parse_range_str(name, param)
		if p1 == false then
			return false, p2
		end
		local iterator = spiral_pos_iterator(p1, p2, mapblock_size)
		table.insert(areas_to_emerge, {
			task = "emerge",
			pos1 = p1,
			pos2 = p2,
			name = name,
			index = 0,
			max_index = get_max_index(p1, p2),
			iterator = iterator
		})
		minetest.chat_send_player(name, "idle_emerge task queued for " .. minetest.pos_to_string(p1)
			.. ", " .. minetest.pos_to_string(p2))
	end,
})

minetest.register_chatcommand("idle_delete", {
	params = "() | (here [<radius>]) | (<pos1> <pos2>) | (\"clear\" [<index>])",
	description = "Slowly delete map blocks contained in area pos1 to pos2 "
		.."(<pos1> and <pos2> must be in parentheses)",
	privs = {server=true},
	func = function(name, param)
		local p1, p2 = parse_range_str(name, param)
		if p1 == false then
			return false, p2
		end
		local iterator = spiral_pos_iterator(p1, p2, mapblock_size)
		table.insert(areas_to_emerge, {
			task = "delete",
			pos1 = p1,
			pos2 = p2,
			name = name,
			index = 0,
			max_index = get_max_index(p1, p2),
			iterator = iterator
		})
		minetest.chat_send_player(name, "idle_delete task queued for " .. minetest.pos_to_string(p1)
			.. ", " .. minetest.pos_to_string(p2))
	end,
})

minetest.register_chatcommand("idle_show_queue", {
	params = "none",
	description = "Display the current idle task queue",
	privs = {server=true},
	func = function(name, param)
		if #areas_to_emerge == 0 then
			minetest.chat_send_player(name, "No tasks queued")
		else
			for i, task in ipairs(areas_to_emerge) do
				local progress
				if task.index == 0 then
					progress = "waiting to start"
				else
					progress = math.floor((task.index/task.max_index) * 100) .. "% done"
				end
				minetest.chat_send_player(name,
					i .. ": " .. task.task .. " from " .. minetest.pos_to_string(task.pos1) .. " to "
					.. minetest.pos_to_string(task.pos2) .. " queued by " .. task.name .. " " .. progress
				)
			end
		end
	end,
})

-- Globalstep loop

local emerging = false
local emerge_delay = 0
--* `action` could be one of the following constant values:
--    * `minetest.EMERGE_CANCELLED`
--    * `minetest.EMERGE_ERRORED`
--    * `minetest.EMERGE_FROM_MEMORY`
--    * `minetest.EMERGE_FROM_DISK`
--    * `minetest.EMERGE_GENERATED`
local emerge_callback
emerge_callback = function(blockpos, action, calls_remaining, param)
	if action == minetest.EMERGE_ERRORED then
		param.error_count = (param.error_count or 0)
		if param.error_count <= 3 then
			param.error_count = param.error_count + 1
			local area = vector.multiply(blockpos, 16)
			minetest.debug("EMERGE_ERRORED for " .. minetest.pos_to_string(area) .. ", retrying " .. param.error_count)
			minetest.emerge_area(area, area, emerge_callback, param)
			return
		end
	end
	emerging = false
	emerge_delay = delay_between_emerge_calls
	if param then
		param.index = param.index + 1
		param.error_count = 0
--		minetest.chat_send_player(param.name, "emerged block " .. param.index .. "   "
--			.. minetest.pos_to_string(vector.multiply(blockpos, 16)))
		save_data()
	end
end

local delete_called = false
local last_ten_delete_dtimes = {}
for i = 1,average_delete_dtime_over do
	table.insert(last_ten_delete_dtimes, 0.1)
end
local delete_dtimes_index = 0
local average_delete_dtime = function()
	local sum = 0
	for _, dtime in ipairs(last_ten_delete_dtimes) do
		sum = sum + dtime
	end
	return sum/average_delete_dtime_over
end

minetest.register_globalstep(function(dtime)
	local first_area = areas_to_emerge[1]
	if delete_called then
		last_ten_delete_dtimes[delete_dtimes_index + 1] = dtime
		delete_dtimes_index = (delete_dtimes_index + 1) % average_delete_dtime_over
		delete_called = false
	end
	
	if not emerging and first_area then
		if check_for_non_admin_players and non_admin_players_present then
			return
		end	
		if emerge_delay > 0 then
			emerge_delay = emerge_delay - dtime
			return
		end
		local target_area = first_area.iterator()
		if target_area then
			local last_chat = first_area.last_chat or 0
			local current_time = minetest.get_gametime()
			if current_time - last_chat > update_user_timer then
				first_area.last_chat = current_time
				local progress =  first_area.index .. "/" .. first_area.max_index .. " ("
					.. math.floor((first_area.index/first_area.max_index) * 100) .. "% done)"
				minetest.chat_send_player(first_area.name, "Idle " .. first_area.task .. " " .. progress)
			end
			if first_area.task == "emerge" then
				emerging = true
				minetest.emerge_area(target_area, target_area, emerge_callback, first_area)
			elseif first_area.task == "delete" then
				-- delete doesn't have a callback function, so we'll have to rely on a timed delay and trust that things are working okay.
				emerge_delay = average_delete_dtime() * delete_time_multiplier + delay_between_emerge_calls
				first_area.index = first_area.index + 1
				delete_called = true
				minetest.delete_area(target_area, target_area)
				save_data()
			end
		else
			minetest.chat_send_player(first_area.name, "finished task " .. first_area.task .. " from " .. minetest.pos_to_string(first_area.pos1) .. " to " .. minetest.pos_to_string(first_area.pos2))
			table.remove(areas_to_emerge, 1) -- FIFO
			save_data()
		end
	end
end)
