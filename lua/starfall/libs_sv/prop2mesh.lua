
local CheckLuaType, CheckPerms, RegisterPrivilege = SF.CheckLuaType, SF.Permissions.check, SF.Permissions.registerPrivilege
local prop2mesh = prop2mesh

list.Set("starfall_creatable_sent", "sent_prop2mesh", {{
    ["Model"] = {TYPE_STRING, "models/hunter/plates/plate.mdl"}
}})

local function p2mOnDestroy( p2m, p2mdata, ply )
    p2mdata[p2m] = nil
end

local _COL    = -1
local _MAT    = -2
local _POS    = -3
local _ANG    = -4
local _SCALE  = -5
local _UVS    = -6
local _PARENT = -7
local _MODEL  = -8
local _NODRAW = -9
local _BUILD  = -10
local _ALPHA  = -11
local _LINK   = -12
local _BUMP   = -13

local cooldowns = {}
cooldowns[_BUILD] = 10
cooldowns[_UVS] = 10
cooldowns[_BUMP] = 10

local errors = {}
errors[_BUILD] = "Don't spam p2m:build"
errors[_UVS] = "Don't spam p2m:setUV"
errors[_BUMP] = "Don't spam p2m:setBump"

local function canspam( check, wait, time )
    if not check or time - check > wait then
        return true
    end
    return false
end

local function antispam( self, action, index )
    if not self.prop2mesh_sf_antispam then
        self.prop2mesh_sf_antispam = {}
    end

    local time = CurTime()
    local wait = cooldowns[action]

    if not index then
        if self.prop2mesh_sf_antispam[action] == time then
            return false
        end
        if not wait or ( wait and canspam( self.prop2mesh_sf_antispam[action], wait, time ) ) then
            self.prop2mesh_sf_antispam[action] = time
            return true
        end
        SF.Throw( errors[action], 3 )
        return false
    else
        if not self.prop2mesh_sf_antispam[index] then
            self.prop2mesh_sf_antispam[index] = {}
        end
        if self.prop2mesh_sf_antispam[index][action] == time then
            return false
        end
        if not wait or ( wait and canspam( self.prop2mesh_sf_antispam[index][action], wait, time ) ) then
            self.prop2mesh_sf_antispam[index][action] = time
            return true
        end
        SF.Throw( errors[action], 3 )
        return false
    end
end

local function checkOwner( ply, ent )
    if CPPI then
        local owner = ent:CPPIGetOwner() or ( ent.GetPlayer and ent:GetPlayer() )
        if owner then
            return owner == ply
        end
    end

    return true
end

local function checkValid( ply, self, action, index, restricted )
    if not checkOwner( ply, self ) or not prop2mesh.isValid( self ) then
        return false
    end
    if restricted and not self.prop2mesh_sf_resevoir then
        SF.Throw( "This function is limited to sf controllers!", 3 )
        return false
    end
    if index and not self.prop2mesh_controllers[index] then
        SF.Throw( string.format( "controller index %d does not exist on %s!", index, tostring( self) ), 3 )
        return false
    end
    if action then
        return antispam( self, action, index )
    end
    return true
end

local function errorcheck( self, index )
    if not self.prop2mesh_controllers[index] then
        SF.Throw( string.format( "controller index %d does not exist on %s!", index, tostring( self ) ), 3 )
    end
    if not self.prop2mesh_sf_resevoir[index] then
        self.prop2mesh_sf_resevoir[index] = {}
    end
    if #self.prop2mesh_sf_resevoir[index] + 1 > 500 then
        SF.Throw( "model limit is 500 per controller", 3 )
    end
end

local function toVec( vec )
    return vec and Vector( vec[1], vec[2], vec[3] ) or Vector()
end

local function toAng( ang )
    return ang and Angle( ang[1], ang[2], ang[3] ) or Angle()
end

local function isVector( op0 )
    return type( op0 ) == "Vector"
end

--- Library for creating and manipulating prop2mesh entities.
-- @name p2m
-- @class library
-- @libtbl p2m_library
SF.RegisterLibrary( "p2m" )


