TOOL.Category = "Render"
TOOL.Name     = "#tool.prop2mesh.name"

local prop2mesh = prop2mesh
local math = math
local ents = ents
local table = table
local IsValid = IsValid

local function GetClientFilters(csv)
	local ret = {}

	for k, v in pairs(string.Split(string.lower(string.Trim(csv)), ",")) do
		v = string.Trim(v)
		ret[v] = true
	end

	return ret
end

if SERVER then
	local pkey, pnum = prop2mesh.getPartClasses()
	local select_color_class = {}

	for k, v in SortedPairsByValue(pkey) do
		select_color_class[v] = HSVToColor((360 / pnum)*(k - 1), 1, 1)
		select_color_class[v].a = 125
	end

	local select_color_p2m = Color(0, 0, 255, 255)
	local select_material  = "models/debug/debugwhite"
	local select_candelete = { prop_physics = true }

	local function checkOwner(ply, ent)
		if CPPI then
			local owner = ent:CPPIGetOwner() or (ent.GetPlayer and ent:GetPlayer())
			if owner then
				return owner == ply
			end
		end
		return true
	end

	TOOL.selection = {}
	TOOL.p2m = {}

	function TOOL:IsLegacyMode()
		return self:GetClientNumber("tool_legacymode") ~= 0
	end

	function TOOL:MakeEnt(tr)
		local legacy = self:IsLegacyMode()
		local ent = ents.Create(legacy and "sent_prop2mesh_legacy" or "sent_prop2mesh")
		local mdl = legacy and "models/hunter/plates/plate.mdl" or self:GetClientInfo("tool_setmodel")
		if not IsUselessModel(mdl) then
			ent:SetModel(mdl)
		else
			ent:SetModel("models/p2m/cube.mdl")
		end
		local ang
		if math.abs(tr.HitNormal.x) < 0.001 and math.abs(tr.HitNormal.y) < 0.001 then
			ang = Vector(0, 0, tr.HitNormal.z):Angle()
		else
			ang = tr.HitNormal:Angle()
		end
		ang.p = ang.p + 90
		ent:SetAngles(ang)
		ent:SetPos(tr.HitPos - ent:LocalToWorld(Vector(0, 0, ent:OBBMins().z)))
		ent:Spawn()
		ent:Activate()
		ent:SetPlayer(self:GetOwner())

		local freeze = self:GetClientNumber("tool_setfrozen") ~= 0
		if freeze then
			local phys = ent:GetPhysicsObject()
			if IsValid(phys) then
				phys:EnableMotion(false)
				phys:Wake()
			end
		end

		if CPPI and ent.CPPISetOwner then
			ent:CPPISetOwner(self:GetOwner())
		end

		if legacy then
			ent:AddController(self:GetClientNumber("tool_setuvsize"))
		end

		undo.Create(ent:GetClass())
			undo.AddEntity(ent)
			undo.SetPlayer(self:GetOwner())
		undo.Finish()

		return ent
	end

	function TOOL:GetClassWhitelist()
		local class_filters = GetClientFilters(self:GetClientInfo("tool_filter_ilist"))
		local class_whitelist = {}

		for k, v in pairs(select_color_class) do
			if not class_filters[k] then class_whitelist[k] = true end
		end

		return class_whitelist
	end

	function TOOL:GetFilteredEntities(tr, group)
		if next(group) == nil then
			return
		end

		local class_whitelist = self:GetClassWhitelist()

		--[[
		local class_whitelist = {}
		if not tobool(self:GetClientNumber("tool_filter_iprop")) then
			class_whitelist.prop_physics = true
		end
		if not tobool(self:GetClientNumber("tool_filter_iholo")) then
			class_whitelist.gmod_wire_hologram = true
			class_whitelist.starfall_hologram = true
		end
		if not tobool(self:GetClientNumber("tool_filter_ilp2m")) then
			class_whitelist.sent_prop2mesh_legacy = true
		end
		if not tobool(self:GetClientNumber("tool_filter_ipacf")) then
			class_whitelist.acf_armor = true
		end
		]]

		local ignore_invs = tobool(self:GetClientNumber("tool_filter_iinvs"))
		local ignore_prnt = tobool(self:GetClientNumber("tool_filter_iprnt"))
		local ignore_cnst = tobool(self:GetClientNumber("tool_filter_icnst"))

		local bycol, bymat, bymass
		if tr.Entity and not tr.HitWorld then
			if tobool(self:GetClientNumber("tool_filter_mcolor")) then
				bycol = self.selection[tr.Entity] and self.selection[tr.Entity].col or tr.Entity:GetColor()
			end
			if tobool(self:GetClientNumber("tool_filter_mmatrl")) then
				bymat = self.selection[tr.Entity] and self.selection[tr.Entity].mat or tr.Entity:GetMaterial()
			end
		end
		if tobool(self:GetClientNumber("tool_filter_mmass")) then
			bymass = self:GetClientNumber("tool_filter_mmass")
		end

		local filtered = {}
		for k, v in pairs(group) do
			local class = v:GetClass()
			if not class_whitelist[class] then
				goto skip
			end
			if ignore_invs and v:GetColor().a == 0 then
				goto skip
			end
			if ignore_prnt and IsValid(v:GetParent()) then
				goto skip
			end
			if ignore_cnst and v:IsConstrained() then
				goto skip
			end
			if bymat and v:GetMaterial() ~= bymat then
				goto skip
			end
			if bycol then
				local c = v:GetColor()
				if c.r ~= bycol.r or c.g ~= bycol.g or c.b ~= bycol.b or c.a ~= bycol.a then
					goto skip
				end
			end
			if bymass then
				local phys = v:GetPhysicsObject()
				if phys:IsValid() then
					if v.EntityMods and v.EntityMods.mass and v.EntityMods.mass.Mass then
						if v.EntityMods.mass.Mass > bymass then
							goto skip
						end
					else
						if phys:GetMass() > bymass then
							goto skip
						end
					end
				end
			end
			table.insert(filtered, v)
			::skip::
		end

		return filtered
	end

	function TOOL:SelectGroup(group)
		if not group or next(group) == nil then
			return
		end
		for k, v in ipairs(group) do
			self:SelectEntity(v)
		end
	end

	local attachments = {}
	attachments.prop_effect = function(ent) return IsValid(ent.AttachedEntity) and ent.AttachedEntity end

	function TOOL:SelectEntity(ent)
		if not IsValid(ent) or self.selection[ent] or ent == self.p2m.ent or not checkOwner(self:GetOwner(), ent) then
			return false
		end
		local class = ent:GetClass()
		if not select_color_class[class] then
			return false
		end

		local temp = attachments[class] and attachments[class](ent) or ent

		self.selection[ent] = { col = temp:GetColor(), mat = temp:GetMaterial(), mode = temp:GetRenderMode() }
		temp:SetColor(select_color_class[class])
		temp:SetRenderMode(RENDERMODE_TRANSCOLOR)
		temp:SetMaterial(select_material)
		ent:CallOnRemove("prop2mesh_deselect", function(e)
			self.selection[e] = nil
		end)
		return true
	end

	function TOOL:DeselectEntity(ent, modify)
		if not self.selection[ent] then
			return false
		end
		if modify then
			duplicator.StoreEntityModifier(ent, "colour", { Color = self.selection[ent].col, RenderMode = self.selection[ent].mode })
		end

		local class = ent:GetClass()
		local temp = attachments[class] and attachments[class](ent) or ent

		temp:SetColor(self.selection[ent].col)
		temp:SetRenderMode(self.selection[ent].mode)
		temp:SetMaterial(self.selection[ent].mat)
		ent:RemoveCallOnRemove("prop2mesh_deselect")
		self.selection[ent] = nil
		return true
	end

	function TOOL:UnsetP2M()
		if IsValid(self.p2m.ent) then
			self.p2m.ent:SetColor(self.p2m.col)
			self.p2m.ent:SetRenderMode(self.p2m.mode)
			self.p2m.ent:SetMaterial(self.p2m.mat)
			self.p2m.ent:RemoveCallOnRemove("prop2mesh_deselect")
		end
		self.p2m = {}
		self:SetStage(0)
	end

	function TOOL:SetP2M(ent)
		local legacy = self:IsLegacyMode()
		if not IsValid(ent) or ent:GetClass() ~= (legacy and "sent_prop2mesh_legacy" or "sent_prop2mesh") or not checkOwner(self:GetOwner(), ent) then
			return
		end

		self.p2m = { ent = ent, col = ent:GetColor(), mat = ent:GetMaterial(), mode = ent:GetRenderMode() }
		ent:SetColor(select_color_p2m)
		ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
		ent:SetMaterial(select_material)
		ent:CallOnRemove("prop2mesh_deselect", function(e)
			for k, v in pairs(self.selection) do
				self:DeselectEntity(k)
			end
			self.selection = {}
		end)
		self:SetStage(1)
	end

	function TOOL:Deploy()
		timer.Simple(0.1, function()
			if IsValid(self.p2m.ent) then
				self:SetStage(1)
			end
		end)
	end

	function TOOL:SetDataByIndex(add)
		if next(self.selection) == nil then
			return
		end
		local legacy = self:IsLegacyMode()
		local index = self:GetOwner():GetInfoNum("prop2mesh_multitool_index", 1)
		if legacy or index ~= 1 then
			self.p2m.ent:ToolDataByINDEX(legacy and 1 or (index - 1), self, add)
			local rmv = self:GetClientNumber("tool_setautoremove") ~= 0
			local alp = not rmv and self:GetClientNumber("tool_setalphazero") ~= 0
			for k, v in pairs(self.selection) do
				if alp then
					v.col.a = 0
					v.mode = RENDERMODE_TRANSALPHA
				end
				self:DeselectEntity(k, alp)
				if rmv and select_candelete[k:GetClass()] then
					SafeRemoveEntity(k)
				end
			end
			self.selection = {}
			self:UnsetP2M()
		end
	end

	function TOOL:RightClick(tr)
		if not tr.Hit then
			return false
		end
		if not IsValid(self.p2m.ent) then
			self:SetP2M(tr.Entity)
		else
			if self:GetOwner():KeyDown(IN_SPEED) then
				if tr.Entity == self.p2m.ent then
					self:SetDataByIndex(true)
				else
					self:SelectGroup(self:GetFilteredEntities(tr, ents.FindInSphere(tr.HitPos, math.Clamp(self:GetClientNumber("tool_filter_radius"), 0, 2048))))
				end
			elseif self:GetOwner():KeyDown(IN_USE) then
				self:SelectGroup(self:GetFilteredEntities(tr, tr.Entity:GetChildren())) -- note, GetChildren seems to return a lookup table now, ipairs wont work!
			else
				if tr.Entity == self.p2m.ent then
					self:SetDataByIndex()
				else
					if self.selection[tr.Entity] then self:DeselectEntity(tr.Entity) else self:SelectEntity(tr.Entity) end
				end
			end
		end
		return true
	end

	--[[
	-- unused code for selecting holos
	if self:GetClientNumber("tool_filter_iprop") ~= 0 and self:GetClientNumber("tool_filter_iholo") == 0 then
		local find = {}
		local cone = ents.FindInCone(tr.StartPos, tr.Normal, tr.HitPos:Distance(tr.StartPos) * 2, math.cos(math.rad(3)))
		local whitelist = { gmod_wire_hologram = true, starfall_hologram = true }
		for k, ent in ipairs(cone) do
			if not whitelist[ent:GetClass()] then
				goto skip
			end
			table.insert(find, { ent = ent, len = (tr.StartPos - ent:GetPos()):LengthSqr() })
			::skip::
		end
		for k, v in SortedPairsByMemberValue(find, "len") do
			if self.selection[v.ent] then
				self:DeselectEntity(v.ent)
				break
			elseif self:SelectEntity(v.ent) then
				break
			end
		end
	else
		if self.selection[tr.Entity] then self:DeselectEntity(tr.Entity) else self:SelectEntity(tr.Entity) end
	end
	]]

	function TOOL:LeftClick(tr)
		if not tr.Hit then
			return false
		end
		if IsValid(self.p2m.ent) then
			if tr.Entity == self.p2m.ent then
				if self:IsLegacyMode() then
					if self:GetOwner():KeyDown(IN_SPEED) then
						self.p2m.ent:SetControllerUVS(1, self:GetClientNumber("tool_setuvsize"))
					end
				else
					if self:GetOwner():KeyDown(IN_SPEED) then
						if next(self.selection) ~= nil then
							self.p2m.ent:ToolDataAUTO(self)
							local rmv = self:GetClientNumber("tool_setautoremove") ~= 0
							local alp = not rmv and self:GetClientNumber("tool_setalphazero") ~= 0
							for k, v in pairs(self.selection) do
								if alp then
									v.col.a = 0
									v.mode = RENDERMODE_TRANSALPHA
								end
								self:DeselectEntity(k, alp)
								if rmv and select_candelete[k:GetClass()] then
									SafeRemoveEntity(k)
								end
							end
							self.selection = {}
							self:UnsetP2M()
						end
					else
						local index = self:GetOwner():GetInfoNum("prop2mesh_multitool_index", 1)
						if index == 1 then
							self.p2m.ent:AddController(self:GetClientNumber("tool_setuvsize"), self:GetClientNumber("tool_setbump"))
						end
					end
				end
			end
		else
			--if (CPPI and tr.Entity:CPPICanTool(self:GetOwner(), "prop2mesh")) or not CPPI then
				self:MakeEnt(tr)
			--end
		end
		return true
	end

	function TOOL:Reload(tr)
		if not tr.Hit then
			return false
		end
		if next(self.selection) ~= nil then
			for k, v in pairs(self.selection) do
				self:DeselectEntity(k)
			end
			self.selection = {}
		else
			self:UnsetP2M()
		end
		return true
	end

	function TOOL:Think()
		if not IsValid(self.p2m.ent) then
			return
		end
		if self.p2m.ent:GetClass() ~= (self:IsLegacyMode() and "sent_prop2mesh_legacy" or "sent_prop2mesh") then
			for k, v in pairs(self.selection) do
				self:DeselectEntity(k)
			end
			self.selection = {}
			self:UnsetP2M()
		end
	end

	local multitool = { modes = {}, legacyoverride = {}, entityoverride = {} }
	multitool.modes.material = function(ply, tr, index)
		if ply:KeyDown(IN_ATTACK2) then
			local mat = tr.Entity:GetControllerMat(index - 1)
			if mat and not string.find(mat, ";") then
				ply:ConCommand("material_override " .. mat)
			end
			return
		end
		local mat
		if ply:KeyDown(IN_RELOAD) then
			mat = prop2mesh.defaultmat
		else
			mat = ply:GetInfo("material_override")
		end
		tr.Entity:SetControllerMat(index - 1, mat)
	end
	multitool.modes.colour = function(ply, tr, index)
		if ply:KeyDown(IN_ATTACK2) then
			local col = tr.Entity:GetControllerCol(index - 1)
			if col then
				ply:ConCommand("colour_r " .. col.r)
				ply:ConCommand("colour_g " .. col.g)
				ply:ConCommand("colour_b " .. col.b)
				ply:ConCommand("colour_a " .. col.a)
			end
			return
		end
		local col
		if ply:KeyDown(IN_RELOAD) then
			col = Color(255, 255, 255, 255)
		else
			col = Color(ply:GetInfoNum("colour_r", 255), ply:GetInfoNum("colour_g", 255), ply:GetInfoNum("colour_b", 255), ply:GetInfoNum("colour_a", 255))
		end
		tr.Entity:SetControllerCol(index - 1, col)
	end
	multitool.modes.remover = function(ply, tr, index)
		if ply:KeyDown(IN_ATTACK) then
			tr.Entity:RemoveController(index - 1)
		end
	end
	multitool.modes.colmat = function(ply, tr, index)
		if ply:KeyDown(IN_ATTACK2) then
			local col = tr.Entity:GetControllerCol(index - 1)
			if col then
				ply:ConCommand("colmat_r " .. col.r)
				ply:ConCommand("colmat_g " .. col.g)
				ply:ConCommand("colmat_b " .. col.b)
				ply:ConCommand("colmat_a " .. col.a)
			end
			local mat = tr.Entity:GetControllerMat(index - 1)
			if mat and not string.find(mat, ";") then
				ply:ConCommand("colmat_material " .. mat)
			end
			return
		end
		local col, mat
		if ply:KeyDown(IN_RELOAD) then
			col = Color(255, 255, 255, 255)
			mat = "hunter/myplastic"
		else
			col = Color(ply:GetInfoNum("colmat_r", 255), ply:GetInfoNum("colmat_g", 255), ply:GetInfoNum("colmat_b", 255), ply:GetInfoNum("colmat_a", 255))
			mat = ply:GetInfo("colmat_material")
		end
		tr.Entity:SetControllerCol(index - 1, col)
		tr.Entity:SetControllerMat(index - 1, mat)
	end

	multitool.legacyoverride.proper_clipping = true
	multitool.modes.proper_clipping = function(ply, tr, index)
		if ply:KeyDown(IN_RELOAD) then
			tr.Entity:ClearControllerClips(index - 1)
			return
		end
		if ply:KeyDown(IN_ATTACK2) then
			local tool = ply:GetTool("proper_clipping")
			if tool:GetStage() == 1 or tool:GetOperation() ~= 0 then
				ply:ChatPrint("Only clip by plane is supported")
				return
			end
			local norm, origin = tool.norm, tool.origin
			if not norm or not origin then
				return
			end

			norm = Vector(norm)
			origin = Vector(origin)

			norm = norm * (ply:KeyDown(IN_WALK) and -1 or 1)
			dist = norm:Dot(tr.Entity:GetPos() - (origin + norm * ply:GetInfoNum("proper_clipping_offset", 0)))
			norm = tr.Entity:WorldToLocalAngles(norm:Angle()):Forward() * -1

			tr.Entity:AddControllerClip(index - 1, norm.x, norm.y, norm.z, dist)
		end
	end

	multitool.legacyoverride.visual_adv = true
	multitool.modes.visual_adv = function(ply, tr, index)
		if ply:KeyDown(IN_RELOAD) then
			tr.Entity:ClearControllerClips(index - 1)
			return
		end
		if ply:KeyDown(IN_ATTACK2) then
			local tool = ply:GetTool("visual_adv")
			if tool.mode ~= 1 then
				ply:ChatPrint("Only clip by plane is supported")
				return
			end
			local norm, origin = tool.norm, tool.pos
			if not norm or not origin then
				return
			end

			norm = Vector(norm)
			origin = Vector(origin)

			norm = norm * (ply:KeyDown(IN_WALK) and -1 or 1) * -1
			dist = norm:Dot(tr.Entity:GetPos() - origin)
			norm = tr.Entity:WorldToLocalAngles(norm:Angle()):Forward() * -1

			tr.Entity:AddControllerClip(index - 1, norm.x, norm.y, norm.z, dist)
		end
	end

	multitool.legacyoverride.resizer = true
	multitool.entityoverride.resizer = function(ply, tr, index)
		local scale
		if ply:KeyDown(IN_ATTACK) then
			scale = Vector(tonumber(ply:GetInfo("resizer_xsize")), tonumber(ply:GetInfo("resizer_ysize")), tonumber(ply:GetInfo("resizer_zsize")))
		elseif ply:KeyDown(IN_ATTACK2) then
			scale = Vector(1, 1, 1)
		end
		if scale then
			for i = 1, #tr.Entity.prop2mesh_controllers do
				tr.Entity:SetControllerScale(i, scale)
			end
		end
	end
	multitool.modes.resizer = function(ply, tr, index)
		if ply:KeyDown(IN_ATTACK) then
			tr.Entity:SetControllerScale(index - 1, Vector(tonumber(ply:GetInfo("resizer_xsize")), tonumber(ply:GetInfo("resizer_ysize")), tonumber(ply:GetInfo("resizer_zsize"))))
		elseif ply:KeyDown(IN_ATTACK2) then
			tr.Entity:SetControllerScale(index - 1, Vector(1, 1, 1))
		end
	end

	hook.Add("CanTool", "prop2mesh_multitool", function(ply, tr, tool)
		if not multitool.modes[tool] or not IsValid(tr.Entity) or not checkOwner(ply, tr.Entity) then
			return
		end

		local class = tr.Entity:GetClass()
		local index
		if multitool.legacyoverride[tool] and class == "sent_prop2mesh_legacy" then
			index = 2
		else
			if class ~= "sent_prop2mesh" then
				return
			end
			index = ply:GetInfoNum("prop2mesh_multitool_index", 1)
		end

		local toolfunc
		if index ~= 1 then
			toolfunc = multitool.modes[tool]
		elseif multitool.entityoverride[tool] then
			toolfunc = multitool.entityoverride[tool]
		end

		if toolfunc then
			toolfunc(ply, tr, index)
			if game.SinglePlayer() then
				local swep = ply:GetActiveWeapon()
				if swep and swep.DoShootEffect then
					swep:DoShootEffect(tr.HitPos, tr.HitNormal, tr.Entity, tr.PhysicsBone, IsFirstTimePredicted())
				end
			end
			return false
		end

		-- if index ~= 1 then
		-- 	multitool.modes[tool](ply, tr, index)
		-- 	if game.SinglePlayer() then
		-- 		local swep = ply:GetActiveWeapon()
		-- 		if swep and swep.DoShootEffect then
		-- 			swep:DoShootEffect(tr.HitPos, tr.HitNormal, tr.Entity, tr.PhysicsBone, IsFirstTimePredicted())
		-- 		end
		-- 	end
		-- 	return false
		-- end

	end)

	return
