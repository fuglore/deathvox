local mvec3_n_equal = mvector3.not_equal
local mvec3_set = mvector3.set
local mvec3_set_st = mvector3.set_static
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_norm = mvector3.normalize
local mvec3_dir = mvector3.direction
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_div = mvector3.divide
local mvec3_lerp = mvector3.lerp
local mvec3_cpy = mvector3.copy
local mvec3_set_l = mvector3.set_length
local mvec3_dot = mvector3.dot
local mvec3_cross = mvector3.cross
local mvec3_dis = mvector3.distance
local mvec3_rot = mvector3.rotate_with
local math_abs = math.abs
local math_max = math.max
local math_clamp = math.clamp
local math_ceil = math.ceil
local math_floor = math.floor
local temp_vec1 = Vector3()
local temp_vec2 = Vector3()

function NavigationManager:reserve_cover(cover, filter)
	local reserved = cover[self.COVER_RESERVED]

	if reserved then
		cover[self.COVER_RESERVED] = reserved + 1
	else
		cover[self.COVER_RESERVED] = 1
		local reservation = {
			radius = 80, --Changed to 80, reduces overcrowding, maintains aggressiveness.
			position = cover[1],
			filter = filter
		}
		cover[self.COVER_RESERVATION] = reservation

		self:add_pos_reservation(reservation)
	end
end

--no more wall-fucking aaaaaaaaaa
function NavigationManager:find_walls_accross_tracker(from_tracker, accross_vec, angle, nr_rays)
	angle = angle or 180 --Do not touch, used for telling which direction it's looking for.
	local center_pos = from_tracker:field_position()
	nr_rays = math.max(4, nr_rays or 8) --Adding more rays to not screw with the math, no real framerate effect, as far as I could tell.
	local rot_step = angle / (nr_rays - 2) --Even-ing out the math as to not be overly precise, this should help cops not walk straight through fucking walls.
	local rot_offset = (math.random() * 2 - 2) * angle * 0.5
	local ray_rot = Rotation((-angle * 0.5 + rot_offset) - rot_step)
	local vec_to = Vector3(accross_vec.x, accross_vec.y)

	mvec3_rot(vec_to, ray_rot)

	local pos_to = Vector3()

	mrotation.set_yaw_pitch_roll(ray_rot, rot_step, 0, 0)

	local tracker_from, pos_from = nil

	if from_tracker:lost() then
		pos_from = center_pos
	else
		tracker_from = from_tracker
	end

	local ray_params = {
		trace = true,
		tracker_from = tracker_from,
		pos_from = pos_from,
		pos_to = pos_to
	}
	local ray_results = {}
	local i_ray = 1

	while i_ray <= nr_rays do
		mvec3_rot(vec_to, ray_rot)
		mvec3_set(pos_to, vec_to)
		mvec3_add(pos_to, center_pos)

		local hit = self:raycast(ray_params)

		if hit then
			table.insert(ray_results, {
				ray_params.trace[1],
				true
			})
		else
			table.insert(ray_results, {ray_params.trace[1]})
		end

		i_ray = i_ray + 1
	end

	return #ray_results > 0 and ray_results
end
