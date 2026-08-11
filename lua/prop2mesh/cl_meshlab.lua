--[[

]]
local prop2mesh = prop2mesh

local util = util
local string = string
local coroutine = coroutine
local notification = notification

local next = next
local SysTime = SysTime
local tonumber = tonumber

local Vector = Vector
local vec = Vector()
local div = vec.Div
local mul = vec.Mul
local add = vec.Add
local dot = vec.Dot
local cross = vec.Cross
local normalize = vec.Normalize
local rotate = vec.Rotate

local math_cos = math.cos
local math_rad = math.rad
local math_abs = math.abs
local math_min = math.min
local math_max = math.max

local string_format = string.format
local string_explode = string.Explode
local string_gsub = string.gsub
local string_trim = string.Trim
local table_concat = table.concat
local table_remove = table.remove
local coroutine_yield = coroutine.yield

local a90 = Angle(0, -90, 0)
local YIELD_THRESHOLD = 30

local devcvar = GetConVar("developer")
local cvar = CreateClientConVar("prop2mesh_render_disable_obj", 0, true, false)
local disable_obj = cvar:GetBool()

cvars.AddChangeCallback("prop2mesh_render_disable_obj", function(cvar, old, new)
    disable_obj = tobool(new)
end, "swapdrawdisable_obj")


--[[

]]
local function calcbounds(min, max, pos)
	if pos.x < min.x then min.x = pos.x elseif pos.x > max.x then max.x = pos.x end
	if pos.y < min.y then min.y = pos.y elseif pos.y > max.y then max.y = pos.y end
	if pos.z < min.z then min.z = pos.z elseif pos.z > max.z then max.z = pos.z end
end

local function copy(v)
	return {
		pos    = Vector(v.pos),
		normal = Vector(v.normal),
		u      = v.u,
		v      = v.v,
		rotate = v.rotate,
		userdata = v.userdata,
	}
end

local function sign(n)
	if n == 0 then
		return 0
	else
		return n > 0 and 1 or -1
	end
end

local function getBoxDir(vec)
	local x, y, z = math_abs(vec.x), math_abs(vec.y), math_abs(vec.z)
	if x > y and x > z then
		return vec.x < -0 and -1 or 1
	elseif y > z then
		return vec.y < 0 and -2 or 2
	end
	return vec.z < 0 and -3 or 3
end

local function getBoxUV(vert, dir, scale)
	if dir == -1 or dir == 1 then
		return vert.z * sign(dir) * scale, vert.y * scale
	elseif dir == -2 or dir == 2 then
		return vert.x * scale, vert.z * sign(dir) * scale
	else
		return vert.x * -sign(dir) * scale, vert.y * scale
	end
end