end

function TOOL:RightClick(tr)
	return tr.Hit
end
function TOOL:LeftClick(tr)
	return tr.Hit
end
function TOOL:Reload(tr)
	return tr.Hit
end


--[[

]]
language.Add("tool.prop2mesh.name", "Prop2Mesh")
language.Add("tool.prop2mesh.desc", "Convert groups of props into a single mesh")

TOOL.Information = {
	{ name = "right0", stage = 0 },
	{ name = "right1", stage = 1 },
	{ name = "right2", stage = 1, icon2 = "gui/key.png" },
	{ name = "right3", stage = 1, icon2 = "gui/e.png" },
}

language.Add("tool.prop2mesh.right0", "Select a p2m entity")
language.Add("tool.prop2mesh.right1", "Select the entities you wish to convert")
language.Add("tool.prop2mesh.right2", "Select [SHIFT] all entities within radius of your aim position")
language.Add("tool.prop2mesh.right3", "Select [E] all entities parented to your aim entity")

local ConVars = {
	["tool_legacymode"]      = 0,
	["tool_setfrozen"]       = 0,
	["tool_setmodel"]        = "models/p2m/cube.mdl",
	["tool_setautocenter"]   = 0,
	["tool_setautoremove"]   = 0,
	["tool_setalphazero"]    = 0,
	["tool_setuvsize"]       = 0,
	["tool_setbump"]         = 0,
	["tool_filter_radius"]   = 512,
	["tool_filter_mcolor"]   = 0,
	["tool_filter_mmatrl"]   = 0,
	["tool_filter_mmass"]    = 0,
	["tool_filter_iinvs"]    = 1,
	["tool_filter_iprnt"]    = 0,
	["tool_filter_icnst"]    = 0,

	--[[
	["tool_filter_iprop"]    = 0,
	["tool_filter_iholo"]    = 0,
	["tool_filter_ilp2m"]    = 1, -- legacy p2m
	["tool_filter_ipacf"]    = 1, -- procedural armor
	]]

	["tool_filter_ilist"]    = "prop_effect, acf_armor, sent_prop2mesh_legacy",
}
TOOL.ClientConVar = ConVars


