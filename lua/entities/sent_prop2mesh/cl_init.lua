--[[

]]
include("shared.lua")

local prop2mesh = prop2mesh

local defaultmat = Material(prop2mesh.defaultmat)
local wireframe = Material("models/debug/debugwhite")

local net = net
local cam = cam
local table = table
local render = render
local string = string
local table_insert = table.insert

local Mesh = Mesh
local Angle = Angle
local Color = Color
local Vector = Vector
local Matrix = Matrix
local unpack = unpack
local IsValid = IsValid
local SysTime = SysTime
local LocalToWorld = LocalToWorld
local RENDERGROUP_BOTH = RENDERGROUP_BOTH
local RENDERMODE_NORMAL = RENDERMODE_NORMAL
local RENDERGROUP_OPAQUE = RENDERGROUP_OPAQUE
local RENDERMODE_TRANSCOLOR = RENDERMODE_TRANSCOLOR

local entMeta = FindMetaTable("Entity")
local Ent_GetPos = entMeta.GetPos
local Ent_SetPos = entMeta.SetPos
local Ent_Remove = entMeta.Remove
local Ent_SetColor = entMeta.SetColor
local Ent_GetTable = entMeta.GetTable
local Ent_DrawModel = entMeta.DrawModel
local Ent_GetAngles = entMeta.GetAngles
local Ent_GetParent = entMeta.GetParent
local Ent_SetParent = entMeta.SetParent
local Ent_SetAngles = entMeta.SetAngles
local Ent_SetMaterial = entMeta.SetMaterial
local Ent_EnableMatrix = entMeta.EnableMatrix
local Ent_DisableMatrix = entMeta.DisableMatrix
local Ent_SetRenderMode = entMeta.SetRenderMode
local Ent_SetRenderBounds = entMeta.SetRenderBounds
local Ent_GetWorldTransformMatrix = entMeta.GetWorldTransformMatrix

local vecMeta = FindMetaTable("Vector")

local angZero = Angle()
local vecZero = Vector()

local empty = { Mesh = Mesh(), Material = Material("models/debug/debugwhite") }
empty.Mesh:BuildFromTriangles({{pos = Vector()},{pos = Vector()},{pos = Vector()}})

do
	local cvar = CreateClientConVar("prop2mesh_cache_time", 604800, true, false, "How long to keep cached prop2mesh data in seconds (default 1 week)")
	file.CreateDir("p2m_cache")
	local maxAge = cvar:GetInt()

	local removed = 0
	local failed = 0
	for _, v in pairs(file.Find("p2m_cache/*.dat", "DATA")) do
		local path = "p2m_cache/" .. v
		if os.time() - file.Time(path, "DATA") > maxAge then
			local deleted = file.Delete(path)
			if deleted then
				removed = removed + 1
			else
				failed = failed + 1
			end
		end
	end

	if removed ~= 0 or failed ~= 0 then
		print("prop2mesh: Cache cleanup complete. Removed " .. removed .. " files" )
		if failed ~= 0 then
			print("prop2mesh: Failed to remove " .. failed .. " files")
		end
	end
end

if not prop2mesh.recycle then prop2mesh.recycle = {} end
if not prop2mesh.garbage then prop2mesh.garbage = {} end

local recycle = prop2mesh.recycle
local garbage = prop2mesh.garbage

function prop2mesh.getMeshInfo(crc, uniqueID)
	local recycled = recycle[crc]
	local mdata = recycled and recycled.meshes[uniqueID]
	if mdata then
		return mdata.pcount, mdata.vcount
	end
end

function prop2mesh.getMeshData(crc, unzip)
	local recycled = recycle[crc]
	local dat = recycled and recycled.zip
	if not unzip or not dat then
		return dat
	end
	return util.JSONToTable(util.Decompress(dat))
end

--[[
concommand.Add("prop2mesh_dump", function()
	PrintTable(recycle)
	PrintTable(garbage)
end)
]]

