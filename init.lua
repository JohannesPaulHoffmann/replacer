--[[
	Replacement tool for creative building (Mod for MineTest)
	Copyright (C) 2013 Sokomine

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.	If not, see <http://www.gnu.org/licenses/>.
--]]

-- Version 3.0

-- Changelog:
-- 09.12.2017 * Got rid of outdated minetest.env
--			* Fixed error in protection function.
--			* Fixed minor bugs.
--			* Added blacklist
-- 02.10.2014 * Some more improvements for inspect-tool. Added craft-guide.
-- 01.10.2014 * Added inspect-tool.
-- 12.01.2013 * If digging the node was unsuccessful, then the replacement will now fail
--				(instead of destroying the old node with its metadata; i.e. chests with content)
-- 20.11.2013 * if the server version is new enough, minetest.is_protected is used
--				in order to check if the replacement is allowed
-- 24.04.2013 * param1 and param2 are now stored
--			* hold sneak + right click to store new pattern
--			* right click: place one of the itmes
--			* receipe changed
--			* inventory image added

-- adds a function to check ownership of a node; taken from VanessaEs homedecor mod
dofile(minetest.get_modpath("replacer").."/check_owner.lua")

replacer = {}

replacer.blacklist = {};

-- playing with tnt and creative building are usually contradictory
-- (except when doing large-scale landscaping in singleplayer)
replacer.blacklist[ "tnt:boom"] = true;
replacer.blacklist[ "tnt:gunpowder"] = true;
replacer.blacklist[ "tnt:gunpowder_burning"] = true;
replacer.blacklist[ "tnt:tnt"] = true;

-- prevent accidental replacement of your protector
replacer.blacklist[ "protector:protect"] = true;
replacer.blacklist[ "protector:protect2"] = true;

-- adds a tool for inspecting nodes and entities
dofile(minetest.get_modpath("replacer").."/inspect.lua")

local function inform(name, msg)
	minetest.chat_send_player(name, msg)
	minetest.log("info", "[replacer] "..name..": "..msg)
end

local mode_infos = {
	single = "Replace single node.",
	field = "Replace field of nodes.",
}

local function get_data(item)
	local daten = (item and item.metadata and item.metadata:split" ") or {}
	return {
			name=daten[1] or "default:dirt",
			param1=tonumber(daten[2]) or 0,
			param2=tonumber(daten[3]) or 0
		},
		mode_infos[daten[4] or ""] and daten[4] or "single"
end

local function set_data(itemstack, node, mode)
	local metadata = (node.name or"default:dirt") .." "
		..(node.param1 or 0).." "..(node.param2 or 0)
		.." "..(mode or "single")
	itemstack:set_metadata(metadata)
	return metadata
end

minetest.register_tool("replacer:replacer", {
	description = "Node replacement tool",
	inventory_image = "replacer_replacer.png",
	stack_max = 1, -- it has to store information - thus only one can be stacked
	liquids_pointable = true, -- it is ok to painit in/with water
	--node_placement_prediction = nil,
	metadata = "default:dirt", -- default replacement: common dirt

	on_place = function(itemstack, placer, pt)
		if not placer
		or not pt then
			return
		end

		local keys = placer:get_player_control()

		if keys.aux1 then
			local item = itemstack:to_table()
			local node, mode = get_data(item)
			if mode == "single" then
				mode = "field"
			else
				mode = "single"
			end
			set_data(item, node, mode)
			itemstack:replace(item)
			inform(name, "Mode changed to: "..mode_infos[mode])
			return itemstack
		end

		-- just place the stored node if now new one is to be selected
		if not keys.sneak then
			return replacer.replace(itemstack, placer, pt, true)
		end

		local name = placer:get_player_name()

		if pt.type ~= "node" then
			inform(name, "Error: No node selected.")
			return
		end

		local item = itemstack:to_table()
		local node, mode = get_data(item)

		node = minetest.get_node_or_nil(pt.under) or node

		local metadata = set_data(itemstack, node, mode)

		inform(name, "Node replacement tool set to: '" .. metadata .. "'.")

		return itemstack --data changed
	end,


--	on_drop = func(itemstack, dropper, pos),

	on_use = function(...)
		return replacer.replace(...)
	end,
})

-- tests if a node can be replaced
local function replaceable(pos, name, pname)
	if minetest.get_node(pos).name ~= name
	or minetest.is_protected(pos, pname) then
		return false
	end
	return true
end