--[[

]]
local help_font = "DebugFixedSmall"
local function BuildPanel_ToolSettings(self)
	local pnl = vgui.Create("DForm")
	pnl:SetName("Tool Settings")

	--
	local btn = pnl:Button("Reset all tool options")
	btn.DoClick = function()
		for var, _ in pairs(ConVars) do
			local convar = GetConVar("prop2mesh_" .. var)
			if convar then
				convar:Revert()
			end
		end
		timer.Simple(0.1, self.tempfixfilters)
	end

	--
	local preset = vgui.Create("ControlPresets", pnl)

	local cvarlist = {}
	for k, v in pairs(ConVars) do
		local name = "prop2mesh_" .. k
		cvarlist[name] = v
		preset:AddConVar(name)
	end

	preset:SetPreset("prop2mesh")
	preset:AddOption("#preset.default", cvarlist)

	preset.OnSelect = function(_, index, value, data)
		if not data then return end
		for k, v in pairs(data) do
			RunConsoleCommand(k, v)
		end
		timer.Simple(0.1, self.tempfixfilters)
	end

	pnl:AddItem(preset)

	--
	local help = pnl:Help("Danger zone")
	help:DockMargin(0, 0, 0, 0)
	help:SetFont(help_font)
	help.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawLine(0, h - 1, w, h - 1)
	end

	local cbox = pnl:CheckBox("Spawn frozen", "prop2mesh_tool_setfrozen")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local cbox = pnl:CheckBox("Enable legacy mode", "prop2mesh_tool_legacymode")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local cbox = pnl:CheckBox("Set selection alpha to 0 when done", "prop2mesh_tool_setalphazero")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local cbox = pnl:CheckBox("Remove selected props when done", "prop2mesh_tool_setautoremove")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	--
	local help = pnl:Help("Selection filters")
	help:DockMargin(0, 0, 0, 0)
	help:SetFont(help_font)
	help.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawLine(0, h - 1, w, h - 1)
	end

	local sld = pnl:NumSlider("Selection radius", "prop2mesh_tool_filter_radius", 0, 2048, 0)
	sld.Scratch:SetDisabled(true)
	pnl:ControlHelp("Hold LSHIFT while selecting to apply below filters to all entities within this radius.")

	pnl:CheckBox("Only select entities with same color", "prop2mesh_tool_filter_mcolor")
	pnl:CheckBox("Only select entities with same material", "prop2mesh_tool_filter_mmatrl")
	pnl:CheckBox("Ignore all invisible entities", "prop2mesh_tool_filter_iinvs")
	pnl:CheckBox("Ignore all parented entities", "prop2mesh_tool_filter_iprnt")
	pnl:CheckBox("Ignore all constrained entities", "prop2mesh_tool_filter_icnst")

	local sld = pnl:NumSlider("Ignore by mass", "prop2mesh_tool_filter_mmass", 0, 50000, 0)
	pnl:ControlHelp("Ignore entities with mass above this value.")

	--
	local class_list_convar = GetConVar("prop2mesh_tool_filter_ilist")
	local class_list_filter = GetClientFilters(class_list_convar:GetString())
	local class_list_display = { "prop_physics", "prop_effect", "gmod_wire_hologram", "starfall_hologram", "acf_armor", "sent_prop2mesh_legacy" }

	local combo = vgui.Create("DComboBox", pnl)
	pnl:AddItem(combo)

	local id = combo:SetText("Class filters...")
	combo:SetFont(help_font)
	combo:SetSortItems(false)

	combo.OnMenuOpened = function(_, menu)
		menu:GetChild(menu:ChildCount()):SetFont("DermaDefaultBold")
	end

	combo.OnSelect = function(_, id, value, func)
		combo:SetText("Class filters...")
		if isfunction(func) then func(id, value, true) end
	end

	local function onChoose(id, value, cmd)
		class_list_filter = GetClientFilters(class_list_convar:GetString())
		if class_list_filter[value] == true then class_list_filter[value] = nil else class_list_filter[value] = true end
		if cmd then RunConsoleCommand("prop2mesh_tool_filter_ilist", table.concat(table.GetKeys(class_list_filter), ",")) end
		combo.ChoiceIcons[id] = class_list_filter[value] and "icon16/cross.png" or nil
	end

	local choices = {}
	for k, v in SortedPairsByValue(class_list_display) do
		local id = combo:AddChoice(v, onChoose, nil, class_list_filter[v] and "icon16/cross.png")
		choices[id] = v
	end

	if Primitive then
		combo:AddSpacer()

		local v = "primitive_shape"
		choices[combo:AddChoice(v, onChoose, nil, class_list_filter[v] and "icon16/cross.png")] = v

		local v = "primitive_airfoil"
		choices[combo:AddChoice(v, onChoose, nil, class_list_filter[v] and "icon16/cross.png")] = v

		local v = "primitive_staircase"
		choices[combo:AddChoice(v, onChoose, nil, class_list_filter[v] and "icon16/cross.png")] = v

		local v = "primitive_ladder"
		choices[combo:AddChoice(v, onChoose, nil, class_list_filter[v] and "icon16/cross.png")] = v
	end

	combo:AddSpacer()
	combo:AddChoice("cancel")

	self.tempfixfilters = function()
		local class_list_filter = GetClientFilters(class_list_convar:GetString())
		for id, value in pairs(choices) do
			combo.ChoiceIcons[id] = class_list_filter[value] and "icon16/cross.png" or nil
		end
	end

	--
	local help = pnl:Help("Entity options")
	help:DockMargin(0, 0, 0, 0)
	help:SetFont(help_font)
	help.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawLine(0, h - 1, w, h - 1)
	end

	local txt, lbl = pnl:TextEntry("Entity model:", "prop2mesh_tool_setmodel")

	local sld = pnl:NumSlider("Texture Size", "prop2mesh_tool_setuvsize", 0, 512, 0)
	pnl:ControlHelp("Tile uvs (1 / n) or set to 0 to use model uvs.")

	local cbx = pnl:CheckBox("Enable Bumpmap:", "prop2mesh_tool_setbump")
	pnl:ControlHelp("Created mesh will have bumpmaps.")

	local cbx = pnl:CheckBox("Autocenter data:", "prop2mesh_tool_setautocenter")
	pnl:ControlHelp("Created mesh will be centered around average position of selection.")

	local help = pnl:Help("You can further modify p2m entities via the context menu.")
	help:SetFont(help_font)

	return pnl
