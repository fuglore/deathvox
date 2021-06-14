local mvec3_dis = mvector3.distance
local mvec3_copy = mvector3.copy

Hooks:PostHook(PlayerManager,"_internal_load","deathvox_on_internal_load",function(self)
--this will send whenever the player respawns, so... hm. 
	if Network:is_server() then 
		deathvox:SyncOptionsToClients()
	else
		deathvox:ResetSessionSettings()
	end
--	Hooks:Call("TCD_OnGameStarted")

	if deathvox:IsTotalCrackdownEnabled() then 
		local grenade = managers.blackmarket:equipped_grenade()
		self:_set_grenade({
			grenade = grenade,
			amount = self:get_max_grenades() --for some reason, in vanilla, spawn amount is math.min()'d with the DEFAULT amount 
		})
	end
end)

function PlayerManager:_chk_fellow_crimin_proximity(unit)
	local players_nearby = 0
		
	local criminals = World:find_units_quick(unit, "sphere", unit:position(), 1500, managers.slot:get_mask("criminals_no_deployables"))

	for _, criminal in ipairs(criminals) do
		players_nearby = players_nearby + 1
	end
		
	if players_nearby <= 0 then
		--log("uhohstinky")
	end
		
	return players_nearby
end

--function written for cd, not vanilla
function PlayerManager:team_upgrade_value_by_level(category, upgrade, level, default)
	local cat = tweak_data.upgrades.values.team[category]
	local upg = cat and cat[upgrade]
	return upg and upg[level] or default
end

--function written for cd, not vanilla
function PlayerManager:team_upgrade_level(category, upgrade, default)
	for peer_id, categories in pairs(self._global.synced_team_upgrades) do
		if categories[category] and categories[category][upgrade] then
			return categories[category][upgrade]
		end
	end

	if not self._global.team_upgrades[category] then
		return default or 0
	end

	if not self._global.team_upgrades[category][upgrade] then
		return default or 0
	end

	return self._global.team_upgrades[category][upgrade]
end


Hooks:PostHook(PlayerManager,"init","tcd_playermanager_init",function(self)
	self._damage_overshield = {}
end)

if deathvox:IsTotalCrackdownEnabled() then
	function PlayerManager:use_messiah_charge()
		--nothing
	end

	function PlayerManager:check_equipment_placement_valid(player, equipment)
		local equipment_data = managers.player:equipment_data_by_name(equipment)

		if not equipment_data then
			return false
		end

		if equipment_data.equipment == "trip_mine" or equipment_data.equipment == "ecm_jammer" then
			return player:equipment():valid_look_at_placement(tweak_data.equipments[equipment_data.equipment]) and true or false
		elseif equipment_data.equipment == "sentry_gun" or equipment_data.equipment == "ammo_bag" or equipment_data.equipment == "sentry_gun_silent" or equipment_data.equipment == "doctor_bag" or equipment_data.equipment == "first_aid_kit" or equipment_data.equipment == "bodybags_bag" then
			local result,revivable_unit = player:equipment():valid_shape_placement(equipment_data.equipment, tweak_data.equipments[equipment_data.equipment])
			return result and true or false,revivable_unit
		elseif equipment_data.equipment == "armor_kit" then
			return player:equipment():valid_shape_placement(equipment_data.equipment,tweak_data.equipments[equipment_data.equipment]) and true or false
		end

		return player:equipment():valid_placement(tweak_data.equipments[equipment_data.equipment]) and true or false
	end
	
	function PlayerManager:damage_reduction_skill_multiplier(damage_type)
		local multiplier = 1
		
		if self._melee_stance_dr_t then
			multiplier = multiplier * 0.8
		end
		
		multiplier = multiplier * self:upgrade_value("player", "infiltrator_passive_DR", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered_strong", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_close_contact", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "revived_damage_resist", 1)
		multiplier = multiplier * self:upgrade_value("player", "damage_dampener", 1)
		multiplier = multiplier * self:upgrade_value("player", "health_damage_reduction", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "first_aid_damage_reduction", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "revive_damage_reduction", 1)
		multiplier = multiplier * self:get_hostage_bonus_multiplier("damage_dampener")
		multiplier = multiplier * self._properties:get_property("revive_damage_reduction", 1)
		multiplier = multiplier * self._temporary_properties:get_property("revived_damage_reduction", 1)
		multiplier = multiplier + self:team_upgrade_value("crewchief","passive_damage_resistance",1)
		
		if self:get_property("armor_plates_active") then 
			multiplier = multiplier * tweak_data.upgrades.armor_plates_dmg_reduction
		end
		
		local dmg_red_mul = self:team_upgrade_value("damage_dampener", "team_damage_reduction", 1)

		local player = self:local_player()
		
		if player:character_damage():get_real_armor() > 0 then
			multiplier = multiplier * self:upgrade_value("player", "armorer_ironclad", 1)
		end
		
		local team_upgrade_level = managers.player:team_upgrade_level("player","civilian_hostage_aoe_damage_resistance")
		if team_upgrade_level > 0 then 
			--this whole mess is for the Leverage skill in Taskmaster
			local player_pos = player:movement():m_pos()
			
			local hostage_range_close,hostage_dmg_resist_1 = unpack(managers.player:team_upgrade_value_by_level("player","civilian_hostage_aoe_damage_resistance",1,{}))
			local hostage_range_far,hostage_dmg_resist_2
			
			if team_upgrade_level == 2 then 
				hostage_range_far,hostage_dmg_resist_2 = unpack(managers.player:team_upgrade_value_by_level("player","civilian_hostage_aoe_damage_resistance",2,{}))
			end
			
			local near_hostage_close,near_hostage_far
			for _,hostage_unit in pairs(World:find_units_quick("sphere",player_pos,hostage_range_far or hostage_range_close,21,22)) do --managers.slot:get_mask("civilians") fails because tied civs are moved out of slot 22 and back into slot upon being moved
				if managers.enemy:is_civilian(hostage_unit) and hostage_unit:brain():is_tied() then 
					
					if team_upgrade_level == 2 then 
						local hostage_pos = hostage_unit:movement():m_pos()
						local hostage_distance = mvec3_dis(player_pos,hostage_pos)
						if hostage_distance <= hostage_range_close then 
							--within close distance is, by definition, also within far distance
							near_hostage_close = true
							near_hostage_far = true
							break
						elseif not near_hostage_far and hostage_distance <= hostage_range_far then 
							--if hasn't already done far hostage check
							near_hostage_far = true
						end
					elseif team_upgrade_level == 1 then 
						near_hostage_close = true
						--only one possible range for basic skill,
						--so we can stop checking hostages now
						break
					end
				end
			end
			
			local hostage_dmg_resist = 1
			
			if near_hostage_far then 
				hostage_dmg_resist = hostage_dmg_resist + hostage_dmg_resist_2
			end
			if near_hostage_close then 
				hostage_dmg_resist = hostage_dmg_resist + hostage_dmg_resist_1
			end
			
			multiplier = multiplier * hostage_dmg_resist
		end
		
		if self:has_category_upgrade("player", "passive_damage_reduction") then
			local health_ratio = self:player_unit():character_damage():health_ratio()
			local min_ratio = self:upgrade_value("player", "passive_damage_reduction")

			if health_ratio < min_ratio then
				dmg_red_mul = dmg_red_mul - (1 - dmg_red_mul)
			end
		end

		multiplier = multiplier * dmg_red_mul

		if damage_type == "melee" then
			multiplier = multiplier * managers.player:upgrade_value("player", "melee_damage_dampener", 1)
		end

		local current_state = self:get_current_state()

		if current_state and current_state:_interacting() then
			multiplier = multiplier * managers.player:upgrade_value("player", "interacting_damage_multiplier", 1)
		end


		return multiplier
	end

	PlayerManager.tcd_orig_health_regen = PlayerManager.health_regen
	function PlayerManager:health_regen(...)
		local health_regen = self:tcd_orig_health_regen(...)
		health_regen = health_regen + self:team_upgrade_value("crewchief","passive_health_regen",0)
		health_regen = health_regen + self:upgrade_value("player", "muscle_health_regen", 0)
		return health_regen 
	end

	--same as vanilla but disabled HUD element in order to prevent conflicting with damage overshield mechanic
	--if/when the actual absorption mechanic is overhauled, this function (and its accompanying HUD element) may also need to be revisited
	function PlayerManager:set_damage_absorption(key, value)
		self._damage_absorption[key] = value and Application:digest_value(value, true) or nil

