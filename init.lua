local areas_to_emerge = {}

local mapgen_chunksize = tonumber(minetest.get_mapgen_setting("chunksize"))
local mapblock_size = mapgen_chunksize * 16

local delay_between_emerge_calls = 1
local check_for_non_admin_players = true

-- adapted from https://stackoverflow.com/questions/398299/looping-in-a-spiral with much modification
local spiral_pos_iterator = function(pos1, pos2, size)
	local minp = vector.divide({x = math.min(pos1.x, pos2.x), y = math.min(pos1.y, pos2.y), z = math.min(pos1.z, pos2.z)}, size)
	local maxp = vector.divide({x = math.max(pos1.x, pos2.x), y = math.max(pos1.y, pos2.y), z = math.max(pos1.z, pos2.z)}, size)
	--minetest.chat_send_all("minp " .. minetest.pos_to_string(minp) .. " maxp " .. minetest.pos_to_string(maxp))
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
	
	return function()
		if y < max_y then
			y = y + 1
			return {x=(x+width_half)*size, y=y*size, z=(z+depth_half)*size}
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
		return {x=(x+width_half)*size, y=y*size, z=(z+depth_half)*size}
	end
end

--* `minetest.emerge_area(pos1, pos2, [callback], [param])`
--    * Queue all blocks in the area from `pos1` to `pos2`, inclusive, to be
--      asynchronously fetched from memory, loaded from disk, or if inexistent,
--      generates them.
--    * If `callback` is a valid Lua function, this will be called for each block
--      emerged.
--    * The function signature of callback is:
--      `function EmergeAreaCallback(blockpos, action, calls_remaining, param)`
--        * `blockpos` is the *block* coordinates of the block that had been
--          emerged.
--        * `action` could be one of the following constant values:
--            * `minetest.EMERGE_CANCELLED`
--            * `minetest.EMERGE_ERRORED`
--            * `minetest.EMERGE_FROM_MEMORY`
--            * `minetest.EMERGE_FROM_DISK`
--            * `minetest.EMERGE_GENERATED`
--        * `calls_remaining` is the number of callbacks to be expected after
--          this one.
--        * `param` is the user-defined parameter passed to emerge_area (or
--          nil if the parameter was absent).


-- Parses a "range" string in the format of "here (number)" or
-- "(x1, y1, z1) (x2, y2, z2)", returning two position vectors
local function parse_range_str(player_name, str)
	local p1, p2
	local args = str:split(" ")
	if args[1] == "here" then
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

minetest.register_chatcommand("idle_emerge", {
	params = "(here [<radius>]) | (<pos1> <pos2>)",
	description = "Load (or, if nonexistent, generate) map blocks "
		.. "contained in area pos1 to pos2 (<pos1> and <pos2> must be in parentheses)",
	privs = {server=true},
	func = function(name, param)
		local p1, p2 = parse_range_str(name, param)
		if p1 == false then
			return false, p2
		end
		table.insert(areas_to_emerge, {pos1 = p1, pos2 = p2, name = name, iterator = spiral_pos_iterator(p1, p2, mapblock_size)})
	end,
})

local emerging = false
local emerge_delay = 0
local emerge_callback = function(blockpos, action, calls_remaining, param)
	emerging = false
	emerge_delay = delay_between_emerge_calls
	if param then
		minetest.chat_send_player(param.name, "emerged " .. minetest.pos_to_string(vector.multiply(blockpos, 16)))
	end
end

minetest.register_globalstep(function(dtime)
	local first_area = areas_to_emerge[1]
	if not emerging and first_area then
		if check_for_non_admin_players then
			local players = minetest.get_connected_players()
			for player in ipairs(players) do
				if not minetest.get_player_privs(player:get_player_name()).server then
					return
				end
			end
		end	
		if emerge_delay > 0 then
			emerge_delay = emerge_delay - dtime
			return
		end
		local target_area = first_area.iterator()
		if target_area then
			emerging = true
			minetest.emerge_area(target_area, target_area, emerge_callback, first_area)
		else
			minetest.chat_send_player(first_area.name, "finished emerging " .. minetest.pos_to_string(first_area.pos1) .. " to " .. minetest.pos_to_string(first_area.pos2))
			table.remove(areas_to_emerge, 1) -- FIFO
		end
	end
end)
