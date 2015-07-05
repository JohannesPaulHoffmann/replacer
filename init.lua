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

minetest.register_tool("replacer:replacer",
{
	description = "Node replacement tool",
	inventory_image = "replacer_replacer.png",
	stack_max = 1, -- it has to store information - thus only one can be stacked
	liquids_pointable = true, -- it is ok to painit in/with water
	--~ node_placement_prediction = nil,
	metadata = "default:dirt", -- default replacement: common dirt

	on_place = function(itemstack, placer, pointed_thing)
		if not placer
		or not pointed_thing then
			return itemstack -- nothing consumed
		end

		local keys = placer:get_player_control()
		-- just place the stored node if now new one is to be selected
		if not keys.sneak then
			return replacer.replace(itemstack, placer, pointed_thing, 0)
		end

		local name = placer:get_player_name()
		--minetest.chat_send_player( name, "You PLACED this on "..minetest.serialize( pointed_thing )..".")

		if pointed_thing.type ~= "node" then
			minetest.chat_send_player(name, "Error: No node selected.")
			return
		end

		local pos = pointed_thing.under
		local node = minetest.get_node_or_nil(pos)

		--minetest.chat_send_player(name, "	Target node: "..minetest.serialize(node).." at pos "..minetest.serialize(pos)..".")

		local metadata = "default:dirt 0 0"
		if node
		and node.name then
			metadata = node.name..' '..node.param1..' '..node.param2
		end
		itemstack:set_metadata(metadata)

		minetest.chat_send_player(name, "Node replacement tool set to: '"
			.. metadata .. "'.")

		return itemstack -- nothing consumed but data changed
	end,


--	on_drop = func(itemstack, dropper, pos),

	on_use = function(...)
		return replacer.replace(...)
	end,
})

replacer.replace = function(itemstack, user, pointed_thing)
	if not user
	or not pointed_thing then
		return
	end
	local name = user:get_player_name()

	if pointed_thing.type ~= "node" then
		minetest.chat_send_player(name, "Error: No node.")
		return
	end

	local pos = pointed_thing.under
	local node = minetest.get_node_or_nil(pos)

	if not node then
		minetest.chat_send_player(name, "Error: Target node not yet loaded. Please wait a moment for the server to catch up.")
		return
	end

	local item = itemstack:to_table()

	-- make sure it is defined
	if not item.metadata
	or item.metadata == "" then
		item.metadata = "default:dirt 0 0"
	end

	-- regain information about nodename, param1 and param2
	local daten = item.metadata:split" "
	-- the old format stored only the node name
	if #daten < 3 then
		daten[2] = 0
		daten[3] = 0
	end

	-- if someone else owns that node then we can not change it
	if replacer_homedecor_node_is_owned(pos, user) then
		return
	end

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
	if node.name == daten[1] then

		-- the node itshelf remains the same, but the orientation was changed
		if node.param1 ~= daten[2]
		or node.param2 ~= daten[3] then
			minetest.add_node(pos, {name = node.name, param1 = daten[2], param2 = daten[3]})
		end

		return
	end

	-- in survival mode, the player has to provide the node he wants to place
	if( not(minetest.setting_getbool("creative_mode") )
	and not( minetest.check_player_privs( name, {creative=true}))) then

		-- players usually don't carry dirt_with_grass around; it's safe to assume normal dirt here
		-- fortionately, dirt and dirt_with_grass does not make use of rotation
		if daten[1] == "default:dirt_with_grass" then
			daten[1] = "default:dirt"
			item.metadata = "default:dirt 0 0"
		end

		-- does the player carry at least one of the desired nodes with him?
		if not user:get_inventory():contains_item("main", daten[1]) then
			minetest.chat_send_player(name, "You have no further '"..(daten[1] or "?").."'. Replacement failed.")
			return
		end

		-- give the player the item by simulating digging if possible
		if node.name ~= "air"
		and node.name ~= "ignore"
		and node.name ~= "default:lava_source"
		and node.name ~= "default:lava_flowing"
		and node.name ~= "default:river_water_source"
		and node.name ~= "default:river_water_flowing"
		and node.name ~= "default:water_source"
		and node.name ~= "default:water_flowing" then

			minetest.node_dig(pos, node, user)

			local dug_node = minetest.get_node_or_nil(pos)
			if not dug_node
			or dug_node.name == node.name then
				minetest.chat_send_player(name, "Replacing '"..(node.name or "air").."' with '"..(item.metadata or "?").."' failed. Unable to remove old node.")
				return
			end
		end

		-- consume the item
		user:get_inventory():remove_item("main", daten[1].." 1")
	end

	--minetest.place_node(pos, {name = item["metadata"]})
	minetest.add_node(pos,
		{name = daten[1], param1 = daten[2], param2 = daten[3]})
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