timer.Create("prop2trash", 60, 0, function()
	local curtime = SysTime()
	for crc, usedtime in pairs(garbage) do
		if curtime - usedtime > 60 then
			if recycle[crc] and recycle[crc].meshes then
				for uniqueID, meshdata in pairs(recycle[crc].meshes) do
					if meshdata.basic then
						if IsValid(meshdata.basic.Mesh) then
							--print("destroying", meshdata.basic.Mesh)
							meshdata.basic.Mesh:Destroy()
							meshdata.basic.Mesh = nil
						end
					end
					if meshdata.complex then
						for m, meshpart in pairs(meshdata.complex) do
							if IsValid(meshpart) then
								--print("destroying", meshpart)
								meshpart:Destroy()
								meshdata.complex[m] = nil
							end
						end
					end
				end
			end
			recycle[crc] = nil
			garbage[crc] = nil
		end
	end
end)

local downloadQueue = {}
timer.Create("prop2mesh_download", 0, 0, function()
	if #downloadQueue == 0 then return end

	local request = table.remove(downloadQueue, 1)
	if not IsValid(request.ent) then return end

	net.Start("prop2mesh_download")
	net.WriteEntity(request.ent)
	net.WriteString(request.crc)
	net.SendToServer()
end)

local function checkdownload(self, crc)
	if recycle[crc] then
		return true
	end

	recycle[crc] = { users = {}, meshes = {} }

	if file.Exists("p2m_cache/" .. crc .. ".dat", "DATA") then
		local data = file.Read("p2m_cache/" .. crc .. ".dat", "DATA")
		if data and util.CRC(data) == crc then
			prop2mesh.handleDownload(crc, data)
			return true
		end

		file.Delete("p2m_cache/" .. crc .. ".dat")
	end

	table.insert(downloadQueue, {ent = self, crc = crc})

	return false
end
prop2mesh.checkdownload = checkdownload

local function setuser(self, crc, bool)
	local recycled = recycle[crc]

	if not recycled then
		garbage[crc] = nil
		return
	end
	if bool then
		recycled.users[self] = true
		garbage[crc] = nil
	else
		recycled.users[self] = nil
		if not next(recycled.users) then
			garbage[crc] = SysTime()
		end
	end
end
prop2mesh.setuser = setuser

local function setRenderBounds(self, min, max, scale)
	if not min or not max then return end
	if scale and (scale.x ~= 1 or scale.y ~= 1 or scale.z ~= 1) then
		Ent_SetRenderBounds(self, Vector(min.x*scale.x, min.y*scale.y, min.z*scale.z), Vector(max.x*scale.x, max.y*scale.y, max.z*scale.z))
	else
		Ent_SetRenderBounds(self, min, max)
	end
end

local function checkmesh(crc, uniqueID)
	local recycled = recycle[crc]
	if not recycled or not recycled.zip or recycled.meshes[uniqueID] then
		return recycled.meshes[uniqueID]
	end
	recycled.meshes[uniqueID] = {}
	prop2mesh.getMesh(crc, uniqueID, recycled.zip)
end

hook.Add("prop2mesh_hook_meshdone", "prop2mesh_meshlab", function(crc, uniqueID, mdata)
	if not mdata or not crc or not uniqueID or not recycle[crc] then
		return
	end

	recycle[crc].meshes[uniqueID] = mdata

	local meshes = mdata.meshes
	local meshCount = #meshes
	if meshCount == 1 then
		local imesh = Mesh()
		imesh:BuildFromTriangles(meshes[1])
		mdata.basic = { Mesh = imesh, Material = defaultmat }
	else
		local complex = {}
		for i = 1, meshCount do
			local imesh = Mesh()
			imesh:BuildFromTriangles(meshes[i])
			table_insert(complex, imesh)
		end

		mdata.complex = complex
	end

	mdata.meshes = nil
	mdata.ready = true

	local mins = mdata.vmins
	local maxs = mdata.vmaxs

	if mins and maxs then
		for user in pairs(recycle[crc].users) do
			if IsValid(user) then
				for k, info in pairs(user.prop2mesh_controllers) do
					if IsValid(info.ent) and info.crc == crc and info.uniqueID == uniqueID then
						setRenderBounds(info.ent, mins, maxs, info.scale)
						--info.ent:SetRenderBounds(mins, maxs)
					end
				end
			else
				setuser(user, crc, false)
			end
		end
	end
end)