-- finds out positions
local function get_ps(pos, name, pname, adps, max)
	local tab = {}
	local num = 1
	local todo = {pos}
	local tab_avoid = {}
	while todo[1] do
		for n,p in pairs(todo) do
			for _,p2 in pairs(adps) do
				p2 = vector.add(p, p2)
				local pstr = p2.x.." "..p2.y.." "..p2.z
				if not tab_avoid[pstr]
				and replaceable(p2, name, pname) then
					tab[num] = p2
					tab_avoid[pstr] = true
					num = num+1
					table.insert(todo, p2)
					if max
					and num > max then
						return false
					end
				end
			end
			todo[n] = nil
		end
	end
	return tab, num-1
end

function replacer.replace(itemstack, user, pt, above)
	if not user
	or not pt then
		return
	end
	local name = user:get_player_name()

	if pt.type ~= "node" then
		inform(name, "Error: No node.")
		return
	end

	local pos = minetest.get_pointed_thing_position(pt, above)
	local node = minetest.get_node_or_nil(pos)

	if not node then
		inform(name, "Error: Target node not yet loaded. Please wait a moment for the server to catch up.")
		return
	end

	local item = itemstack:to_table()
	local nnd, mode = get_data(item)

	if replacer.blacklist[node.name] then
		minetest.chat_send_player(name, "Replacing blocks of the type '" ..
			node.name ..
			"' is not allowed on this server. Replacement failed.")
		return
	end

	if replacer.blacklist[daten[1]] then
		minetest.chat_send_player(name, "Placing blocks of the type '" ..
			daten[1] ..
			"' with the replacer is not allowed on this server. " ..
			"Replacement failed.")
		return
	end

	-- do not replace if there is nothing to be done
	if node.name == nnd.name then
		-- only the orientation was changed
		if node.param1 ~= nnd.param1
		or node.param2 ~= nnd.param2 then
			minetest.set_node(pos, nnd)
		end
		return
	end

	if mode == "field" then
		-- area replacing

		-- get connected positions
		local pdif = vector.subtract(pt.above, pt.under)
		local adps = {}
		for _,i in pairs{"x", "y", "z"} do
			if pdif[i] == 0 then
				for a = -1,1,2 do
					local p = {x=0, y=0, z=0}
					p[i] = a
					adps[#adps+1] = p
				end
			end
		end
		local ps,num = get_ps(pt.under, node.name, name, adps, 8799)
		if not ps then
			inform(name, "Aborted, too many nodes detected.")
			return
		end

		-- set nodes
		for _,pos in pairs(ps) do
			minetest.set_node(pos, nnd)
		end
		inform(name, num.." nodes replaced.")
		return
	end

	-- in survival mode, the player has to provide the node he wants to be placed
	if not minetest.setting_getbool"creative_mode"
	and not minetest.check_player_privs(name, {creative=true}) then

		-- players usually don't carry dirt_with_grass around; it's safe to assume normal dirt here
		-- fortionately, dirt and dirt_with_grass does not make use of rotation
		if nnd.name == "default:dirt_with_grass" then
			nnd.name = "default:dirt"
			item.metadata = "default:dirt 0 0 0"
		end

		-- does the player carry at least one of the desired nodes with him?
		if not user:get_inventory():contains_item("main", nnd.name) then
			inform(name, "You have no further '"..(nnd.name or "?").."'. Replacement failed.")
			return
		end


		-- give the player the item by simulating digging if possible
		if  node.name ~= "default:lava_source"
		and node.name ~= "default:lava_flowing"
		and node.name ~= "default:river_water_source"
		and node.name ~= "default:river_water_flowing"
		and node.name ~= "default:water_source"
		and node.name ~= "default:water_flowing" then

			minetest.node_dig(pos, node, user)

			local dug_node = minetest.get_node_or_nil(pos)
			if not dug_node
			or dug_node.name == node.name then
				inform(name, "Replacing '"..(node.name or "air").."' with '"..(item.metadata or "?").."' failed. Unable to remove old node.")
				return
			end

		end

		-- consume the item
		user:get_inventory():remove_item("main", nnd.name.." 1")
	end

	--minetest.place_node(pos, nnd)
	minetest.add_node(pos, nnd)
	return
end


minetest.register_craft({
	output = "replacer:replacer",
	recipe = {
		{"default:chest", "default:obsidian", "default:obsidian"},
		{"default:obsidian", "default:stick", "default:obsidian"},
		{"default:obsidian", "default:obsidian", "default:chest"},
	}
})
