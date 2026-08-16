local string = string
local table = table
local math = math
local net = net

file.CreateDir("p2m")


--[[

	skin and panel overrides

]]
local theme = {}

local editor_font = "prop2mesh_editor_font"
surface.CreateFont(editor_font, {font = "Consolas", size = 14, weight = 800, antialias = 1})

theme.colorText_add = Color(100, 200, 100)
theme.colorText_edit = Color(100, 100, 255)
theme.colorText_kill = Color(255, 100, 100)
theme.colorText_default = Color(75, 75, 75)
theme.colorMain = Color(75, 75, 75)
theme.colorTree = Color(245, 245, 245)

local wireframe = Material("models/wireframe")

local TreeAddNode, NodeAddNode
function TreeAddNode(self, text, icon, font)
	local node = DTree.AddNode(self, string.lower(text), icon)
	node.Label:SetFont(font or editor_font)
	node.Label:SetTextColor(theme.colorText_default)
	node.AddNode = NodeAddNode
	return node
end
function NodeAddNode(self, text, icon, font)
	local node = DTree_Node.AddNode(self, string.lower(text), icon)
	node.Label:SetFont(font or editor_font)
	node.Label:SetTextColor(theme.colorText_default)
	node.AddNode = NodeAddNode
	return node
end

local function HideIcons() return false end


--[[

	uploader

]]
local filecache_data = {}
local filecache_keys = {}

local upstreams = {}

net.Receive("prop2mesh_upload_start", function(len)
	local eid = net.ReadUInt(16)
	for i = 1, net.ReadUInt(8) do
		local crc = net.ReadString()
		if filecache_keys[crc] and filecache_keys[crc].data then
			net.Start("prop2mesh_upload")
			net.WriteUInt(eid, 16)
			net.WriteString(crc)
			upstreams[crc] = prop2mesh.WriteStream(filecache_keys[crc].data)
			net.SendToServer()
		end
	end
end)

local function upstreamProgress()
	local max = 0
	for crc, stream in pairs(upstreams) do
		local client = next(stream.clients)
		if client and stream.clients[client] then
			client = stream.clients[client]
			if client.finished then
				upstreams[crc] = nil
			else
				local progress = client.progress / stream.numchunks
				if max < progress then
					max = progress
				end
			end
		end
	end
	return max
end