--[[

]]
local cvar = CreateClientConVar("prop2mesh_render_disable", 0, true, false)
local draw_disable = cvar:GetBool()

cvars.AddChangeCallback("prop2mesh_render_disable", function(cvar, old, new)
	draw_disable = tobool(new)
end, "swapdrawdisable")

local draw_wireframe
concommand.Add("prop2mesh_render_wireframe", function(ply, cmd, args)
	draw_wireframe = not draw_wireframe
end)


--[[

]]
local function getComplex(crc, uniqueID)
	local meshes = recycle[crc] and recycle[crc].meshes[uniqueID]
	return meshes and meshes.complex
end

local vec = Vector()
local debugwhite = CreateMaterial("p2mdebugwhite", "UnlitGeneric", {
	["$basetexture"] = "color/white",
	["$vertexcolor"] = 1
})

local renderOverride
do
	local Vec_Dot = vecMeta.Dot
	local Vec_Rotate = vecMeta.Rotate
	local render_EnableClipping = render.EnableClipping
	local render_PopCustomClipPlane = render.PopCustomClipPlane
	local render_PushCustomClipPlane = render.PushCustomClipPlane

	renderOverride = function(self)
		local prev = render_EnableClipping(true)

		local pos = Ent_GetPos(self)
		local ang = Ent_GetAngles(self)

		local clips = self.clips
		local clipCount = #clips
		for i = 1, clipCount do
			local clip = clips[i]
			local norm = Vector(clip.n)
			Vec_Rotate(norm, ang)

			render_PushCustomClipPlane(norm, Vec_Dot(norm, pos + norm * clip.d))
		end

		Ent_DrawModel(self)

		-- if true then
		-- 	render.CullMode(MATERIAL_CULLMODE_CW)
		-- 	self:DrawModel()
		-- 	render.CullMode(MATERIAL_CULLMODE_CCW)
		-- end

		for _ = 1, clipCount do
			render_PopCustomClipPlane()
		end

		render_EnableClipping(prev)
	end
end

local drawModel
do
	local Vec_SetUnpacked = vecMeta.SetUnpacked
	local Ent_GetColor = entMeta.GetColor
	local Ent_GetRenderBounds = entMeta.GetRenderBounds

	local render_DrawBox = render.DrawBox
	local render_SetBlend = render.SetBlend
	local render_SetMaterial = render.SetMaterial
	local render_DrawWireframeBox = render.DrawWireframeBox
	local render_SetColorModulation = render.SetColorModulation
	local render_ModelMaterialOverride = render.ModelMaterialOverride
	local render_SuppressEngineLighting = render.SuppressEngineLighting

	drawModel = function(self)
		local selfTable = Ent_GetTable( self )

		if draw_disable then
			local pos = Ent_GetPos(self)
			local angles = Ent_GetAngles(self)

			local min, max = Ent_GetRenderBounds(self)
			local color = Ent_GetColor(self)
			Vec_SetUnpacked(vec, color.r/255, color.g/255, color.b/255)
			debugwhite:SetVector("$color", vec)
			render_SetMaterial(debugwhite)
			render_DrawBox(pos, angles, min, max)
			render_DrawWireframeBox(pos, angles, min, max, color_black, true)
			return
		end

		if draw_wireframe and selfTable.isowner then
			render_SetBlend(0.025)
			render_SetColorModulation(1, 1, 1)
			render_SuppressEngineLighting(true)
			render_ModelMaterialOverride(wireframe)
			Ent_DrawModel(self)
			render_SetBlend(1)
			render_SuppressEngineLighting(false)
			render_ModelMaterialOverride()
		else
			Ent_DrawModel(self)
		end

		local complex = getComplex(selfTable.crc, selfTable.uniqueID)
		if complex then
			local matrix = Ent_GetWorldTransformMatrix(self)
			local scale = selfTable.scale
			if scale then
				matrix:SetScale(scale)
			end
			cam.PushModelMatrix(matrix)
			for i = 1, #complex do
				complex[i]:Draw()
			end
			cam.PopModelMatrix()
		end
	end