--		managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:damage_absorption())
	end
	function PlayerManager:update_cocaine_hud()
		if managers.hud then
--			managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:damage_absorption())
		end
	end
	

	Hooks:PostHook(PlayerManager,"check_skills","deathvox_check_cd_skills",function(self)
		
		if self:has_category_upgrade("class_throwing","projectile_charged_damage_mul") then
			self:set_property("charged_throwable_damage_bonus",0)
		end
		
		if self:has_category_upgrade("class_throwing","throwing_boosts_melee_loop") then
			local duration,value = unpack(self:upgrade_value("class_throwing","throwing_boosts_melee_loop",{0,0}))
			self._message_system:register(Message.OnEnemyShot,"proc_shuffle_cut_basic",function(unit,attack_data)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
				if not (weapon_base and weapon_base.is_weapon_class and weapon_base:is_weapon_class("class_throwing") and weapon_base._thrower_unit and weapon_base._thrower_unit == player) then 
					return
				end
				self:activate_temporary_property("shuffle_cut_melee_bonus_damage",duration,value)
			end)
		end
		
		if self:has_category_upgrade("class_melee","melee_boosts_throwing_loop") then 
			local duration,value = unpack(self:upgrade_value("class_melee","melee_boosts_throwing_loop",{0,0}))
			Hooks:Add("OnPlayerMeleeHit","proc_shuffle_cut_aced",function(character_unit,col_ray,action_data,defense_data,t)
				self:activate_temporary_property("shuffle_cut_throwing_bonus_damage",duration,value)
			end)
		end
	
		
		if self:has_category_upgrade("weapon","xbow_headshot_instant_reload") then 
		
			self._message_system:register(Message.OnLethalHeadShot,"proc_good_hunting_aced",
				function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_category("crossbow") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					weapon_base:set_ammo_remaining_in_clip(weapon_base:calculate_ammo_max_per_clip())
					for i,selection in pairs(player:inventory():available_selections()) do 
						managers.hud:set_ammo_amount(i, selection.unit:base():ammo_info())
					end
				end
			)
		end
		
	
		if self:has_category_upgrade("player","melee_hit_speed_boost") then
			Hooks:Add("OnPlayerMeleeHit","cd_proc_butterfly_bee_aced",
				function(hit_unit,col_ray,action_data,defense_data,t)
					if hit_unit and not managers.enemy:is_civilian(hit_unit) then 
						managers.player:activate_temporary_property("float_butterfly_movement_speed_multiplier",unpack(managers.player:upgrade_value("player","melee_hit_speed_boost",{0,0})))
					end
				end
			)
		end
		
		if self:has_category_upgrade("player","escape_plan") then 
			Hooks:Add("OnPlayerShieldBroken","cd_proc_escape_plan",
				function(player_unit)
					if alive(player_unit) then 
						local movement = player_unit:movement()
						
						local escape_plan_data = managers.player:upgrade_value("player","escape_plan",{0,0,0,0})
						local stamina_restored_percent = escape_plan_data[1]
						local sprint_speed_bonus = escape_plan_data[2]
						local escape_plan_duration = escape_plan_data[3]
						local move_speed_bonus = escape_plan_data[4]
						movement:_change_stamina(movement:_max_stamina() * stamina_restored_percent)
						self:activate_temporary_property("escape_plan_speed_bonus",escape_plan_duration,{sprint_speed_bonus,move_speed_bonus})
					end
				end
			)
		end
		
		if self:has_category_upgrade("saw","consecutive_damage_bonus") then 
			self:set_property("rolling_cutter_aced_stacks",0)
			
			Hooks:Register("OnProcRollingCutterBasic")
			Hooks:Add("OnProcRollingCutterBasic","AddToRollingCutterStacks",
				function(stack_add)
					stack_add = stack_add or 1

					local max_stacks = self:upgrade_value("saw","consecutive_damage_bonus",{0,0})[2]
					local new_stacks = self:get_property("rolling_cutter_aced_stacks",0) + stack_add
				
					self:set_property("rolling_cutter_aced_stacks", math.min(new_stacks,max_stacks))
				end
			)
		end
	
		if self:has_category_upgrade("class_heavy","collateral_damage") then 
			local slot_mask = managers.slot:get_mask("enemies")
			
			local collateral_damage_data = self:upgrade_value("class_heavy","collateral_damage",{0,0})
			local damage_mul = collateral_damage_data[1]
			local radius = collateral_damage_data[2]
			
			self._message_system:register(Message.OnWeaponFired,"proc_collateral_damage",
				function(weapon_unit,result)
				
					--this is called on any weapon firing,
					--so this needs checks to make sure that the weapon class is heavy
					--and that the user_unit is the player
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					if #result.rays == 0 then 
						return
					end
					
					local first_ray = result.rays[1] 
					local from = player:movement():current_state():get_fire_weapon_position()
					--sort of cheating here by assuming the origin of the ray is the current fire position
					local dir = mvec3_copy(first_ray.ray)
					local to
					local hits = {}
					for n,ray in ipairs(result.rays) do 
						local damage = weapon_base:_get_current_damage()
						local dir = ray.ray or Vector3()
						if ray.damage_result then 
							local attack_data = ray.damage_result.attack_data or {}
							damage = attack_data and attack_data.damage_raw or damage
						end
						damage = damage * damage_mul
						if ray.unit then
							hits[ray.unit:key()] = {
								disabled = true
							}
						end
						to = mvec3_copy(ray.hit_position or ray.position or Vector3())
--						Draw:brush(Color.red:with_alpha(0.1),5):sphere(from,50)
--						Draw:brush(Color.blue:with_alpha(0.1),5):sphere(to,50)
--						Draw:brush(Color(1,n / #result.rays,1):with_alpha(0.1),5):cylinder(from,to,radius)
						local grazed_enemies = World:raycast_all("ray", from, to, "sphere_cast_radius", radius, "disable_inner_ray", "slot_mask", slot_mask)
						for _,hit in pairs(grazed_enemies) do 
							local hit_data = hits[hit.unit:key()]
							local add_hit = not (hit_data and hit_data.disabled)
							if add_hit and hit_data and hit_data.damage < damage then 
								add_hit = false
							end
							if add_hit and hit.unit then 
								hits[hit.unit:key()] = {
									unit = hit.unit,
									damage = damage,
									attacker_unit = player,
									pos = mvec3_copy(from),
									attack_dir = mvec3_copy(dir)
								}
							end
							--collect hits here to prevent the same enemy from being hit by multiple rays, in the case of penetrating or ricochet shots
						end
						
						from = mvec3_copy(to)
					end

					
					for _,hit_data in pairs(hits) do 
						if not hit_data.disabled then 
							local enemy = hit_data.unit
							if enemy and enemy.character_damage and enemy:character_damage() then 
								enemy:character_damage():damage_simple({
									variant = "graze",
									damage = hit_data.damage,
									attacker_unit = hit_data.attacker_unit,
									pos = hit_data.pos,
									attack_dir = hit_data.attack_dir
								})
							end
						end
					end
					
				end
			)
		end
		
		if self:has_category_upgrade("class_heavy","death_grips_stacks") then
			self:set_property("current_death_grips_stacks",0)
			self._message_system:register(Message.OnEnemyKilled,"proc_death_grips",
				function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					local death_grips_data = self:upgrade_value("class_heavy","death_grips_stacks",{0,0})
					self:set_property("current_death_grips_stacks",math.min(self:get_property("current_death_grips_stacks") + 1,death_grips_data[2]))
					managers.enemy:remove_delayed_clbk("death_grips_stacks_expire",true)
					managers.enemy:add_delayed_clbk("death_grips_stacks_expire",
						function()
							self:set_property("current_death_grips_stacks",0)
						end,
						Application:time() + death_grips_data[1]
					)
				end
			)
		end
		
		if self:has_category_upgrade("class_heavy","lead_farmer") then 
			self:set_property("current_lead_farmer_stacks",0)
			self._message_system:register(Message.OnEnemyKilled,"proc_lead_farmer",
				function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_lead_farmer_stacks",1)
				end
			)
			
			Hooks:Add("OnPlayerReloadComplete","on_player_reloaded_consume_lead_farmer",
				--Message.OnPlayerReload is called when reload STARTS, which is before the reload mul is calculated.
				--so it's pretty useless to reset stacks from that message event.
				function(weapon_unit)
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base:is_weapon_class("class_heavy") then 
						managers.player:set_property("current_lead_farmer_stacks",0)
					end
				end
			)
		end
		
		if self:has_category_upgrade("class_shotgun","shell_games_reload_bonus") then
			self:set_property("shell_games_rounds_loaded",0)
		end
		if self:has_category_upgrade("weapon", "making_miracles_basic") then
			self:set_property("making_miracles_stacks",0)
			self._message_system:register(Message.OnHeadShot,"proc_making_miracles_basic",
				function()
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon = player:inventory():equipped_unit():base()
					if not weapon:is_weapon_class("class_rapidfire") then 
						return
					end
					
					self:add_to_property("making_miracles_stacks",1) --add one stack
					managers.enemy:remove_delayed_clbk("making_miracles_stack_expire",true) --reset timer if active
					managers.enemy:add_delayed_clbk("making_miracles_stack_expire", --add 4-second removal timer for stacks
						function()
							self:set_property("making_miracles_stacks",0)
						end,
						Application:time() + self:upgrade_value("weapon","making_miracles_basic",{0,0})[2]
					)
				end
			)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"proc_making_miracles_basic")
		end
		
		if self:has_category_upgrade("weapon","making_miracles_aced") then 
			self._message_system:register(Message.OnLethalHeadShot,"proc_making_miracles_aced",
				function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_rapidfire") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					self:add_to_property("making_miracles_stacks",1)
				end
			)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"proc_making_miracles_aced")
		end
		self:set_property("current_point_and_click_stacks",0)
		if self:has_category_upgrade("player","point_and_click_stacks") then 
			Hooks:Add("TCD_Create_Stack_Tracker_HUD","TCD_CreatePACElement",function(hudtemp)
			 --check_skills() is called before the hud is created so it must instead call on an event
			
				--create buff-specific hud element; todo create a hudbuff class to handle this
				--this is temporary until more of the core systems are done, and then i can dedicate more time 
				--to creating a buff tracker system + hud elements 
				--		-offy\
				
--				local hudtemp = managers.hud and managers.hud._hud_temp and managers.hud._hud_temp._hud_panel
				if hudtemp and alive(hudtemp) then
					if alive(hudtemp:child("point_and_click_tracker")) then 
						BeardLib:RemoveUpdater("update_tcd_buffs_hud")
						hudtemp:remove(hudtemp:child("point_and_click_tracker"))
					end
					local trackerhud = hudtemp:panel({
						name = "point_and_click_tracker",
						w = 100,
						h = 100
					})
					trackerhud:set_position((hudtemp:w() - trackerhud:w()) / 2,450)
					local debug_trackerhud = trackerhud:rect({
						name = "debug",
						color = Color.red,
						visible = false,
						alpha = 0.1
					})
					local icon_size = 64
					local icon_x,icon_y = unpack(tweak_data.skilltree.skills.triathlete.icon_xy) --triathlete is the skill that point and click replaced
--					local skill_atlas = "guis/textures/pd2/skilltree/icons_atlas"
					local skill_atlas_2 = "guis/textures/pd2/skilltree_2/icons_atlas_2"
--					local perkdeck_atlas = "guis/textures/pd2/specialization/icons_atlas"	

					local icon = trackerhud:bitmap({
						name = "icon",
						texture = skill_atlas_2,
						texture_rect = {icon_x * 80,icon_y * 80,80,80},
						alpha = 0.9,
--						x = (trackerhud:w() - icon_size) / 2,
--						y = 0,
						w = icon_size,
						h = icon_size
					})
					icon:set_center(trackerhud:w()/2,trackerhud:h()/2)
					local stack_count = trackerhud:text({
						name = "text",
						text = "0",
						font = tweak_data.hud.medium_font,
						font_size = 16,
						align = "center",
						color = Color.white,
						vertical = "bottom"
					})
					
					BeardLib:AddUpdater("update_tcd_buffs_hud",function(t,dt)
						if alive(stack_count) then 
							stack_count:set_text(self:get_property("current_point_and_click_stacks",0))
							if managers.enemy:is_clbk_registered("point_and_click_on_shot_missed") and alive(icon) then 
								icon:set_color(Color(math.sin(t * 300 * math.pi),0,0))
							else
								icon:set_color(Color.white)
							end
						end
					end,false)
				end
			end)
			
			self._message_system:register(Message.OnEnemyShot,"proc_point_and_click",function(unit,attack_data)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stacks",0))
			end)
			if self:has_category_upgrade("player","point_and_click_stack_from_kill") then 
				self._message_system:register(Message.OnEnemyKilled,"proc_investment_returns_basic",function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stack_from_kill",0))
				end)
			else
				self._message_system:unregister(Message.OnEnemyKilled,"proc_investment_returns_basic")
			end
			
			if self:has_category_upgrade("player","point_and_click_stack_from_headshot_kill") then 
				self._message_system:register(Message.OnLethalHeadShot,"proc_investment_returns_aced",function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stack_from_headshot_kill",0))
				end)
			else
				self._message_system:unregister(Message.OnLethalHeadShot,"proc_investment_returns_aced")
			end
			
			if self:has_category_upgrade("player","point_and_click_stack_mulligan") then 
				self._message_system:register(Message.OnEnemyKilled,"proc_mulligan_reprieve",function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					managers.enemy:remove_delayed_clbk("point_and_click_on_shot_missed",true)
				end)
			else
				self._message_system:unregister(Message.OnEnemyKilled,"proc_mulligan_reprieve")
			end
			
			self._message_system:register(Message.OnWeaponFired,"clear_point_and_click_stacks",function(weapon_unit,result)
				if result and result.hit_enemy then
					return
				end
				
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				
				local weapon_base = weapon_unit and weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				
				if (self:get_property("current_point_and_click_stacks",0) > 0) and not managers.enemy:is_clbk_registered("point_and_click_on_shot_missed") then 
					managers.enemy:add_delayed_clbk("point_and_click_on_shot_missed",callback(self,self,"set_property","current_point_and_click_stacks",0),
						Application:time() + self:upgrade_value("player","point_and_click_stack_mulligan",0)
					)
				end
			end)
		else
			self._message_system:unregister(Message.OnEnemyShot,"proc_point_and_click")
			self._message_system:unregister(Message.OnWeaponFired,"clear_point_and_click_stacks")
		end
		
		if self:has_category_upgrade("weapon","magic_bullet") then 
			self._message_system:register(Message.OnLethalHeadShot,"proc_magic_bullet",function(attack_data)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = attack_data.weapon_unit and attack_data.weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				
				if not weapon_base:ammo_full() then 
					local magic_bullet_level = self:upgrade_level("weapon","magic_bullet",0)
					local clip_current = weapon_base:get_ammo_remaining_in_clip()
					local clip_max = weapon_base:get_ammo_max_per_clip()
					local weapon_index = self:equipped_weapon_index()
					if (magic_bullet_level == 2) and (clip_current < clip_max) then
						weapon_base:set_ammo_remaining_in_clip(math.min(clip_max,clip_current + self:upgrade_value("weapon","magic_bullet",0)))
					end
					weapon_base:add_ammo_to_pool(self:upgrade_value("weapon","magic_bullet",0),self:equipped_weapon_index())
					managers.hud:set_ammo_amount(weapon_index, weapon_base:ammo_info())
					player:sound():play("pickup_ammo")
				end
			end)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"proc_magic_bullet")
		end
		
		if self:has_category_upgrade("player","throwable_regen") then 
			self._improv_expert_basic_throwable_regen_kills = 0
			local kills_to_regen_grenade,grenades_replenished = unpack(self:upgrade_value("player","throwable_regen",{0,0}))
			if kills_to_regen_grenade > 0 then 
				self._message_system:register(Message.OnEnemyKilled,"proc_improv_expert_basic",function(weapon_unit,variant,killed_unit)

					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					
					local grenade_id = managers.blackmarket:equipped_grenade()
					local ptd = tweak_data.blackmarket.projectiles
					local gtd = ptd and grenade_id and ptd[grenade_id]
					local is_a_grenade = gtd.is_a_grenade
					
					self._improv_expert_basic_throwable_regen_kills = self._improv_expert_basic_throwable_regen_kills + 1
					if self._improv_expert_basic_throwable_regen_kills >= kills_to_regen_grenade then 
						if is_a_grenade then 
							self:add_grenade_amount(grenades_replenished,true)
						end
						self._improv_expert_basic_throwable_regen_kills = 0
					end
					
				end)
			end
		end
		
	end)
	
	function PlayerManager:movement_speed_multiplier(speed_state, bonus_multiplier, upgrade_level, health_ratio)
		local multiplier = 1
		local armor_penalty = self:mod_movement_penalty(self:body_armor_value("movement", upgrade_level, 1))
		
		multiplier = multiplier + armor_penalty - 1
		
		if multiplier < 1.05 then
			local diff = 1.05 - multiplier
			
			diff = diff * self:upgrade_value("player", "armorer_armor_pen_mul", 1)
			
			multiplier = 1.05 - diff
			
			--log("speed_mul: " .. tostring(multiplier))
		end
		
		if bonus_multiplier then
			multiplier = multiplier + bonus_multiplier - 1
		end

		multiplier = multiplier + self:get_temporary_property("float_butterfly_movement_speed_multiplier",0)
		
		local escape_plan_status = self:get_temporary_property("escape_plan_speed_bonus",false)
		local escape_plan_sprint_bonus = 0
		local escape_plan_movement_bonus = 0

		if escape_plan_status and type(escape_plan_status) == "table" then 
			escape_plan_sprint_bonus = escape_plan_status[1] or escape_plan_sprint_bonus
			escape_plan_movement_bonus = escape_plan_status[2] or escape_plan_movement_bonus
		end
		
		if speed_state then
			multiplier = multiplier + self:upgrade_value("player", speed_state .. "_speed_multiplier", 1) - 1
			
			if speed_state == "run" then 
				multiplier = multiplier + escape_plan_sprint_bonus
			end
		end
		multiplier = multiplier + escape_plan_movement_bonus

		multiplier = multiplier + self:get_hostage_bonus_multiplier("speed") - 1
		multiplier = multiplier + self:upgrade_value("player", "movement_speed_multiplier", 1) - 1

		if self:num_local_minions() > 0 then
			multiplier = multiplier + self:upgrade_value("player", "minion_master_speed_multiplier", 1) - 1
		end

		if self:has_category_upgrade("player", "secured_bags_speed_multiplier") then
			local bags = 0
			bags = bags + (managers.loot:get_secured_mandatory_bags_amount() or 0)
			bags = bags + (managers.loot:get_secured_bonus_bags_amount() or 0)
			multiplier = multiplier + bags * (self:upgrade_value("player", "secured_bags_speed_multiplier", 1) - 1)
		end

		if managers.player:has_activate_temporary_upgrade("temporary", "berserker_damage_multiplier") then
			multiplier = multiplier * (tweak_data.upgrades.berserker_movement_speed_multiplier or 1)
		end

		if health_ratio then
			local damage_health_ratio = self:get_damage_health_ratio(health_ratio, "movement_speed")
			multiplier = multiplier * (1 + managers.player:upgrade_value("player", "movement_speed_damage_health_ratio_multiplier", 0) * damage_health_ratio)
		end

		local damage_speed_multiplier = managers.player:temporary_upgrade_value("temporary", "damage_speed_multiplier", managers.player:temporary_upgrade_value("temporary", "team_damage_speed_multiplier_received", 1))
		multiplier = multiplier * damage_speed_multiplier
		return multiplier
	end

	function PlayerManager:get_max_grenades(grenade_id)
		local eq_gr,eq_max = managers.blackmarket:equipped_grenade()
		local max_amount = 0
		if not grenade_id then 
			grenade_id = eq_gr
			max_amount = eq_max
		end
		local ptd = tweak_data.blackmarket.projectiles
		local gtd = ptd and grenade_id and ptd[grenade_id]