local function formatOBJ(filestr)
	local vcount = 0
	local condensed = {}

	for line in string.gmatch(filestr, "(.-)\n") do
		local temp = string.Explode(" ", string.gsub(string.Trim(line), "%s+", " "))
		local head = table.remove(temp, 1)

		if head == "f" then
			local v1 = string.Explode("/", temp[1])
			local v2 = string.Explode("/", temp[2])
			for i  = 3, #temp do
				local v3 = string.Explode("/", temp[i])
				condensed[#condensed + 1] = string.format("f %d %d %d\n", v1[1], v2[1], v3[1])
				v2 = v3
			end
		else
			if head == "v" then
				local x = tonumber(temp[1])
				local y = tonumber(temp[2])
				local z = tonumber(temp[3])

				x = math.abs(x) < 1e-4 and 0 or x
				y = math.abs(y) < 1e-4 and 0 or y
				z = math.abs(z) < 1e-4 and 0 or z

				condensed[#condensed + 1] = string.format("v %s %s %s\n", x, y, z)
				vcount = vcount + 1
			end
		end

		if vcount > 63999 then return end
	end

	return table.concat(condensed)
end

local export_output, export_iter
local function exportOBJ(meshparts, additive, id)
	if not meshparts then
		return
	end

	local concat  = table.concat
	local format  = string.format

	local p_verts = "v %f %f %f\n"
	local p_norms = "vn %f %f %f\n"
	local p_uvws  = "vt %f %f\n"
	local p_faces = "f %d/%d/%d %d/%d/%d %d/%d/%d\n"
	local p_parts = "#PART NUMBER %d\n"

	local function push(tbl, pattern, ...)
		tbl[#tbl + 1] = format(pattern, ...)
	end

	if not export_iter or not export_output then
		export_output = {}
		export_iter = 1
	end

	for i = 2, #meshparts do
		local part = meshparts[i]

		local s_verts = {}
		local s_norms = {}
		local s_uvws  = {}
		local s_faces = {}

		for j = 1, #part, 3 do
			local v1 = part[j + 0]
			local v2 = part[j + 1]
			local v3 = part[j + 2]

			push(s_verts, p_verts, v1.pos.x, v1.pos.y, v1.pos.z)
			push(s_verts, p_verts, v2.pos.x, v2.pos.y, v2.pos.z)
			push(s_verts, p_verts, v3.pos.x, v3.pos.y, v3.pos.z)

			push(s_norms, p_norms, v1.normal.x, v1.normal.y, v1.normal.z)
			push(s_norms, p_norms, v2.normal.x, v2.normal.y, v2.normal.z)
			push(s_norms, p_norms, v3.normal.x, v3.normal.y, v3.normal.z)

			push(s_uvws, p_uvws, v1.u, v1.v)
			push(s_uvws, p_uvws, v2.u, v2.v)
			push(s_uvws, p_uvws, v3.u, v3.v)

			push(s_faces, p_faces, export_iter, export_iter, export_iter, export_iter + 2, export_iter + 2, export_iter + 2, export_iter + 1, export_iter + 1, export_iter + 1)
			export_iter = export_iter + 3
		end

		export_output[#export_output + 1] = concat({
			format("\no id %d model %d\n", id or 1, i - 1),
			concat(s_verts),
			concat(s_norms),
			concat(s_uvws),
			concat(s_faces)
		})
	end

	if not additive then
		local ret = concat(export_output)
		export_iter = nil
		export_output = nil

		return ret
	end
end

local function formatE2(conroot, skipheader)
	if conroot.crc == "!none" then return end

	local format = string.format
	local concat = table.concat

	local header = {}

	p2m = conroot.pname or "P2M1"

	if not skipheader then
		header[#header + 1] = "#---- UNCOMMENT IF NECESSARY\n#---- ONLY NEEDED ONCE PER ENTITY\n"
		header[#header + 1] = "#[\nBase = entity()\nP2M1 = p2mCreate( put count here, Base:pos(), Base:angles())\nP2M1:p2mSetParent(Base)\n]#\n\n"
		header[#header + 1] = "#---- UNCOMMENT AND PUT AT END OF CODE\n#P2M1:p2mBuild()\n\n"
	end

	header[#header + 1] = format("#---- CONTROLLER %d\nlocal Index = %d\n", conroot.num, conroot.num)
	header[#header + 1] = format("%s:p2mSetUV(Index, %d)", p2m, conroot.info.uvs)
	if tobool( conroot.info.bump ) then
		header[#header + 1] = format("%s:p2mSetBump(Index, %d)", p2m, 1)
	end
	header[#header + 1] = format("%s:p2mSetScale(Index, vec(%.3f, %.3f, %.3f))", p2m, conroot.info.scale.x, conroot.info.scale.y, conroot.info.scale.z)
	header[#header + 1] = format("%s:p2mSetColor(Index, vec4(%d, %d, %d, %d))", p2m, conroot.info.col.r, conroot.info.col.g, conroot.info.col.b, conroot.info.col.a)
	header[#header + 1] = format("%s:p2mSetMaterial(Index, \"%s\")\n\n", p2m, conroot.info.mat)

	local specialk = {
		clips = true, vsmooth = true, vinside = true, bodygroup = true, submodels = true
	}

	local body = {}
	for k, v in ipairs(prop2mesh.getMeshData(conroot.info.crc, true) or {}) do
		if not v.prop and not v.holo then
			goto CONTINUE
		end

		local special
		for i, j in pairs(v) do
			if specialk[i] then
				special = true
				break
			end
		end

		if special then
			local push = {}

			push[#push + 1] = format("    \"model\" = \"%s\"", v.prop or v.holo)
			push[#push + 1] = format("    \"pos\" = vec(%.3f, %.3f, %.3f)", v.pos.x, v.pos.y, v.pos.z)
			push[#push + 1] = format("    \"ang\" = ang(%.3f, %.3f, %.3f)", v.ang.p, v.ang.y, v.ang.r)

			if v.scale then
				push[#push + 1] = format("    \"scale\" = vec(%.3f, %.3f, %.3f)", v.scale.x, v.scale.y, v.scale.z)
			end
			if v.vsmooth then
				push[#push + 1] = "    \"flat\" = 1"
			end
			if v.vinside then
				push[#push + 1] = "    \"inside\" = 1"
			end
			if v.bodygroup then
				push[#push + 1] = format("    \"bodygroup\" = %d", v.bodygroup)
			end
			if v.submodels then
				push[#push + 1] = format("    \"submodels\" = array(%s)", concat(table.GetKeys(v.submodels), ","))
			end
			if v.clips then
				local clips = {}
				for i, clip in ipairs(v.clips) do
					local pos = clip.n * clip.d
					clips[#clips + 1] = format("vec(%.3f, %.3f, %.3f), vec(%.3f, %.3f, %.3f)", pos.x, pos.y, pos.z, clip.n.x, clip.n.y, clip.n.z)
				end
				push[#push + 1] = format("    \"clips\" = array(\n        %s\n    )", concat(clips, ",\n        "))
			end

			body[#body + 1] = format("%s:p2mPushModel(Index, table(\n%s\n))", p2m, concat(push, ",\n"))
		else
			if v.scale then
				body[#body + 1] = format("%s:p2mPushModel(Index, \"%s\", vec(%.3f, %.3f, %.3f), ang(%.3f, %.3f, %.3f), vec(%.3f, %.3f, %.3f))",
					p2m, v.prop or v.holo, v.pos.x, v.pos.y, v.pos.z, v.ang.p, v.ang.y, v.ang.r, v.scale.x, v.scale.y, v.scale.z)
			else
				body[#body + 1] = format("%s:p2mPushModel(Index, \"%s\", vec(%.3f, %.3f, %.3f), ang(%.3f, %.3f, %.3f))",
					p2m, v.prop or v.holo, v.pos.x, v.pos.y, v.pos.z, v.ang.p, v.ang.y, v.ang.r)
			end
		end

		::CONTINUE::
	end

	return concat({ concat(header, "\n"), concat(body, "\n") })
end


--[[

	batch exporter

]]
local function batchExportObj(batch)
	local pnl = Derma_StringRequest("", "Exporting all controllers to folder:", "default", function(text)
		local gid = 0
		text = string.lower(string.StripExtension(text))

		for ent in pairs(batch) do
			export_iter = nil
			export_output = nil

			for index, info in ipairs(ent.prop2mesh_controllers) do
				exportOBJ(prop2mesh.getMeshDirect(info.crc, info.uniqueID), true, index)
			end

			gid = gid + 1

			local dir = string.format("p2m/%s", text)
			file.CreateDir(dir)
			file.Write(string.format("%s/controller%d.txt", dir, gid), table.concat(export_output))
		end
	end)

	pnl.lblTitle:SetFont(editor_font)
	pnl.lblTitle:SetTextColor(color_white)

	local time = SysTime()

	pnl.Paint = function(_, w, h)
		Derma_DrawBackgroundBlur(pnl, time)
		surface.SetDrawColor(theme.colorMain)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
end

local function batchFormatE2(batch)
	openE2Editor()
	if not wire_expression2_editor then return end

	local codeblocks = {""}

	local header = {}
	header[#header + 1] = "#----\nBase = entity()\n\n"

	local eid = 0
	for ent in pairs(batch) do
		eid = eid + 1
		for index, info in ipairs(ent.prop2mesh_controllers) do
			codeblocks[#codeblocks + 1] = formatE2({ pname = string.format("P2M%d", eid), num = index, info = info }, true)
		end
		header[#header + 1] = string.format("P2M%d = p2mCreate(%d, Base:pos(), Base:angles())\n", eid, #ent.prop2mesh_controllers)
	end

	header[#header + 1] = "\n"
	for i = 1, eid do
		header[#header + 1] = string.format("P2M%d:p2mSetParent(Base)\n", i)
	end

	local footer = {"#----\n"}
	for i = 1, eid do
		footer[#footer + 1] = string.format("P2M%d:p2mBuild()\n", i)
	end

	codeblocks[1] = table.concat(header)
	codeblocks[#codeblocks + 1] = table.concat(footer)

	wire_expression2_editor:NewTab()
	wire_expression2_editor:SetCode(table.concat(codeblocks, "\n\n"))
	spawnmenu.ActivateTool("wire_expression2")
end

net.Receive("prop2mesh_export", function()
	local type = net.ReadUInt(8)

	local count = net.ReadUInt(32)
	local batch = {}

	for i = 1, count do
		local ent = Entity(net.ReadUInt(32))
		if IsValid(ent) then
			batch[ent] = true
		end
	end

	if next(batch) == nil then return end

	if type == 1 then
		batchExportObj(batch)
	end

	if type == 2 and E2Lib and openE2Editor then
		batchFormatE2(batch)
	end
end)

local function CanToolClient(ent)
	return true
	--if not CPPI then return true end
	--return IsValid( ent ) and ent.CPPIGetOwner and ent:CPPIGetOwner() == LocalPlayer()
	--return IsValid(ent) and ent.CPPICanTool and ent:CPPICanTool(LocalPlayer(), "prop2mesh")
end

--[[

	editor components

]]
local function changetable(partnode, key, diff)
	if not partnode.mod then
		if partnode.set then
			partnode.set[key] = diff and partnode.new[key] or nil

			local color = next(partnode.set) and theme.colorText_edit
			partnode.Label:SetTextColor(color or theme.colorText_default)
			partnode.Icon:SetImageColor(color or color_white)
		end
		return
	end
	if diff then
		if not partnode.mod[partnode.num] then
			partnode.mod[partnode.num] = {}
		end
		partnode.mod[partnode.num][key] = partnode.new[key]
		local color = partnode.mod[partnode.num].kill and theme.colorText_kill or theme.colorText_edit
		partnode.Label:SetTextColor(color)
		partnode.Icon:SetImageColor(color)
	elseif partnode.mod[partnode.num] then
		partnode.mod[partnode.num][key] = nil
		if not next(partnode.mod[partnode.num]) then
			partnode.mod[partnode.num] = nil
			partnode.Label:SetTextColor(theme.colorText_default)
			partnode.Icon:SetImageColor(color_white)
		end
	end
end

local function registerColor(partnode, name, key)
	local node = partnode:AddNode(name, "icon16/bullet_black.png")
	local color_o = Color(120, 120, 120)

	node.Icon.Paint = function(btn, w, h)
		local w = w - 2
		local h = h - 2

		draw.RoundedBox(3, 0, 0, w, h, color_o)
		draw.RoundedBox(3, 1, 1, w - 2, h - 2, color_white)
		draw.RoundedBox(3, 2, 2, w - 4, h - 4, partnode.new[key])
	end

	node.PerformLayout = function(self, w, h)
		DTree_Node.PerformLayout(self, w, h)

    	local spacing = 4
    	local cellWidth = math.ceil((w - 48) / 3) - spacing

	    node.Icon:SetPos(24, 0)
		node.Icon:SetSize(h, h)

	    node.Label:SetPos(spacing + spacing - 1, 0)
	end

	local color

	local function ValueChanged( pnl, val )
		local diff = false
		for k, v in pairs(val) do
			if partnode.new[key][k] ~= v then
				diff = true
				break
			end
		end

		if not diff then
			return
		end

		partnode.new[key].r = val.r
		partnode.new[key].g = val.g
		partnode.new[key].b = val.b
		partnode.new[key].a = val.a

		local diff = false
		for k, v in pairs(partnode.new[key]) do
			if partnode.old[key][k] ~= v then
				diff = true
				break
			end
		end

		if diff then
			node.Label:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)
			changetable(partnode, key, true)
		else
			node.Label:SetTextColor(theme.colorText_default)
			changetable(partnode, key, false)
		end
	end

	node.DoClick = function()
		if color and IsValid(color) then
			return
		end

		local window = partnode:GetParentNode():GetParent()

		color = vgui.Create("DColorCombo", window)
		color.Mixer:SetPalette(false)
		color.Mixer:SetAlphaBar(true)
		color.Mixer:SetWangs(true)

		color:SetupCloseButton(function()
			color:Remove()
			color = nil
		end)

		color.Mixer:SetColor(table.Copy(partnode.new[key]))

		local x, y = window:ScreenToLocal(gui.MouseX(), gui.MouseY())
		local w = window:GetWide()
		color:Dock(NODOCK)
		color:SetSize(w*0.75, w*0.75)
		color:Center()
		color:SetPos(color:GetX(), y + 12)

		color.Mixer.ValueChanged = function(pnl, val)
			ValueChanged( pnl, val )
		end
	end

	return function( col )
		ValueChanged( nil, table.Copy( col ) )
	end
end

local function callbackString(partnode, name, text, key, val)
	if not tostring(val) or partnode.new[key] == val then
		return
	end

	partnode.new[key] = tostring(val)

	if partnode.new[key] ~= partnode.old[key] then
		name.Label:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)
		text:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)

		changetable(partnode, key, true)
	else
		name.Label:SetTextColor(theme.colorText_default)
		text:SetTextColor(theme.colorText_default)

		changetable(partnode, key, false)
	end
end

local function registerString(partnode, name, key)
	local node = partnode:AddNode(name, "icon16/bullet_black.png"):AddNode("")
	node.ShowIcons = HideIcons
	node:SetDrawLines(false)

	local text = vgui.Create("DTextEntry", node)

	node.PerformLayout = function(self, w, h)
		DTree_Node.PerformLayout(self, w, h)

    	local spacing = 4
    	local cellWidth = math.ceil((w - 48) / 1) - spacing

	    text:SetPos(24, 0)
		text:SetSize(cellWidth, h)
	end

	text:SetFont(editor_font)
	text.OnValueChange = function(self, val)
		if not tostring(val) then
			self:SetText(partnode.new[key])
			return
		end

		self:SetText(val)
		callbackString(partnode, node:GetParentNode(), self, key, val)
	end
	text:SetValue(partnode.new[key])

	return function( val )
		text:SetValue( val )
	end
end

local function callbackVector(partnode, name, text, key, i, val)
	if not tonumber(val) or partnode.new[key][i] == val then
		return
	end

	partnode.new[key][i] = tonumber(val)

	if partnode.new[key][i] ~= partnode.old[key][i] then
		name.Label:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)
		text:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)

		changetable(partnode, key, true)
	else
		name.Label:SetTextColor(theme.colorText_default)
		text:SetTextColor(theme.colorText_default)

		local diff = false
		for j = 1, 3 do
			if partnode.new[key][j] ~= partnode.old[key][j] then
				diff = true
				break
			end
		end

		changetable(partnode, key, diff)
	end
end

local function registerVector(partnode, name, key)
	local node = partnode:AddNode(name, "icon16/bullet_black.png"):AddNode("")
	node.ShowIcons = HideIcons
	node:SetDrawLines(false)

	local x = vgui.Create("DTextEntry", node)
	local y = vgui.Create("DTextEntry", node)
	local z = vgui.Create("DTextEntry", node)

	node.PerformLayout = function(self, w, h)
		DTree_Node.PerformLayout(self, w, h)

    	local spacing = 4
    	local cellWidth = math.ceil((w - 48) / 3) - spacing

	    x:SetPos(24, 0)
		x:SetSize(cellWidth, h)

	    y:SetPos(24 + cellWidth + spacing, 0)
	    y:SetSize(cellWidth, h)

	    z:SetPos(24 + (cellWidth + spacing) * 2, 0)
	    z:SetSize(cellWidth, h)
	end

	for i, v in ipairs({x, y, z}) do
		v:SetFont(editor_font)
		v:SetNumeric(true)
		v.OnValueChange = function(self, val)
			if not tonumber(val) then
				self:SetText(string.format("%.4f", partnode.new[key][i]))
				return
			end
			self:SetText(string.format("%.4f", val))
			callbackVector(partnode, node:GetParentNode(), self, key, i, val)
		end
		v:SetValue(partnode.new[key][i])
	end

	return function( vx, vy, vz )
		if vx ~= nil then x:SetValue( vx ) end
		if vy ~= nil then y:SetValue( vy ) end
		if vz ~= nil then z:SetValue( vz ) end
	end
end

local function callbackBoolean(partnode, name, key, val)
	if partnode.new[key] == val then
		return
	end

	partnode.new[key] = val

	if partnode.new[key] ~= partnode.old[key] then
		name:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)

		changetable(partnode, key, true)
	else
		name:SetTextColor(theme.colorText_default)

		changetable(partnode, key, false)
	end
end

local function registerBoolean(partnode, name, key)
	local node = partnode:AddNode("")
	node.ShowIcons = HideIcons

	local x = vgui.Create("DCheckBoxLabel", node)
	x:SetText(name)
	x:Dock(LEFT)
	x:DockMargin(24, 0, 4, 0)
	x.Label:SetDisabled(true)

	x.OnChange = function(self, val)
		callbackBoolean(partnode, self, key, val and 1 or 0)
	end

	x:SetValue(partnode.new[key] == 1)
	x:SetTextColor(theme.colorText_default)
	x:SetFont(editor_font)

	return function( val )
		x:SetValue( tobool( val ) )
	end
end

local function registerFloat(partnode, name, key, min, max)
	local node = partnode:AddNode("")
	node.ShowIcons = HideIcons

	local x = vgui.Create("DCheckBoxLabel", node)
	x:Dock(LEFT)
	x:DockMargin(24, 0, 4, 0)
	x:SetText(name)
	x:SetFont(editor_font)
	x:SetTextColor(theme.colorText_default)

	local s = vgui.Create("DNumSlider", node)
	s.UpdateNotches = function(pnl)
		return pnl.Slider:SetNotches(8)
	end
	s.Scratch:SetVisible(false)
	s.Label:SetVisible(false)
	s.Label:SetTextColor(theme.colorText_default)
	s.TextArea:SetFont(editor_font)
	s:SetWide(128)
	s:DockMargin(24, 0, 4, 0)
	s:Dock(LEFT)
	s:SetMin(min)
	s:SetMax(max)
	s:SetDecimals(0)

	s.OnValueChanged = function(self, val)
		x:SetChecked(val > 0)
		callbackBoolean(partnode, x, key, math.Round(val))
	end

	x.OnChange = function(self, value)
		self:SetChecked(s:GetValue() > 0)
	end

	s:SetValue(partnode.new[key])

	return function( val )
		s:SetValue( val )
	end
end

local function registerSubmodels(partnode)
	if partnode.new.objd or (not partnode.new.prop and not partnode.new.holo) then
		return
	end

	local submeshes = util.GetModelMeshes(partnode.new.prop or partnode.new.holo, 0, partnode.new.bodygroup or 0)
	if not submeshes then
		return
	end

	local new = partnode.new.submodels
	local old = partnode.old.submodels

	local node = partnode:AddNode("sub-models", "icon16/bullet_black.png")

	for i = 1, #submeshes do
		local subnode = node:AddNode("")
		subnode.ShowIcons = HideIcons
		subnode:SetDrawLines(false)

		local x = vgui.Create("DCheckBoxLabel", subnode)
		x:Dock(LEFT)
		x:DockMargin(24, 0, 4, 0)
		x.Label:SetDisabled(true)

		if new[i] == nil then new[i] = 0 end
		if old[i] == nil then old[i] = 0 end

		x.OnChange = function(self, val)
			if new[i] == val then
				return
			end

			new[i] = val and 1 or 0

			if new[i] ~= old[i] then
				x:SetTextColor((partnode.mod or partnode.set) and theme.colorText_edit or theme.colorText_add)
				changetable(partnode, "submodels", true)
			else
				x:SetTextColor(theme.colorText_default)

				local diff = false
				for k, v in pairs(new) do
					if old[k] ~= v then
						diff = true
						break
					end
				end
				changetable(partnode, "submodels", diff)
			end
			x:SetText(string.format("part %d will be %s", i, val and "ignored" or "generated"))
		end

		x:SetValue(new[i] == 1)
		x:SetToolTip(string.format("tris: %d\nmat: %s", #submeshes[i].triangles, submeshes[i].material))
		x:SetTextColor(theme.colorText_default)
		x:SetFont(editor_font)
	end
end


--[[

	menus

]]
local function installEditors(partnode)
	registerSubmodels(partnode)
	registerVector(partnode, "pos", "pos")
	registerVector(partnode, "ang", "ang")
	registerVector(partnode, "scale", "scale")
	registerBoolean(partnode, "render_inside", "vinside")

	if partnode.new.objd then
		registerBoolean(partnode, "render_invert", "vinvert")
		registerFloat(partnode, "render_smooth", "vsmooth", 0, 180)
	else
		registerBoolean(partnode, "render_flat", "vsmooth")
	end

	partnode:ExpandRecurse(true)
	partnode.edited = true
end

local function copyclips(clips)
	local ret = {}
	for k, clip in ipairs(clips) do
		ret[k] = {d = clip.d, n = {clip.n.x, clip.n.y, clip.n.z}}
	end
	return ret
end

local copydeeper
function copydeeper(t, lookup_table)
	if t == nil then return nil end

	local copy = {}
	setmetatable(copy, debug.getmetatable(t))

	for i, v in pairs(t) do
		if not istable(v) then
			if isvector(v) then
				copy[i] = Vector(v.x, v.y, v.z)
			elseif isangle(v) then
				copy[i] = Angle(v.p, v.y, v.r)
			else
				copy[i] = v
			end
		else
			lookup_table = lookup_table or {}
			lookup_table[t] = copy
			if lookup_table[v] then
				copy[i] = lookup_table[v]
			else
				copy[i] = copydeeper(v, lookup_table)
			end
		end
	end
	return copy
end

local function partcopy(from)
	local a = { pos = {0, 0, 0}, ang = {0, 0, 0}, scale = {1, 1, 1}, vinvert = 0, vinside = 0, vsmooth = 0, submodels = {}, clips = {} }
	local b = { pos = {0, 0, 0}, ang = {0, 0, 0}, scale = {1, 1, 1}, vinvert = 0, vinside = 0, vsmooth = 0, submodels = {}, clips = {} }
	for k, v in pairs(from) do
		if isnumber(v) or isstring(v) then
			a[k] = v
			b[k] = v
		elseif isvector(v) then
			a[k] = {v.x, v.y, v.z}
			b[k] = {v.x, v.y, v.z}
		elseif isangle(v) then
			a[k] = {v.p, v.y, v.r}
			b[k] = {v.p, v.y, v.r}
		else
			if k == "submodels" then
				a[k] = table.Copy(v)
				b[k] = table.Copy(v)
			elseif k == "clips" then
				a[k] = copyclips(v)
				b[k] = copyclips(v)
			elseif k == "primitive" then
				a[k] = copydeeper(v)
				b[k] = copydeeper(v)
			end
		end
	end
	return a, b
end

local function partmenu(frame, partnode)
	local menu = DermaMenu()

	if not partnode.edited then
		menu:AddOption("edit part", function()
			installEditors(partnode)
		end):SetIcon("icon16/brick_edit.png")
	end

	menu:AddOption(partnode.new.kill and "undo remove part" or "remove part", function()
		partnode.new.kill = not partnode.new.kill
		changetable(partnode, "kill", partnode.new.kill)
		partnode:SetExpanded(false, true)
	end):SetIcon("icon16/brick_delete.png")

	menu:AddSpacer()
	menu:AddOption("cancel"):SetIcon("icon16/cancel.png")
	menu:Open()
end

local function objmenu(frame, objnode)
	local menu = DermaMenu()

	menu:AddOption("remove model", function()
		objnode:Remove()
		objnode = nil
	end):SetIcon("icon16/brick_delete.png")

	menu:AddSpacer()
	menu:AddOption("cancel"):SetIcon("icon16/cancel.png")
	menu:Open()
end

local function attach(pathnode)
	local filepath = pathnode.path
	local filestr = file.Read(pathnode.path)
	local filecrc = tostring(util.CRC(filestr))

	if not filecache_data[filecrc] then
		local valid, contents = pcall(formatOBJ, filestr)
		if not valid then
			chat.AddText(Color(255, 125, 125), "unexpected error!")
			return
		end
		if not contents then
			chat.AddText(Color(255, 125, 125), ".obj must have fewer than 64000 vertices!")
			return
		end
		local crc = tostring(util.CRC(contents))
		filecache_data[filecrc] = { crc = crc, data = util.Compress(contents) }
		filecache_keys[crc] = filecache_data[filecrc]
	end
	if not filecache_data[filecrc] then
		chat.AddText(Color(255, 125, 125), "unexpected error!")
		return
	end

	local filename = string.GetFileFromFilename(pathnode.path)
	local partnode = pathnode.list:AddNode(string.format("[new!] %s", filename), "icon16/brick.png")

	partnode.Label:SetTextColor(theme.colorText_add)
	partnode.Icon:SetImageColor(theme.colorText_add)

	partnode.menu = objmenu
	partnode.new, partnode.old = partcopy({ objn = filename, objd = filecache_data[filecrc].crc })
	pathnode.list.add[partnode] = true

	installEditors(partnode)

	partnode:ExpandTo(true)
end

local function objfilemenu(frame, pathnode)
	local menu = DermaMenu()

	menu:AddOption("attach model", function()
		attach(pathnode)
	end):SetIcon("icon16/brick_add.png")

	menu:AddSpacer()
	menu:AddOption("cancel"):SetIcon("icon16/cancel.png")
	menu:Open()
end

local function setGlobalValue(frame, conroot, mod, key, value, name, force)
	if force then
		for i = 1, conroot.count do
			if not mod[i] then
				mod[i] = {}
			end
			mod[i][key] = value
		end

		frame.btnConfirm:DoClick()
	else
		local pnl = Derma_Query("This will CONFIRM any other changes to all controllers.", string.format("Set %s to %s on all parts?", name or key, tostring(value)), "Yes", function()
			for i = 1, conroot.count do
				if not mod[i] then
					mod[i] = {}
				end
				mod[i][key] = value
			end

			frame.btnConfirm:DoClick()
		end, "No")

		pnl.lblTitle:SetFont(editor_font)
		pnl.lblTitle:SetTextColor(color_white)

		local time = SysTime()

		pnl.Paint = function(_, w, h)
			Derma_DrawBackgroundBlur(pnl, time)
			surface.SetDrawColor(theme.colorMain)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(0, 0, 0)
			surface.DrawOutlinedRect(0, 0, w, h)
		end
	end
end

local function conmenu(frame, conroot)
	local menu = DermaMenu()

	local updates = frame.updates and frame.updates[conroot.num]
	if updates and updates.mod and updates.set then
		local opt = menu:AddOption("remove controller", function()
			local pnl = Derma_Query("This will IGNORE any unconfirmed changes to all controllers.", string.format("Remove controller [%s]?", conroot.info.name or conroot.num), "Yes", function()
				for k, v in pairs(frame.updates) do
					v.add = {}
					v.mod = {}
					v.set = {}
				end

				updates.set.remove = true

				frame.btnConfirm:DoClick()
			end, "No", function() end)

			pnl.lblTitle:SetFont(editor_font)
			pnl.lblTitle:SetTextColor(color_white)

			local time = SysTime()

			pnl.Paint = function(_, w, h)
				Derma_DrawBackgroundBlur(pnl, time)
				surface.SetDrawColor(theme.colorMain)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(0, 0, 0)
				surface.DrawOutlinedRect(0, 0, w, h)
			end
		end)

		opt:SetIcon("icon16/controller_delete.png")
		opt:SetTextColor(theme.colorText_kill)

		menu:AddSpacer()
		local sub, opt = menu:AddSubMenu("copy values to other")
		opt:SetIcon("icon16/world.png")

		sub:AddOption( "pos offset", function()
			local copy = frame.conroots[conroot.num].setroot.new.linkpos
			local x = copy[1]
			local y = copy[2]
			local z = copy[3]

			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_linkpos( x, y, z )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "ang offset", function()
			local copy = frame.conroots[conroot.num].setroot.new.linkang
			local x = copy[1]
			local y = copy[2]
			local z = copy[3]

			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_linkang( x, y, z )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "scale", function()
			local copy = frame.conroots[conroot.num].setroot.new.scale
			local x = copy[1]
			local y = copy[2]
			local z = copy[3]

			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_scale( x, y, z )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "material", function()
			local copy = frame.conroots[conroot.num].setroot.new.mat
			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_mat( copy )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "color", function()
			local copy = frame.conroots[conroot.num].setroot.new.col
			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_col( copy )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "texture size", function()
			local copy = frame.conroots[conroot.num].setroot.new.uvs
			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_uvs( copy )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		sub:AddOption( "enable bumpmap", function()
			local copy = frame.conroots[conroot.num].setroot.new.bump
			for k, v in pairs( frame.conroots ) do
				if k ~= conroot.num then
					v.conroot.setvalue_bump( copy )
				end
			end
		end ):SetIcon( "icon16/bullet_black.png" )

		local mergesub, mergeopt = menu:AddSubMenu("merge into")
		mergeopt:SetIcon("icon16/chart_organisation.png")

		-- Build a list of all other controllers to merge into, excluding the current one
		for k, v in pairs(frame.conroots) do
			if k ~= conroot.num then
				local target = v.conroot
				local label = target.info.name or string.format("controller %d", target.num)

				mergesub:AddOption(label, function()
					local pnl = Derma_Query(string.format("This will IGNORE any unconfirmed changes to all controllers, and match [%s]'s material, color, and other appearance settings.", label), string.format("Merge controller [%s] into [%s]?", conroot.info.name or conroot.num, label), "Yes", function()
						-- discard unconfirmed edits so indices aren't left stale once the merge shifts controllers
						for pk, pv in pairs(frame.updates) do pv.add, pv.mod, pv.set = {}, {}, {} end

						updates.set.mergeinto = target.num

						frame.btnConfirm:DoClick()
					end, "No", function() end)

					pnl.lblTitle:SetFont(editor_font)
					pnl.lblTitle:SetTextColor(color_white)

					local time = SysTime()

					pnl.Paint = function(_, w, h)
						Derma_DrawBackgroundBlur(pnl, time)
						surface.SetDrawColor(theme.colorMain)
						surface.DrawRect(0, 0, w, h)
						surface.SetDrawColor(0, 0, 0)
						surface.DrawOutlinedRect(0, 0, w, h)
					end
				end):SetIcon("icon16/bullet_black.png")
			end
		end

		menu:AddOption("set controller name", function()
			local pnl = Derma_StringRequest(string.format("Set name of controller [%s]?", conroot.info.name or conroot.num), "This will CONFIRM any other changes to all controllers.", conroot.info.name or "", function(text)
				if text == "" or conroot.info.name == text then
					return
				end
				updates.set.name = text
				frame.btnConfirm:DoClick()
			end)

			pnl.lblTitle:SetFont(editor_font)
			pnl.lblTitle:SetTextColor(color_white)

			local time = SysTime()

			pnl.Paint = function(_, w, h)
				Derma_DrawBackgroundBlur(pnl, time)
				surface.SetDrawColor(theme.colorMain)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(0, 0, 0)
				surface.DrawOutlinedRect(0, 0, w, h)
			end
		end):SetIcon("icon16/text_signature.png")

		local sub, opt = menu:AddSubMenu("set controller flags")
		opt:SetIcon("icon16/flag_yellow.png")

		for k, v in SortedPairsByValue({ ["vsmooth"] = "render_flat", ["vinside"] = "render_inside" }) do
			sub:AddSpacer()
			local opt = sub:AddOption("set all " .. v, function()
				setGlobalValue(frame, conroot, updates.mod, k, 1, v)
			end):SetIcon("icon16/flag_blue.png")
			local opt = sub:AddOption("unset all " .. v, function()
				setGlobalValue(frame, conroot, updates.mod, k, 0, v)
			end):SetIcon("icon16/flag_red.png")
		end
	end

	menu:AddSpacer()
	menu:AddOption("export as .obj", function()
		if not CanToolClient( frame.Entity ) then return end
		local pnl = Derma_StringRequest("", string.format("Exporting and saving controller %d as:", conroot.num), "default.txt", function(text)
			local filedata = exportOBJ(prop2mesh.getMeshDirect(conroot.info.crc, conroot.info.uniqueID))
			if filedata then
				local filename = string.lower(string.StripExtension(string.GetFileFromFilename(text)))
				file.Write(string.format("p2m/%s.txt", filename), filedata)
			end
		end)

		local time = SysTime()

		pnl.Paint = function(_, w, h)
			Derma_DrawBackgroundBlur(pnl, time)
			surface.SetDrawColor(theme.colorMain)
			surface.DrawRect(0, 24, w, h - 24)
			surface.SetDrawColor(0, 0, 0)
			surface.DrawOutlinedRect(0, 24, w, h - 24)
		end
	end):SetIcon("icon16/car.png")

	if E2Lib and openE2Editor then
		local opt = menu:AddOption("export to expression2", function()
			if not CanToolClient( frame.Entity ) then return end
			openE2Editor()
			if wire_expression2_editor then
				local e2code = formatE2(conroot)

				wire_expression2_editor:NewTab()
				wire_expression2_editor:SetCode(e2code)
				spawnmenu.ActivateTool("wire_expression2")
			end
		end)
		opt:SetIcon("icon16/cog.png")
		opt.m_Image:SetImageColor(Color(255, 125, 125))
	end

	menu:AddSpacer()
	menu:AddOption("cancel"):SetIcon("icon16/cancel.png")
	menu:Open()
end


--[[

	derma

]]
local PANEL = {}

local function setEntityActual(self, ent)
	self.Entity = ent
	self.Entity:CallOnRemove("prop2mesh_editor_close", function()
		self:Remove()
	end)
	self.lblTitle:SetFont(editor_font)
	self:SetTitle(tostring(self.Entity))
	self:RemakeTree()
end

function PANEL:RequestSetEntity(ent)
	if IsValid(self.Entity) then
		local edited
		for index, updates in pairs(self.updates) do
			for k, v in pairs(updates) do
				if next(v) then
					edited = true
					break
				end
			end
		end
		if edited then
			local pnl = Derma_Query("Unconfirmed changes, are you sure?", "", "Yes", function()
				self.Entity:RemoveCallOnRemove("prop2mesh_editor_close")
				setEntityActual(self, ent)
			end, "No")
			pnl.Paint = function(_, w, h)
				surface.SetDrawColor(theme.colorMain)
				surface.DrawRect(0, 24, w, h - 24)
				surface.SetDrawColor(0, 0, 0)
				surface.DrawOutlinedRect(0, 24, w, h - 24)
			end
			return
		else
			self.Entity:RemoveCallOnRemove("prop2mesh_editor_close")
		end
	end
	setEntityActual(self, ent)
end

function PANEL:CreateGhost()
	self.Ghost = ents.CreateClientside("base_anim")
	self.Ghost:SetNoDraw(true)
	self.Ghost.Draw = function(ent)
		local clips, prev = ent.clips, nil
		if clips then
			prev = render.EnableClipping(true)

			local pos = ent:GetPos()
			local ang = ent:GetAngles()

			for i = 1, #clips do
				local clip = clips[i]
				local norm = Vector(unpack(clip.n))
				norm:Rotate(ang)

				render.PushCustomClipPlane(norm, norm:Dot(pos + norm * clip.d))
			end
		end

		render.ModelMaterialOverride(wireframe)
		cam.IgnoreZ(true)
		ent:DrawModel()
		cam.IgnoreZ(false)
		render.ModelMaterialOverride(nil)

		if clips then
			for _ = 1, #clips do
				render.PopCustomClipPlane()
			end
			render.EnableClipping(prev)
		end
	end

	self.Ghost:Spawn()
end

function PANEL:PerformLayout()
	local titlePush = 0
	if IsValid(self.imgIcon) then
		self.imgIcon:SetPos(5, 5)
		self.imgIcon:SetSize(16, 16)
		titlePush = 16
	end

	local w, h = self:GetSize()

	self.btnExit:SetPos(w - 51, 4)
	self.btnExit:SetSize(45, 22)

	self.btnWiki:SetPos(w - 77, 4)
	self.btnWiki:SetSize(24, 22)

	self.btnTools:SetPos(w - 103, 4)
	self.btnTools:SetSize(24, 22)

	self.lblTitle:SetPos(8 + titlePush, 6)
	self.lblTitle:SetSize(w - 25 - titlePush, 20)
end

function PANEL:Init()
	self.btnClose:Remove()
	self.btnMinim:Remove()
	self.btnMaxim:Remove()

	self.btnExit = vgui.Create("DButton", self)
	self.btnExit:SetText("r")
	self.btnExit:SetFont("Marlett")
	self.btnExit.DoClick = function(button)
		self:Close()
	end

	self.btnWiki = vgui.Create("DButton", self)
	self.btnWiki:SetTooltip("Open wiki")
	self.btnWiki:SetText("")
	self.btnWiki:SetImage("icon16/help.png")
	self.btnWiki.DoClick = function (button)
		gui.OpenURL("https://github.com/shadowscion/Prop2Mesh/wiki")
	end
	self.btnWiki.Paint = function(panel, w, h)
		if not (panel:IsHovered() or panel:IsDown()) then return end
		derma.SkinHook("Paint", "Button", panel, w, h)
	end

	self.btnTools = vgui.Create("DButton", self)
	self.btnTools:SetText("")
	self.btnTools:SetImage("icon16/wrench.png")
	self.btnTools.DoClick = function (button)
		local menu = DermaMenu()

		-- local sub, opt = menu:AddSubMenu("pac3")
		-- opt:SetIcon("icon16/layout.png")

		-- sub:AddOption("import new", function()
		-- end):SetIcon("icon16/layout_add.png")

		-- sub:AddOption("import and merge", function()
		-- end):SetIcon("icon16/layout_edit.png")

		-- sub:AddOption("export all", function()
		-- end):SetIcon("icon16/layout_delete.png")

		local opt = menu:AddOption("Export all as .obj", function()
			if not CanToolClient( self.Entity ) then return end
			batchExportObj({[self.Entity] = true})
		end)
		opt:SetIcon("icon16/car.png")

		local opt = menu:AddOption("Export all to E2", function()
			if not CanToolClient( self.Entity ) then return end
			batchFormatE2({[self.Entity] = true})
		end)
		opt:SetIcon("icon16/cog.png")
		opt.m_Image:SetImageColor(Color(255, 125, 125))

		menu:AddSpacer()
		menu:AddOption("cancel"):SetIcon("icon16/cancel.png")

		menu:Open()
	end
	self.btnTools.Paint = function(panel, w, h)
		if not (panel:IsHovered() or panel:IsDown()) then return end
		derma.SkinHook("Paint", "Button", panel, w, h)
	end

	self:CreateGhost()

	self.updates = {}

	self.contree = vgui.Create("DTree", self)
	self.contree:Dock(FILL)
	self.contree.AddNode = TreeAddNode
	self.contree:SetClickOnDragHover(true)
	self.contree.DoRightClick = function(pnl, node)
		if node.menu then node.menu(self, node) end
	end
	self.contree.Paint = function(pnl, w, h)
		surface.SetDrawColor(theme.colorTree)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
	self.contree:DockMargin(1, 1, 1, 1)

	self.btnConfirm = vgui.Create("DButton", self)
	self.btnConfirm:Dock(BOTTOM)
	self.btnConfirm:DockMargin(0, 2, 0, 0)
	self.btnConfirm:SetFont(editor_font)
	self.btnConfirm:SetText("Confirm changes")
	self.btnConfirm.DoClick = function()
		if not IsValid(self.Entity) then
			return false
		end

		if self.filebrowser then
			self.filebrowser:Remove()
		end

		local set = {}
		local add = {}
		local mod = {}

		for k, v in pairs(self.updates) do
			if next(v.set) then
				if not set[k] then
					set[k] = {}
				end
				for i, j in pairs(v.set) do
					set[k][i] = j
				end
				if not next(set[k]) then
					set[k] = nil
				end
			end
			if next(v.add) then
				if not add[k] then
					add[k] = {}
				end
				for i in pairs(v.add) do
					if IsValid(i) then
						add[k][#add[k] + 1] = i.new
					end
				end
				if not next(add[k]) then
					add[k] = nil
				end
			end
			if next(v.mod) then
				if not mod[k] then
					mod[k] = {}
				end
				for i, j in pairs(v.mod) do
					mod[k][i] = j.kill and { kill = true } or j
				end
			end
		end

		if next(set) or next(add) or next(mod) then
			net.Start("prop2mesh_upload_start")
			net.WriteUInt(self.Entity:EntIndex(), 16)
			for k, v in ipairs({set, add, mod}) do
				if next(v) then
					net.WriteBool(true)
					net.WriteTable(v)
				else
					net.WriteBool(false)
				end
			end
			net.SendToServer()
		end
	end
	self.btnConfirm:DockMargin(1, 1, 1, 1)

	self.progress = vgui.Create("DPanel", self)
	self.progress:Dock(BOTTOM)
	self.progress:DockMargin(1, 1, 1, 1)
	self.progress:SetTall(16)

	local disabled = GetConVar("prop2mesh_disable")
	self.progress.Paint = function(pnl, w, h)
		surface.SetDrawColor(theme.colorTree)
		surface.DrawRect(0, 0, w, h)

		if pnl.frac then
			if disabled:GetBool() then
				surface.SetDrawColor(255, 0, 0)
				surface.DrawRect(0, 0, w*0.25, h)
				draw.SimpleText("prop2mesh is disabled...", editor_font, w*0.5, h*0.5, theme.colorText_kill, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			else
				surface.SetDrawColor(0, 255, 0)
				surface.DrawRect(0, 0, pnl.frac*w, h)
				if pnl.text then
					draw.SimpleText(pnl.text, editor_font, w*0.5, h*0.5, theme.colorText_default, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end
		end

		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
end

--[[
function PANEL:AddSearchBar()
	self.searchbar = vgui.Create("DPanel", self)
	self.searchbar:Dock(BOTTOM)
	self.searchbar:DockMargin(1, 1, 1, 1)
	self.searchbar:SetTall( 24 )

	self.searchbar.Paint = function(pnl, w, h)
		surface.SetDrawColor(theme.colorTree)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end

	local text = vgui.Create("DTextEntry", self.searchbar)
	self.searchbar.textentry = text

	local btn1 = vgui.Create("DButton", self.searchbar)
	btn1:SetText("Find Next")
	btn1:SetTall( 20 )

	local btn2 = vgui.Create("DButton", self.searchbar)
	btn2:SetText("Find Prev")
	btn2:SetTall( 20 )

	self.searchbar.PerformLayout = function(pnl, w, h)
		text:SetWide( w * 0.5 )
		text:SetPos( 2, 2 )

		local rw = w * 0.5 - 6

		btn1:SetPos( w * 0.5 + 4, 2 )
		btn1:SetWide( rw / 2 )

		btn2:SetPos( w * 0.5 + 6 + rw / 2, 2 )
		btn2:SetWide( rw / 2 )
	end
end
]]

function PANEL:Paint(w, h)
	surface.SetDrawColor(theme.colorMain)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(0, 0, 0)
	surface.DrawOutlinedRect(0, 0, w, h)
end

function PANEL:OnRemove()
	if IsValid(self.Entity) then
		self.Entity:RemoveCallOnRemove("prop2mesh_editor_close")
		self.Entity.prop2mesh_triggereditor = nil
	end
	if IsValid(self.Ghost) then
		self.Ghost:Remove()
		self.Ghost.GetRenderMesh = nil
		if self.Ghost.RenderMesh then
			self.Ghost.RenderMesh:Destroy()
			self.Ghost.RenderMesh = nil
		end
	end
end

function PANEL:Think()
	if not IsValid(self.Entity) then
		return
	end

	if self.Entity:GetNetworkedBool("uploading", false) then
		if not self.disable or not self.contree:GetDisabled() then
			self.disable = true
			self.contree:SetDisabled(true)
			self.btnConfirm:SetDisabled(true)
		end
		self.progress.frac = upstreamProgress()
		self.progress.text = "uploading data..."
	else
		if self.disable or self.contree:GetDisabled() then
			local ready, status = self.Entity:GetAllDataReady()
			if ready then
				self.progress.frac = nil
				self.disable = nil
				self.contree:SetDisabled(false)
				self.btnConfirm:SetDisabled(false)
				self:RemakeTree()
			elseif status == 1 then -- no data
				self.progress.frac = 1
				self.progress.text = "downloading data..."
			elseif status == 2 then -- data but no meshes
				self.progress.frac = 1
				self.progress.text = "generating mesh..."
			end
		elseif self.Entity.prop2mesh_triggereditor then
			self.Entity.prop2mesh_triggereditor = nil
			self:RemakeTree()
		end
	end
end

local function onPartHover(label)
	local self = prop2mesh.editor
	if not self then
		return
	end

	local partnode = label:GetParent()
	if self.contree:GetSelectedItem() ~= partnode then
		CloseDermaMenus()

		self.contree:SetSelectedItem(partnode)

		if partnode.new then

			if partnode.new.holo or partnode.new.prop then
				self.Ghost.GetRenderMesh = nil
				if self.Ghost.RenderMesh then
					self.Ghost.RenderMesh:Destroy()
					self.Ghost.RenderMesh = nil
				end

				if self.Ghost.lastSubmodels then
					for k in pairs(self.Ghost.lastSubmodels) do
						self.Ghost:SetSubMaterial(k - 1, nil)
					end
					self.Ghost.lastSubmodels = nil
				end

				self.Ghost:SetNoDraw(false)
				self.Ghost:SetModel(partnode.new.holo or partnode.new.prop)
				self.Ghost:SetRenderBounds(self.Ghost:GetModelBounds())

				local scale = partnode:GetParentNode().conscale or Vector(1,1,1)

				local pos, ang = LocalToWorld(Vector(unpack(partnode.new.pos))*scale, Angle(unpack(partnode.new.ang)), self.Entity:GetPos(), self.Entity:GetAngles())

				self.Ghost:SetParent(self.Entity)
				self.Ghost:SetPos(pos)
				self.Ghost:SetAngles(ang)

				if partnode.new.submodels then
					self.Ghost.lastSubmodels = {}
					for k, v in pairs(partnode.new.submodels) do
						if v == 1 then
							self.Ghost.lastSubmodels[k] = true
							self.Ghost:SetSubMaterial(k - 1, "Models/effects/vol_light001")
						end
					end
				end

				if partnode.new.clips and #partnode.new.clips > 0 then
					self.Ghost.clips = partnode.new.clips
				else
					self.Ghost.clips = nil
				end

				if partnode.new.scale then
					local matrix = Matrix()
					matrix:SetScale(Vector(unpack(partnode.new.scale))*scale)
					self.Ghost:EnableMatrix("RenderMultiply", matrix)
				else
					self.Ghost:DisableMatrix("RenderMultiply")
				end

			elseif partnode.new.primitive and prop2mesh.primitive then
				self.Ghost.GetRenderMesh = nil
				if self.Ghost.RenderMesh then
					self.Ghost.RenderMesh:Destroy()
					self.Ghost.RenderMesh = nil
				end

				if self.Ghost.lastSubmodels then
					for k in pairs(self.Ghost.lastSubmodels) do
						self.Ghost:SetSubMaterial(k - 1, nil)
					end
					self.Ghost.lastSubmodels = nil
				end

				self.Ghost:SetNoDraw(false)
				self.Ghost:SetModel("models/Combine_Helicopter/helicopter_bomb01.mdl")

				local _, submeshes = prop2mesh.primitive.construct.get(partnode.new.primitive.construct, partnode.new.primitive, false, false)

				if submeshes and submeshes.tris then
					self.Ghost:SetRenderBounds(submeshes.mins, submeshes.maxs)

					self.Ghost.RenderMesh = Mesh()
					self.Ghost.RenderMesh:BuildFromTriangles(submeshes.tris)

					self.Ghost.GetRenderMesh = function(e)
						return { Mesh = self.Ghost.RenderMesh, Material = wireframe }
					end
				end

				local scale = partnode:GetParentNode().conscale or Vector(1,1,1)

				local pos, ang = LocalToWorld(Vector(unpack(partnode.new.pos))*scale, Angle(unpack(partnode.new.ang)), self.Entity:GetPos(), self.Entity:GetAngles())

				self.Ghost:SetParent(self.Entity)
				self.Ghost:SetPos(pos)
				self.Ghost:SetAngles(ang)

				if partnode.new.clips and #partnode.new.clips > 0 then
					self.Ghost.clips = partnode.new.clips
				else
					self.Ghost.clips = nil
				end

				if partnode.new.scale then
					local matrix = Matrix()
					matrix:SetScale(Vector(unpack(partnode.new.scale))*scale)
					self.Ghost:EnableMatrix("RenderMultiply", matrix)
				else
					self.Ghost:DisableMatrix("RenderMultiply")
				end
			else
				self.Ghost:SetNoDraw(true)
			end

		else
			self.Ghost:SetNoDraw(true)
		end

		label:InvalidateLayout(true)
	end
end

function PANEL:RemakeTree()
	if IsValid(self.Ghost) then
		self.Ghost:SetNoDraw(true)
	end

	self.contree:Clear()
	self.updates = {}
	self.conroots = {}

	for i = 1, #self.Entity.prop2mesh_controllers do
		self.updates[i] = { mod = {}, add = {}, set = {} }

		local info = self.Entity.prop2mesh_controllers[i]
		local condata = prop2mesh.getMeshData(info.crc, true) or {}
		local conroot = self.contree:AddNode(string.format("controller [%s] [%d]", info.name or i, #condata), "icon16/controller.png")

		conroot.num = i
		conroot.info = info
		conroot.menu = conmenu
		conroot.count = #condata
		conroot.Label.OnCursorEntered = onPartHover

		local setroot = conroot:AddNode("settings", "icon16/cog.png")

		self.conroots[i] = { conroot = conroot, setroot = setroot }

		setroot.set = self.updates[i].set

		local setscale = info.scale
		local setcol = info.col
		local setpos = info.linkpos or Vector()
		local setang = info.linkang or Angle()
		setroot.old = { col = {r=setcol.r,g=setcol.g,b=setcol.b,a=setcol.a}, mat = info.mat, uvs = info.uvs, bump = info.bump and 1 or 0, uniqueID = info.uniqueID,
			scale = {setscale.x,setscale.y,setscale.z}, linkpos = {setpos.x,setpos.y,setpos.z}, linkang = {setang.p,setang.y,setang.r} }
		setroot.new = { col = {r=setcol.r,g=setcol.g,b=setcol.b,a=setcol.a}, mat = info.mat, uvs = info.uvs, bump = info.bump and 1 or 0, uniqueID = info.uniqueID,
			scale = {setscale.x,setscale.y,setscale.z}, linkpos = {setpos.x,setpos.y,setpos.z}, linkang = {setang.p,setang.y,setang.r} }

		conroot.setvalue_linkpos = registerVector(setroot, "pos offset", "linkpos")
		conroot.setvalue_linkang = registerVector(setroot, "ang offset", "linkang")
		conroot.setvalue_scale = registerVector(setroot, "scale", "scale")
		conroot.setvalue_mat = registerString(setroot, "material", "mat")
		conroot.setvalue_col = registerColor(setroot, "color", "col")
		conroot.setvalue_uvs = registerFloat(setroot, "texture map size", "uvs", 0, 512)
		conroot.setvalue_bump = registerBoolean(setroot, "enable bumpmap", "bump")

		setroot:ExpandRecurse(true)

		local objroot = conroot:AddNode(".obj", "icon16/pictures.png")

		local import = objroot:AddNode("")
		import.ShowIcons = HideIcons

		local btnImport = vgui.Create("DButton", import)
		btnImport:SetFont(editor_font)
		btnImport:SetText("Open file browser")
		btnImport:SizeToContents()
		btnImport:Dock(LEFT)
		btnImport:DockMargin(24, 0, 4, 0)

		local objlist = objroot:AddNode("attachments", "icon16/bullet_picture.png")
		local mdllist = conroot:AddNode(".mdl", "icon16/images.png")

		objlist.add = self.updates[i].add
		btnImport.DoClick = function(panel)
			if self.filebrowser then
				self.filebrowser:Remove()
			end
			self.filebrowser = self:OpenFileBrowser("Attach obj file", "p2m", {"*.txt", "*.obj"}, objlist, objfilemenu)
		end

		objlist.conscale = setscale
		mdllist.conscale = setscale

		local realdata = {}
		for k, v in ipairs(condata) do
			local name = v.prop or v.holo or v.objn or v.objd or (v.primitive and "primitive_" .. v.primitive.construct)
			v.nicename = string.GetFileFromFilename(name)
			if v.prop then
				v.nicetype = "prop"
			elseif v.holo then
				v.nicetype = "holo"
			elseif v.primitive then
				v.nicetype = "primitive"
			elseif v.objd or v.objn then
				v.nicetype = "obj"
			end
			realdata[k] = v
		end

		local fakeid = 0
		for k, v in SortedPairsByMemberValue( realdata, "nicename" ) do
			if not istable( v ) or not v.nicename or k == "custom" then goto SKIP end

			fakeid = fakeid + 1

			local root = v.objd and objlist or mdllist
			local part = root:AddNode(string.format("[%d] %s", fakeid, v.nicename))
			part:SetIcon("icon16/brick.png")

			part.fullname = v.prop or v.holo
			part.nicetype = v.nicetype
			part.Label.OnCursorEntered = onPartHover
			part.menu = partmenu
			part.new, part.old = partcopy(v)
			part.mod = self.updates[i].mod
			part.num = k

			part.Label:SetToolTip(string.format("index: %d\ntype: %s\npath: %s", part.num, part.nicetype, part.fullname))

			::SKIP::
		end
	end
end

function PANEL:OpenFileBrowser(title, folder, wildcards, attachmentNode, menuCallback)
	local frame = vgui.Create("DFrame", self)

	frame.lblTitle:SetFont(editor_font)
	frame:SetTitle(title)
	frame:SetSize(self:GetWide()*0.75, self:GetTall()*0.5)
	frame:Center()

	frame.btnClose:Remove()
	frame.btnMinim:Remove()
	frame.btnMaxim:Remove()

	frame.Paint = function(pnl, w, h)
		surface.SetDrawColor(theme.colorMain)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end

	frame.PerformLayout = function(pnl)
		local w, h = pnl:GetSize()

		pnl.btnExit:SetPos(w - 51, 4)
		pnl.btnExit:SetSize(45, 22)

		pnl.lblTitle:SetPos(8, 6)
		pnl.lblTitle:SetSize(w - 25, 20)
	end

	frame.btnExit = vgui.Create("DButton", frame)
	frame.btnExit:SetText("r")
	frame.btnExit:SetFont("Marlett")
	frame.btnExit.DoClick = function(button)
		frame:Close()
	end

	local tree = vgui.Create("DTree", frame)

	tree:SetClickOnDragHover(true)
	tree:Dock(FILL)
	tree:DockMargin(1, 1, 1, 1)

	tree.AddNode = TreeAddNode
	tree.DoRightClick = function(pnl, node)
		if node.menu then node.menu(self, node) end
	end

	tree.Paint = function(pnl, w, h)
		surface.SetDrawColor(theme.colorTree)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(0, 0, 0)
		surface.DrawOutlinedRect(0, 0, w, h)
	end

	local populate, root_folder
	populate = function(node, root, filter, callback)
		local node_folder = node:AddNode(root)
		if not root_folder then
			root_folder = node_folder
		end
		local files, folders = file.Find(string.format("%s/*", root), "DATA")
		for k, v in pairs(folders) do
			populate(node_folder, string.format("%s/%s", root, v), filter, callback)
		end
		for k, v in ipairs(filter) do
			for _, filename in pairs(file.Find(string.format("%s/%s", root, v), "DATA")) do
				local node_file = node_folder:AddNode(filename, "icon16/page_white_text.png")
				node_file.list = attachmentNode
				node_file.menu = menuCallback
				node_file.path = string.format("%s/%s", root, filename)
				node_file.Label.OnCursorEntered = onPartHover
			end
		end
	end

	populate(tree, folder, wildcards)

	root_folder:ExpandTo(true)

	return frame
end

vgui.Register("prop2mesh_editor", PANEL, "DFrame")