end

local function drawMesh(self)
	local meshes = recycle[self.crc] and recycle[self.crc].meshes[self.uniqueID]
	return meshes and meshes.basic or empty
end

local function refreshSetColor(infoEnt, col)
	local isOpaque = col.a == 255

	Ent_SetColor(infoEnt, col)
	Ent_SetRenderMode(infoEnt, isOpaque and RENDERMODE_NORMAL or RENDERMODE_TRANSCOLOR)
	infoEnt.RenderGroup = isOpaque and RENDERGROUP_OPAQUE or RENDERGROUP_BOTH
end

local function refreshSetScale(infoEnt, scale)
	if scale.x ~= 1 or scale.y ~= 1 or scale.z ~= 1 then
		local matrix = Matrix()
		matrix:SetScale(scale)
		Ent_EnableMatrix(infoEnt, "RenderMultiply", matrix)
		infoEnt.scale = scale
	else
		Ent_DisableMatrix(infoEnt, "RenderMultiply")
		infoEnt.scale = nil
	end
end

local function refreshSetPosAng(infoEnt, info, p2mEnt)
	local linkEnt = info.linkent
	local parent = IsValid(linkEnt) and linkEnt or p2mEnt
	local pos, ang = LocalToWorld(info.linkpos or vecZero, info.linkang or angZero, Ent_GetPos(parent), Ent_GetAngles(parent))

	if parent ~= Ent_GetParent(infoEnt) then
		Ent_SetParent(infoEnt, parent)
	end

	Ent_SetPos(infoEnt, pos)
	Ent_SetAngles(infoEnt, ang)
end

local function refresh(self, info)
	local infoEnt = info.ent

	if not IsValid(infoEnt) then
		infoEnt = ents.CreateClientside("base_anim")
		infoEnt:SetModel("models/hunter/plates/plate.mdl")
		infoEnt:DrawShadow(false)
		infoEnt.Draw = drawModel
		infoEnt.GetRenderMesh = drawMesh
		infoEnt:Spawn()
		infoEnt:Activate()

		info.ent = infoEnt
	end

	local infoEntTable = Ent_GetTable(infoEnt)

	Ent_SetMaterial(infoEnt, info.mat)
	refreshSetColor(infoEnt, info.col)
	refreshSetScale(infoEnt, info.scale)
	refreshSetPosAng(infoEnt, info, self)

	local infoCrc = info.crc
	local infoUniqueID = info.uniqueID
	infoEntTable.crc = infoCrc
	infoEntTable.uvs = info.uvs
	infoEntTable.bump = info.bump
	infoEntTable.uniqueID = infoUniqueID
	infoEntTable.isowner = self.isowner

	local infoClips = info.clips
	if infoClips then
		infoEntTable.clips = infoClips
		infoEntTable.RenderOverride = renderOverride
	else
		infoEntTable.RenderOverride = nil
	end

	if checkdownload(self, infoCrc) then
		local mdata = checkmesh(infoCrc, infoUniqueID)
		if mdata and mdata.ready then
			setRenderBounds(infoEnt, mdata.vmins, mdata.vmaxs, infoEntTable.scale)
		end
	end

	setuser(self, infoCrc, true)
end
prop2mesh.refresh = refresh

