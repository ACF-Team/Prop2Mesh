--[[
	-- one of
	prop 		-- modelpath
	holo 		-- modelpath
	objd     -- crc of uncompressed data

	-- required
	pos 		-- local pos
	ang 		-- local ang

	-- optional
	scale       -- x y z scales
	bodygroup   -- mask
	vsmooth     -- unset to use model normals, 0 to use flat shading, degrees to calculate
	vinvert     -- flip normals
	vinside     -- render inside
	objn        -- prettyprint
	submodels   -- lookup table of bools that hides submeshes by index
]]

local prop2mesh = prop2mesh

local next = next
local TypeID = TypeID
local IsValid = IsValid
local WorldToLocal = WorldToLocal
local LocalToWorld = LocalToWorld

prop2mesh.entclass = {}
local entclass = prop2mesh.entclass


--[[

]]
function prop2mesh.getPartClasses()
	local keys = table.GetKeys(entclass)
	return keys, #keys
end

function prop2mesh.partsFromEnts(entlist, worldpos, worldang)
	local partlist = {}

	for k, v in pairs(entlist) do
		local ent
		if TypeID(k) == TYPE_ENTITY then ent = k else ent = v end

		local class = IsValid(ent) and entclass[ent:GetClass()]
		if class then
			class(partlist, ent, worldpos, worldang)
		end
	end

	return next(partlist) and partlist
end

function prop2mesh.sanitizeCustom(partlist) -- remove unused obj data
	if not partlist.custom then
		return
	end

	local lookup = {}
	for crc, data in pairs(partlist.custom) do
		lookup[crc .. ""] = data
	end

	local custom = {}
	for index, part in ipairs(partlist) do
		if part.objd then
			local crc = part.objd .. ""
			if crc and lookup[crc] then
				custom[crc] = lookup[crc]
				lookup[crc] = nil
			end
		end
		if not next(lookup) then
			break
		end
	end

	partlist.custom = custom
end