local function calcTangents(verts, threaded)
    -- credit to https://gamedev.stackexchange.com/questions/68612/how-to-compute-tangent-and-bitangent-vectors
    -- seems to work but i have no idea how or why, nor why i cant do this during triangulation

    local tan1 = {}
    local tan2 = {}

    for i = 1, #verts do
        tan1[i] = Vector(0, 0, 0)
        tan2[i] = Vector(0, 0, 0)

        if threaded and (i % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
    end

    for i = 1, #verts - 2, 3 do
        local v1 = verts[i]
        local v2 = verts[i + 1]
        local v3 = verts[i + 2]

        local p1 = v1.pos
        local p2 = v2.pos
        local p3 = v3.pos

        local x1 = p2.x - p1.x
        local x2 = p3.x - p1.x
        local y1 = p2.y - p1.y
        local y2 = p3.y - p1.y
        local z1 = p2.z - p1.z
        local z2 = p3.z - p1.z

        local us1 = v2.u - v1.u
        local us2 = v3.u - v1.u
        local ut1 = v2.v - v1.v
        local ut2 = v3.v - v1.v

        local r = 1 / (us1*ut2 - us2*ut1)

        local sdir = Vector((ut2*x1 - ut1*x2)*r, (ut2*y1 - ut1*y2)*r, (ut2*z1 - ut1*z2)*r)
        local tdir = Vector((us1*x2 - us2*x1)*r, (us1*y2 - us2*y1)*r, (us1*z2 - us2*z1)*r)

        add(tan1[i], sdir)
        add(tan1[i + 1], sdir)
        add(tan1[i + 2], sdir)

        add(tan2[i], tdir)
        add(tan2[i + 1], tdir)
        add(tan2[i + 2], tdir)

        if threaded and (i % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
    end

    for i = 1, #verts do
        local n = verts[i].normal
        local t = tan1[i]

        local tangent = (t - n*dot(n, t))
        normalize(tangent)

        verts[i].userdata = { tangent[1], tangent[2], tangent[3], dot(cross(n, t), tan2[i]) }

        if threaded and (i % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
    end
end

local function clip(v1, v2, plane, length, getUV)
	local d1 = dot(v1.pos, plane) - length
	local d2 = dot(v2.pos, plane) - length
	local t  = d1 / (d1 - d2)
	local vert = {
		pos    = v1.pos + t * (v2.pos - v1.pos),
		normal = v1.normal + t * (v2.normal - v1.normal),
		rotate = v1.rotate or v2.rotate,
	}
	if getUV then
		vert.u = v1.u + t * (v2.u - v1.u)
		vert.v = v1.v + t * (v2.v - v1.v)
	end
	return vert
end

-- method https:--github.com/chenchenyuyu/DEMO/blob/b6bf971a302c71403e0e34e091402982dfa3cd2d/app/src/pages/vr/decal/decalGeometry.js#L102
local function applyClippingPlane(verts, plane, length, getUV)
	local temp = {}
	for i = 1, #verts, 3 do
		local d1 = length - dot(verts[i + 0].pos, plane)
		local d2 = length - dot(verts[i + 1].pos, plane)
		local d3 = length - dot(verts[i + 2].pos, plane)

		local ov1 = d1 > 0
		local ov2 = d2 > 0
		local ov3 = d3 > 0

		local total = (ov1 and 1 or 0) + (ov2 and 1 or 0) + (ov3 and 1 or 0)

		local nv1, nv2, nv3, nv4

		if total == 0 then
			temp[#temp + 1] = verts[i + 0]
			temp[#temp + 1] = verts[i + 1]
			temp[#temp + 1] = verts[i + 2]
		elseif total == 1 then
			if ov1 then
				nv1 = verts[i + 1]
				nv2 = verts[i + 2]
				nv3 = clip(verts[i + 0], nv1, plane, length, getUV)
				nv4 = clip(verts[i + 0], nv2, plane, length, getUV)

				temp[#temp + 1] = copy(nv1)
				temp[#temp + 1] = copy(nv2)
				temp[#temp + 1] = nv3
				temp[#temp + 1] = nv4
				temp[#temp + 1] = copy(nv3)
				temp[#temp + 1] = copy(nv2)
			elseif ov2 then
				nv1 = verts[i + 0]
				nv2 = verts[i + 2]
				nv3 = clip(verts[i + 1], nv1, plane, length, getUV)
				nv4 = clip(verts[i + 1], nv2, plane, length, getUV)

				temp[#temp + 1] = nv3
				temp[#temp + 1] = copy(nv2)
				temp[#temp + 1] = copy(nv1)
				temp[#temp + 1] = copy(nv2)
				temp[#temp + 1] = copy(nv3)
				temp[#temp + 1] = nv4
			elseif ov3 then
				nv1 = verts[i + 0]
				nv2 = verts[i + 1]
				nv3 = clip(verts[i + 2], nv1, plane, length, getUV)
				nv4 = clip(verts[i + 2], nv2, plane, length, getUV)

				temp[#temp + 1] = copy(nv1)
				temp[#temp + 1] = copy(nv2)
				temp[#temp + 1] = nv3
				temp[#temp + 1] = nv4
				temp[#temp + 1] = copy(nv3)
				temp[#temp + 1] = copy(nv2)
			end
		elseif total == 2 then
			if not ov1 then
				nv1 = copy(verts[i + 0])
				nv2 = clip(nv1, verts[i + 1], plane, length, getUV)
				nv3 = clip(nv1, verts[i + 2], plane, length, getUV)

				temp[#temp + 1] = nv1
				temp[#temp + 1] = nv2
				temp[#temp + 1] = nv3
			elseif not ov2 then
				nv1 = copy(verts[i + 1])
				nv2 = clip(nv1, verts[i + 2], plane, length, getUV)
				nv3 = clip(nv1, verts[i + 0], plane, length, getUV)

				temp[#temp + 1] = nv1
				temp[#temp + 1] = nv2
				temp[#temp + 1] = nv3
			elseif not ov3 then
				nv1 = copy(verts[i + 2])
				nv2 = clip(nv1, verts[i + 0], plane, length, getUV)
				nv3 = clip(nv1, verts[i + 1], plane, length, getUV)

				temp[#temp + 1] = nv1
				temp[#temp + 1] = nv2
				temp[#temp + 1] = nv3
			end
		end
	end
	return temp
end


--[[

]]
local function getVertsFromPrimitive(partnext, meshtex, meshbump, vmins, vmaxs, direct)
    partnext.primitive.skip_bounds = true
    partnext.primitive.skip_tangents = true
    partnext.primitive.skip_inside = true
    partnext.primitive.skip_invert = true
    partnext.primitive.skip_uv = meshtex and true

	if partnext.vsmooth == 1 and partnext.primitive then
		partnext.primitive.skip_normals = true
	end

	local _, submeshes = prop2mesh.primitive.construct.get(partnext.primitive.construct, partnext.primitive, false, false)
	submeshes = submeshes and submeshes.tris

	if not submeshes then
		return
	end

	local partpos = partnext.pos
	local partang = partnext.ang
	local partscale = partnext.scale
	local partclips = partnext.clips

	local partverts = {}
	local modeluv = not meshtex

	local submeshdata  = submeshes
	local submeshverts = {}

	for vertid = 1, #submeshdata do
		local vert   = submeshdata[vertid]
		local pos    = Vector(vert.pos)
		local normal = Vector(vert.normal)

		if partscale then
			pos.x = pos.x * partscale.x
			pos.y = pos.y * partscale.y
			pos.z = pos.z * partscale.z
		end

		local vcopy = {
			pos    = pos,
			normal = normal,
			rotate = submeshfix,
		}

		if modeluv then
			vcopy.u = vert.u
			vcopy.v = vert.v
		end

		submeshverts[#submeshverts + 1] = vcopy
	end

	if partclips then
		for clipid = 1, #partclips do
			submeshverts = applyClippingPlane(submeshverts, partclips[clipid].n, partclips[clipid].d, modeluv)
		end
	end

	for vertid = 1, #submeshverts do
		local vert = submeshverts[vertid]
		if vert.rotate then
			rotate(vert.normal, vert.rotate.ang or partang)
			rotate(vert.pos, vert.rotate.ang or partang)
			vert.rotate = nil
		else
			rotate(vert.normal, partang)
			rotate(vert.pos, partang)
		end
		add(vert.pos, partpos)
		partverts[#partverts + 1] = vert
		calcbounds(vmins, vmaxs, vert.pos)
	end

	if #partverts == 0 then
		return
	end

	local nflat = partnext.vsmooth == 1
	if meshtex or nflat then
		for pv = 1, #partverts, 3 do
			local normal = cross(partverts[pv + 2].pos - partverts[pv].pos, partverts[pv + 1].pos - partverts[pv].pos)
			normalize(normal)

			if nflat then
				partverts[pv    ].normal = Vector(normal)
				partverts[pv + 1].normal = Vector(normal)
				partverts[pv + 2].normal = Vector(normal)
			end

			if meshtex then
				local boxDir = getBoxDir(normal)
				partverts[pv    ].u, partverts[pv    ].v = getBoxUV(partverts[pv    ].pos, boxDir, meshtex)
				partverts[pv + 1].u, partverts[pv + 1].v = getBoxUV(partverts[pv + 1].pos, boxDir, meshtex)
				partverts[pv + 2].u, partverts[pv + 2].v = getBoxUV(partverts[pv + 2].pos, boxDir, meshtex)
			end
		end
	end

	if meshbump then calcTangents(partverts, not direct) end

	return partverts
end


local meshmodelcache
local function getVertsFromMDL(partnext, meshtex, meshbump, vmins, vmaxs, direct)
	local modelpath = partnext.prop or partnext.holo
	if prop2mesh.isBlockedModel(modelpath) then
		return
	end

	local submeshes
	if meshmodelcache[modelpath] then
		submeshes = meshmodelcache[modelpath][partnext.bodygroup or 0]
	else
		meshmodelcache[modelpath] = {}
	end
	if not submeshes then
		submeshes = util.GetModelMeshes(modelpath, 0, partnext.bodygroup or 0)
		if not submeshes then
			return
		end
		submeshes.modelfixer = prop2mesh.getModelFix(modelpath)
		submeshes.modelfixergeneric = isbool(submeshes.modelfixer)
		meshmodelcache[modelpath][partnext.bodygroup or 0] = submeshes
	end

	local partpos = partnext.pos
	local partang = partnext.ang
	local partscale = partnext.scale
	local partclips = partnext.clips
	--local partsubmodels = partnext.submodels

	local submeshfixlookup
	if submeshes.modelfixer then
		local rotated = Angle(partang)
		rotated:RotateAroundAxis(rotated:Up(), 90)

		submeshfixlookup = {}
		for submeshid = 1, #submeshes do
			if submeshes.modelfixergeneric then
				submeshfixlookup[submeshid] = { ang = rotated }
			else
				local ang = submeshes.modelfixer(submeshid, #submeshes, rotated, partang) or rotated
				submeshfixlookup[submeshid] = { ang = ang, diff = ang ~= rotated }
			end
		end

		if partscale then
			if partnext.holo then
				partscale = Vector(partscale.y, partscale.x, partscale.z)
			else
				partscale = Vector(partscale.x, partscale.z, partscale.y)
			end
		end

		if partclips then
			local clips = {}
			for clipid = 1, #partclips do
				local normal = Vector(partclips[clipid].n)
				rotate(normal, a90)
				clips[#clips + 1] = {
					d  = partclips[clipid].d,
					no = partclips[clipid].n,
					n  = normal,
				}
			end
			partclips = clips
		end
	end

	local partverts = {}
	local modeluv = not meshtex

	local submodels_whitelist, submodels_blacklist
	if partnext.submodels then
		if partnext.submodelswl then
			submodels_whitelist = partnext.submodels
		else
			submodels_blacklist = partnext.submodels
		end
	end

	for submeshid = 1, #submeshes do
		if submodels_blacklist then
			if submodels_blacklist[submeshid] then
				goto CONTINUE
			end
		elseif submodels_whitelist then
			if not submodels_whitelist[submeshid] then
				goto CONTINUE
			end
		end

		local submeshdata   = submeshes[submeshid].triangles
		local submeshfix    = submeshfixlookup and submeshfixlookup[submeshid]
		local submeshverts  = {}

		for vertid = 1, #submeshdata do
			local vert   = submeshdata[vertid]
			local pos    = Vector(vert.pos)
			local normal = Vector(vert.normal)

			if partscale then
				if submeshfix and submeshfix.diff then
					pos.x = pos.x * partnext.scale.x
					pos.y = pos.y * partnext.scale.y
					pos.z = pos.z * partnext.scale.z
				else
					pos.x = pos.x * partscale.x
					pos.y = pos.y * partscale.y
					pos.z = pos.z * partscale.z
				end
			end

			local vcopy = {
				pos    = pos,
				normal = normal,
				rotate = submeshfix,
			}

			if modeluv then
				vcopy.u = vert.u
				vcopy.v = vert.v
			end

			submeshverts[#submeshverts + 1] = vcopy
		end

		if partclips then
			if submeshfix then
				for clipid = 1, #partclips do
					submeshverts = applyClippingPlane(submeshverts, submeshfix.diff and partclips[clipid].no or partclips[clipid].n, partclips[clipid].d, modeluv)
				end
			else
				for clipid = 1, #partclips do
					submeshverts = applyClippingPlane(submeshverts, partclips[clipid].n, partclips[clipid].d, modeluv)
				end
			end
		end

		for vertid = 1, #submeshverts do
			local vert = submeshverts[vertid]
			if vert.rotate then
				rotate(vert.normal, vert.rotate.ang or partang)
				rotate(vert.pos, vert.rotate.ang or partang)
				vert.rotate = nil
			else
				rotate(vert.normal, partang)
				rotate(vert.pos, partang)
			end
			add(vert.pos, partpos)
			partverts[#partverts + 1] = vert
			calcbounds(vmins, vmaxs, vert.pos)
		end

		::CONTINUE::
	end

	if #partverts == 0 then
		return
	end

	local nflat = partnext.vsmooth == 1
	if meshtex or nflat then
		for pv = 1, #partverts, 3 do
			local normal = cross(partverts[pv + 2].pos - partverts[pv].pos, partverts[pv + 1].pos - partverts[pv].pos)
			normalize(normal)

			if nflat then
				partverts[pv    ].normal = Vector(normal)
				partverts[pv + 1].normal = Vector(normal)
				partverts[pv + 2].normal = Vector(normal)
			end

			if meshtex then
				local boxDir = getBoxDir(normal)
				partverts[pv    ].u, partverts[pv    ].v = getBoxUV(partverts[pv    ].pos, boxDir, meshtex)
				partverts[pv + 1].u, partverts[pv + 1].v = getBoxUV(partverts[pv + 1].pos, boxDir, meshtex)
				partverts[pv + 2].u, partverts[pv + 2].v = getBoxUV(partverts[pv + 2].pos, boxDir, meshtex)
			end
		end
	end

	if meshbump then calcTangents(partverts, not direct) end

	return partverts
end

local function getFallbackOBJ(custom, partnext, meshtex, meshbump, vmins, vmaxs, direct)
	local modeluid = tonumber(partnext.objd)
	local modelobj = custom[modeluid]

	if not modelobj then
		return
	end

	local omins, omaxs = Vector(), Vector()

	local pos = partnext.pos
	local ang = partnext.ang
	local scale = partnext.scale

	if scale then
		if scale.x == 1 and scale.y == 1 and scale.z == 1 then scale = nil end
	end

	local parseLoopCount = 0
	for line in string.gmatch(modelobj, "(.-)\n") do
		if not direct and (parseLoopCount % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
		parseLoopCount = parseLoopCount + 1
		local temp = string_explode(" ", string_gsub(string_trim(line), "%s+", " "))
		local head = table_remove(temp, 1)

		if head == "v" then
			local vert = Vector(tonumber(temp[1]), tonumber(temp[2]), tonumber(temp[3]))
			if scale then
				vert.x = vert.x * scale.x
				vert.y = vert.y * scale.y
				vert.z = vert.z * scale.z
			end
			calcbounds(omins, omaxs, vert)
		end
	end

	pos = (omins + omaxs)*0.5
	ang = ang or Angle()

	return getVertsFromMDL({ang	= ang, pos	= pos, prop = "models/hunter/blocks/cube025x025x025.mdl", scale = (omaxs - omins)/12}, meshtex, meshbump, vmins, vmaxs, direct)
end

-- Rewritten to use less string/gmatch/string indices etc
local getChar            = string.byte

local NEWLINE = getChar('\n')
local SPACE   = getChar(' ')
local POUND   = getChar('#')
local PERIOD  = getChar('.')
local DASH    = getChar('-')
local SLASH  = getChar('/')

local validOBJHeaders = {}
local maxObjHeaderDepth = 0
local function addHeaderFunction(header, func)
	local lookup = validOBJHeaders
	for i = 1, #header do
		local index = getChar(header, i)
		local tempLookup = lookup[index]
		if not tempLookup then
			tempLookup = {}
			lookup[index] = tempLookup
		end
		if i > maxObjHeaderDepth then
			maxObjHeaderDepth = i
		end
		lookup = tempLookup
	end

	lookup[SPACE] = func
end

-- Returns the character index in a string from a match condition
local function skipUntil(modelobj, i, matchCond)
	for c = 0, 1024 do
		local ch = getChar(modelobj, i)
		if not ch or ch == 0 then return i end

		if matchCond(ch) then
			return i
		end
		i = i + 1
	end

	return false, "Too much data in a data field!"
end

local CONDITION_ISNEWLINE  = function(ch) return ch == NEWLINE end
local CONDITION_ISNOTSPACE = function(ch) return ch ~= SPACE end
local CONDITION_ISNOTWHITESPACE = function(ch) return ch ~= SPACE and ch ~= NEWLINE end

local function skipToNextLine(modelobj, i)
	local err
	i, err = skipUntil(modelobj, i, CONDITION_ISNEWLINE)
	if i then return i + 1 end
	return i, err
end

local function unimplementedHeader(header)
	addHeaderFunction(header, function(modelobj, i)
		return skipToNextLine(modelobj, i)
	end)
end

local DIGITS = {}
for i = 0, 9 do DIGITS[getChar(tostring(i))] = i end
local function bytesToNumber(modelobj, i)
	local num = 0
	local dec = false
	local neg = 1
	for _ = 1, 128 do
		local ch = getChar(modelobj, i)
		if not ch or ch == 0 then break end
		i = i + 1

		local di = DIGITS[ch]
		if not di then
			if ch == PERIOD then
				dec = 1 -- switching to divisor mode
			elseif _ == 1 and ch == DASH then
				neg = -1
			else
				break
			end
		elseif not dec then
			num = (num * 10) + di
		else
			dec = dec * 10
			num = num + (di / dec)
		end
	end
	return num * neg, i
end

local function getFace(modelobj, i)
	local face = {}
	local x
	for k = 1, 32 do
		x, i = bytesToNumber(modelobj, i)
		face[k] = x
		local ch = getChar(modelobj, i - 1)
		if ch ~= SLASH then break end
	end

	return i, face
end

addHeaderFunction("f", function(modelobj, i, vmesh, vlook, vmins, vmaxs, pos, ang, scale, invert, meshtex)
	local f1, f2
	i, f1 = getFace(modelobj, i) if not i then return i, "Bad face 1" end
	i, f2 = getFace(modelobj, i) if not i then return i, "Bad face 2" end

	for k = 3, 256 do
		i, f3 = getFace(modelobj, i) if not i then return i, "Bad face " .. k end

		local v1, v2, v3
		if invert then
			v1 = { pos = Vector(vlook[f3[1]]) }
			v2 = { pos = Vector(vlook[f2[1]]) }
			v3 = { pos = Vector(vlook[f1[1]]) }
		else
			v1 = { pos = Vector(vlook[f1[1]]) }
			v2 = { pos = Vector(vlook[f2[1]]) }
			v3 = { pos = Vector(vlook[f3[1]]) }
		end

		local normal = cross(v3.pos - v1.pos, v2.pos - v1.pos)
		normalize(normal)

		v1.normal = Vector(normal)
		v2.normal = Vector(normal)
		v3.normal = Vector(normal)

		local boxDir = getBoxDir(normal)
		v1.u, v1.v = getBoxUV(v1.pos, boxDir, meshtex)
		v2.u, v2.v = getBoxUV(v2.pos, boxDir, meshtex)
		v3.u, v3.v = getBoxUV(v3.pos, boxDir, meshtex)

		vmesh[#vmesh + 1] = v1
		vmesh[#vmesh + 1] = v2
		vmesh[#vmesh + 1] = v3

		f2 = f3
		-- Get the character here
		if getChar(modelobj, i - 1) == NEWLINE then
			break
		end
	end

	return i
end)
addHeaderFunction("v", function(modelobj, i, vmesh, vlook, vmins, vmaxs, pos, ang, scale, invert, meshtex)
	local x, y, z
	local err

	x, i = bytesToNumber(modelobj, i)
	i, err = skipUntil(modelobj, i, CONDITION_ISNOTSPACE) if not i then return i, err end
	y, i = bytesToNumber(modelobj, i)
	i, err = skipUntil(modelobj, i, CONDITION_ISNOTSPACE) if not i then return i, err end
	z, i = bytesToNumber(modelobj, i)

	local vert
	if scale then
		vert = Vector(x * scale[1], y * scale[2], z * scale[3])
	else
		vert = Vector(x, y, z)
	end

	if ang then rotate(vert, ang) end
	if pos then add(vert, pos) end
	vlook[#vlook + 1] = vert
	calcbounds(vmins, vmaxs, vert)

	i, err = skipToNextLine(modelobj, i - 2) if not i then return i, err end
	return i
end)
unimplementedHeader("#")
unimplementedHeader("vt")
unimplementedHeader("vn")
unimplementedHeader("vp")
unimplementedHeader("l")
unimplementedHeader("p")
unimplementedHeader("o")
unimplementedHeader("g")
unimplementedHeader("s")
unimplementedHeader("mtllib")
unimplementedHeader("usemtl")

local function tryParseObj(modelobj, vmesh, vlook, vmins, vmaxs, pos, ang, scale, invert, meshtex)
	local line = 1
	local i    = 1
	local len  = #modelobj
	local err
	local parseFailed

	for iter = 1, 1000000 do
		i, err = skipUntil(modelobj, i, CONDITION_ISNOTWHITESPACE)
		if not i then return err or "??", i, line end
		-- Start header lookup
		local lookup = validOBJHeaders
		for d = 0, maxObjHeaderDepth do
			local char = getChar(modelobj, i + d)
			lookup = lookup[char]

			-- From what I can tell comments don't require the space inbetween the header and comment
			-- So just in case that is true, this is a special case to handle that
			if d == 0 and char == POUND then lookup = lookup[SPACE] i = i + 1 break end

			if lookup then
				if char == SPACE then
					-- When char == SPACE and lookup is present, then a header function exists and the loop breaks

					-- Lets say v 0 0 0 was the line
					-- i would be 1, pointing to v
					-- +d points to whatever is after v

					i = i + d
					break
				end
			else
				-- Parsing failed
				parseFailed = "parsing failed, invalid header '" .. string.sub(modelobj, i, i + d) .. "'"
				break
			end
		end

		if parseFailed then return parseFailed, i, line end
		-- Skip whitespace
		i, err = skipUntil(modelobj, i, CONDITION_ISNOTSPACE) if not i then return err, i, line end
		local newI
		newI, err = lookup(modelobj, i, vmesh, vlook, vmins, vmaxs, pos, ang, scale, invert, meshtex)
		if not newI then return err or "<no error provided>", i, line end
		line = line + 1
		i = newI
		if i > len then break end
	end
end

local function getVertsFromOBJ(custom, partnext, meshtex, meshbump, vmins, vmaxs, direct)
	if disable_obj then
		return getFallbackOBJ(custom, partnext, meshtex, meshbump, vmins, vmaxs, direct)
	end

	local modeluid = tonumber(partnext.objd)
	local modelobj = custom[modeluid]

	if not modelobj then
		return
	end

	local pos = partnext.pos
	local ang = partnext.ang
	local scale = partnext.scale

	if pos and (pos.x == 0 and pos.y == 0 and pos.z == 0) then pos = nil end
	if ang and (ang.p == 0 and ang.y == 0 and ang.r == 0) then ang = nil end
	if scale and (scale[1] == 1 and scale[2] == 1 and scale[3] == 1) then scale = nil end

	local vlook = {}
	local vmesh = {}

	meshtex = meshtex or 1 / 48
	local invert = partnext.vinvert
	local smooth = partnext.vsmooth
	local parseErr, errChar, errLine = tryParseObj(modelobj, vmesh, vlook, vmins, vmaxs, pos, ang, scale, invert, meshtex)
	if parseErr then
		if devcvar:GetBool() then
			ErrorNoHalt("Prop2Mesh getVertsFromOBJ failure at line " .. errLine .. ", char " .. errChar .. ": " .. tostring(parseErr) .. "\n")
		end

		coroutine_yield(false)
	end

	local validMesh = vmesh and #vmesh > 0
	-- https:--github.com/thegrb93/StarfallEx/blob/b6de9fbe84040e9ebebcbe858c30adb9f7d937b5/lua/starfall/libs_sh/mesh.lua#L229
	-- credit to Sevii
	if validMesh and smooth and smooth ~= 0 then
		local smoothrad = math_cos(math_rad(smooth))
		if smoothrad ~= 1 then
			local norms = setmetatable({},{__index = function(t,k) local r=setmetatable({},{__index=function(t,k) local r=setmetatable({},{__index=function(t,k) local r={} t[k]=r return r end}) t[k]=r return r end}) t[k]=r return r end})
			for i, vertex in ipairs(vmesh) do
				if not direct and (i % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
				local pos = vertex.pos
				local norm = norms[pos[1]][pos[2]][pos[3]]
				norm[#norm+1] = vertex.normal
			end

			for i, vertex in ipairs(vmesh) do
				if not direct and (i % YIELD_THRESHOLD == 0) then coroutine_yield(false) end
				local normal = Vector()
				local count = 0
				local pos = vertex.pos

				for _, norm in ipairs(norms[pos[1]][pos[2]][pos[3]]) do
					if dot(vertex.normal, norm) >= smoothrad then
						add(normal, norm)
						count = count + 1
					end
				end

				if count > 1 then
					div(normal, count)
					vertex.normal = normal
				end
			end
		end
	end

	if validMesh and meshbump then calcTangents(vmesh, not direct) end

	return validMesh and vmesh
end


--[[

]]
local function getMeshFromData(data, uniqueID, direct, split)
	if not data or not uniqueID then
		if not direct then coroutine_yield(true) else return end
	end
	local partlist = util.JSONToTable(util.Decompress(data))
	if not partlist then
		if not direct then coroutine_yield(true) else return end
	end

	prop2mesh.loadModelFixer()
	if not meshmodelcache then
		meshmodelcache = {}
	end

	local uvb = string.Explode("_", uniqueID .. "")
	uvb[1] = tonumber(uvb[1] or 16)

	local meshpcount = 0
	local meshvcount = 0
	local vmins = Vector()
	local vmaxs = Vector()
	local meshtex = (uvb[1] and uvb[1] ~= 0) and (1 / uvb[1]) or nil
	local meshbump = tobool(uvb[2]) or system.IsLinux()

	local meshlist = { {} }
	local meshnext = meshlist[1]

	local partcount = #partlist

	for partid = 1, partcount do
		local partnext = partlist[partid]
		local partverts

		if partnext.prop or partnext.holo then
			partverts = getVertsFromMDL(partnext, meshtex, meshbump, vmins, vmaxs, direct)
		elseif partnext.objd and partlist.custom then
			local valid, opv = pcall(getVertsFromOBJ, partlist.custom, partnext, meshtex, meshbump, vmins, vmaxs, direct)
			if valid and opv then
				partverts = opv
			else
				print(opv)
			end
		elseif partnext.primitive then
			local valid, opv = pcall(getVertsFromPrimitive, partnext, meshtex, meshbump, vmins, vmaxs, direct)
			if valid and opv then
				partverts = opv
			else
				print(opv)
			end
		end

		if partverts then
			meshpcount = meshpcount + 1

			if partnext.vinside then
				for pv = #partverts, 1, -1 do
					local vdupe = copy(partverts[pv])
					vdupe.normal = -vdupe.normal
					partverts[#partverts + 1] = vdupe
				end
			end

			local partvcount = #partverts
			if #meshnext + partvcount > 63999 or split then
				meshlist[#meshlist + 1] = {}
				meshnext = meshlist[#meshlist]
			end
			for pv = 1, partvcount do
				meshnext[#meshnext + 1] = partverts[pv]
			end
			meshvcount = meshvcount + partvcount
		end

		if not direct then coroutine_yield(false) end
	end

	if not direct then
		coroutine_yield(true, { meshes = meshlist, vcount = meshvcount, vmins = vmins, vmaxs = vmaxs, pcount = meshpcount })
	else
		return meshlist
	end
end


--[[

]]
local meshlabs = {}
function prop2mesh.getMesh(crc, uniqueID, data)
	if not crc or not uniqueID or not data then
		return false
	end

	local key = string.format("%s_%s", crc, uniqueID)
	if not meshlabs[key] then
		meshlabs[key] = { crc = crc, uniqueID = uniqueID, data = data, coro = coroutine.create(getMeshFromData) }
		return true
	end

	return false
end

function prop2mesh.getMeshDirect(crc, uniqueID)
	local data = prop2mesh.getMeshData(crc)
	if not data then
		return
	end

	local meshlist = getMeshFromData(data, uniqueID, true, true)

	prop2mesh.unloadModelFixer()
	meshmodelcache = nil

	return meshlist
end

local message
local function setmessage(text)
	if not IsValid(message) then
		local parent
		if GetOverlayPanel then parent = GetOverlayPanel() end

		message = vgui.Create("DPanel", parent)

		local green = Color(255, 255, 0)
		local black = Color(0,0,0)
		local font  = "Default"

		message.Paint = function(self, w, h)
			draw.SimpleTextOutlined(self.text, font, 0, 0, green, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, black)
		end

		message.SetText = function(self, txt)
			if self.text ~= txt then
				self.text = txt

				surface.SetFont(font)
				local w, h = surface.GetTextSize(self.text)

				self:SetPos(ScrW() - w - 1, ScrH() - h - 1)
				self:SetSize(w, h)
			end
		end
	end

	message:SetText(text)
	message.time = SysTime()
end

local function pluralf(pattern, number)
	return string.format(pattern, number, number == 1 and "" or "s")
end

prop2mesh.maxCpuTimeLoad = 0.005
hook.Add("Think", "prop2mesh_meshlab", function()
	if not prop2mesh or not prop2mesh.downloads then
		return
	end

	if prop2mesh.downloads > 0 then
		setmessage(pluralf("prop2mesh %d server download%s remaining", prop2mesh.downloads))
	end
	if message and SysTime() - message.time > 0.25 then
		if IsValid(message) then
			message:Remove()
		end
		message = nil
	end

	local key, lab = next(meshlabs)
	if not key or not lab then
		return
	end

	local curtime = SysTime()
	local maxCpuTimeLoad = prop2mesh.maxCpuTimeLoad
	while SysTime() - curtime < maxCpuTimeLoad do
		local ok, err, mdata = coroutine.resume(lab.coro, lab.data, lab.uniqueID)

		if not ok then
			if devcvar:GetBool() then
				ErrorNoHaltWithStack("Prop2Mesh Meshlab error: " .. (tostring(err) or "<nil>"))
			end

			meshlabs[key] = nil
			break
		end

		if err then
			hook.Run("prop2mesh_hook_meshdone", lab.crc, lab.uniqueID, mdata)
			meshlabs[key] = nil
			break
		end
	end

	if next(meshlabs) == nil then
		prop2mesh.unloadModelFixer()
		meshmodelcache = nil
	else
		if not message then
			setmessage(pluralf("prop2mesh %d mesh build%s remaining", table.Count(meshlabs)))
		end
	end
end)
