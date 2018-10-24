function CopActionReload:_play_reload(loop_t, loop_t_multiplier)
	local weap_tweak = self._weapon_unit and self._weapon_unit:base() and self._weapon_unit:base():weapon_tweak_data()

	if weap_tweak and weap_tweak.reload == "looped" then
		local sound_prefix = weap_tweak.sounds.prefix
		local single_reload = sound_prefix == "nagant_npc" or sound_prefix == "ching_npc"
		local loop_amount = not single_reload and weap_tweak.CLIP_AMMO_MAX or 1

		local redir_res = self._ext_movement:play_redirect("reload_looped")

		if redir_res then
			self._looped_reload = true
			self._loop_t = loop_t + (1 * ((0.45 * loop_amount) / loop_t_multiplier))
		else
			cat_print("george", "[CopActionReload:_play_reload_looped] redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		return redir_res
	else
		local redir_res = self._ext_movement:play_redirect("reload")

		if not redir_res then
			cat_print("george", "[CopActionReload:_play_reload] redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		return redir_res
	end
end

function CopActionReload:update_looped(t)
	if self._looped_reload then
		if self._loop_t < t then
			local res = self._ext_movement:play_redirect("reload_looped_exit")

			if res then
				self._looped_reload = nil
			end
		end
	end
end