return function( instance )

    local CheckType = instance.CheckType
    local p2m_library = instance.Libraries.p2m
    local owrap, ounwrap = instance.WrapObject, instance.UnwrapObject
    local ents_methods, wrap, unwrap = instance.Types.Entity.Methods, instance.Types.Entity.Wrap, instance.Types.Entity.Unwrap
    local ang_meta, awrap, aunwrap = instance.Types.Angle, instance.Types.Angle.Wrap, instance.Types.Angle.Unwrap
    local vec_meta, vwrap, vunwrap = instance.Types.Vector, instance.Types.Vector.Wrap, instance.Types.Vector.Unwrap
    local col_meta, cwrap, cunwrap = instance.Types.Color, instance.Types.Color.Wrap, instance.Types.Color.Unwrap

    instance:AddHook( "initialize", function()
        instance.data.p2ms = { p2ms = {} }
    end)

    instance:AddHook( "deinitialize", function()
        local p2ms = instance.data.p2ms.p2ms

        for p2m, _ in pairs( p2ms ) do
            if p2m:IsValid() then
                p2m:RemoveCallOnRemove( "starfall_p2m_delete" )
                p2mOnDestroy( p2m, p2ms, instance.player )
                p2m:Remove()
            end
        end
    end)

    local function checkClips(clips)
        if #clips == 0 or #clips % 2 ~= 0 then
            return
        end

        local swap = {}
        for i = 1, #clips, 2 do
            local op1 = vunwrap( clips[i] )
            local op2 = vunwrap( clips[i + 1] )

            if not isVector( op1 ) or not isVector( op2 ) then
                goto CONTINUE
            end

            local normal = op2
            normal:Normalize()

            swap[#swap + 1] = { d = op1:Dot( normal ), n = normal }

            ::CONTINUE::
        end

        return swap
    end

    local function checkSubmodels( submodels )
        if #submodels == 0 then
            return
        end

        local swap = {}
        for i = 1, #submodels do
            local n = isnumber( submodels[i] ) and math.floor( math.abs( submodels[i] ) )
            if n > 0 then
                swap[n] = 1
            end
        end

        return next( swap ) and swap
    end

    local MAX_CONTROLLERS = 64

    --- Creates a p2m controller.
    -- @param number count Number of controllers
    -- @param Vector pos The position to create the p2m ent
    -- @param Angle ang The angle to create the p2m ent
    -- @param number? uvs The uvscale to give the p2m controllers
    -- @param Vector? scale The meshscale to give the p2m controllers
    -- @param boolean? bump Enable bumpmaps on the p2m controllers
    -- @return The p2m ent
    function p2m_library.create( count, pos, ang, uvs, scale, bump )
        CheckLuaType( count, TYPE_NUMBER )

        local count = math.abs( math.ceil( count or 1 ) )
        if count > MAX_CONTROLLERS then
            SF.Throw( "controller limit is " .. MAX_CONTROLLERS .. " per entity", 3 )
        end

        local pos = vunwrap( pos )
        local ang = aunwrap( ang )
        local ply = instance.player
        local p2mdata = instance.data.p2ms.p2ms

        if not ply:CheckLimit( "prop2mesh" ) then return end

        local ent = ents.Create( "sent_prop2mesh" )

        ent:SetNoDraw( true )
        ent:SetModel( "models/hunter/plates/plate.mdl" )
        ent:SetPos( SF.clampPos( pos ) )
        ent:SetAngles( ang )
        ent:Spawn()

        if not IsValid( ent ) then
            return NULL
        end

        if CPPI then
            ent:CPPISetOwner( ply )
        end

        if ply.AddCleanup then ply:AddCleanup( "sent_prop2mesh", ent ) end
        if ply.AddCount then ply:AddCount( "prop2mesh", ent ) end

        ent:SetPlayer( ply )
        ent:SetSolid( SOLID_NONE )
        ent:SetMoveType( MOVETYPE_NONE )
        ent:DrawShadow( false )
        ent:Activate()

        ent:CallOnRemove( "starfall_p2m_delete", p2mOnDestroy, p2mdata, ply )

        ent.DoNotDuplicate = true
        ent.prop2mesh_sf_resevoir = {}

        if uvs ~= nil then
            CheckLuaType( uvs, TYPE_NUMBER )
            uvs = math.Clamp( math.floor( math.abs( uvs ) ), 0, 512 )
        end
        if scale ~= nil then
            scale = vunwrap( scale )
            CheckLuaType( scale, TYPE_VECTOR )
        end
        if bump ~= nil then
            CheckLuaType( bump, TYPE_BOOL )
        end

        for i = 1, count do
            ent:AddController()
            if uvs then
                ent:SetControllerUVS( i, uvs )
            end
            if scale then
                ent:SetControllerScale( i, scale )
            end
            if bump then
                ent:SetControllerBump( i, bump )
            end
        end

        p2mdata[ent] = true

        if ply ~= SF.Superuser then gamemode.Call( "PlayerSpawnedSENT", ply, ent ) end

        return wrap( ent )
    end

    --- Creates controllers on a P2M entity.
    -- @param number count Number of controllers
    function ents_methods:p2mAddControllers( count )
        CheckLuaType( count, TYPE_NUMBER )

        local ent = unwrap( self )
        if not checkValid( instance.player, ent, nil, nil, false ) then
            return
        end

        local count = math.abs( math.ceil( count or 1 ) ) - (ent.prop2mesh_controllers and #ent.prop2mesh_controllers or 0)
        if count > MAX_CONTROLLERS then
            SF.Throw( "controller limit is " .. MAX_CONTROLLERS .. " per entity", 3 )
        end

        for i = 1, count do
            ent:AddController()
        end
    end

    --- Adds a model to the build stack.
    -- @param number index index of controller
    -- @param string model model to add
    -- @param Vector pos local pos offset
    -- @param Angle ang local ang offset
    -- @param Vector? scale model scale
    -- @param table? clips table of alternating clip origins and clip normals
    -- @param boolean? render_inside
    -- @param boolean? render_flat use flat normal shading
    -- @param table? submodels ignore submodels
    -- @param boolean? submodelswl submodels as whitelist
    function ents_methods:p2mPushModel( index, model, pos, ang, scale, clips, vinside, vsmooth, bodygroup, submodels, submodelswl )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, nil, index, true ) then
            return
        end

        errorcheck( ent, index )

        CheckLuaType( model, TYPE_STRING )

        local pos = vunwrap( pos )
        local ang = aunwrap( ang )

        if scale then
            scale = vunwrap( scale )
            if scale.x == 1 and scale.y == 1 and scale.z == 1 then
                scale = nil
            end
        end

        if clips then
            CheckLuaType( clips, TYPE_TABLE )
            clips = checkClips( clips )
        end

        if submodels then submodels = checkSubmodels( submodels ) end

        if bodygroup then
            bodygroup = math.floor( math.abs( bodygroup ) )
            if bodygroup == 0 then
                bodygroup = nil
            end
        end

        ent.prop2mesh_sf_resevoir[index][#ent.prop2mesh_sf_resevoir[index] + 1] = {
            prop = model,
            pos = pos,
            ang = ang,
            scale = scale,
            clips = clips,
            vinside = tobool( vinside ) and 1 or nil,
            vsmooth = tobool( vsmooth ) and 1 or nil,
            bodygroup = bodygroup,
            submodels = submodels,
            submodelswl = tobool( submodelswl ) and 1 or nil,
        }
    end

    --- Build the model stack.
    function ents_methods:p2mBuild()
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        if not checkValid( instance.player, ent, _BUILD, nil, true ) then
            return
        end

        for k, v in pairs( ent.prop2mesh_sf_resevoir ) do
            if ent.prop2mesh_controllers[k] then
                ent:SetControllerData( k, v )
            end
        end

        ent.prop2mesh_sf_resevoir = {}
    end

    --- Gets the number of prop2mesh controllers
    -- @shared
    -- @return number count
    function ents_methods:p2mGetCount()
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        if not checkValid( instance.player, ent, nil, nil, nil ) then
            return 0
        end

        return ent.prop2mesh_controllers and #ent.prop2mesh_controllers or 0
    end

    --- Gets the color of the controller
    -- @shared
    -- @param number index
    -- @return Color the color
    function ents_methods:p2mGetColor( index )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, nil, index, nil ) then
            return cwrap( Color( 255,255,255,255 ) )
        end

        return cwrap( ent:GetControllerCol( index ) )
    end

    --- Sets the local position of the controller
    -- @shared
    -- @param number index
    -- @param Vector position
    function ents_methods:p2mSetPos( index, pos )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        if not checkValid( instance.player, ent, _POS, index, nil ) then
            return
        end

        ent:SetControllerLinkPos( index, vunwrap( pos ) )
    end

    --- Gets the local position of the controller
    -- @shared
    -- @param number index
    -- @return Vector local position
    function ents_methods:p2mGetPos( index )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        if not checkValid( instance.player, ent, _POS, index, nil ) then
            return
        end

        return vwrap( ent:GetControllerLinkPos( index ) )
    end

    --- Sets the local angle of the controller
    -- @shared
    -- @param number index
    -- @param Angle angle
    function ents_methods:p2mSetAng( index, ang )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        if not checkValid( instance.player, ent, _ANG, index, nil ) then
            return
        end

        ent:SetControllerLinkAng( index, aunwrap( ang ) )
    end

    --- Gets the local angle of the controller
    -- @shared
    -- @param number index
    -- @return Angle local angle
    function ents_methods:p2mGetAng( index )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        if not checkValid( instance.player, ent, _ANG, index, nil ) then
            return
        end

        return awrap( ent:GetControllerLinkAng( index ) )
    end

    --- Sets the color of the controller
    -- @shared
    -- @param number index
    -- @param Color color
    function ents_methods:p2mSetColor( index, color )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, _COL, index, nil ) then
            return
        end

        ent:SetControllerCol( index, cunwrap( color ) )
    end

    --- Sets the alpha of the controller
    -- @shared
    -- @param number index
    -- @param number alpha
    function ents_methods:p2mSetAlpha( index, alpha )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, _ALPHA, index, nil ) then
            return
        end

        CheckLuaType( alpha, TYPE_NUMBER )

        ent:SetControllerAlpha( index, alpha )
    end

    --- Gets the material of the controller
    -- @shared
    -- @param number index
    -- @return string material name
    function ents_methods:p2mGetMaterial( index )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, nil, index, nil ) then
            return ""
        end

        return ent:GetControllerMat( index )
    end

    --- Sets the material of the controller
    -- @shared
    -- @param number index
    -- @param string mat material name
    function ents_methods:p2mSetMaterial( index, mat )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        CheckLuaType( mat, TYPE_STRING )

        if not checkValid( instance.player, ent, _MAT, index, nil ) then
            return
        end

        ent:SetControllerMat( index, mat )
    end

    --- Sets the scale of the controller
    -- @shared
    -- @param number index
    -- @param Vector scale
    function ents_methods:p2mSetScale( index, scale )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )
        if not checkValid( instance.player, ent, _SCALE, index, nil ) then
            return
        end

        ent:SetControllerScale( index, vunwrap( scale ) )
    end

    --- Sets the UVs of the controller
    -- @param number index
    -- @param number uvs
    function ents_methods:p2mSetUV( index, uvs )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, _UVS, index, nil ) then
            return
        end

        CheckLuaType( uvs, TYPE_NUMBER )
        ent:SetControllerUVS( index, math.Clamp( math.floor( math.abs( uvs ) ), 0, 512 ) )
    end

    --- Enables or disables bumpmaps on the controller
    -- @param number index
    -- @param boolean bump
    function ents_methods:p2mSetBump( index, bump )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, _BUMP, index, nil ) then
            return
        end

        CheckLuaType( bump, TYPE_BOOL )
        ent:SetControllerBump( index, bump )
    end

    --- Sets the controller's link data
    -- @param number index
    -- @param Entity ent link entity
    -- @param Vector pos link position
    -- @param Angle ang link angle
    function ents_methods:p2mSetLink( index, other, pos, ang )
        CheckType( self, ents_metatable )
        local ent = unwrap( self )

        CheckLuaType( index, TYPE_NUMBER )

        if not checkValid( instance.player, ent, _LINK, index, nil ) then
            return
        end

        other = unwrap( other )

        if other == ent or not other:IsValid() or not checkOwner( instance.player, other ) then
            return
        end

        pos = vunwrap( pos )
        ang = aunwrap( ang )

        ent:SetControllerLinkEnt( index, other )
        ent:SetControllerLinkPos( index, pos )
        ent:SetControllerLinkAng( index, ang )
    end

end
