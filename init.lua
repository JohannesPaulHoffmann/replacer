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

local path = minetest.get_modpath"replacer"

-- adds a function to check ownership of a node; taken from VanessaEs homedecor mod
dofile(path.."/check_owner.lua")

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
dofile(path.."/inspect.lua")

local function inform(name, msg)
	minetest.chat_send_player(name, msg)
	minetest.log("info", "[replacer] "..name..": "..msg)
end

local mode_infos = {
	single = "Replace single node.",
	field = "Replace field of nodes.",
	crust = "Replace nodes touching each other and translucent.",
	chunkborder = "Replace mantle of nodes touching each other.",
}
local modes = {"single", "field", "crust", "chunkborder"}
for n,i in ipairs(modes) do
	modes[i] = n
end

local function get_data(item)
	local daten = item and item.metadata and item.metadata:split" " or {}
	return {
			name = daten[1] or "default:dirt",
			param1 = tonumber(daten[2]) or 0,
			param2 = tonumber(daten[3]) or 0
		},
		modes[daten[4] or ""] and daten[4] or modes[1]
end

local function set_data(itemstack, node, mode)
	local metadata = (node.name or "default:dirt") .. " "
		.. (node.param1 or 0) .. " "
		.. (node.param2 or 0) .." "
		.. (mode or modes[1])
	--~ local item = itemstack:to_table()
	--~ item.metadata = metadata
	--~ itemstack:replace(item)
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
		local name = placer:get_player_name()

		if keys.aux1 then
			local item = itemstack:to_table()
			local node, mode = get_data(item)
			mode = modes[modes[mode]%#modes+1]
			set_data(itemstack, node, mode)
			inform(name, "Mode changed to: "..mode..": "..mode_infos[mode])
			return itemstack
		end

		-- just place the stored node if now new one is to be selected
		if not keys.sneak then
			return replacer.replace(itemstack, placer, pt, true)
		end


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

local set = vector.set_data_to_pos
local get = vector.get_data_from_pos

-- don't use minetest.get_node more times for the same position
local known_nodes = {}
--[[
local function remove_node(pos)
	known_nodes[pos.z .." "..pos.y .." "..pos.x] = {name="air", param2=0}
	minetest.remove_node(pos)
end

local function dig_node(pos, node, digger)
	known_nodes[pos.z .." "..pos.y .." "..pos.x] = {name="air", param2=0}
	minetest.node_dig(pos, node, digger)
end--]]

local function get_node(pos)
	local z,y,x = vector.unpack(pos)
	local node = get(known_nodes, z,y,x)
	if node then
		return node
	end
	node = minetest.get_node(pos)
	set(known_nodes, z,y,x, node)
	return node
end


-- tests if a node can be replaced
local function replaceable(pos, name, pname)
	if get_node(pos).name ~= name
	or minetest.is_protected(pos, pname) then
		return false
	end
	return true
end

local trans_nodes = {}
local function node_translucent(name)
	if trans_nodes[name] ~= nil then
		return trans_nodes[name]
	end
	local data = minetest.registered_nodes[name]
	if data
	and (not data.drawtype or data.drawtype == "normal") then
		trans_nodes[name] = false
		return false
	end
	trans_nodes[name] = true
	return true
end

local function field_position(pos, data)
	if not replaceable(pos, data.name, data.pname)
	or node_translucent(get_node(vector.add(data.above, pos)).name) == data.ptab then
		return false
	end
	return true
end

local default_adps = {}
for _,i in pairs{"x", "y", "z"} do
	for a = -1,1,2 do
		local p = {x=0, y=0, z=0}
		p[i] = a
		default_adps[#default_adps+1] = p
	end
end

local strong_adps = {}
for x = -1,1 do
	for y = -1,1 do
		for z = -1,1 do
			local p = {x=x, y=y, z=z}
			if x ~= 0
			or y ~= 0
			or z ~= 0 then
				strong_adps[#strong_adps+1] = p
			end
		end
	end
end

-- avoid replacing nodes behind the crust
local function crust_above_position(pos, data)
	local nd = get_node(pos).name
	if nd == data.name
	or not node_translucent(nd) then
		return false
	end
	for _,p2 in pairs(strong_adps) do
		if replaceable(vector.add(pos, p2), data.name, data.pname) then
			return true
		end
	end
	return false
end

local function crust_under_position(pos, data)
	if not replaceable(pos, data.name, data.pname) then
		return false
	end
	for _,p2 in pairs(strong_adps) do
		local z,y,x = vector.unpack(vector.add(pos, p2))
		if get(data.aboves, z,y,x) then
			return true
		end
	end
	return false
end

local function reduce_crust_ps(data)
	for n,p in pairs(data.ps) do
		local found
		for _,p2 in pairs(default_adps) do
			local z,y,x = vector.unpack(vector.add(p, p2))
			if get(data.aboves, z,y,x) then
				found = true
				break
			end
		end
		if not found then
			data.ps[n] = nil
			data.num = data.num-1
		end
	end
end

local function reduce_crust_above_ps(data)
	for n,p in pairs(data.ps) do
		local found
		if replaceable(p, "air", data.pname) then
			for _,p2 in pairs(default_adps) do
				if replaceable(vector.add(p, p2), data.name, data.pname) then
					found = true
					break
				end
			end
		end
		if not found then
			data.ps[n] = nil
			data.num = data.num-1
		end
	end
end

local function mantle_position(pos, data)
	if not replaceable(pos, data.name, data.pname) then
		return false
	end
	for _,p2 in pairs(default_adps) do
		local p = vector.add(pos, p2)
		if get_node(p).name ~= data.name then
			return true
		end
	end
	return false
end

-- finds out positions
local function get_ps(pos, fdata, adps, max)
	adps = adps or default_adps

	local tab = {}
	local num = 1

	local todo = {pos}
	local ti = 1

	local tab_avoid = {}

	while ti ~= 0 do
		local p = todo[ti]
		todo[ti] = nil
		ti = ti-1

		for _,p2 in pairs(adps) do
			p2 = vector.add(p, p2)
			local z,y,x = vector.unpack(p2)
			if not get(tab_avoid, z,y,x)
			and fdata.func(p2, fdata) then

				tab[num] = p2
				num = num+1

				ti = ti+1
				todo[ti] = p2

				set(tab_avoid, z,y,x, true)

				if max
				and num > max then
					return false
				end
			end
		end
	end
	return tab, num-1, tab_avoid
end

local creative = minetest.setting_getbool"creative_mode" -- rebase artifact

-- replaces one node with another one and returns if it was successful
local function replace_single_node(pos, node, nnd, user, name, inv)
	if minetest.is_protected(pos, name) then
		return false, "Protected at "..minetest.pos_to_string(pos)
	end

	-- do not replace if there is nothing to be done
	if node.name == nnd.name then
		-- only the orientation was changed
		if node.param1 ~= nnd.param1
		or node.param2 ~= nnd.param2 then
			minetest.set_node(pos, nnd)
		end
		return true
	end

	-- does the player carry at least one of the desired nodes with him?
	if not creative
	and not inv:contains_item("main", nnd.name) then
		return false, "You have no further '"..(nnd.name or "?").."'. Replacement failed."
	end

	-- give the player the item by simulating digging if possible
	local def = minetest.registered_nodes[node.name]
	if not def then
		return false, "Unknown node: "..node.name
	end

	if not def.buildable_to then

		minetest.node_dig(pos, node, user)

		local dug_node = minetest.get_node_or_nil(pos)
		if not dug_node
		or dug_node.name == node.name then
			return false, "Replacing '".. node.name .."' with '"..dump(nnd).."' failed. Unable to remove old node."
		end

	end

	if not creative then
		-- consume the item
		inv:remove_item("main", nnd.name.." 1")
	end

	--minetest.place_node(pos, nnd)
	minetest.add_node(pos, nnd)
	return true
end

-- the function which happens when the replacer is used
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

	if replacer.blacklist[nnd.name] then
		minetest.chat_send_player(name, "Placing blocks of the type '" ..
			nnd.name ..
			"' with the replacer is not allowed on this server. " ..
			"Replacement failed.")
		return
	end

	-- in survival mode, the player has to provide the node he wants to be placed
	if not creative then

		-- players usually don't carry dirt_with_grass around; it's safe to assume normal dirt here
		-- fortionately, dirt and dirt_with_grass does not make use of rotation
		if nnd.name == "default:dirt_with_grass" then
			nnd.name = "default:dirt"
			item.metadata = "default:dirt 0 0 0"
		end
	end

	if mode == "single" then
		local succ,err = replace_single_node(pos, node, nnd, user, name, user:get_inventory())

		if not succ then
			inform(name, err)
		end
		return
	end

	local pos
	if above then
		above = true
		pos = pt.above
	else
		above = false
		pos = pt.under
	end

	local ps,num
	if mode == "field" then
		-- get connected positions for plane field replacing
		local pdif = vector.subtract(pt.above, pt.under)
		local adps,n = {},1
		for _,i in pairs{"x", "y", "z"} do
			if pdif[i] == 0 then
				for a = -1,1,2 do
					local p = {x=0, y=0, z=0}
					p[i] = a
					adps[n] = p
					n = n+1
				end
			end
		end
		if above then
			pdif = vector.multiply(pdif, -1)
		end
		ps,num = get_ps(pos, {func=field_position, name=node.name, pname=name, above=pdif, ptab=above}, adps, 8799)
	elseif mode == "crust" then
		local nodename = get_node(pt.under).name
		local aps,n,aboves = get_ps(pt.above, {func=crust_above_position, name=nodename, pname=name}, nil, 8799)
		if aps then
			if above then
				local data = {ps=aps, num=n, name=nodename, pname=name}
				reduce_crust_above_ps(data)
				ps,num = data.ps, data.num
			else
				ps,num = get_ps(pt.under, {func=crust_under_position, name=node.name, pname=name, aboves=aboves}, strong_adps, 8799)
				if ps then
					local data = {aboves=aboves, ps=ps, num=num}
					reduce_crust_ps(data)
					ps,num = data.ps, data.num
				end
			end
		end
	elseif mode == "chunkborder" then
		ps,num = get_ps(pos, {func=mantle_position, name=node.name, pname=name}, nil, 8799)
	end

	-- reset known nodes table
	known_nodes = {}

	if not ps then
		inform(name, "Aborted, too many nodes detected.")
		return
	end

	-- set nodes
	local inv = user:get_inventory()
	for _,pos in pairs(ps) do
		local succ,err = replace_single_node(pos, minetest.get_node(pos), nnd, user, name, inv)
		if not succ then
			inform(name, err)
			return
		end
	end
	inform(name, num.." nodes replaced.")
end


minetest.register_craft({
	output = "replacer:replacer",
	recipe = {
		{"default:chest", "default:obsidian", "default:obsidian"},
		{"default:obsidian", "default:stick", "default:obsidian"},
		{"default:obsidian", "default:obsidian", "default:chest"},
	}
})