--		local max_amount = tweak_data:get_raw_value("blackmarket", "projectiles", grenade_id, "max_amount") or 0
		if gtd then 
			max_amount = gtd.max_amount or max_amount
			if gtd.throwable then
				if gtd.is_a_grenade then 
					max_amount = math.round(max_amount * self:upgrade_value("player","grenades_amount_increase_mul",1))
				else
					max_amount = math.round(max_amount * self:upgrade_value("class_throwing","throwing_amount_increase_mul",1))
				end
			end
			max_amount = managers.modifiers:modify_value("PlayerManager:GetThrowablesMaxAmount", max_amount)
		end
		return max_amount
	end

end


		--The overshield mechanic is only used in Total Crackdown ((TCD), but its methods are present outside of TCD so that two versions of player damage for any given damage type (damage_bullet, damage_explosion, damage_melee, etc) aren't necessary for TCD and normal Crackdown

--new overshield mechanic whose sources are separate like damage absorption, and provides flat damage reduction like absorption, except the amount of damage you take is subtracted from your overshield amount.
--....so, like overshield in basically any other video game.
function PlayerManager:set_damage_overshield(id,amount,params,skip_update)
	local overshield_data
	
	for i,_overshield_data in pairs(self._damage_overshield) do 
		if _overshield_data.id == id then 
			overshield_data = _overshield_data
			break
		end
	end
	if not overshield_data then 
		local i = #self._damage_overshield + 1
		self._damage_overshield[i] = {}
		overshield_data = self._damage_overshield[i]
	end
	
	overshield_data.amount = amount
	if params then 
		if params.depleted_callback then 
			overshield_data.depleted_callback = params.depleted_callback
		end
	end
	
	--none of that Application:digest_value() nonsense here
	if not skip_update then 
		--skip_update should ideally be used when setting multiple damage overshields at once,
		--since the get_damage_overshield_total() func involves iterating over a table,
		--so it is somewhat inefficient
		self:sort_damage_overshield()
	end
end

--completely unregister a damage overshield
function PlayerManager:remove_damage_overshield(key,skip_update)
	self._damage_overshield[key] = nil
	if not skip_update then 
		self:sort_damage_overshield()
	end
end

--subtracts incoming damage from overshields, and returns remaining damage
--smaller overshield amounts are consumed first
function PlayerManager:consume_damage_overshield(damage)
	--overshield 
	if damage <= 0 then 
		return damage
	end
	local queued_remove = {}
	for i,overshield_data in ipairs(self._damage_overshield) do 
		if damage <= 0 then 
			break
		end
		local prev_overshield_amount = overshield_data.amount
		local new_overshield_amount = math.max(overshield_data.amount - damage,0)
		overshield_data.amount = new_overshield_amount
		local blocked_damage = prev_overshield_amount - new_overshield_amount
		if new_overshield_amount <= 0 then 
			if type(overshield_data.depleted_callback) == "function" then 
				overshield_data.depleted_callback(damage,blocked_damage)
				--note that this callback is performed before the player damage calculation is complete!
			end
			table.insert(queued_remove,i)
		end
		damage = damage - blocked_damage
	end
	
	if #queued_remove > 0 then 
		for i=#queued_remove,1,-1 do 
			table.remove(self._damage_overshield,queued_remove[i])
		end
	end
	self:sort_damage_overshield()
	
	return damage
end

function PlayerManager:sort_damage_overshield()
	table.sort(self._damage_overshield,function(a,b)
		return a.amount > b.amount
	end)
	
	managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:get_damage_overshield_total())