local function refreshAll(self, prop2mesh_controllers)
	for k, info in pairs(prop2mesh_controllers) do
		refresh(self, info)
	end
end

local function discard(self, prop2mesh_controllers)
	if not prop2mesh_controllers then
		return
	end

	for _, info in pairs(prop2mesh_controllers) do
		local infoEnt = info.ent
		if IsValid(infoEnt) then
			Ent_Remove(infoEnt)
			info.ent = nil
		end

		setuser(self, info.crc, false)
	end
end


--[[

]]
function ENT:Initialize()
	self.prop2mesh_controllers = {}
end

function ENT:Draw()
	Ent_DrawModel(self)
end

local function SyncOwner(self)
	if not CPPI or game.SinglePlayer() then
		self.isowner = true
		return
	end
	self.isowner = self:CPPIGetOwner() == LocalPlayer()
end

function ENT:Think()
	if not self.prop2mesh_sync then
		SyncOwner(self)
		refreshAll(self, self.prop2mesh_controllers)

		net.Start("prop2mesh_sync")
		net.WriteEntity(self)
		net.WriteString(self.prop2mesh_synctime or "")
		net.SendToServer()

		self.prop2mesh_refresh = nil
		self.prop2mesh_sync = true
	end

	if self.prop2mesh_refresh then
		SyncOwner(self)
		refreshAll(self, self.prop2mesh_controllers)
		self.prop2mesh_refresh = nil
	end
end

function ENT:OnRemove()
	local snapshot = self.prop2mesh_controllers
	if not snapshot or next(snapshot) == nil then
		return
	end
	timer.Simple(0, function()
		if IsValid(self) then
			return
		end
		discard(self, snapshot)
	end)
end

function ENT:GetAllDataReady()
	for k, info in ipairs(self.prop2mesh_controllers) do
		local crc = info.crc
		if not crc or crc == "!none" then
			goto CONTINUE
		end

		if not recycle[crc] or not recycle[crc].zip then
			return false, 1
		else
			local meshes = recycle[crc].meshes[info.uniqueID]
			if not meshes or (meshes and not meshes.ready) then
				return false, 2
			end
		end

		::CONTINUE::
	end

	return true, 3
end

function ENT:GetDownloadProgress()
	--[[
	local max
	for i = 1, #self.prop2mesh_controllers do
		local stream = recycle[self.prop2mesh_controllers[i].crc].stream
		if stream then
			if not max then max = 0 end
			local progress = stream:GetProgress()
			if max < progress then
				max = progress
			end
		end
	end
	return max
	]]
	return 1
end


local kvpass = {}
local function applyPropertyWithKVPass(ent, index, key, val)
	local info = ent.prop2mesh_controllers[index]
	if not info then return end

	local pass = kvpass[key]

	if pass then
		pass(self, info, val)
		val = info[key] -- Get the modified result
	else
		info[key] = val
	end

	return val, info.ent
end

function ENT:SetControllerCol(index, col)
	local infoEnt
	col, infoEnt = applyPropertyWithKVPass(self, index, "col", col)
	if col == nil then return end
	if not IsValid(infoEnt) then return end

	refreshSetColor(infoEnt, col)
end

function ENT:SetControllerPos(index, linkpos)
	local infoEnt
	linkpos, infoEnt = applyPropertyWithKVPass(self, index, "linkpos", linkpos)
	if linkpos == nil then return end
	if not IsValid(infoEnt) then return end

	refreshSetPosAng(infoEnt, self.prop2mesh_controllers[index], self)
end

function ENT:SetControllerAng(index, linkang)
	local infoEnt
	linkang, infoEnt = applyPropertyWithKVPass(self, index, "linkang", linkang)
	if linkang == nil then return end
	if not IsValid(infoEnt) then return end

	refreshSetPosAng(infoEnt, self.prop2mesh_controllers[index], self)
end

