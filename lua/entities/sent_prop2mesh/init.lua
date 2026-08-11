--[[

]]
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local net = net
local util = util
local table = table
local pairs = pairs
local ipairs = ipairs
local prop2mesh = prop2mesh

util.AddNetworkString("prop2mesh_sync")
util.AddNetworkString("prop2mesh_update")
util.AddNetworkString("prop2mesh_download")

--[[
local download_wait = 0.1
local download_time = SysTime()
local download_list

hook.Add("Think", "prop2mesh_download_queue", function()
	if not download_list or SysTime() - download_time < download_wait then
		return
	end

	download_time = SysTime()

	local crc, download = next(download_list)
	if not crc or not download then
		download_list = nil

		if prop2mesh.enablelog then
			prop2mesh.log(string.format("no more downloads"))
		end

		return
	end

	if not next(download.players) or not download.data then
		download_list[crc] = nil

		if prop2mesh.enablelog then
			prop2mesh.log(string.format("download %s -> no more clients", crc))
		end

		return
	end

	local clients = {}
	for pl, sendme in pairs(download.players) do
		if IsValid(pl) then
			if sendme == true then
				download.players[pl] = false
				clients[#clients + 1] = pl
			end
		else
			download.players[pl] = nil
		end
	end

	if next(clients) then
		net.Start("prop2mesh_download")
		net.WriteString(crc)
		net.WriteStream(download.data, function(client)
			download.players[client] = nil

			if prop2mesh.enablelog then
				prop2mesh.log(string.format("download %s -> client %s is finished", crc, client))
			end
		end)
		net.Send(clients)

		if prop2mesh.enablelog then
			prop2mesh.log(string.format("download %s -> sending to %d clients", crc, #clients))
		end
	end
end)

net.Receive("prop2mesh_download", function(len, pl)
	local self = net.ReadEntity()
	if not prop2mesh.isValid(self) then
		return
	end

	local crc = net.ReadString()
	if not crc or not isstring(self.prop2mesh_partlists[crc]) then
		return
	end

	if not download_list then
		download_list = {}
	end

	if not download_list[crc] then
		download_list[crc] = {
			players = {},
			data = self.prop2mesh_partlists[crc],
		}
	end

	if download_list[crc].players[pl] == nil then
		download_list[crc].players[pl] = true

		if prop2mesh.enablelog then
			prop2mesh.log(string.format("adding %s to download queue %s", tostring(pl), crc))
		end
	end
end)
]]


local allow_disable = GetConVar("prop2mesh_disable_allowed")
local function plyDisabledP2m(pl)
	if not allow_disable:GetBool() then
		return false
	end

	return tobool(pl:GetInfoNum("prop2mesh_disable", 0))
end

function prop2mesh.sendDownload(pl, self, crc)
    net.Start("prop2mesh_download")
    net.WriteString(crc)
    prop2mesh.WriteStream(self.prop2mesh_partlists[crc])
    net.Send(pl)
end

function prop2mesh.sendToInterested(plys)
	plys = plys or player.GetAll()
	local recipients = RecipientFilter()

	for _, pl in ipairs(plys) do
		if not plyDisabledP2m(pl) then
			recipients:AddPlayer(pl)
		end
	end

	net.Send(recipients)
end

net.Receive("prop2mesh_download", function(len, pl)
	if plyDisabledP2m(pl) then return end

	local self = net.ReadEntity()
	if not prop2mesh.isValid(self) then
		return
	end

	local crc = net.ReadString()
	if not crc or not isstring(self.prop2mesh_partlists[crc]) then
		return
	end

	prop2mesh.sendDownload(pl, self, crc)
end)

net.Receive("prop2mesh_sync", function(len, pl)
	if allow_disable:GetBool() and tobool(pl:GetInfoNum("prop2mesh_disable", 0)) then return end

	local self = net.ReadEntity()
	if not prop2mesh.isValid(self) then
		return
	end
	if not self.prop2mesh_syncwith then
		self.prop2mesh_syncwith = {}
	end
	self.prop2mesh_syncwith[pl] = net.ReadString()
	--print("sync", pl)
end)


--[[

]]
function ENT:Initialize()
	self:DrawShadow(false)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)

	self.prop2mesh_controllers = {}
	self.prop2mesh_partlists = {}
	self.prop2mesh_sync = true
end

function ENT:SetPlayer(pl)
	self:SetVar("Founder", pl)
end

function ENT:GetPlayer()
	return self:GetVar("Founder", NULL)
end

local kvpass = {}
kvpass.scale = function(val)
	return { val.x, val.y, val.z }
end

function ENT:Think()
	if self.prop2mesh_upload_queue then
		self:SetNetworkedBool("uploading", true)
		return
	end

	if self.prop2mesh_sync then
		self.prop2mesh_updates = nil
		self.prop2mesh_synctime = SysTime() .. ""
		self.prop2mesh_syncwith = nil
		self.prop2mesh_sync = nil

		self:SendControllers()
	else
		if self.prop2mesh_syncwith then
			local syncwith = {}
			for pl, pltime in pairs(self.prop2mesh_syncwith) do
				if IsValid(pl) and pltime ~= self.prop2mesh_synctime then
					syncwith[#syncwith + 1] = pl
				end
			end

			if next(syncwith) then
				self:SendControllers(syncwith)
			end

			self.prop2mesh_syncwith = nil
		end
		if self.prop2mesh_updates then
			self.prop2mesh_synctime = SysTime() .. ""

			net.Start("prop2mesh_update")
			net.WriteEntity(self)
			net.WriteString(self.prop2mesh_synctime)

			for index, update in pairs(self.prop2mesh_updates) do
				for key in pairs(update) do
					if kvpass[key] then
						update[key] = kvpass[key](self.prop2mesh_controllers[index][key])
					else
						update[key] = self.prop2mesh_controllers[index][key]
					end
				end
			end

			net.WriteTable(self.prop2mesh_updates)
			prop2mesh.sendToInterested()

			self.prop2mesh_updates = nil
		else
			if self:GetNetworkedBool("uploading") then
				self:SetNetworkedBool("uploading", false)
			end
		end
	end
end

function ENT:PreEntityCopy()
	duplicator.StoreEntityModifier(self, "prop2mesh", {
		[1] = self.prop2mesh_controllers,
		[2] = self.prop2mesh_partlists,
	})
end

function ENT:PostEntityCopy()
	duplicator.ClearEntityModifier(self, "prop2mesh")
end

function ENT:PostEntityPaste()
	duplicator.ClearEntityModifier(self, "prop2mesh")
end

duplicator.RegisterEntityModifier("prop2mesh", function(ply, self, dupe)
	if not prop2mesh.isValid(self) then
		return
	end
	local dupe_controllers = dupe[1]
	if istable(dupe_controllers) and next(dupe_controllers) and table.IsSequential(dupe_controllers) then
		self.prop2mesh_sync = true

		local dupe_data = dupe[2]
		local dupe_lookup = {}

		self.prop2mesh_controllers = {}
		for k, v in ipairs(dupe_controllers) do
			local info = self:AddController()
			self:SetControllerCol(k, v.col)
			self:SetControllerMat(k, v.mat)
			self:SetControllerUVS(k, v.uvs)
			self:SetControllerBump(k, v.bump)
			self:SetControllerScale(k, v.scale)

			if v.clips then
				for _, clip in pairs(v.clips) do
					self:AddControllerClip(k, unpack(clip))
				end
			end

			if dupe_data and dupe_data[v.crc] then
				dupe_lookup[v.crc] = true
				info.crc = v.crc
			end

			--self:SetControllerLinkEnt(k, v.linkent) ??
			self:SetControllerLinkPos(k, v.linkpos)
			self:SetControllerLinkAng(k, v.linkang)

			if v.name then
				self:SetControllerName(k, v.name)
			end
		end

		self.prop2mesh_partlists = {}
		for crc in pairs(dupe_lookup) do
			self.prop2mesh_partlists[crc] = dupe_data[crc]
		end
	end
end)

function ENT:AddController(uvs, bump)
	table.insert(self.prop2mesh_controllers, prop2mesh.getEmpty())
	self.prop2mesh_sync = true
	if uvs then
		self:SetControllerUVS(#self.prop2mesh_controllers, uvs)
	end
	if tobool(bump) then
		self:SetControllerBump(#self.prop2mesh_controllers, true)
	end
	return self.prop2mesh_controllers[#self.prop2mesh_controllers]
end

function ENT:RemoveController(index)
	if not self.prop2mesh_controllers[index] then
		return false
	end

	local crc = self.prop2mesh_controllers[index].crc
	table.remove(self.prop2mesh_controllers, index)

	local keepdata
	for _, info in pairs(self.prop2mesh_controllers) do
		if info.crc == crc then
			keepdata = true
			break
		end
	end

	if not keepdata then
		self.prop2mesh_partlists[crc] = nil
	end

	self.prop2mesh_sync = true

	return true
end

function ENT:MergeControllers(fromIndex, intoIndex)
	fromIndex = tonumber(fromIndex)
	intoIndex = tonumber(intoIndex)

	-- both controllers must exist, and merging into itself makes no sense
	local fromInfo = fromIndex and self.prop2mesh_controllers[fromIndex]
	local intoInfo = intoIndex and self.prop2mesh_controllers[intoIndex]
	if not fromInfo or not intoInfo or fromIndex == intoIndex then
		return false
	end

	-- decompress both partlists so their part arrays can be concatenated
	local fromData = self:GetControllerData(fromIndex) or {}
	local intoData = self:GetControllerData(intoIndex) or {}

	-- start from the target's parts/custom meshes, keeping its material/color/etc.
	local merged = { custom = {} }
	for i = 1, #intoData do
		merged[#merged + 1] = intoData[i]
	end
	if intoData.custom then
		for crc, data in pairs(intoData.custom) do
			merged.custom[crc] = data
		end
	end

	-- append the source's parts/custom meshes on top
	for i = 1, #fromData do
		merged[#merged + 1] = fromData[i]
	end
	if fromData.custom then
		for crc, data in pairs(fromData.custom) do
			merged.custom[crc] = data
		end
	end

	-- write the combined partlist to the target, then delete the source controller
	if #merged > 0 then
		self:SetControllerData(intoIndex, merged)
	else
		self:ResetControllerData(intoIndex)
	end
	self:RemoveController(fromIndex)

	return true
end

function ENT:MergeEntities(other)
	-- the target must be a different, valid prop2mesh controller entity
	if not prop2mesh.isValid(other) or other == self then return false end
	if not next(self.prop2mesh_controllers) then return false end

	local frompos, fromang = self:GetPos(), self:GetAngles()
	local intopos, intoang = other:GetPos(), other:GetAngles()

	for index, info in ipairs(self.prop2mesh_controllers) do
		-- add a matching controller on the target and copy this one's appearance
		other:AddController()
		local newIndex = #other.prop2mesh_controllers

		other:SetControllerCol(newIndex, info.col)
		other:SetControllerMat(newIndex, info.mat)
		other:SetControllerUVS(newIndex, info.uvs)
		other:SetControllerBump(newIndex, info.bump)
		other:SetControllerScale(newIndex, info.scale)

		if info.clips then
			for _, clip in ipairs(info.clips) do
				other:AddControllerClip(newIndex, unpack(clip))
			end
		end

		if info.name then
			other:SetControllerName(newIndex, info.name)
		end

		-- transform mesh parts into new controller's frame.
		-- positions are multiplied by scale, so need to undo that first.
		local partlist = self:GetControllerData(index)
		if partlist then
			local sx, sy, sz = info.scale.x, info.scale.y, info.scale.z
			for _, part in ipairs(partlist) do
				local pos = Vector(part.pos.x * sx, part.pos.y * sy, part.pos.z * sz)
				local wpos, wang = LocalToWorld(pos, part.ang, frompos, fromang)
				local lpos, lang = WorldToLocal(wpos, wang, intopos, intoang)
				part.pos = Vector(sx ~= 0 and lpos.x / sx or 0, sy ~= 0 and lpos.y / sy or 0, sz ~= 0 and lpos.z / sz or 0)
				part.ang = lang
			end
			other:SetControllerData(newIndex, partlist)
		end
	end

	other.prop2mesh_sync = true

	self:Remove()

	return true
end

function ENT:SendControllers(syncwith)
	net.Start("prop2mesh_sync")

	net.WriteEntity(self)
	net.WriteString(self.prop2mesh_synctime)
	net.WriteUInt(#self.prop2mesh_controllers, 8)

	for i = 1, #self.prop2mesh_controllers do
		local info = self.prop2mesh_controllers[i]

		net.WriteString(info.crc)
		net.WriteUInt(info.uvs, 12)
		net.WriteBool(info.bump)
		net.WriteString(info.mat)
		net.WriteUInt(info.col.r, 8)
		net.WriteUInt(info.col.g, 8)
		net.WriteUInt(info.col.b, 8)
		net.WriteUInt(info.col.a, 8)
		net.WriteFloat(info.scale.x)
		net.WriteFloat(info.scale.y)
		net.WriteFloat(info.scale.z)

		net.WriteUInt(#info.clips, 4)
		for j = 1, #info.clips do
			local clip = info.clips[j]
			net.WriteFloat(clip[1])
			net.WriteFloat(clip[2])
			net.WriteFloat(clip[3])
			net.WriteFloat(clip[4])
		end

		if info.linkent and IsValid(info.linkent) then
			net.WriteBool(true)
			net.WriteEntity(info.linkent)
		else
			net.WriteBool(false)
		end
		if info.linkpos then
			net.WriteBool(true)
			net.WriteFloat(info.linkpos.x)
			net.WriteFloat(info.linkpos.y)
			net.WriteFloat(info.linkpos.z)
		else
			net.WriteBool(false)
		end
		if info.linkang then
			net.WriteBool(true)
			net.WriteFloat(info.linkang.p)
			net.WriteFloat(info.linkang.y)
			net.WriteFloat(info.linkang.r)
		else
			net.WriteBool(false)
		end

		if info.name then
			net.WriteBool(true)
			net.WriteString(info.name)
		else
			net.WriteBool(false)
		end
	end

	prop2mesh.sendToInterested(syncwith)
end

function ENT:AddControllerUpdate(index, key)
	if self.prop2mesh_sync or not self.prop2mesh_controllers[index] then
		return
	end
	if not self.prop2mesh_updates then self.prop2mesh_updates = {} end
	if not self.prop2mesh_updates[index] then self.prop2mesh_updates[index] = {} end
	self.prop2mesh_updates[index][key] = true
end

function ENT:SetControllerLinkEnt(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isentity(val)) then
		if not IsValid(val) or info.linkent == val then
			return
		end
		info.linkent = val
		self:AddControllerUpdate(index, "linkent")
	end
end

function ENT:SetControllerLinkPos(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isvector(val)) then
		if not info.linkpos then
			info.linkpos = Vector()
		end
		if (info.linkpos.x ~= val.x or info.linkpos.y ~= val.y or info.linkpos.z ~= val.z) then
			info.linkpos.x = val.x
			info.linkpos.y = val.y
			info.linkpos.z = val.z
			self:AddControllerUpdate(index, "linkpos")
		end
	end
end

function ENT:SetControllerLinkAng(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isangle(val)) then
		if not info.linkang then
			info.linkang = Angle()
		end
		if (info.linkang.p ~= val.p or info.linkang.y ~= val.y or info.linkang.r ~= val.r) then
			info.linkang.p = val.p
			info.linkang.y = val.y
			info.linkang.r = val.r
			self:AddControllerUpdate(index, "linkang")
		end
	end
end

function ENT:SetControllerName(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isstring(val)) and (info.name ~= val) then
		info.name = val
		self:AddControllerUpdate(index, "name")
	end
end

function ENT:SetControllerAlpha(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isnumber(val)) and (info.col.a ~= val) then
		info.col.a = val
		self:AddControllerUpdate(index, "col")
	end
end

function ENT:SetControllerCol(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and IsColor(val) or istable(val)) and (info.col.r ~= val.r or info.col.g ~= val.g or info.col.b ~= val.b or info.col.a ~= val.a) then
		info.col.r = val.r
		info.col.g = val.g
		info.col.b = val.b
		info.col.a = val.a
		self:AddControllerUpdate(index, "col")
	end
end

function ENT:SetControllerMat(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isstring(val) and not string.find(val, ";")) and (info.mat ~= val) then
		info.mat = val
		self:AddControllerUpdate(index, "mat")
	end
end

function ENT:SetControllerScale(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isvector(val)) and (info.scale.x ~= val.x or info.scale.y ~= val.y or info.scale.z ~= val.z) then
		info.scale.x = val.x
		info.scale.y = val.y
		info.scale.z = val.z
		self:AddControllerUpdate(index, "scale")
	end
end

function ENT:SetControllerUVS(index, val)
	local info = self.prop2mesh_controllers[index]
	if (info and isnumber(val)) and (info.uvs ~= val) then
		info.uvs = val
		self:AddControllerUpdate(index, "uvs")
	end
end

function ENT:SetControllerBump(index, val)
	local info = self.prop2mesh_controllers[index]
	if info and (info.bump ~= tobool(val)) then
		info.bump = tobool(val)
		self:AddControllerUpdate(index, "bump")
	end
end

local function ClipExists(clips, normx, normy, normz, dist)
	local x = math.Round(normx, 4)
	local y = math.Round(normy, 4)
	local z = math.Round(normz, 4)
	local d = math.Round(dist, 2)

	for i, clip in ipairs(clips) do
		if math.Round(clip[1], 4) ~= x then continue end
		if math.Round(clip[2], 4) ~= y then continue end
		if math.Round(clip[3], 4) ~= z then continue end
		if math.Round(clip[4], 2) ~= d then continue end

		return true, i
	end

	return false
end

function ENT:AddControllerClip(index, normx, normy, normz, dist)
	local info = self.prop2mesh_controllers[index]
	if info then
		if not ClipExists(info.clips, normx, normy, normz, dist) then
			table.insert(info.clips, { normx, normy, normz, dist })
			self:AddControllerUpdate(index, "clips")
		end
	end
end

function ENT:RemoveControllerClip(index, clipindex)
	local info = self.prop2mesh_controllers[index]
	if info and info.clips[clipindex] then
		table.remove(info.clips, clipindex)
		self:AddControllerUpdate(index, "clips")
	end
end

function ENT:ClearControllerClips(index)
	local info = self.prop2mesh_controllers[index]
	if info and #info.clips > 0 then
		info.clips = {}
		self:AddControllerUpdate(index, "clips")
	end
end

function ENT:ResetControllerData(index)
	if self.prop2mesh_controllers[index] then
		self.prop2mesh_controllers[index].crc = "!none"
		self:AddControllerUpdate(index, "crc")
	end
end

function ENT:SetControllerData(index, partlist, uvs, addTo)
	local info = self.prop2mesh_controllers[index]
	if not info or not partlist then
		return
	end

	if addTo and next(partlist) then -- MESS
		local currentData = self:GetControllerData(index)
		if currentData then
			for i = 1, #currentData do
				partlist[#partlist + 1] = currentData[i]
			end
			if currentData.custom then
				if not partlist.custom then
					partlist.custom = {}
				end
				for crc, data in pairs(currentData.custom) do
					partlist.custom[crc] = data
				end
			end
		end
	end

	if not next(partlist) then
		self:ResetControllerData(index)
		return
	end

	prop2mesh.sanitizeCustom(partlist)

	--uvs = uvs or partlist.uvs
	--partlist.uvs = nil

	local json = util.TableToJSON(partlist)
	if not json then
		return
	end

	local data = util.Compress(json)
	local dcrc = util.CRC(data)
	local icrc = info.crc

	if icrc == dcrc then
		return
	end

	self.prop2mesh_partlists[dcrc] = data

	info.crc = dcrc
	self:AddControllerUpdate(index, "crc")
	if uvs then
		info.uvs = uvs
		self:AddControllerUpdate(index, "uvs")
	end

	local keepdata
	for k, v in pairs(self.prop2mesh_controllers) do
		if v.crc == icrc then
			keepdata = true
			break
		end
	end
	if not keepdata then
		self.prop2mesh_partlists[icrc] = nil
	end
end

function ENT:GetControllerData(index, nodecomp)
	if not self.prop2mesh_controllers[index] then
		return
	end
	local ret = self.prop2mesh_partlists[self.prop2mesh_controllers[index].crc]
	if not ret or nodecomp then
		return ret
	end
	return util.JSONToTable(util.Decompress(ret))
end

function ENT:ToolDataByINDEX(index, tool, addTo)
	if not self.prop2mesh_controllers[index] then
		return false
	end

	local pos = self:GetPos()
	local ang = self:GetAngles()

	if tool:GetClientNumber("tool_setautocenter") ~= 0 then
		pos = Vector()
		local num = 0
		for ent, _ in pairs(tool.selection) do
			pos = pos + ent:GetPos()
			num = num + 1
		end
		pos = pos * (1 / num)
	end

	-- local uvsize
	-- if not addTo then
	-- 	uvsize = tool:GetClientNumber("tool_setuvsize")
	-- end

	self:SetControllerData(index, prop2mesh.partsFromEnts(tool.selection, pos, ang), nil, addTo)
end

function ENT:ToolDataAUTO(tool)
	local autocenter = tool:GetClientNumber("tool_setautocenter") ~= 0
	local pos, ang, num

	if autocenter then
		pos = Vector()
		ang = self:GetAngles()
		num = 0
	else
		pos = self:GetPos()
		ang = self:GetAngles()
	end

	local sorted = {}
	for k, v in pairs(tool.selection) do
		local vmat = v.mat
		if vmat == "" then vmat = prop2mesh.defaultmat end

		if not sorted[vmat] then
			sorted[vmat] = {}
		end
		local key = string.format("%d %d %d %d", v.col.r, v.col.g, v.col.b, v.col.a)
		if not sorted[vmat][key] then
			sorted[vmat][key] = {}
		end
		table.insert(sorted[vmat][key], k)
		if autocenter then
			pos = pos + k:GetPos()
			num = num + 1
		end
	end

	if autocenter then
		pos = pos * (1 / num)
	end

	local uvs = tool:GetClientNumber("tool_setuvsize")

	for kmat, vmat in pairs(sorted) do
		for kcol, vcol in pairs(vmat) do
			local parts = prop2mesh.partsFromEnts(vcol, pos, ang)
			if parts then
				local info = self:AddController()
				local temp = string.Explode(" ", kcol)
				info.col = Color(temp[1], temp[2], temp[3], temp[4])
				info.mat = kmat
				info.uvs = parts.uvs or uvs
				if parts.uvs then parts.uvs = nil end
				self:SetControllerData(#self.prop2mesh_controllers, parts)
			end
		end
	end
end