end

local function BuildPanel_Profiler(self)
	local pnl = vgui.Create("DForm")
	pnl:SetName("Profiler")
	pnl:DockPadding(0, 0, 0, 10)

	local tree = vgui.Create("DTree", pnl)
	tree:SetTall(256)
	tree:Dock(FILL)
	pnl:AddItem(tree)

	pnl.Header.OnCursorEntered = function()
		tree:Clear()

		local struct = {}
		for k, v in ipairs(ents.FindByClass("sent_prop2mesh*")) do
			local root = CPPI and v:CPPIGetOwner():Nick() or k

			if not struct[root] then
				local sdata = {
					root = tree:AddNode(root, "icon16/user.png"),
					num_mdls = 0,
					num_tris = 0,
					num_ctrl = 0,
					num_ents = 0,
				}

				sdata.node_mdls = sdata.root:AddNode("", "icon16/bullet_black.png")
				sdata.node_tris = sdata.root:AddNode("", "icon16/bullet_black.png")
				sdata.node_ctrl = sdata.root:AddNode("", "icon16/bullet_black.png")
				sdata.node_ents = sdata.root:AddNode("", "icon16/bullet_black.png")
				sdata.root:SetExpanded(true, true)

				struct[root] = sdata
			end

			local sdata = struct[root]

			sdata.num_ctrl = sdata.num_ctrl + #v.prop2mesh_controllers
			sdata.num_ents = sdata.num_ents + 1

			sdata.node_ctrl:SetText(string.format("%d total controllers", sdata.num_ctrl))
			sdata.node_ents:SetText(string.format("%d total entities", sdata.num_ents))

			for i, info in ipairs(v.prop2mesh_controllers) do
				local pcount, vcount = prop2mesh.getMeshInfo(info.crc, info.uniqueID)
				if pcount and vcount then
					sdata.num_mdls = sdata.num_mdls + pcount
					sdata.num_tris = sdata.num_tris + vcount / 3
				end
			end

			sdata.node_mdls:SetText(string.format("%d total models", sdata.num_mdls))
			sdata.node_tris:SetText(string.format("%d total triangles", sdata.num_tris))
		end
	end

	return pnl
