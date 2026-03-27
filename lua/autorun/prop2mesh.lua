--[[

]]
if not prop2mesh then prop2mesh = {} end


--[[

]]
prop2mesh.defaultmat = "hunter/myplastic"

prop2mesh.enablelog = false
function prop2mesh.log(msg)
	MsgC(Color(255,255,0), "prop2mesh> ", Color(255,255,255), msg, "\n")
end

prop2mesh.validClasses = { ["sent_prop2mesh"] = true, ["sent_prop2mesh_legacy"] = true }
function prop2mesh.isValid(self)
	return IsValid(self) and prop2mesh.validClasses[self:GetClass()] or false
end

function prop2mesh.getBodygroupMask(ent)
	local mask = 0
	local offset = 1

	for index = 0, ent:GetNumBodyGroups() - 1 do
		local bg = ent:GetBodygroup(index)
		mask = mask + offset * bg
		offset = offset * ent:GetBodygroupCount(index)
	end

	return mask
end


--[[

]]
if SERVER then
	resource.AddWorkshop("2458909924")

	CreateConVar("prop2mesh_disable_allowed", 0, {FCVAR_NOTIFY, FCVAR_ARCHIVE}, "prevents prop2mesh data from networking")
	CreateConVar("prop2mesh_disabled_transparency_enabled", 1, {FCVAR_NOTIFY, FCVAR_ARCHIVE}, "enables transparency support for disabled prop2mesh entities")

	AddCSLuaFile("prop2mesh/cl_meshlab.lua")
	AddCSLuaFile("prop2mesh/cl_modelfixer.lua")
	AddCSLuaFile("prop2mesh/cl_editor.lua")
	AddCSLuaFile("prop2mesh/compat/construct.lua")
	AddCSLuaFile("prop2mesh/sh_netstream.lua")

	include("prop2mesh/sh_netstream.lua")
	include("prop2mesh/sv_entparts.lua")
	include("prop2mesh/sv_editor.lua")

	function prop2mesh.getEmpty()
		return {
			crc = "!none",
			uvs = 0,
			bump = false,
			col = Color(255, 255, 255, 255),
			mat = prop2mesh.defaultmat,
			scale = Vector(1, 1, 1),
			clips = {},
		}
	end

	local function makeEntity(class, pl, dupedata) -- limits would go here?
		local self = ents.Create(class)
		if not (self and self:IsValid()) then
			return false
		end

		if dupedata then
			duplicator.DoGeneric(self, dupedata)
		end
		self:Spawn()
		self:Activate()
		self:SetPlayer(pl)

		return self
	end
	prop2mesh.makeEntity = makeEntity

	duplicator.RegisterEntityClass("sent_prop2mesh", function(pl, data)
		return makeEntity("sent_prop2mesh", pl, data)
	end, "Data")

	duplicator.RegisterEntityClass("sent_prop2mesh_legacy", function(pl, data)
		return makeEntity("sent_prop2mesh_legacy", pl, data)
	end, "Data")

elseif CLIENT then
	CreateClientConVar("prop2mesh_disable", 0, true, true)

	include("prop2mesh/sh_netstream.lua")
	include("prop2mesh/cl_meshlab.lua")
	include("prop2mesh/cl_modelfixer.lua")
	include("prop2mesh/cl_editor.lua")
	include("prop2mesh/compat/construct.lua")

	concommand.Add("prop2mesh_debug_bodygroups", function(ply, cmd, args)
		local eid = tonumber(args[1])
		local ent = eid and Entity(eid) or ply:GetEyeTrace().Entity
		if ent and IsValid(ent) then
			if ent:IsPlayer() then return end
				local mask = prop2mesh.getBodygroupMask(ent)
				local submeshes = util.GetModelMeshes(ent:GetModel(), 0, mask or 0)

				chat.AddText(
					Color(225, 255, 155), "model: ", color_white, ent:GetModel() .. "\n",
					Color(225, 255, 155), "bodygroup-mask: ", color_white, mask .. "\n",
					Color(225, 255, 155), "submesh-count: ", color_white, (submeshes and #submeshes or 0) .. "")
		end
	end)

	timer.Simple(0.1, function()
		if not E2Helper then return end
		local backcompat = "Legacy Support - Defaults to index 1"
		E2Helper.Descriptions["p2mCreate(va)"] = backcompat
		E2Helper.Descriptions["p2mCreate(van)"] = backcompat
		E2Helper.Descriptions["p2mCreate(vann)"] = backcompat
		E2Helper.Descriptions["p2mHideModel(e:n)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:sva)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svann)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svannr)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svanr)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svav)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svavnn)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svavnnr)"] = backcompat
		E2Helper.Descriptions["p2mPushModel(e:svavnr)"] = backcompat
		E2Helper.Descriptions["p2mSetColor(e:v)"] = backcompat
		E2Helper.Descriptions["p2mSetColor(e:xv4)"] = backcompat
		E2Helper.Descriptions["p2mSetMaterial(e:s)"] = backcompat
		E2Helper.Descriptions["p2mSetMeshScale(e:n)"] = backcompat
	end)
end

--[[
	local concat = {}
	for k, v in SortedPairs(wire_expression2_funcs) do
		if string.StartWith(k, "p2m") then
			concat[#concat + 1] = string.format("**%s** | `%s`", "function", v[1])
			concat[#concat + 1] = "------------ | -------------"
			concat[#concat + 1] = string.format("**%s** | `%s`", "return", v[2] == "" and "void" or v[2])
			concat[#concat + 1] = "**args** | "
			for i = 1, #v.argnames do
				concat[#concat + 1] = string.format("&nbsp; | `%s`", v.argnames[i])
			end
			concat[#concat + 1] = "\n"
		end
	end
	file.Write("test.txt", table.concat(concat, "\n"))
]]
