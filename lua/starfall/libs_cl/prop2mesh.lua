
local CheckLuaType, CheckPerms, RegisterPrivilege = SF.CheckLuaType, SF.Permissions.check, SF.Permissions.registerPrivilege
local prop2mesh = prop2mesh

local function checkOwner( ply, ent )
    if CPPI then
        local owner = ent:CPPIGetOwner() or ( ent.GetPlayer and ent:GetPlayer() )
        if owner then
            return owner == ply
        end
    end

    return true
end

local function checkValid( ply, self, action, index )
    if not checkOwner( ply, self ) or not prop2mesh.isValid( self ) then
        return false
    end
    if index and not self.prop2mesh_controllers[index] then
        SF.Throw( string.format( "controller index %d does not exist on %s!", index, tostring( self) ), 3 )
        return false
    end
    return true
end

return function( instance )
    local CheckType = instance.CheckType
    local p2m_library = instance.Libraries.p2m
    local owrap, ounwrap = instance.WrapObject, instance.UnwrapObject
    local ents_methods, wrap, unwrap = instance.Types.Entity.Methods, instance.Types.Entity.Wrap, instance.Types.Entity.Unwrap
    local ang_meta, awrap, aunwrap = instance.Types.Angle, instance.Types.Angle.Wrap, instance.Types.Angle.Unwrap
    local vec_meta, vwrap, vunwrap = instance.Types.Vector, instance.Types.Vector.Wrap, instance.Types.Vector.Unwrap
    local col_meta, cwrap, cunwrap = instance.Types.Color, instance.Types.Color.Wrap, instance.Types.Color.Unwrap
    local checkpermission = instance.player ~= SF.Superuser and SF.Permissions.check or function() end

    local recycle = prop2mesh.recycle


    local function getControllerInfo(ent, index)
        CheckLuaType(index, TYPE_NUMBER)

        local controllers = ent.prop2mesh_controllers
        if not controllers then
            SF.Throw("This function is limited to sf controllers!", 3)
            return false
        end

        local info = controllers[index]
        if not info then
            SF.Throw(string.format("controller index %d does not exist on %s!", index, tostring(ent)), 3)
            return false
        end

        return info
    end


    --- Manually sets controller info from a table clientside. It's important to note that this does not set the controller info serverside, so any modifications made to this P2M, dupe copying, etc. will not copy the inputted info
    -- @param number index index of controller
    -- @param table controllerData controller table to insert
    function ents_methods:p2mSetControllerInfo(index, controllerData)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)

        CheckLuaType(index, TYPE_NUMBER)
        if not checkValid(instance.player, ent, nil, index, true) then
            return
        end

        CheckLuaType(controllerData, TYPE_TABLE)
        controllerData = instance.Unsanitize(controllerData)

        local controller = ent.prop2mesh_controllers[index]
        local controllerDataComp = util.Compress(util.TableToJSON(controllerData))
        local dataCRC = util.CRC(controllerDataComp)
        controller.crc = dataCRC

        recycle[dataCRC] = { users = {[ent] = true}, meshes = {} }
        prop2mesh.handleDownload(dataCRC, controllerDataComp)
        prop2mesh.refresh(ent, controller)
    end

    function ents_methods:p2mGetCount()
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        local controllers = ent.prop2mesh_controllers
        if not controllers then SF.Throw("This function is limited to sf controllers!", 2) end

        return #controllers
    end

    function ents_methods:p2mSetColor(index, color)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        if not getControllerInfo(ent, index) then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        ent:SetControllerCol(index, cunwrap(color))
    end

    function ents_methods:p2mGetColor(index)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)

        return cwrap(getControllerInfo(ent, index).col)
    end

    function ents_methods:p2mSetAlpha(index, alpha)
        CheckType(self, ents_metatable)
        CheckLuaType(alpha, TYPE_NUMBER)
        local ent = unwrap(self)
        local info = getControllerInfo(ent, index)
        if not info then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        info.col.a = alpha
        ent:SetControllerCol(index, info.col)
    end

    function ents_methods:p2mSetPos(index, pos)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        if not getControllerInfo(ent, index) then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        ent:SetControllerPos(index, vunwrap(pos))
    end

    function ents_methods:p2mGetPos(index)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        local info = getControllerInfo(ent, index)
        if not info then return end

        return vwrap(info.linkpos or Vector())
    end

    function ents_methods:p2mSetAng(index, ang)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        if not getControllerInfo(ent, index) then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        ent:SetControllerAng(index, aunwrap(ang))
    end

    function ents_methods:p2mGetAng(index)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        local info = getControllerInfo(ent, index)
        if not info then return end

        return awrap(info.linkang or Angle())
    end

    function ents_methods:p2mSetMaterial(index, mat)
        CheckType(self, ents_metatable)
        CheckLuaType(mat, TYPE_STRING)
        local ent = unwrap(self)
        if not getControllerInfo(ent, index) then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        ent:SetControllerMat(index, mat)
    end

    function ents_methods:p2mGetMaterial(index)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)

        return getControllerInfo(ent, index).mat
    end

    function ents_methods:p2mSetScale(index, scale)
        CheckType(self, ents_metatable)
        local ent = unwrap(self)
        if not getControllerInfo(ent, index) then return end
        checkpermission(instance, ent, "entities.setRenderProperty")

        ent:SetControllerScale(index, vunwrap(scale))
    end
end