-- Stores ImprovedClipping clips in their own part.iclips field, separate from legacy
-- part.clips. Both keep the side the normal points toward (dot(pos, n) >= d).
local function append_improved_clips(part, ent)
	if not ImprovedClipping then return end

	local iclips = ImprovedClipping.GetClips(ent)
	if not iclips[1] then return end

	local pclips = {}
	for _, clip in ipairs(iclips) do
		pclips[#pclips + 1] = { n = clip.Normal, d = clip.Distance, s = clip.Seal or nil }
	end

	part.iclips = pclips
end

local function basic_info(partlist, ent, worldpos, worldang)
	local part = {}

	part.pos, part.ang = WorldToLocal(ent:GetPos(), ent:GetAngles(), worldpos, worldang)

	local scale
	if ent.GetScale then scale = ent:GetScale() else scale = ent:GetManipulateBoneScale(0) end
	if isvector(scale) and scale.x ~= 1 or scale.y ~= 1 or scale.z ~= 1 then
		part.scale = scale
	end

	local clips = ent.ClipData or ent.EntityMods and ent.EntityMods.clips
	if clips then
		local pclips = {}
		for _, clip in ipairs(clips) do
			if not clip.n or not clip.d then
				goto badclip
			end
			if clip.inside then
				part.vinside = 1
			end
			local normal = clip.n:Forward()
			pclips[#pclips + 1] = { n = normal, d = clip.d + normal:Dot(ent.OBBCenterOrg or ent:OBBCenter()) }

			::badclip::
		end
		if next(pclips) then
			part.clips = pclips
		end
	end

	append_improved_clips(part, ent)

	return part
end


--[[

]]
local getBodygroupMask = prop2mesh.getBodygroupMask

entclass.prop_physics = function(partlist, ent, worldpos, worldang)
	local part = basic_info(partlist, ent, worldpos, worldang)

	part.prop = ent:GetModel()

	local bodygroup = getBodygroupMask(ent)
	if bodygroup ~= 0 then
		part.bodygroup = bodygroup
	end

	partlist[#partlist + 1] = part
end

entclass.prop_effect = function(partlist, ent, worldpos, worldang)
	ent = ent.AttachedEntity

	if not ent or not IsValid(ent) or ent:GetClass() ~= "prop_dynamic" then return end

	entclass.prop_physics(partlist, ent, worldpos, worldang)
end

entclass.acf_armor = entclass.prop_physics

entclass.gmod_wire_hologram = function(partlist, ent, worldpos, worldang)
	local holo = ent.E2HoloData
	if not holo then
		return
	end

	local part = { holo = ent:GetModel() }

	part.pos, part.ang = WorldToLocal(ent:GetPos(), ent:GetAngles(), worldpos, worldang)

	local bodygroup = getBodygroupMask(ent)
	if bodygroup ~= 0 then
		part.bodygroup = bodygroup
	end

	if holo.scale and (holo.scale.x ~= 1 or holo.scale.y ~= 1 or holo.scale.z ~= 1) then
		part.scale = Vector(holo.scale)
	end

	if holo.clips then
		local pclips = {}
		for _, clip in pairs(holo.clips) do
			if clip.localentid == 0 then -- this is a global clip... what to do here?
				goto badclip
			end
			local clipTo = Entity(clip.localentid)
			if not IsValid(clipTo) then
				goto badclip
			end

			local normal = ent:WorldToLocal(clipTo:LocalToWorld(clip.normal:GetNormalized()) - clipTo:GetPos() + ent:GetPos())
			local origin = ent:WorldToLocal(clipTo:LocalToWorld(clip.origin))
			pclips[#pclips + 1] = { n = normal, d = normal:Dot(origin) }

			::badclip::
		end
		if next(pclips) then
			part.clips = pclips
		end
	end

	partlist[#partlist + 1] = part
end

entclass.starfall_hologram = function(partlist, ent, worldpos, worldang)
	local part = { holo = ent:GetModel() }

	part.pos, part.ang = WorldToLocal(ent:GetPos(), ent:GetAngles(), worldpos, worldang)

	local bodygroup = getBodygroupMask(ent)
	if bodygroup ~= 0 then
		part.bodygroup = bodygroup
	end

	local NVs = ent:GetNetworkVars()
	if NVs["Scale"] ~= nil then
		part.scale = NVs["Scale"]
	end

	if ent.clips then
		local pclips = {}
		for _, clip in pairs(ent.clips) do
			if not IsValid(clip.entity) then
				goto badclip
			end

			local normal = ent:WorldToLocal(clip.entity:LocalToWorld(clip.normal:GetNormalized()) - clip.entity:GetPos() + ent:GetPos())
			local origin = ent:WorldToLocal(clip.entity:LocalToWorld(clip.origin))
			pclips[#pclips + 1] = { n = normal, d = normal:Dot(origin) }

			::badclip::
		end
		if next(pclips) then
			part.clips = pclips
		end
	end

	partlist[#partlist + 1] = part
end

local function transformPartlist(ent, index, worldpos, worldang)
	local partlist = ent:GetControllerData(index)
	if not partlist then
		return
	end

	local localpos = ent:GetPos()
	local localang = ent:GetAngles()

	for k, v in ipairs(partlist) do
		v.pos, v.ang = LocalToWorld(v.pos, v.ang, localpos, localang)
		v.pos, v.ang = WorldToLocal(v.pos, v.ang, worldpos, worldang)
	end

	return partlist
end

entclass.sent_prop2mesh_legacy = function(partlist, ent, worldpos, worldang)
	local ok, err = pcall(transformPartlist, ent, 1, worldpos, worldang)

	if ok then
		if err.custom then
			if not partlist.custom then
				partlist.custom = {}
			end
			for k, v in pairs(err.custom) do
				partlist.custom[k] = v
			end
		end
		for i = 1, #err do
			partlist[#partlist + 1] = err[i]
		end

		--partlist.uvs = ent:GetControllerUVS(1)
	else
		print(err)
	end
end


entclass.primitive_shape = function(partlist, ent, worldpos, worldang)
	local vars = ent.primitive and ent.primitive.keys
	if not istable(vars) or next(vars) == nil then return end

	vars = table.Copy(vars)

	vars.construct = vars.PrimTYPE
	vars.PrimTYPE = nil

	local part = basic_info(partlist, ent, worldpos, worldang)
	part.primitive = vars

	partlist[#partlist + 1] = part
end

entclass.primitive_airfoil = function(partlist, ent, worldpos, worldang)
	local vars = ent.primitive and ent.primitive.keys
	if not istable(vars) or next(vars) == nil then return end

	vars = table.Copy(vars)

	vars.construct = "airfoil"

	local part = basic_info(partlist, ent, worldpos, worldang)
	part.primitive = vars

	partlist[#partlist + 1] = part
end

entclass.primitive_staircase = function(partlist, ent, worldpos, worldang)
	local vars = ent.primitive and ent.primitive.keys
	if not istable(vars) or next(vars) == nil then return end

	vars = table.Copy(vars)

	vars.construct = "staircase"

	local part = basic_info(partlist, ent, worldpos, worldang)
	part.primitive = vars

	partlist[#partlist + 1] = part
end

entclass.primitive_ladder = function(partlist, ent, worldpos, worldang)
	local vars = ent.primitive and ent.primitive.keys
	if not istable(vars) or next(vars) == nil then return end

	vars = table.Copy(vars)

	vars.construct = "ladder"

	local part = basic_info(partlist, ent, worldpos, worldang)
	part.primitive = vars

	partlist[#partlist + 1] = part
end