end

function PlayerManager:get_damage_overshield_total()
	local sum = 0
	for k,v in pairs(self._damage_overshield) do 
		sum = sum + v.amount
	end
	return sum
end

function PlayerManager:health_skill_addend()
	local addend = 0
	addend = addend + self:upgrade_value("team", "crew_add_health", 0)
	
	if self._beach_health_points then
		addend = addend + self._beach_health_points
	end
	
	if table.contains(self._global.kit.equipment_slots, "thick_skin") then
		addend = addend + self:upgrade_value("player", "thick_skin", 0)
	end

	return addend
end

function PlayerManager:health_skill_multiplier()
	local multiplier = 1
	multiplier = multiplier + self:upgrade_value("player", "health_multiplier", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "muscle_health_mul", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "passive_health_multiplier", 1) - 1
	multiplier = multiplier + self:team_upgrade_value("health", "passive_multiplier", 1) - 1
	multiplier = multiplier + self:get_hostage_bonus_multiplier("health") - 1
	multiplier = multiplier - self:upgrade_value("player", "health_decrease", 0)

	if self:num_local_minions() > 0 then
		multiplier = multiplier + self:upgrade_value("player", "minion_master_health_multiplier", 1) - 1
	end

	return multiplier
end

function PlayerManager:body_armor_value(category, override_value, default)
	local armor_data = tweak_data.blackmarket.armors[managers.blackmarket:equipped_armor(true, true)]
	
	if category == "damage_shake" then
		local shake = self:upgrade_value_by_level("player", "body_armor", category, {})[override_value or armor_data.upgrade_level] or default or 0
		
		shake = shake * self:upgrade_value("player", "armorer_shake_mul", 1)
		
		return shake
	end
	
	return self:upgrade_value_by_level("player", "body_armor", category, {})[override_value or armor_data.upgrade_level] or default or 0