end

local function BuildPanel_AddonSettings(self)
	local pnl = vgui.Create("DForm")
	pnl:SetName("Addon Settings")

	local btn = pnl:Button("Open Wiki")
	btn.DoClick = function()
		gui.OpenURL("https://github.com/shadowscion/Prop2Mesh/wiki")
	end

	local help = pnl:Help("Stranger zone")
	help:DockMargin(0, 0, 0, 0)
	help:SetFont(help_font)
	help.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawLine(0, h - 1, w, h - 1)
	end

	local cbox = pnl:CheckBox("Disable legacy cubes", "prop2mesh_legacy_hide")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local cbox = pnl:CheckBox("Disable obj generation", "prop2mesh_render_disable_obj")
	cbox:SetTooltip("Note: unless you rejoin, this will not apply to already generated meshes")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local cbox = pnl:CheckBox("Disable rendering", "prop2mesh_render_disable")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end

	local slider = pnl:NumSlider("Transparency:", "prop2mesh_disabled_transparency", 0, 1, 2)

	local cbox = pnl:CheckBox("Disable everything", "prop2mesh_disable")
	cbox:SetTooltip("Note: unless you rejoin, this will not apply to already generated meshes")
	cbox.OnChange = function(_, value)
		cbox.Label:SetTextColor(value and Color(255, 0, 0) or nil)
	end
	pnl:ControlHelp("This must also be enabled on the server.")

	return pnl