function ENT:SetControllerMat(index, mat)
	local infoEnt
	mat, infoEnt = applyPropertyWithKVPass(self, index, "mat", mat)
	if mat == nil then return end
	if not IsValid(infoEnt) then return end

	Ent_SetMaterial(infoEnt, mat)
end

function ENT:SetControllerScale(index, scale)
	local infoEnt
	scale, infoEnt = applyPropertyWithKVPass(self, index, "scale", scale)
	if scale == nil then return end
	if not IsValid(infoEnt) then return end

	refreshSetScale(infoEnt, scale)
end


--[[

]]
kvpass.crc = function(self, info, val)
	local crc = info.crc
	info.crc = val

	local keepdata
	for k, v in pairs(self.prop2mesh_controllers) do
		if v.crc == crc then
			keepdata = true
			break
		end
	end

	if not keepdata then
		setuser(self, crc, false)
	end
end

local function safeuvs(val)
	val = math.abs(math.floor(tonumber(val) or 0))
	if val > 512 then val = 512 end
	return val
end

kvpass.uvs = function(self, info, val)
	info.uvs = safeuvs(val)
	info.uniqueID = info.uvs .. "_" .. (info.bump and 1 or 0)
end

kvpass.bump = function(self, info, val)
	info.bump = tobool(val)
	info.uniqueID = info.uvs .. "_" .. (info.bump and 1 or 0)
end

-- https:--github.com/wiremod/wire/blob/1a0c31105d5a02a243cf042ea413867fb569ab4c/lua/wire/wireshared.lua#L56
local function normalizedFilepath(path)
    local null = string.find(path, "\x00", 1, true)

    if null then
        path = string.sub(path, 1, null - 1)
    end

    local tbl = string.Explode("[/\\]+", path, true)
    local i = 1

    while i <= #tbl do
        if tbl[i] == "." or tbl[i] == "" then
            table.remove(tbl, i)
        elseif tbl[i] == ".." then
            table.remove(tbl, i)

            if i > 1 then
                i = i - 1
                table.remove(tbl, i)
            end
        else
            i = i + 1
        end
    end

    return table.concat(tbl, "/")
end

local baddies = {
	["effects/ar2_altfire1"] = true,
	["engine/writez"] = true,
	["pp/copy"] = true,
}

local function safemat(val)
	val = string.sub(val, 1, 260)
	local path = string.StripExtension(normalizedFilepath(string.lower(val)))
	if baddies[path] then return "" end
	return val
end

kvpass.mat = function(self, info, val)
	info.mat = safemat(val)
end

kvpass.scale = function(self, info, val)
	if type(val) == "table" then val = Vector(unpack(val)) end
	info.scale = val
end

kvpass.clips = function(self, info, val)
	local clips = {}
	for i = 1, #val do
		local clip = val[i]
		table_insert(clips, { n = Vector(clip[1], clip[2], clip[3]), d = clip[4] })
	end

	info.clips = clips
end

local function LinkEntRemoved(linkent)
	local snapshot = linkent.prop2mesh_links

	if not snapshot or next(snapshot) == nil then
		return
	end

	timer.Simple(0, function()
		if IsValid(linkent) then
			return
		end

		for info, self in pairs(snapshot) do
			info.linkent = nil

			local infoEnt = info.ent
			if IsValid(self) and IsValid(infoEnt) then
				Ent_SetParent(infoEnt, self)
				Ent_SetPos(infoEnt, Ent_GetPos(self))
				Ent_SetAngles(infoEnt, Ent_GetAngles(self))
			end
		end
	end)
end

kvpass.linkent = function(self, info, val)
	if IsValid(val) then
		if not val.prop2mesh_links then
			val.prop2mesh_links = {}
		end
		val.prop2mesh_links[info] = self
		info.linkent = val
		info.linkent:CallOnRemove("prop2mesh_linkent_removed", LinkEntRemoved)
	else
		info.linkent = nil
	end
end

kvpass.linkpos = function(self, info, val)
	info.linkpos = val