end

local crook_armor_types = {
	level_2 = true,
	level_3 = true,
	level_4 = true
}

function PlayerManager:body_armor_skill_multiplier(override_armor)
	local multiplier = 1
	multiplier = multiplier + self:upgrade_value("player", "armorer_armor_mul", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "tier_armor_multiplier", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "passive_armor_multiplier", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "armor_multiplier", 1) - 1
	multiplier = multiplier + self:team_upgrade_value("armor", "multiplier", 1) - 1
	multiplier = multiplier + self:get_hostage_bonus_multiplier("armor") - 1
	multiplier = multiplier + self:upgrade_value("player", "perk_armor_loss_multiplier", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", tostring(override_armor or managers.blackmarket:equipped_armor(true, true)) .. "_armor_multiplier", 1) - 1
	multiplier = multiplier + self:upgrade_value("player", "chico_armor_multiplier", 1) - 1

	return multiplier
end

function PlayerManager:body_armor_skill_addend(override_armor)
	local addend = 0
	addend = addend + self:upgrade_value("player", tostring(override_armor or managers.blackmarket:equipped_armor(true, true)) .. "_armor_addend", 0)

	if self:has_category_upgrade("player", "armor_increase") then
		local health_multiplier = self:health_skill_multiplier()
		local max_health = (PlayerDamage._HEALTH_INIT + self:health_skill_addend()) * health_multiplier
		addend = addend + max_health * self:upgrade_value("player", "armor_increase", 1)
	end
	
	if self:has_category_upgrade("player", "crook_vest_armor_addend") then
		local armor = tostring(override_armor or managers.blackmarket:equipped_armor(true, true))

		if crook_armor_types[armor] then
			addend = addend + self:upgrade_value("player", "crook_vest_armor_addend", 0)
		end
	end

	addend = addend + self:upgrade_value("team", "crew_add_armor", 0)

	return addend
end

function PlayerManager:body_armor_regen_multiplier(moving, health_ratio)
	local multiplier = 1
	multiplier = multiplier * self:upgrade_value("player", "armorer_armor_regen_mul", 1)
	multiplier = multiplier * self:upgrade_value("player", "hitman_armor_regen", 1)
	
	
	if self:has_category_upgrade("player", "crook_vest_armor_regen") then
		local armor = tostring(override_armor or managers.blackmarket:equipped_armor(true, true))
		
		if crook_armor_types[armor] then
			multiplier = multiplier * self:upgrade_value("player", "crook_vest_armor_regen", 0)
		end
	end
	
	--log("regen_mul: " .. tostring(multiplier) .. "")
	multiplier = multiplier * self:upgrade_value("player", "armor_regen_timer_multiplier_tier", 1)
	multiplier = multiplier * self:upgrade_value("player", "armor_regen_timer_multiplier", 1)
	multiplier = multiplier * self:upgrade_value("player", "armor_regen_timer_multiplier_passive", 1)
	multiplier = multiplier * self:team_upgrade_value("armor", "regen_time_multiplier", 1)
	multiplier = multiplier * self:team_upgrade_value("armor", "passive_regen_time_multiplier", 1)
	multiplier = multiplier * self:upgrade_value("player", "perk_armor_regen_timer_multiplier", 1)

	if not moving then
		multiplier = multiplier * managers.player:upgrade_value("player", "armor_regen_timer_stand_still_multiplier", 1)
	end

	if health_ratio then
		local damage_health_ratio = self:get_damage_health_ratio(health_ratio, "armor_regen")
		multiplier = multiplier * (1 - managers.player:upgrade_value("player", "armor_regen_damage_health_ratio_multiplier", 0) * damage_health_ratio)
	end

	return multiplier
end

function PlayerManager:skill_dodge_chance(running, crouching, on_zipline, override_armor, detection_risk)
	local chance = self:upgrade_value("player", "passive_dodge_chance", 0)
	local dodge_shot_gain = self:_dodge_shot_gain()

	for _, smoke_screen in ipairs(self._smoke_screen_effects or {}) do
		if smoke_screen:is_in_smoke(self:player_unit()) then
			if smoke_screen:mine() then
				chance = chance * self:upgrade_value("player", "sicario_multiplier", 1)
				dodge_shot_gain = dodge_shot_gain * self:upgrade_value("player", "sicario_multiplier", 1)
			else
				chance = chance + smoke_screen:dodge_bonus()
			end
		end
	end

	chance = chance + dodge_shot_gain
	chance = chance + self:upgrade_value("player", "tier_dodge_chance", 0)
	chance = chance + self:upgrade_value("player", "rogue_dodge_add", 0)

	if running then
		chance = chance + self:upgrade_value("player", "run_dodge_chance", 0)
	end

	if crouching then
		chance = chance + self:upgrade_value("player", "crouch_dodge_chance", 0)
	end

	if on_zipline then
		chance = chance + self:upgrade_value("player", "on_zipline_dodge_chance", 0)
	end

	local detection_risk_add_dodge_chance = managers.player:upgrade_value("player", "detection_risk_add_dodge_chance")
	chance = chance + self:get_value_from_risk_upgrade(detection_risk_add_dodge_chance, detection_risk)
	
	if self:has_category_upgrade("player", "crook_vest_dodge_addend") then
		local armor = tostring(override_armor or managers.blackmarket:equipped_armor(true, true))
		
		if crook_armor_types[armor] then
			chance = chance + self:upgrade_value("player", "crook_vest_dodge_addend", 0)
		end
	end
	
	chance = chance + self:upgrade_value("player", tostring(override_armor or managers.blackmarket:equipped_armor(true, true)) .. "_dodge_addend", 0)
	chance = chance + self:upgrade_value("team", "crew_add_dodge", 0)
	chance = chance + self:temporary_upgrade_value("temporary", "pocket_ecm_kill_dodge", 0)

	return chance
end

function PlayerManager:on_killshot(killed_unit, variant, headshot, weapon_id)
	local player_unit = self:player_unit()

	if not player_unit then
		return
	end

	if CopDamage.is_civilian(killed_unit:base()._tweak_table) then
		return
	end

	local weapon_melee = weapon_id and tweak_data.blackmarket and tweak_data.blackmarket.melee_weapons and tweak_data.blackmarket.melee_weapons[weapon_id] and true

	if killed_unit:brain().surrendered and killed_unit:brain():surrendered() and (variant == "melee" or weapon_melee) then
		managers.custom_safehouse:award("daily_honorable")
	end

	managers.modifiers:run_func("OnPlayerManagerKillshot", player_unit, killed_unit:base()._tweak_table, variant)

	local equipped_unit = self:get_current_state()._equipped_unit
	self._num_kills = self._num_kills + 1

	if self._num_kills % self._SHOCK_AND_AWE_TARGET_KILLS == 0 and self:has_category_upgrade("player", "automatic_faster_reload") then
		self:_on_enter_shock_and_awe_event()
	end
	
	if self:has_category_upgrade("player", "muscle_beachyboys") then
		if not self._beach_health_points then
			self._beach_health_points = 0.1
		elseif self._beach_health_points < 20 then
			self._beach_health_points = self._beach_health_points + 0.1
		end
	end

	self._message_system:notify(Message.OnEnemyKilled, nil, equipped_unit, variant, killed_unit)

	if self._saw_panic_when_kill and variant ~= "melee" then
		local equipped_unit = self:get_current_state()._equipped_unit:base()

		if equipped_unit:is_category("saw") then
			local pos = player_unit:position()
			local skill = self:upgrade_value("saw", "panic_when_kill")

			if skill and type(skill) ~= "number" then
				local area = skill.area
				local chance = skill.chance
				local amount = skill.amount
				local enemies = World:find_units_quick("sphere", pos, area, 12, 21)

				for i = 1, #enemies do
					local unit = enemies[i]
					
					if unit:character_damage() then
						unit:character_damage():build_suppression(amount, chance)
					end
				end
			end
		end
	end

	local t = Application:time()
	local damage_ext = player_unit:character_damage()

	if self:has_category_upgrade("player", "kill_change_regenerate_speed") then
		local amount = self:body_armor_value("skill_kill_change_regenerate_speed", nil, 1)
		local multiplier = self:upgrade_value("player", "kill_change_regenerate_speed", 0)

		damage_ext:change_regenerate_speed(amount * multiplier, tweak_data.upgrades.kill_change_regenerate_speed_percentage)
	end
	
	if damage_ext then
		if variant == "melee" then
			damage_ext:restore_health(self:upgrade_value("player", "infiltrator_melee_heal", 0))
			damage_ext:restore_armor_percent(self:upgrade_value("player", "infiltrator_armor_restore", 0))
		else
			local equipped_unit = self:get_current_state()._equipped_unit:base()
				
			if equipped_unit:is_category("saw") then
				damage_ext:restore_health(self:upgrade_value("player", "infiltrator_melee_heal", 0))
				damage_ext:restore_armor_percent(self:upgrade_value("player", "infiltrator_armor_restore", 0))
			end
		end
	end

	local gain_throwable_per_kill = managers.player:upgrade_value("team", "crew_throwable_regen", 0)

	if gain_throwable_per_kill ~= 0 then
		self._throw_regen_kills = (self._throw_regen_kills or 0) + 1

		if gain_throwable_per_kill < self._throw_regen_kills then
			managers.player:add_grenade_amount(1, true)

			self._throw_regen_kills = 0
		end
	end

	if self._on_killshot_t and t < self._on_killshot_t then
		return
	end

	local regen_armor_bonus = self:upgrade_value("player", "killshot_regen_armor_bonus", 0)
	local dist_sq = mvector3.distance_sq(player_unit:movement():m_pos(), killed_unit:movement():m_pos())
	local close_combat_sq = tweak_data.upgrades.close_combat_distance * tweak_data.upgrades.close_combat_distance

	if dist_sq <= close_combat_sq then
		regen_armor_bonus = regen_armor_bonus + self:upgrade_value("player", "killshot_close_regen_armor_bonus", 0)
		local panic_chance = self:upgrade_value("player", "killshot_close_panic_chance", 0)
		panic_chance = managers.modifiers:modify_value("PlayerManager:GetKillshotPanicChance", panic_chance)

		if panic_chance > 0 or panic_chance == -1 then
			local slotmask = managers.slot:get_mask("enemies")
			local units = World:find_units_quick("sphere", player_unit:movement():m_pos(), tweak_data.upgrades.killshot_close_panic_range, slotmask)

			for e_key, unit in pairs(units) do
				if alive(unit) and unit:character_damage() and not unit:character_damage():dead() then
					unit:character_damage():build_suppression(0, panic_chance)
				end
			end
		end
	end

	if damage_ext and regen_armor_bonus > 0 then
		damage_ext:restore_armor(regen_armor_bonus)
	end

	local regen_health_bonus = 0

	if variant == "melee" then
		regen_health_bonus = regen_health_bonus + self:upgrade_value("player", "melee_kill_life_leech", 0)
	end

	if damage_ext and regen_health_bonus > 0 then
		damage_ext:restore_health(regen_health_bonus)
	end

	self._on_killshot_t = t + (tweak_data.upgrades.on_killshot_cooldown or 0)

	if _G.IS_VR then
		local steelsight_multiplier = equipped_unit:base():enter_steelsight_speed_multiplier()
		local stamina_percentage = (steelsight_multiplier - 1) * tweak_data.vr.steelsight_stamina_regen
		local stamina_regen = player_unit:movement():_max_stamina() * stamina_percentage

		player_unit:movement():add_stamina(stamina_regen)
	end
end

function PlayerManager:on_damage_dealt(unit, damage_info)
	local player_unit = self:player_unit()

	if not player_unit then
		return
	end

	local t = Application:time()

	self:_check_damage_to_hot(t, unit, damage_info)
	self:_check_damage_to_cops(t, unit, damage_info)
	
	if self:has_category_upgrade("player", "infiltrator_melee_stance_DR") then
		local current_state = self:get_current_state()
		
		if damage_info.variant == "melee" then
			self._melee_stance_dr_t = t + 5
		else
			local equipped_unit = current_state._equipped_unit:base()
			
			if equipped_unit:is_category("saw") and damage_info.variant == "bullet" then
				self._melee_stance_dr_t = t + 5
			end
		end
	end

	if self._on_damage_dealt_t and t < self._on_damage_dealt_t then
		return
	end

	self._on_damage_dealt_t = t + (tweak_data.upgrades.on_damage_dealt_cooldown or 0)
end

function PlayerManager:update(t, dt)
	self._message_system:update()
	self:_update_timers(t)

	if self._need_to_send_player_status then
		self._need_to_send_player_status = nil

		self:need_send_player_status()
	end

	self._sent_player_status_this_frame = nil
	local local_player = self:local_player()

	if self:has_category_upgrade("player", "close_to_hostage_boost") and (not self._hostage_close_to_local_t or self._hostage_close_to_local_t <= t) then
		self._is_local_close_to_hostage = alive(local_player) and managers.groupai and managers.groupai:state():is_a_hostage_within(local_player:movement():m_pos(), tweak_data.upgrades.hostage_near_player_radius)
		self._hostage_close_to_local_t = t + tweak_data.upgrades.hostage_near_player_check_t
	end
	
	if self:has_category_upgrade("player", "infiltrator_melee_stance_DR") then
		local current_state = self:get_current_state()
		
		if current_state then
			if current_state.in_melee and current_state:in_melee() then
				self._melee_stance_dr_t = t + 5
			else
				local equipped_unit = current_state._equipped_unit:base()
				
				if equipped_unit:is_category("saw") then
					self._melee_stance_dr_t = t + 5
				end
			end
		end
	end
		
	if self._melee_stance_dr_t and self._melee_stance_dr_t < t then
		self._melee_stance_dr_t = nil
	end

	self:_update_damage_dealt(t, dt)

	if #self._global.synced_cocaine_stacks >= 4 then
		local amount = 0

		for i, stack in pairs(self._global.synced_cocaine_stacks) do
			if stack.in_use then
				amount = amount + stack.amount
			end

			if PlayerManager.TARGET_COCAINE_AMOUNT <= amount then
				managers.achievment:award("mad_5")
			end
		end
	end

	self._coroutine_mgr:update(t, dt)
	self._action_mgr:update(t, dt)

	if self._unseen_strike and not self._coroutine_mgr:is_running(PlayerAction.UnseenStrike) then
		local data = self:upgrade_value("player", "unseen_increased_crit_chance", 0)

		if data ~= 0 then
			self._coroutine_mgr:add_coroutine(PlayerAction.UnseenStrike, PlayerAction.UnseenStrike, self, data.min_time, data.max_duration, data.crit_chance)
		end
	end

	self:update_smoke_screens(t, dt)
end