end

TOOL.BuildCPanel = function(self)
	self:AddPanel(BuildPanel_AddonSettings(self))
	self:AddPanel(BuildPanel_ToolSettings(self))
	self:AddPanel(BuildPanel_Profiler(self))
end


--[[

]]
local multitool = { modes = {}, lines = {} }

multitool.lines_font = "multitool_16"
multitool.title_font = "multitool_32"

surface.CreateFont(multitool.lines_font, { font = "Consolas", size = 16, weight = 200, shadow = false })
surface.CreateFont(multitool.title_font, { font = "Consolas", size = 32, weight = 200, shadow = false })

multitool.lines_color_text1 = Color(255, 255, 255, 255)
multitool.lines_color_text2 = Color(0, 0, 0, 255)
multitool.lines_color_bg1 = Color(25, 25, 25, 200)
multitool.lines_color_bg2 = Color(75, 75, 75, 200)
multitool.lines_color_bg3 = Color(0, 255, 0, 255)
multitool.title_color_text = Color(255, 255, 255, 255)
multitool.title_color_bg1 = Color(50, 50, 50, 255)

multitool.lines_display_lim = 10

if p2m_dmodelpanel then
	p2m_dmodelpanel:Remove()
	p2m_dmodelpanel = nil
end
timer.Simple(1, function()
	if not p2m_dmodelpanel then
		p2m_dmodelpanel = vgui.Create("DModelPanel")
		p2m_dmodelpanel:SetSize(200,200)
		p2m_dmodelpanel:SetModel("models/hunter/blocks/cube025x025x025.mdl")

		local pos = p2m_dmodelpanel.Entity:GetPos()
		p2m_dmodelpanel:SetLookAt(pos)
		p2m_dmodelpanel:SetCamPos(pos - Vector(-25, 0, 0))
		p2m_dmodelpanel:SetVisible(false)
	end
end)

local function GetMaxLineSize(tbl, font)
	if font then
		surface.SetFont(font)
	end
	local text_w, text_h = 0, 0
	for i = 1, #tbl do
		local tw, th = surface.GetTextSize(tbl[i])
		if text_w < tw then text_w = tw end
		if text_h < th then text_h = th end
	end
	return text_w, text_h
end

local index = CreateClientConVar("prop2mesh_multitool_index", 1, false, true)
function multitool:GetIndex()
	return index:GetInt()
end
function multitool:SetIndex(int)
	index:SetInt(int)
end


--[[

]]
function multitool:PlayerBindPress(ply, bind, pressed)
	if self.sleep or not pressed or not IsValid(self.entity) then
		return
	end

	local add
	if bind == "invnext" then add = 1 end
	if bind == "invprev" then add = -1 end
	if not add then
		return
	end

	self:onTrigger()

	local value = self:GetIndex()
	local vdiff = math.Clamp(value + add, 1, self.lines_c)

	if value ~= vdiff then
		LocalPlayer():EmitSound("weapons/pistol/pistol_empty.wav")
		self:SetIndex(vdiff)
		self:onTrigger()
	end

	return true
end


--[[

]]
function multitool:Think()
	local ply = LocalPlayer()
	local weapon = ply:GetActiveWeapon()
	if IsValid(weapon) then
		self.sleep = weapon:GetClass() ~= "gmod_tool"
	else
		self.sleep = true
	end
	if self.sleep then
		if p2m_dmodelpanel and p2m_dmodelpanel:IsVisible() then
			p2m_dmodelpanel:SetVisible(false)
		end
		return
	end
	self.trace = ply:GetEyeTrace()
	if not IsValid(self.entity) then
		if IsValid(self.trace.Entity) and self.trace.Entity:GetClass() == "sent_prop2mesh" then
			self.entity = self.trace.Entity
			self:onTrigger()
		end
		if p2m_dmodelpanel and p2m_dmodelpanel:IsVisible() then
			p2m_dmodelpanel:SetVisible(false)
		end
	else
		if self.trace.Entity ~= self.entity then
			if p2m_dmodelpanel then
				p2m_dmodelpanel:SetVisible(false)
			end
			self.entity = nil
		else
			local stage = weapon:GetStage()
			if self.stage ~= stage then
				self.entity.prop2mesh_triggertool = true
				self.stage = stage
			end
			if not self.shift then
				if LocalPlayer():KeyDown(IN_SPEED) then
					self.shift = true
					self:onTrigger()
				end
			end
			if self.shift then
				if not LocalPlayer():KeyDown(IN_SPEED) then
					self.shift = nil
					self:onTrigger()
				end
			end
			if self.entity.prop2mesh_triggertool then
				self.entity.prop2mesh_triggertool = nil
				self:onTrigger()
			else
			end
		end
	end
end