end

kvpass.linkang = function(self, info, val)
	info.linkang = val
end


--[[

]]
net.Receive("prop2mesh_update", function(len)
	local self = net.ReadEntity()
	if not prop2mesh.isValid(self) then
		return
	end

	local synctime = net.ReadString()

	for index, update in pairs(net.ReadTable()) do
		local info = self.prop2mesh_controllers[index]
		if not info then
			self.prop2mesh_sync = nil
			return
		end
		for key, val in pairs(update) do
			if kvpass[key] then kvpass[key](self, info, val) else info[key] = val end
		end
		refresh(self, info)
	end

	self.prop2mesh_synctime = synctime
	self.prop2mesh_triggertool = true
	self.prop2mesh_triggereditor = prop2mesh.editor and true
end)

net.Receive("prop2mesh_sync", function(len)
	local self = net.ReadEntity()
	if not prop2mesh.isValid(self) then
		return
	end

	discard(self, self.prop2mesh_controllers)

	self.prop2mesh_synctime = net.ReadString()
	self.prop2mesh_controllers = {}

	for i = 1, net.ReadUInt(8) do
		local info = {
			crc   = net.ReadString(),
			uvs   = safeuvs(net.ReadUInt(12)),
			bump  = net.ReadBool(),
			mat   = safemat(net.ReadString()),
			col   = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)),
			scale = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()),
			index = i,
		}

		info.uniqueID = info.uvs .. "_" .. (info.bump and 1 or 0)

		local clipnum = net.ReadUInt(4)
		if clipnum > 0 then
			info.clips = {}
			for j = 1, clipnum do
				info.clips[#info.clips + 1] = { n = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat()), d = net.ReadFloat() }
			end
		end

		if net.ReadBool() then
			local linkent = net.ReadEntity()
			info.linkent = IsValid(linkent) and linkent or nil
		end
		if net.ReadBool() then
			info.linkpos = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
		end
		if net.ReadBool() then
			info.linkang = Angle(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
		end

		if net.ReadBool() then
			info.name = net.ReadString()
			if info.name == "" then
				info.name = nil
			end
		end

		self.prop2mesh_controllers[i] = info
	end

	self.prop2mesh_refresh = true
	self.prop2mesh_triggertool = true
	self.prop2mesh_triggereditor = prop2mesh.editor and true
end)

prop2mesh.downloads = 0
function prop2mesh.handleDownload(crc, data)
	if not crc or not isstring(data) then
		prop2mesh.downloads = math.max(0, prop2mesh.downloads - 1)
		return
	end

	if not recycle[crc] then
		recycle[crc] = { users = {}, meshes = {} }
	end

	if crc == util.CRC(data) then
		recycle[crc].zip = data

		file.Write("p2m_cache/" .. crc .. ".dat", data)

		for user in pairs(recycle[crc].users) do
			if IsValid(user) then
				for k, info in pairs(user.prop2mesh_controllers) do
					if info.crc == crc then
						checkmesh(crc, info.uniqueID)
					end
				end
			else
				setuser(user, crc, false)
			end
		end
	else
		garbage[crc] = SysTime() + 500
	end

	prop2mesh.downloads = math.max(0, prop2mesh.downloads - 1)
end

net.Receive("prop2mesh_download", function(len)
	local crc = net.ReadString()
	if not crc then
		return
	end

	prop2mesh.downloads = prop2mesh.downloads + 1

	prop2mesh.ReadStream(nil, function(data)
		prop2mesh.handleDownload(crc, data)
	end)
end)

hook.Add("NotifyShouldTransmit", "prop2mesh_sync", function(self, bool)
	if bool then self.prop2mesh_sync = nil end
end)

hook.Add("OnGamemodeLoaded", "prop2mesh_sync", function()
	for k, self in ipairs(ents.FindByClass("sent_prop2mesh*")) do
		self.prop2mesh_sync = nil
	end
end)