--[[

]]
function multitool:HUDPaint()
	if self.sleep or not IsValid(self.entity) then
		return
	end

	local _w = ScrW()
	local _h = ScrH()
	local _x = _w*0.5
	local _y = _h*0.5

	local mode = self.modes[self.active]
	if mode.hud then
		mode:hud(_x, _y, _w, _h)
	end

	local px = _x - self.lines_w*1.5
	local py = _y - self.lines_t*0.5

	if px < 0 then px = self.lines_h end
	if py < 0 then py = self.lines_h end

	if self.scroll then
		surface.SetDrawColor(0, 0, 0, 225)
		surface.DrawRect(px + self.lines_w, py, 8, self.scroll_a)
		surface.SetDrawColor(255, 255, 255, 225)
		surface.DrawRect(px + self.lines_w + 1, py + self.scroll_y + 1, 6, self.scroll_h - 2)
	end

	-- header
	surface.SetDrawColor(self.title_color_bg1)
	surface.DrawRect(px, py - self.title_h, self.lines_w + (self.scroll and 8 or 0), self.title_h)
	surface.SetFont(self.title_font)
	surface.SetTextColor(self.title_color_text)
	surface.SetTextPos(px + 4, py - self.title_h)
	surface.DrawText(self.title)

	-- body
	surface.SetFont(self.lines_font)
	for i = self.lines_display_min, self.lines_display_max do
		local ypos = py + self.lines_h*(i - self.lines_display_min)
		if i == self.lines_display_sel then
			surface.SetTextColor(mode.lines_color_htext or self.lines_color_text2)
			surface.SetDrawColor(mode.lines_color_hbg or self.lines_color_bg3)
			surface.DrawRect(px + 2, ypos + 2, self.lines_w - 4, self.lines_h - 4)

			if self.model and p2m_dmodelpanel then
				p2m_dmodelpanel:SetPos(px + self.lines_w, ypos - self.model*0.5)
				self.model = nil
			end
		else
			surface.SetTextColor(self.lines_color_text1)
			surface.SetDrawColor(i % 2 == 0 and self.lines_color_bg1 or self.lines_color_bg2)
			surface.DrawRect(px, ypos, self.lines_w, self.lines_h)
		end
		surface.SetTextPos(px + 4, ypos + 4)
		surface.DrawText(self.lines[i])
	end
end


--[[

]]
function multitool:onTrigger()
	if not IsValid(self.entity) then
		return
	end
	self.stage = LocalPlayer():GetActiveWeapon():GetStage()

	local mode = self.modes[self.active]

	self.title = mode.title_text
	self.title_w = mode.title_w
	self.title_h = mode.title_h

	mode:getLines()

	self.lines_c = #self.lines

	if self:GetIndex() > self.lines_c then
		self:SetIndex(self.lines_c)
	end

	self.lines_display_sel = self:GetIndex()
	self.lines_display_num = math.min(self.lines_display_lim - 1, self.lines_c)
	self.lines_display_min = math.max(self.lines_display_sel - self.lines_display_num, 1)
	self.lines_display_max = math.min(self.lines_display_min + self.lines_display_num, self.lines_c)

	self.lines_w, self.lines_h = GetMaxLineSize(self.lines, self.lines_font)
	self.lines_w = math.max(self.lines_w, self.title_w) + 8
	self.lines_h = self.lines_h + 8
	self.lines_t = self.lines_h*self.lines_display_num

	if self.lines_display_num < self.lines_c - 1 then
		local all = self.lines_c - 1
		local vis = self.lines_display_num
		local pos = (self.lines_display_sel - 1) / all

		self.scroll_a = self.lines_t + self.lines_h
		self.scroll_h = (vis / all)*self.scroll_a
		self.scroll_y = pos*(self.scroll_a - self.scroll_h)
		self.scroll = true
	else
		self.scroll = nil
	end

	if p2m_dmodelpanel then
		--p2m_dmodelpanel:SetVisible(false)
		local tbl = self.entity.prop2mesh_controllers[self.lines_display_sel - 1]
		if tbl then
			self.model = self.lines_h*self.lines_display_lim*0.5
			p2m_dmodelpanel:SetSize(self.model, self.model)
			p2m_dmodelpanel:SetColor(tbl.col)
			p2m_dmodelpanel.Entity:SetMaterial(tbl.mat)
			p2m_dmodelpanel:SetVisible(true)
		else
			p2m_dmodelpanel:SetVisible(false)
			self.model = nil
		end
	end
end


--[[

]]
function multitool:PreDrawHalos()
	if self.sleep or not IsValid(self.entity) then
		return
	end
	local info = self.entity.prop2mesh_controllers[self:GetIndex() - 1]
	if info then
		halo.Add({ info.ent }, color_white, 2, 2, 5, true)
	end
end

--
local function SetToolMode(convar_name, value_old, value_new)
	if not multitool.modes[value_new] then
		if multitool.active then
			for k, v in ipairs({"PreDrawHalos", "PostDrawHUD", "Think", "PlayerBindPress"}) do
				hook.Remove(v, "prop2mesh_multitool")
			end
			multitool:SetIndex(1)
			multitool.entity = nil
			multitool.active = nil
			if p2m_dmodelpanel then
				p2m_dmodelpanel:SetVisible(false)
			end
		end
		return
	end
	if not multitool.active then
		hook.Add("PreDrawHalos", "prop2mesh_multitool", function()
			multitool:PreDrawHalos()
		end)
		hook.Add("PostDrawHUD", "prop2mesh_multitool", function()
			multitool:HUDPaint()
		end)
		hook.Add("Think", "prop2mesh_multitool", function()
			multitool:Think()
		end)
		hook.Add("PlayerBindPress", "prop2mesh_multitool", function(ply, bind, pressed)
			if multitool:PlayerBindPress(ply, bind, pressed) then
				return true
			end
		end)
		multitool:SetIndex(1)
		multitool.entity = nil
	end
	multitool.active = value_new
	multitool:onTrigger()
end
cvars.AddChangeCallback("gmod_toolmode", SetToolMode)--, "prop2mesh_multitoolmode")

for k, v in ipairs({"PreDrawHalos", "PostDrawHUD", "Think", "PlayerBindPress"}) do
	hook.Remove(v, "prop2mesh_multitool")
end

hook.Add("Think", "prop2mesh_fixmultitoolmode", function()
	local tool = LocalPlayer():GetTool()
	if tool then
		if tool.Mode and tool.Mode ~= multitool.active then
			SetToolMode(nil, nil, tool.Mode)
		end
		hook.Remove("Think", "prop2mesh_fixmultitoolmode")
	end
end)


--[[

]]
local mode = {}
multitool.modes.prop2mesh = mode

mode.title_text = "PROP2MESH TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

local lang_tmp0 = "[Right] click to select this p2m entity"
local lang_tmp1 = "[-Left] click to automatically add controllers"
local lang_tmp2 = "[+Left] click to add controller"
local lang_tmp3 = "[+Right] click to SET models on controller [%s]"
local lang_tmp4 = "[-Right] click to ADD models to controller [%s]"

function mode:getLines()
	if multitool.stage == 0 then
		multitool.lines = { lang_tmp0 }
		return
	end
	if multitool.stage == 1 then
		multitool.lines = { multitool.shift and lang_tmp1 or lang_tmp2 }
		for i = 1, #multitool.entity.prop2mesh_controllers do
			multitool.lines[#multitool.lines + 1] = string.format(multitool.shift and lang_tmp4 or lang_tmp3, multitool.entity.prop2mesh_controllers[i].name or i)
		end
	end
end

local _gray  = Color(125, 125, 125)
local _red   = Color(255, 0, 0)
local _green = Color(0, 255, 0)
local _blue  = Color(0, 0, 255)

function mode:hud()
	cam.Start3D()
		local pos = multitool.entity:GetPos()
		local min, max = multitool.entity:GetModelBounds()
		render.DrawWireframeBox(pos, multitool.entity:GetAngles(), min, max, _gray)
		render.DrawLine(pos, pos + multitool.entity:GetForward()*3, _green)
		render.DrawLine(pos, pos + multitool.entity:GetRight()*3, _red)
		render.DrawLine(pos, pos + multitool.entity:GetUp()*3, _blue)
	cam.End3D()
end


--[[

]]
local mode = {}
multitool.modes.remover = mode

mode.title_text = "REMOVER TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

mode.lines_color_hbg = Color(255, 0, 0, 255)

local lang_tmp1 = "remove entity"
local lang_tmp2 = "remove controller [%s]"

function mode:getLines()
	multitool.lines = { lang_tmp1 }
	for i = 1, #multitool.entity.prop2mesh_controllers do
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2, multitool.entity.prop2mesh_controllers[i].name or i)
	end
end


--[[

]]
local mode = {}
multitool.modes.material = mode

mode.title_text = "MATERIAL TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

local lang_tmp1 = "entity [%s]"
local lang_tmp2 = "controller [%s] [%s]"

function mode:getLines()
	multitool.lines = { string.format(lang_tmp1, multitool.entity:GetMaterial()) }
	for i = 1, #multitool.entity.prop2mesh_controllers do
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2, multitool.entity.prop2mesh_controllers[i].name or i, multitool.entity.prop2mesh_controllers[i].mat)
	end
end


--[[

]]
local mode = {}
multitool.modes.colour = mode

mode.title_text = "COLOR TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

local lang_tmp1 = "entity [%d %d %d %d]"
local lang_tmp2 = "controller [%s] [%d %d %d %d]"

function mode:getLines()
	local col = multitool.entity:GetColor()
	multitool.lines = { string.format(lang_tmp1, col.r, col.g, col.b, col.a) }
	for i = 1, #multitool.entity.prop2mesh_controllers do
		col = multitool.entity.prop2mesh_controllers[i].col
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2, multitool.entity.prop2mesh_controllers[i].name or i, col.r, col.g, col.b, col.a)
	end
end


--[[

]]
local mode = {}
multitool.modes.colmat = mode

mode.title_text = "COLORMATER TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

local lang_tmp1 = "entity [%d %d %d %d] [%s]"
local lang_tmp2 = "controller [%s] [%d %d %d %d] [%s]"

function mode:getLines()
	local col = multitool.entity:GetColor()
	multitool.lines = { string.format(lang_tmp1, col.r, col.g, col.b, col.a, multitool.entity:GetMaterial()) }
	for i = 1, #multitool.entity.prop2mesh_controllers do
		col = multitool.entity.prop2mesh_controllers[i].col
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2,
			multitool.entity.prop2mesh_controllers[i].name or i, col.r, col.g, col.b, col.a, multitool.entity.prop2mesh_controllers[i].mat)
	end
end


--[[
	clipping tools
]]
local lang_tmp1 = "clip entity"
local lang_tmp2 = "clip controller [%s] [%d clips]"

local cliptext = function(self)
	multitool.lines = { lang_tmp1 }
	local controllers = multitool.entity.prop2mesh_controllers
	for i = 1, #controllers do
		local num = controllers[i].clips and #controllers[i].clips or 0
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2, multitool.entity.prop2mesh_controllers[i].name or i, num)
	end
end


-- visclip adv
local mode = {}
multitool.modes.visual_adv = mode

mode.title_text = "VISUAL CLIP ADV TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

mode.getLines = cliptext


-- properclipping
local mode = {}
multitool.modes.proper_clipping = mode

mode.title_text = "PROPER CLIPPING TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

mode.getLines = cliptext


--[[

]]
local mode = {}
multitool.modes.resizer = mode

mode.title_text = "RESIZER TOOL"

surface.SetFont(multitool.title_font)
mode.title_w, mode.title_h = surface.GetTextSize(mode.title_text)

local lang_tmp1 = "apply scale to all controllers"
local lang_tmp2 = "controller [%s] [%d %d %d]"

function mode:getLines()
	multitool.lines = { lang_tmp1 }
	for i = 1, #multitool.entity.prop2mesh_controllers do
		local scale = multitool.entity.prop2mesh_controllers[i].scale
		multitool.lines[#multitool.lines + 1] = string.format(lang_tmp2, multitool.entity.prop2mesh_controllers[i].name or i, scale.x, scale.y, scale.z)
	end
end


--[[
function mode:hud()
	local controller = multitool.entity.prop2mesh_controllers[multitool.lines_display_sel - 1]
	if not controller then
		return
	end

	local tool = LocalPlayer():GetTool()
	if tool.norm and tool.origin and controller.ent then
		cam.IgnoreZ(true)
			local i = LocalPlayer():KeyDown(IN_WALK)
			local offset = tool:GetClientNumber("offset") * (i and -1 or 1)

			local prev = render.EnableClipping(true)
			render.SuppressEngineLighting(true)

			render.PushCustomClipPlane(tool.norm * (i and 1 or -1), tool.norm:Dot(tool.origin) * (i and 1 or -1) - offset)
			render.SetColorModulation(0.3, 2, 0.5)
			controller.ent:DrawModel()
			render.PopCustomClipPlane()

			render.PushCustomClipPlane(tool.norm * (i and -1 or 1), tool.norm:Dot(tool.origin) * (i and -1 or 1) + offset)
			render.SetColorModulation(2, 0.2, 0.3)
			controller.ent:DrawModel()
			render.PopCustomClipPlane()

			render.SuppressEngineLighting(false)
			render.EnableClipping(prev)
		cam.IgnoreZ(false)
	end
end
]]
