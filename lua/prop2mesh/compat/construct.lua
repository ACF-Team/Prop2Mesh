
-------------------------------
-- CONSTRUCT LIBRARY
--
-- BY SHADOWSCION
-------------------------------
-- Feel free to use this file in your projects, but please change the below global table to your addon
prop2mesh.primitive = {}
local addon = prop2mesh.primitive

-- Primitive.minSize, copied rather than read, so this library doesn't need that addon installed
local MinSize = 0.4


-------------------------------
local bit, math, util, table, isvector, WorldToLocal, LocalToWorld, Vector, Angle =
      bit, math, util, table, isvector, WorldToLocal, LocalToWorld, Vector, Angle

local math_abs, math_sin, math_cos, math_tan, math_asin, math_acos, math_atan, math_atan2, math_rad, math_deg, math_sqrt =
      math.abs, math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.atan2, math.rad, math.deg, math.sqrt

local math_ceil, math_floor, math_round, math_min, math_max, math_clamp =
      math.ceil, math.floor, math.Round, math.min, math.max, math.Clamp

local next, pairs, table_insert, coroutine_yield =
      next, pairs, table.insert, coroutine.yield

local vec, ang = Vector(), Angle()
local vec_cross, vec_dot, vec_add, vec_sub, vec_mul, vec_div, vec_rotate, vec_length, vec_lengthsqr, vec_normalize, vec_getnormalized, vec_angle =
      vec.Cross, vec.Dot, vec.Add, vec.Sub, vec.Mul, vec.Div, vec.Rotate, vec.Length, vec.LengthSqr, vec.Normalize, vec.GetNormalized, vec.Angle

local math_pi = math.pi
local math_tau = math.pi * 2


-------------------------------
local util_Ease = {}
util_Ease.linear = function( lhs, rhs )
    return lhs / rhs
end
util_Ease.cosine = function( lhs, rhs )
    return 1 - 0.5 * ( math_cos( ( lhs / rhs ) * math_pi ) + 1 )
end
util_Ease.quadratic = function( lhs, rhs )
    return ( lhs / rhs ) ^ 2
end

local function util_MapF( x, in_min, in_max, out_min, out_max )
    return ( x - in_min ) * ( out_max - out_min ) / ( in_max - in_min ) + out_min
end

local function util_Transform( points, rot, add, threaded )
    -- NOTE: Vectors are mutable objects, which means this may have unexpected results if used
    -- incorrectly ( applying util_Transform to same vertex multiple times by mistake ). That's why it's
    -- per construct, instead of in the global getter function.

    rot = isangle( rot ) and ( rot.p ~= 0 or rot.y ~= 0 or rot.r ~= 0 ) and rot or nil
    add = isvector( add ) and ( add.x ~= 0 or add.y ~= 0 or add.z ~= 0 ) and add or nil

    if rot and add then
        for i = 1, #points do
            local v = points[i]

            vec_rotate( v, rot )
            vec_add( v, add )
        end
    elseif rot then
        for i = 1, #points do vec_rotate( points[i], rot ) end
    elseif add then
        for i = 1, #points do vec_add( points[i], add ) end
    end
end

local function util_IntersectPlaneLine( lineStart, lineDir, planePos, planeNormal )
    local a = vec_dot( planeNormal, lineDir )

    if a == 0 then
        if vec_dot( planeNormal, planePos - lineStart ) == 0 then
            return lineStart
        end
        return false
    end

    local d = vec_dot( planeNormal, planePos - lineStart )

    return lineStart + lineDir * ( d / a )
end

local function util_IntersectPlaneLineSegment( lineStart, lineFinish, planePos, planeNormal )
    local lineDir = lineFinish - lineStart
    local xpoint = util_IntersectPlaneLine( lineStart, lineDir, planePos, planeNormal )

    if xpoint and vec_lengthsqr( xpoint - lineStart ) <= vec_lengthsqr( lineDir ) then
        return xpoint
    end

    return false
end

local function util_PointMirror( point, origin, normal )
    local l = vec_dot( normal, origin - point )
    return point + normal * l * 2
end


-------------------------------
addon.construct = { simpleton = {} }

local registerType, getType
local construct_types = {}

do
    --[[
        @FUNCTION: addon.construct.registerType

        @DESCRIPTION: Register a new construct type

        @PARAMETERS:
            [string] name -- the name of the new type
            [function]( param, data, threaded, physics )

        @RETURN:
    --]]
    function registerType( name, factory, data )
        if not istable( data ) then
            data = {}
        end

        data.name = name or "NO_NAME"
        construct_types[name] = { factory = factory, data = data }
    end
    addon.construct.registerType = registerType


    --[[
        @FUNCTION: addon.construct.getType

        @DESCRIPTION:

        @PARAMETERS:

        @RETURN:
            the construct table
    --]]
    function getType( name )
        return construct_types[name]
    end
    addon.construct.getType = getType


    local function errorModel( code, name, err )
        local message
        if code == 1 then message = "Non-existant construct" end
        if code == 2 then message = "Lua error" end
        if code == 3 then message = "Bad return" end
        if code == 4 then message = "Bad physics table" end
        if code == 5 then message = "Bad vertex table" end
        if code == 6 then message = "Triangulation failed" end

        local construct  = construct_types.error
        local result = construct.factory( param, construct.data, thread, physics )

        result.error = {
            code = code,
            name = name,
            lua = err,
            msg = message,
        }

        if CLIENT then
            result:Build( {} )
        end

        print( "-----------------------------" )
        PrintTable( result.error )
        print( "-----------------------------" )

        return result
    end

    local function getResult( construct, name, param, threaded, physics )
        local success, result = pcall( construct.factory, param, construct.data, threaded, physics )

        -- lua error, error model CODE 2
        if not success then
            return true, errorModel( 2, name, result )
        end

        -- Bad return, error model CODE 3
        if not istable( result ) then
            return true, errorModel( 3, name )
        end

        -- Bad physics table, error model CODE 4
        if physics and ( not istable( result.convexes ) or #result.convexes < 1 ) then
            return true, errorModel( 4, name )
        end

        if CLIENT then
            -- Bad vertex table, error model CODE 5
            if not istable( result.verts ) or #result.verts < 3 then
                return true, errorModel( 5, name )
            end

            if istable( result.index ) and not param.skip_tris then
                local suc, err = pcall( result.Build, result, param, threaded, physics )

                -- Triangulation failed, error model CODE 6
                if not suc or err or not istable( result.tris ) or #result.tris < 3 then
                    return true, errorModel( 6, name, err )
                end
            end
        else
            result.verts = nil
            result.index = nil
        end

        return true, result
    end


    --[[
        @FUNCTION: addon.construct.generate

        @DESCRIPTION:
            NOTE: Although this function can be called with a valid but unregistered construct, that should only be done
            for convenience while developing. Not registering the construct means other addons ( like prop2mesh )
            will not have quick access to it.

        @PARAMETERS:
            [table] construct
            [table] param      -- passed to the builder function
            [boolean] threaded -- return a coroutine (if possible)
            [boolean] physics  -- generate a collison model

        @RETURN:
            either a function or a coroutine that will build the mesh
    --]]
    function addon.construct.generate( construct, param, threaded, physics, missingname )
        if SERVER then threaded = nil end

        -- Non-existant construct, error model CODE 1. Named by the caller, since a construct
        -- that doesn't exist has no data table to read a name out of.
        if construct == nil then
            return true, errorModel( 1, missingname or "NO_NAME" )
        end

        construct.data.name = construct.data.name or "NO_NAME"
        local name = construct.data.name

        -- Expected yield: true, true, table
        if threaded and construct.data.canThread then
            return true, coroutine.create( function()
                coroutine_yield( getResult( construct, name, param, true, physics ) )
            end )
        end

        -- Expected return: true, table
        return getResult( construct, name, param, false, physics )
    end


    --[[
        @FUNCTION: addon.construct.get

        @DESCRIPTION:

        @PARAMETERS:
            [string] name
            [table] param      -- passed to the builder function
            [boolean] threaded -- return a coroutine (if possible)
            [boolean] physics  -- generate a collison model

        @RETURN:
            either a function or a coroutine that will build the mesh
    --]]
    function addon.construct.get( name, param, threaded, physics )
        return addon.construct.generate( construct_types[name], param, threaded, physics, name )
    end
end


local simpleton = addon.construct.simpleton
do
    local meta = {}
    meta.__index = meta


    --[[
        @FUNCTION: simpleton.New

        @DESCRIPTION: Create a new simpleton object, which is a table with a list of vertices and indices.

        @PARAMETERS:

        @RETURN:
            [table]
                [table] verts -- table containing all vertices
                [table] index -- table containing all triangle indices
                [table] key   -- used by the clipping engine to store original indices
    --]]
    function simpleton.New()
        return setmetatable( { verts = {}, index = {}, key = {} }, meta )
    end


    --[[
        @FUNCTION: simpleton.ClipPlane

        @DESCRIPTION: Create a new clipping plane

        @PARAMETERS:
            [vector] pos        - origin of  plane
            [vector] normal     - direction of plane
            [number] renderSize - display size of plane if drawn (optional)
            [color] renderColor - display color of plane if drawn (optional)

        @RETURN:
            [table]
                [vector] normal
                [vector] pos
                [table] verts
                [function] Draw

    --]]
    function simpleton.ClipPlane( pos, normal, renderSize, renderColor )
        vec_normalize( normal )

        local plane = {}

        plane.pos = pos
        plane.normal = normal
        plane.distance = -vec_dot( normal, pos )
        plane.renderColor = renderColor

        local v0 = normal:Angle():Up()
        local v1 = v0:Cross( normal )
        plane.verts = { pos + v0 * renderSize, pos + v1 * renderSize, pos - v0 * renderSize, pos - v1 * renderSize }

        plane.Draw = function( self )
            render.SetColorMaterial()
            render.DrawQuad( self.verts[1], self.verts[2], self.verts[3], self.verts[4], self.renderColor or color_white )
            render.DrawQuad( self.verts[4], self.verts[3], self.verts[2], self.verts[1], self.renderColor or color_white )
        end

        return plane
    end


    --[[
        @FUNCTION: simpleton.RegisterPrefa

        @DESCRIPTION:

        @PARAMETERS:
            [string] name
            [table] verts
            [table] index

        @RETURN:
    --]]
    local prefab_types = {}

    function simpleton.RegisterPrefab( name, index, verts )
        prefab_types[name] = {
            name = name,
            verts = verts,
            index = index,
        }
        return prefab_types[name]
    end


    --[[
        @FUNCTION: simpleton:PushPrefab

        @DESCRIPTION: Insert a prefab shape into a simpleton's table

        @PARAMETERS:
            [string] name
            [vector] local pos
            [angle] local ang
            [vector] scale
            [boolean] pushindex
            [table] additional table to add vertices to (optional)
            [number] subtable id of ^, increments if not given (optional)

        @RETURN:
            [table] key table of added vertices
    --]]
    function meta:PushPrefab( name, pos, ang, scale, pushindex, vtable, vtableN )
        local prefab = prefab_types[name]
        if not prefab then
            return
        end

        local key = {}
        local verts, index = prefab.verts, prefab.index

        if vtable and not vtableN then
            vtable[#vtable + 1] = {}
            vtable = vtable[#vtable]
        end

        for i = 1, #verts do
            local vertex = Vector( verts[i] )

            if scale then vec_mul( vertex, scale ) end
            if ang then vec_rotate( vertex, ang ) end
            if pos then vec_add( vertex, pos ) end

            local n = #self.verts + 1
            self.verts[n] = vertex

            key[i] = n

            if vtable then vtable[#vtable + 1] = vertex end
        end

        if pushindex then
            for i = 1, #index do
                self:PushIndex( key[index[i]] )
            end
        end

        return key
    end


    --[[
        @FUNCTION: simpleton:Mirror

        @DESCRIPTION: Mirror a simpleton across a plane

        @PARAMETERS:
            [vector] mirror plane origin
            [vector] mirror plane normal

        @RETURN:
    --]]
    function meta:Mirror( origin, normal )
        local clone = simpleton.New()

        local index = self.index
        local verts = self.verts

        for i = 1, #index, 3 do
            local a = index[i]
            local b = index[i + 1]
            local c = index[i + 2]

            index[i] = c
            index[i + 1] = b
            index[i + 2] = a
        end

        local set = origin.Set
        for i = 1, #verts do
            local vertex = verts[i]
            set( vertex, util_PointMirror( vertex, origin, normal ) )
        end
    end


    --[[
        @FUNCTION: simpleton:Clone

        @DESCRIPTION: Make a clone of a simpleton, optionally, mirror it across a plane

        @PARAMETERS:
            [vector] mirror plane origin (optional)
            [vector] mirror plane normal (optional)

        @RETURN: The clone
    --]]
    function meta:Clone( origin, normal )
        local clone = simpleton.New()

        local index = self.index
        local verts = self.verts

        if isvector( origin ) and isvector( normal ) then
            for i = 1, #index, 3 do
                local a = index[i]
                local b = index[i + 1]
                local c = index[i + 2]

                clone.index[i] = c
                clone.index[i + 1] = b
                clone.index[i + 2] = a
            end

            for i = 1, #verts do
                clone.verts[i] = util_PointMirror( verts[i], origin, normal )
            end

            return clone
        else
            for i = 1, #index do
                clone.index[i] = index[i]
            end

            for i = 1, #verts do
                clone.verts[i] = Vector( verts[i] )
            end

            return clone
        end
    end


    --[[
        @FUNCTION: simpleton:Merge

        @DESCRIPTION: Add the contents of one simpleton to another.

        @PARAMETERS:
            [simpleton] rhs

        @RETURN:
    --]]
    function meta:Merge( rhs )
        local key = {}
        local verts = rhs.verts
        local index = rhs.index

        for i = 1, #verts do
            key[i] = self:PushVertex( verts[i] )
        end

        for i = 1, #index do
            self:PushIndex( key[index[i]] )
        end
    end


    --[[
        @FUNCTION: simpleton:PushIndex

        @DESCRIPTION: Add a single index to the index table. NOTE, the builder requires triplets.

        @PARAMETERS:
            [number] n -- id of index

        @RETURN:
    --]]
    function meta:PushIndex( n )
        self.index[#self.index + 1] = n
    end


    --[[
        @FUNCTION: simpleton:PushTriangle

        @DESCRIPTION: Add a triangle consisting of 3 indexes to the index table.

        @PARAMETERS:
            [number] a -- first index
            [number] b -- second index
            [number] c -- third index

        @RETURN:
    --]]
    function meta:PushTriangle( a, b, c )
        self:PushIndex( a )
        self:PushIndex( b )
        self:PushIndex( c )
    end


    --[[
        @FUNCTION: simpleton:PushFace

        @DESCRIPTION: Triangulates a variable number of indices and adds each triplet to the index table.
                      NOTE, this creates a triangle fan, which only works for a convex face.
        @PARAMETERS:
            [number...] -- variadic arguments

        @RETURN:
    --]]
    function meta:PushFace( ... )
        local f = { ... }
        local a, b, c = f[1], f[2]

        for i = 3, #f do
            c = f[i]
            self:PushTriangle( a, b, c )
            b = c
        end
    end


    --[[
        @FUNCTION: simpleton:PushFaceTable

        @DESCRIPTION: Triangulates a variable number of indices and adds each triplet to the index table.
                      NOTE, this creates a triangle fan, which only works for a convex face.
        @PARAMETERS:
            [table] -- face index table

        @RETURN:
    --]]
    function meta:PushFaceTable( f )
        local a, b, c = f[1], f[2]

        for i = 3, #f do
            c = f[i]
            self:PushTriangle( a, b, c )
            b = c
        end
    end


    --[[
        @FUNCTION: simpleton:PushVertex

        @DESCRIPTION: Add a single vertex to the vertex table

        @PARAMETERS:
            [vector] v -- the vertex to add

        @RETURN:
            [number] -- the index of the added vertex
    --]]
    function meta:PushVertex( v )
        if not v then return end
        self.verts[#self.verts + 1] = Vector( v )
        return #self.verts
    end


    --[[
        @FUNCTION: simpleton:CopyVertex

        @DESCRIPTION: Copy an existing vertex and add it to the vertex table

        @PARAMETERS:
            [number] n -- the existing vertex index
            [number] x -- optional setter
            [number] y -- optional setter
            [number] z -- optional setter

        @RETURN:
            [number] -- the index of the added vertex
    --]]
    function meta:CopyVertex( n, x, y, z )
        local copy = self.verts[n]
        if not copy then return end
        self.verts[#self.verts + 1] = Vector( x or copy.x, y or copy.y, z or copy.z )
        return #self.verts
    end


    --[[
        @FUNCTION: simpleton:PushXYZ

        @DESCRIPTION: Add a single vertex to the vertex table, differs from PushVertex in that
                      PushVertex clones the passed vector.

        @PARAMETERS:
            [number] x
            [number] y
            [number] z

        @RETURN:
            [number] -- the index of the added vertex
    --]]
    function meta:PushXYZ( x, y, z )
        self.verts[#self.verts + 1] = Vector( x, y, z )
        return #self.verts
    end


    --[[
        @FUNCTION: simpleton:SetScale

        @DESCRIPTION: Multiplies every vertex by a vector

        @PARAMETERS:
            [vector] v -- the scale

        @RETURN:
    --]]
    function meta:SetScale( v )
        for i = 1, #self.verts do
            vec_mul( self.verts[i], v )
        end
    end


    --[[
        @FUNCTION: simpleton:Translate

        @DESCRIPTION: Translates every vertex by a vector

        @PARAMETERS:
            [vector] v -- the translation

        @RETURN:
    --]]
    function meta:Translate( v )
        for i = 1, #self.verts do
            vec_add( self.verts[i], v )
        end
    end


    --[[
        @FUNCTION: simpleton:Rotate

        @DESCRIPTION: Rotates every vertex by an angle

        @PARAMETERS:
            [angle] a -- the rotation

        @RETURN:
    --]]
    function meta:Rotate( a )
        for i = 1, #self.verts do
            vec_rotate( self.verts[i], a )
        end
    end


    --[[
        CLIPPING ENGINE
    ]]
    local function pushClippedTriangle( self, a, b, c )
        if not a or not b or not c then print( a, b, c ) return end

        local v0 = self.key[a]
        local v1 = self:PushVertex( b )
        local v2 = isvector( c ) and self:PushVertex( c ) or self.key[c]

        self:PushIndex( v0 )
        self:PushIndex( v1 )
        self:PushIndex( v2 )
    end

    local tempT, tempV, tempB = {}, {}, {}

    local function intersection( self, index, planePos, planeNormal, abovePlane, belowPlane )
        -- Temporarily store each index, vertex, and whether or not
        -- the abovePlane mesh contains the index.
        for i = 0, 2 do
            local n = self.index[index + i]
            tempT[i] = n
            tempV[i] = self.verts[n]
            tempB[i] = abovePlane.key[n] ~= nil
        end

        -- If all 3 indices are stored on the same side ( abovePlane or belowPlane ), there
        -- are no intersections, so the triangle is simply added to that side.
        if tempB[0] == tempB[1] and tempB[1] == tempB[2] then
            local side = tempB[0] and abovePlane or belowPlane

            side:PushIndex( side.key[tempT[0]] )
            side:PushIndex( side.key[tempT[1]] )
            side:PushIndex( side.key[tempT[2]] )

            return false
        end

        -- In every clipped triangle there will be one vertex that falls on the side opposite
        -- of the other two vertices. This vertex is used as the origin of the intersection checks. ( line AB, line AC )
        local tA = 2
        if tempB[0] ~= tempB[1] then tA = tempB[0] ~= tempB[2] and 0 or 1 end

        local tB = tA - 1
        if tB == -1 then tB = 2 end

        local tC = tA + 1
        if tC == 3 then tC = 0 end

        -- Perform a line-segment/plane intersectin between the two
        -- new edges and the clipping plane to get the new vertices.
        local instersect_tAB = util_IntersectPlaneLineSegment( tempV[tA], tempV[tB], planePos, planeNormal )
        local instersect_tAC = util_IntersectPlaneLineSegment( tempV[tA], tempV[tC], planePos, planeNormal )

        local side = tempB[tA] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tA], instersect_tAC, instersect_tAB )

        local side = tempB[tB] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tB], instersect_tAB, tempT[tC] )

        local side = tempB[tB] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tC], instersect_tAB, instersect_tAC )

        -- The new vertices are also returned to be used for whatever later on
        if tempB[tA] then
            return instersect_tAB, instersect_tAC
        else
            return instersect_tAC, instersect_tAB
        end
    end

    local function closeEdgeLoop( abovePlane, belowPlane, loopCenter, loopPoints )
        local aA
        if abovePlane then
            aA = abovePlane:PushVertex( loopCenter )
        end

        local bA
        if belowPlane then
            bA = belowPlane:PushVertex( loopCenter )
        end

        local wrap = { [#loopPoints] = 1 }

        for i = 1, #loopPoints do
            local p0 = loopPoints[i]
            local p1 = loopPoints[wrap[i] or i + 1]

            if aA then
                abovePlane:PushTriangle( aA, abovePlane:PushVertex( p0 ), abovePlane:PushVertex( p1 ) )
            end
            if bA then
                belowPlane:PushTriangle( bA, belowPlane:PushVertex( p1 ), belowPlane:PushVertex( p0 ) )
            end
        end
    end

    --[[ Given an unordered list of line segments, return a closed boundary
    local function closeEdgeLoop( lineSegments )
        local polychain = {}

        -- pop a line segment from the list
        local prevID, prevAB = next( lineSegments )
        lineSegments[prevID] = nil

        -- loop until there are no more lineSegments left to check
        while next( lineSegments ) do
            local pass

            for nextID, nextAB in pairs( lineSegments ) do
                -- check some condition between the previous and next segment
                if nextAB.A == prevAB.B or math_abs( vec_lengthsqr( nextAB.A - prevAB.B ) ) <= 1e-3 then
                    -- if it passes, add the previous segment start point to the polychain
                    polychain[#polychain + 1] = Vector( prevAB.A )

                    -- remove the new segment from the original lineSegments list
                    prevID, prevAB = nextID, nextAB
                    lineSegments[prevID] = nil

                    -- no need to check the others
                    pass = true
                    break
                end
            end

            if not pass then return false end -- invalid polygon chain
        end

        return polychain
    end
    ]]

    --[[
        @FUNCTION: simpleton:Bisect

        @DESCRIPTION: Cut a simpleton along a plane

        @PARAMETERS:
            [table] plane -- the plane should have a pos and normal field

        @RETURN:
            [table] abovePlane simpleton
            [table] belowPlane simpleton
    --]]
    function meta:Bisect( plane, fillAbove, fillBelow )
        -- Separate original vertices into two tables, determined by
        -- which side of clipping plane they are on.
        -- Store the original index of each vertex in the key table [ original = new ].
        local abovePlane = simpleton.New()
        local belowPlane = simpleton.New()

        local planePos = plane.pos
        local planeNormal = plane.normal

        for i = 1, #self.verts do
            if vec_dot( planeNormal, self.verts[i] - planePos ) >= 1e-6 then
                abovePlane.key[i] = abovePlane:PushVertex( self.verts[i] )
            else
                belowPlane.key[i] = belowPlane:PushVertex( self.verts[i] )
            end
        end

        -- If either mesh has a vertex count of 0, there are no
        -- intersections and we can stop here.
        if #abovePlane.verts == 0 or #belowPlane.verts == 0 then
            return false
        end

        -- Check each edge of each triangle for an intersection with the plane.
        -- All that intersect are split into two smaller triangles.
        local loopCenter = Vector()
        local loopPoints = ( fillAbove or fillBelow ) and {} or nil

        for i = 1, #self.index, 3 do
            local l0, l1 = intersection( self, i, planePos, planeNormal, abovePlane, belowPlane )

            if loopPoints and l0 and l1 then
                vec_add( loopCenter, l0 )
                loopPoints[#loopPoints + 1] = l0
            end
        end

        if loopPoints then
            loopCenter = loopCenter / #loopPoints

            table.sort( loopPoints, function( sa, sb )
                return vec_dot( planeNormal, vec_cross( sa - loopCenter, sb - loopCenter ) ) < 0
            end )

            closeEdgeLoop( fillAbove and abovePlane, fillBelow and belowPlane, loopCenter, loopPoints )
        end

        abovePlane.key = {}
        belowPlane.key = {}

        return abovePlane, belowPlane
    end


    if CLIENT then
        local YIELD_THRESHOLD = 30

        local function calcUV( a, b, c, normal, scale )
            local nx, ny, nz = math_abs( normal.x ), math_abs( normal.y ), math_abs( normal.z )
            if nx > ny and nx > nz then
                local nw = normal.x < 0 and -1 or 1
                a.u = a.pos.z * nw * scale
                a.v = a.pos.y * scale
                b.u = b.pos.z * nw * scale
                b.v = b.pos.y * scale
                c.u = c.pos.z * nw * scale
                c.v = c.pos.y * scale

            elseif ny > nz then
                local nw = normal.y < 0 and -1 or 1
                a.u = a.pos.x * scale
                a.v = a.pos.z * nw * scale
                b.u = b.pos.x * scale
                b.v = b.pos.z * nw * scale
                c.u = c.pos.x * scale
                c.v = c.pos.z * nw * scale

            else
                local nw = normal.z < 0 and 1 or -1
                a.u = a.pos.x * nw * scale
                a.v = a.pos.y * scale
                b.u = b.pos.x * nw * scale
                b.v = b.pos.y * scale
                c.u = c.pos.x * nw * scale
                c.v = c.pos.y * scale

            end
        end

        local function calcInside( verts, threaded )
            for i = #verts, 1, -1 do
                local v = verts[i]
                verts[#verts + 1] = { pos = v.pos, normal = -v.normal, u = v.u, v = v.v, userdata = v.userdata }

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local function calcBounds( vertex, mins, maxs )
            local x = vertex.x
            local y = vertex.y
            local z = vertex.z
            if x < mins.x then mins.x = x elseif x > maxs.x then maxs.x = x end
            if y < mins.y then mins.y = y elseif y > maxs.y then maxs.y = y end
            if z < mins.z then mins.z = z elseif z > maxs.z then maxs.z = z end
        end

        local function calcNormals( verts, deg, threaded )
            -- credit to Sevii for this craziness
            deg = math_cos( math_rad( deg ) )

            local norms = setmetatable( {}, { __index = function( t, k ) local r = setmetatable( {}, { __index = function( t, k ) local r = setmetatable( {}, { __index = function( t, k ) local r = {} t[k] = r return r end } ) t[k] = r return r end } ) t[k] = r return r end } )

            for i = 1, #verts do
                local vertex = verts[i]
                local pos = vertex.pos
                local norm = norms[pos[1]][pos[2]][pos[3]]
                norm[#norm + 1] = vertex.normal

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            for i = 1, #verts do
                local vertex = verts[i]
                local normal = Vector()
                local count = 0
                local pos = vertex.pos

                local nk = norms[pos[1]][pos[2]][pos[3]]
                for j = 1, #nk do
                    local norm = nk[j]
                    if vec_dot( vertex.normal, norm ) >= deg then
                        vec_add( normal, norm )
                        count = count + 1
                    end
                end

                if count > 1 then
                    vec_div( normal, count )
                    vertex.normal = normal
                end

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local function calcTangents( verts, threaded )
            -- credit to https://gamedev.stackexchange.com/questions/68612/how-to-compute-tangent-and-bitangent-vectors
            -- seems to work but i have no idea how or why, nor why i cant do this during triangulation

            local tan1 = {}
            local tan2 = {}

            for i = 1, #verts do
                tan1[i] = Vector( 0, 0, 0 )
                tan2[i] = Vector( 0, 0, 0 )

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
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

                local r = 1 / ( us1 * ut2 - us2 * ut1 )

                local sdir = Vector( ( ut2 * x1 - ut1 * x2 ) * r, ( ut2 * y1 - ut1 * y2 ) * r, ( ut2 * z1 - ut1 * z2 ) * r )
                local tdir = Vector( ( us1 * x2 - us2 * x1 ) * r, ( us1 * y2 - us2 * y1 ) * r, ( us1 * z2 - us2 * z1 ) * r )

                vec_add( tan1[i], sdir )
                vec_add( tan1[i + 1], sdir )
                vec_add( tan1[i + 2], sdir )

                vec_add( tan2[i], tdir )
                vec_add( tan2[i + 1], tdir )
                vec_add( tan2[i + 2], tdir )

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            for i = 1, #verts do
                local n = verts[i].normal
                local t = tan1[i]

                local tangent = ( t - n * vec_dot( n, t ) )
                vec_normalize( tangent )

                verts[i].userdata = { tangent[1], tangent[2], tangent[3], vec_dot( vec_cross( n, t ), tan2[i] ) }

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local ENUM_TANGENTS = 1
        local ENUM_INSIDE = 2
        local ENUM_INVERT = 4


        --[[
            @FUNCTION: simpleton:Build

            @DESCRIPTION: Convert a simpleton into imesh vertex structure

            @PARAMETERS:

            @RETURN:
                [table] imesh vertex struct
        --]]
        function meta:Build( param, threaded, physics )
            --[[
                CONFIG

                if necessary, other addons ( like prop2mesh ) can override flags by setting the skip params
                    .skip_bounds
                    .skip_tangents
                    .skip_inside
                    .skip_invert
                    .skip_uv
                    .skip_normals
            ]]

            local fbounds, ftangents, finside, finvert

            local mins, maxs
            if not param.skip_bounds then

                -- if physics are generated we can use GetCollisionBounds for SetRenderBounds
                -- otherwise we need to get mins and maxs manually

                if not physics then
                    mins = Vector( math.huge, math.huge, math.huge )
                    maxs = Vector( -math.huge, -math.huge, -math.huge )

                    fbounds = true
                end
            end

            local bits = tonumber( param.PrimMESHENUMS ) or 0

            if not param.skip_tangents then
                if system.IsLinux() or system.IsOSX() then ftangents = true else ftangents = bit.band( bits, ENUM_TANGENTS ) == ENUM_TANGENTS end
            end

            if not param.skip_inside then
                finside = bit.band( bits, ENUM_INSIDE ) == ENUM_INSIDE
            end

            if not param.skip_invert then
                finvert = bit.band( bits, ENUM_INVERT ) == ENUM_INVERT
            end

            local uvmap
            if not param.skip_uv then
                uvmap = tonumber( param.PrimMESHUV ) or 48
                if uvmap < 8 then uvmap = 8 end
                uvmap = 1 / uvmap
            end

            -- TRIANGULATE
            self.tris = {}

            local tris  = self.tris
            local verts = self.verts
            local index = self.index

            for i = 1, #index, 3 do
                local p0 = verts[index[i]]
                local p1 = verts[index[i + 2]]
                local p2 = verts[index[i + 1]]

                if fbounds then
                    calcBounds( p0, mins, maxs )
                    calcBounds( p1, mins, maxs )
                    calcBounds( p2, mins, maxs )
                end

                local normal = vec_cross( p2 - p0, p1 - p0 )
                vec_normalize( normal )

                local v0 = { pos = Vector( finvert and p2 or p0 ), normal = Vector( normal ) }
                local v1 = { pos = Vector( p1 ), normal = Vector( normal ) }
                local v2 = { pos = Vector( finvert and p0 or p2 ), normal = Vector( normal ) }

                if uvmap then calcUV( v0, v1, v2, normal, uvmap ) end

                tris[#tris + 1] = v0
                tris[#tris + 1] = v1
                tris[#tris + 1] = v2

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            -- POSTPROCESS
            if not param.skip_normals then
                local smooth = tonumber( param.PrimMESHSMOOTH ) or 0
                if smooth ~= 0 then
                    calcNormals( tris, smooth, threaded )
                end
            end

            if ftangents then
                calcTangents( tris, threaded )
            end

            if finside then
                calcInside( tris, threaded )
            end

            if fbounds then
                self.mins = mins
                self.maxs = maxs
            end
        end
    end
end


-- PREFABS
simpleton.RegisterPrefab( "cube",
    {
        1, 5, 6,
        1, 6, 2,
        5, 7, 8,
        5, 8, 6,
        7, 3, 4,
        7, 4, 8,
        3, 1, 2,
        3, 2, 4,
        4, 2, 6,
        4, 6, 8,
        1, 3, 7,
        1, 7, 5,
    },
    {
        Vector( -0.5, 0.5, -0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( 0.5, 0.5, -0.5 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( -0.5, -0.5, -0.5 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( 0.5, -0.5, -0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
    }
)
simpleton.RegisterPrefab( "plane",
    {
        1, 2, 3,
        1, 3, 4,
    },
    {
        Vector( -0.5, 0.5, 0 ),
        Vector( -0.5, -0.5, 0 ),
        Vector( 0.5, -0.5, 0 ),
        Vector( 0.5, 0.5, 0 ),
    }
)
simpleton.RegisterPrefab( "slider_blade",
    {
        1, 2, 3,
        2, 4, 6,
        2, 6, 3,
        3, 6, 5,
        3, 5, 1,
        4, 8, 7,
        4, 7, 6,
        6, 7, 9,
        6, 9, 5,
        11, 10, 7,
        11, 7, 8,
        9, 7, 10,
        9, 10, 12,
        14, 13, 10,
        14, 10, 11,
        12, 10, 13,
        12, 13, 15,
        17, 16, 13,
        17, 13, 14,
        15, 13, 16,
        15, 16, 18,
        21, 16, 17,
        21, 17, 19,
        20, 18, 16,
        20, 16, 21,
        20, 21, 19,
        19, 17, 14,
        19, 14, 11,
        19, 11, 8,
        19, 8, 4,
        19, 4, 2,
        1, 5, 9,
        1, 9, 12,
        1, 12, 15,
        1, 15, 18,
        1, 18, 20,
        2, 1, 20,
        2, 20, 19,
    },
    {
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( 0.5, -0.25, 0.153185 ),
        Vector( 0.433013, -0.5, 0.173407 ),
        Vector( 0.433013, 0.5, 0.173407 ),
        Vector( 0.433013, -0.25, -0.173407 ),
        Vector( 0.25, -0.25, -0.41249 ),
        Vector( 0.25, -0.5, -0.065675 ),
        Vector( 0.25, 0.5, -0.065675 ),
        Vector( 0, -0.25, -0.5 ),
        Vector( 0, -0.5, -0.153185 ),
        Vector( -0, 0.5, -0.153185 ),
        Vector( -0.25, -0.25, -0.41249 ),
        Vector( -0.25, -0.5, -0.065675 ),
        Vector( -0.25, 0.5, -0.065675 ),
        Vector( -0.433013, -0.25, -0.173407 ),
        Vector( -0.433013, -0.5, 0.173407 ),
        Vector( -0.433013, 0.5, 0.173407 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( -0.5, -0.25, 0.153186 ),
    }
)
simpleton.RegisterPrefab( "slider_cube",
    {
        1, 5, 6,
        1, 6, 2,
        5, 7, 8,
        5, 8, 6,
        7, 3, 4,
        7, 4, 8,
        3, 1, 2,
        3, 2, 4,
        4, 2, 6,
        4, 6, 8,
        1, 3, 7,
        1, 7, 5,
    },
    {
        Vector( -0.5, 0.5, -0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( 0.5, 0.5, -0.5 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( -0.5, -0.5, -0.5 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( 0.5, -0.5, -0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
    }
)
simpleton.RegisterPrefab( "slider_spike",
    {
        3, 5, 1,
        6, 5, 3,
        1, 5, 4,
        4, 5, 6,
        9, 6, 3,
        9, 3, 2,
        2, 3, 1,
        2, 1, 8,
        8, 1, 4,
        8, 4, 7,
        7, 4, 6,
        7, 6, 9,
        7, 9, 2,
        7, 2, 8,
    },
    {
        Vector( 0.5, -0.5, 0.3 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, -0.5, 0.3 ),
        Vector( 0.5, 0.5, 0.3 ),
        Vector( 0, 0, -0.5 ),
        Vector( -0.5, 0.5, 0.3 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
    }
)
simpleton.RegisterPrefab( "slider_wedge",
    {
        9, 1, 6,
        9, 6, 7,
        9, 2, 3,
        9, 3, 1,
        1, 3, 5,
        1, 5, 6,
        6, 5, 8,
        6, 8, 7,
        7, 8, 2,
        7, 2, 9,
        3, 10, 4,
        3, 4, 5,
        8, 4, 10,
        8, 10, 2,
        2, 10, 3,
        5, 4, 8,
    },
    {
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.3 ),
        Vector( -0.5, -0.5, 0.3 ),
        Vector( 0.5, -0, -0.5 ),
        Vector( 0.5, -0.5, 0.3 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, 0.5, 0.3 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( -0.5, 0, -0.5 ),
    }
)


-- ERROR
registerType( "error", function( param, data, threaded, physics )
    local model = simpleton.New()

    model:PushXYZ( 12, -12, -12 )
    model:PushXYZ( 12, 12, -12 )
    model:PushXYZ( 12, 12, 12 )
    model:PushXYZ( 12, -12, 12 )
    model:PushXYZ( -12, -12, -12 )
    model:PushXYZ( -12, 12, -12 )
    model:PushXYZ( -12, 12, 12 )
    model:PushXYZ( -12, -12, 12 )

    if CLIENT then
        model:PushFace( 1, 2, 3, 4 )
        model:PushFace( 2, 6, 7, 3 )
        model:PushFace( 6, 5, 8, 7 )
        model:PushFace( 5, 1, 4, 8 )
        model:PushFace( 4, 3, 7, 8 )
        model:PushFace( 5, 6, 2, 1 )
    end

    model.convexes = { model.verts }

    return model
end )


-- CONE
registerType( "cone", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = util_MapF( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = util_MapF( param.PrimTY or 0, -1, 1, -2, 2 )

    local model = simpleton.New()
    local verts = model.verts

    for i = 0, numseg do
        local a = math_rad( ( i / maxseg ) * -360 )
        model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        for i = 1, c0 - 1 do
            model:PushTriangle( i, i + 1, c2 )
            model:PushTriangle( i, c1, i + 1 )
        end
        if numseg ~= maxseg then
            model:PushTriangle( c0, c1, c2 )
            model:PushTriangle( c0 + 1, 1, c2 )
        end
    end

    if physics then
        local convexes

        if numseg ~= maxseg then
            convexes = {
                { verts[c1], verts[c2] },
                { verts[c1], verts[c2] },
            }

            for i = 1, c0 do
                if ( i - 1 <= maxseg * 0.5 ) then
                    table_insert( convexes[1], verts[i] )
                end
                if ( i - 0 >= maxseg * 0.5 ) then
                    table_insert( convexes[2], verts[i] )
                end
            end
        else
            convexes = { verts }
        end

        model.convexes = convexes
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE
registerType( "cube", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()

    if tx == 0 and ty == 0 then
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( 0, 0, dz )

        if CLIENT then
            model:PushTriangle( 1, 2, 5 )
            model:PushTriangle( 2, 4, 5 )
            model:PushTriangle( 4, 3, 5 )
            model:PushTriangle( 3, 1, 5 )
            model:PushFace( 3, 4, 2, 1 )
        end
    else
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( dx * tx, dy * ty, dz )
        model:PushXYZ( dx * tx, -dy * ty, dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, dy * ty, dz )
        model:PushXYZ( -dx * tx, -dy * ty, dz )

        if CLIENT then
            model:PushFace( 1, 2, 3, 4 )
            model:PushFace( 2, 6, 7, 3 )
            model:PushFace( 6, 5, 8, 7 )
            model:PushFace( 5, 1, 4, 8 )
            model:PushFace( 4, 3, 7, 8 )
            model:PushFace( 5, 6, 2, 1 )
        end
    end

    if physics then model.convexes = { model.verts } end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_MAGIC
registerType( "cube_magic", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then -- simple diff check is not correct, should be sine of taper angle?
        local construct = construct_types.cube
        return construct.factory( param, construct.data, threaded, physics )
    end

    local sides
    for i = 1, 6 do
        local flag = bit.lshift( 1, i - 1 )
        local bits = bit.band( tonumber( param.PrimSIDES ) or 0, flag ) == flag

        if bits then
            if not sides then sides = {} end
            sides[i] = true
        end
    end

    if not sides then sides = { true, true, true, true, true, true } end

    local normals = {
        Vector( 1, 0, 0 ):Angle(),
        Vector( -1, 0, 0 ):Angle(),
        Vector( 0, 1, 0 ):Angle(),
        Vector( 0, -1, 0 ):Angle(),
        Vector( 0, 0, 1 ):Angle(),
        Vector( 0, 0, -1 ):Angle(),
    }

    local a = Vector( 1, -1, -1 )
    local b = Vector( 1, 1, -1 )
    local c = Vector( 1, 1, 1 )
    local d = Vector( 1, -1, 1 )

    local model = simpleton.New()
    local verts = model.verts

    local convexes
    if physics then
        convexes = {}
        model.convexes = convexes
    end

    local ibuffer = 1

    for k, v in ipairs( normals ) do
        if not sides[k] then
            ibuffer = ibuffer - 8
        else
            local pos = Vector( a )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( b )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( c )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( d )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            if physics then
                local count = #verts
                convexes[#convexes + 1] = {
                    verts[count - 0],
                    verts[count - 1],
                    verts[count - 2],
                    verts[count - 3],
                    verts[count - 4],
                    verts[count - 5],
                    verts[count - 6],
                    verts[count - 7],
                }
            end

            if CLIENT then
                local n = ( k - 1 ) * 8 + ibuffer
                model:PushFace( n + 0, n + 2, n + 4, n + 6 )
                model:PushFace( n + 3, n + 1, n + 7, n + 5 )
                model:PushFace( n + 1, n + 0, n + 6, n + 7 )
                model:PushFace( n + 2, n + 3, n + 5, n + 4 )
                model:PushFace( n + 5, n + 7, n + 6, n + 4 )
                model:PushFace( n + 0, n + 1, n + 3, n + 2 )
            end
        end
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_HOLE
registerType( "cube_hole", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then
        local construct = construct_types.cube
        return construct.factory( param, construct.data, threaded, physics )
    end

    local numseg = param.PrimNUMSEG or 4
    if numseg > 4 then numseg = 4 elseif numseg < 1 then numseg = 1 end

    local numring = 4 * math_round( ( param.PrimSUBDIV or 32 ) / 4 )
    if numring < 4 then numring = 4 elseif numring > 32 then numring = 32 end

    local cube_angle = Angle( 0, 90, 0 )
    local cube_corner0 = Vector( 1, 0, 0 )
    local cube_corner1 = Vector( 1, 1, 0 )
    local cube_corner2 = Vector( 0, 1, 0 )

    local ring_steps0 = numring / 4
    local ring_steps1 = numring / 2
    local capped = numseg ~= 4

    local model = simpleton.New()
    local verts = model.verts

    if CLIENT and capped then
        model:PushFace( 8, 7, 1, 4 )
    end

    if physics then
        convexes = {}
        model.convexes = convexes
    end

    for i = 0, numseg - 1 do
        vec_rotate( cube_corner0, cube_angle )
        vec_rotate( cube_corner1, cube_angle )
        vec_rotate( cube_corner2, cube_angle )

        local part
        if physics then part = {} end

        model:PushXYZ( cube_corner0.x * dx, cube_corner0.y * dy, -dz )
        model:PushXYZ( cube_corner1.x * dx, cube_corner1.y * dy, -dz )
        model:PushXYZ( cube_corner2.x * dx, cube_corner2.y * dy, -dz )
        model:PushXYZ( cube_corner0.x * dx, cube_corner0.y * dy, dz )
        model:PushXYZ( cube_corner1.x * dx, cube_corner1.y * dy, dz )
        model:PushXYZ( cube_corner2.x * dx, cube_corner2.y * dy, dz )

        local count_end0 = #verts
        if CLIENT then
            model:PushFace( count_end0 - 5, count_end0 - 4, count_end0 - 1, count_end0 - 2 )
            model:PushFace( count_end0 - 4, count_end0 - 3, count_end0 - 0, count_end0 - 1 )
        end

        local ring_angle = -i * 90
        for j = 0, ring_steps0 do
            local a = math_rad( ( j / numring ) * -360 + ring_angle )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), dz )
        end

        local count_end1 = #verts
        if physics then
            convexes[#convexes + 1] = {
                verts[count_end0 - 0],
                verts[count_end0 - 3],
                verts[count_end0 - 4],
                verts[count_end0 - 1],
                verts[count_end1 - 0],
                verts[count_end1 - 1],
                verts[count_end1 - ring_steps1 * 0.5],
                verts[count_end1 - ring_steps1 * 0.5 - 1],
            }
            convexes[#convexes + 1] = {
                verts[count_end0 - 2],
                verts[count_end0 - 5],
                verts[count_end0 - 4],
                verts[count_end0 - 1],
                verts[count_end1 - ring_steps1],
                verts[count_end1 - ring_steps1 - 1],
                verts[count_end1 - ring_steps1 * 0.5],
                verts[count_end1 - ring_steps1 * 0.5 - 1],
            }
        end

        if CLIENT then
            model:PushTriangle( count_end0 - 1, count_end0 - 0, count_end1 - 0 )
            model:PushTriangle( count_end0 - 1, count_end1 - ring_steps1, count_end0 - 2 )
            model:PushTriangle( count_end0 - 4, count_end1 - 1, count_end0 - 3 )
            model:PushTriangle( count_end0 - 4, count_end0 - 5, count_end1 - ring_steps1 - 1 )

            for j = 0, ring_steps0 - 1 do
                local count_end2 = count_end1 - j * 2
                model:PushTriangle( count_end0 - 1, count_end2, count_end2 - 2 )
                model:PushTriangle( count_end0 - 4, count_end2 - 3, count_end2 - 1 )
                model:PushFace( count_end2, count_end2 - 1, count_end2 - 3, count_end2 - 2 )
            end

            if capped and i == numseg  - 1 then
                model:PushFace( count_end0, count_end0 - 3, count_end1 - 1, count_end1 )
            end
        end
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_CYLINDER
registerType( "cylinder", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()
    local verts = model.verts

    if tx == 0 and ty == 0 then
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
        end
    else
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx * tx ), math_cos( a ) * ( dy * ty ), dz )
        end
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( 0, 0, dz )

    if CLIENT then
        if tx == 0 and ty == 0 then
            for i = 1, c0 - 1 do
                model:PushTriangle( i, i + 1, c2 )
                model:PushTriangle( i, c1, i + 1 )
            end

            if numseg ~= maxseg then
                model:PushTriangle( c0, c1, c2 )
                model:PushTriangle( c0 + 1, 1, c2 )
            end
        else
            for i = 1, c0 - 2, 2 do
                model:PushFace( i, i + 2, i + 3, i + 1 )
                model:PushTriangle( i, c1, i + 2 )
                model:PushTriangle( i + 1, i + 3, c2 )
            end

            if numseg ~= maxseg then
                model:PushFace( c1, c2, c0, c0 - 1 )
                model:PushFace( c1, 1, 2, c2 )
            end
        end
    end

    if physics then
        local convexes

        if numseg ~= maxseg then
            convexes = {
                { verts[c1], verts[c2] },
                { verts[c1], verts[c2] },
            }

            if tx == 0 and ty == 0 then
                for i = 1, c0 do
                    if ( i - 1 <= maxseg * 0.5 ) then
                        table_insert( convexes[1], verts[i] )
                    end
                    if ( i - 1 >= maxseg * 0.5 ) then
                        table_insert( convexes[2], verts[i] )
                    end
                end
            else
                for i = 1, c0 do
                    if i - ( maxseg > 3 and 2 or 1 ) <= maxseg then
                        table_insert( convexes[1], verts[i] )
                    end
                    if i - 1 >= maxseg then
                        table_insert( convexes[2], verts[i] )
                    end
                end
            end
        else
            convexes = { verts }
        end

        model.convexes = convexes
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- DOME
registerType( "dome", function( param, data, threaded, physics )

    return construct_types.sphere.factory( param, data, threaded, physics )

end, { canThread = true, domePlane = { pos = Vector(), normal = Vector( 0, 0, 1 ) } } )


-- PLANE
registerType( "plane", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = 0.5

    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()
    if physics then
        model.convexes = { model.verts }
    end

    if ty == 0 then
        model:PushXYZ( dx, 0, 0 )
        model:PushXYZ( -dx, dy, 0 )
        model:PushXYZ( -dx, -dy, 0 )

        if CLIENT then
            model:PushTriangle( 1, 2, 3 )
        end

        if physics then
            model:PushXYZ( dx, 0, -dz )
            model:PushXYZ( -dx, dy, -dz )
            model:PushXYZ( -dx, -dy, -dz )
        end
    else
        model:PushXYZ( dx, dy * ty, 0 )
        model:PushXYZ( dx, -dy * ty, 0 )
        model:PushXYZ( -dx, dy, 0 )
        model:PushXYZ( -dx, -dy, 0 )

        if CLIENT then
            model:PushTriangle( 1, 3, 4 )
            model:PushTriangle( 1, 4, 2 )
        end

        if physics then
            model:PushXYZ( dx, dy * ty, -dz )
            model:PushXYZ( dx, -dy * ty, -dz )
            model:PushXYZ( -dx, dy, -dz )
            model:PushXYZ( -dx, -dy, -dz )
        end
    end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- PYRAMID
registerType( "pyramid", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = util_MapF( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = util_MapF( param.PrimTY or 0, -1, 1, -2, 2 )

    local model = simpleton.New()

    model:PushXYZ( dx, -dy, -dz )
    model:PushXYZ( dx, dy, -dz )
    model:PushXYZ( -dx, -dy, -dz )
    model:PushXYZ( -dx, dy, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        model:PushTriangle( 1, 2, 5 )
        model:PushTriangle( 2, 4, 5 )
        model:PushTriangle( 4, 3, 5 )
        model:PushTriangle( 3, 1, 5 )
        model:PushTriangle( 3, 4, 2 )
        model:PushTriangle( 3, 2, 1 )
    end

    if physics then
        model.convexes = { model.verts }
    end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- SPHERE
local function MakeSphere( model, subdiv, dx, dy, dz, threaded )
    for y = 0, subdiv do
        local v = y / subdiv
        local t = v * math_pi

        local cosPi = math_cos( t )
        local sinPi = math_sin( t )

        for x = 0, subdiv  do
            local u = x / subdiv
            local p = u * math_tau

            local cosTau = math_cos( p )
            local sinTau = math_sin( p )

            model:PushXYZ( -dx * cosTau * sinPi, dy * sinTau * sinPi, dz * cosPi )
        end

        if y > 0 then
            local i = #model.verts - 2 * ( subdiv + 1 )

            while ( i + subdiv + 2 ) < #model.verts do
                model:PushFace( i + 1, i + 2, i + subdiv + 3, i + subdiv + 2 )
                i = i + 1
            end
        end
    end
end

registerType( "sphere", function( param, data, threaded, physics )
    local subdiv = 2 * math_round( ( param.PrimSUBDIV or 32 ) / 2 )
    if subdiv < 4 then subdiv = 4 elseif subdiv > 32 then subdiv = 32 end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local domePlane = data.domePlane

    local model = simpleton.New()

    if CLIENT then
        MakeSphere( model, subdiv, dx, dy, dz, threaded )

        if domePlane then
            model, _ = model:Bisect( domePlane, true )
        end

        util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

        if physics then
            if subdiv <= 8 then
                model.convexes = { model.verts } -- no need to recompute the sphere if subdivisions are not clamped
            else
                local convex = simpleton.New()
                MakeSphere( convex, 8, dx, dy, dz, threaded )

                if domePlane then
                    convex, _ = convex:Bisect( domePlane, true )
                end

                model.convexes = { convex.verts }

                util_Transform( convex.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
            end
        end
    else
        if physics then
            MakeSphere( model, math_min( subdiv, 8 ), dx, dy, dz, threaded )

            if domePlane then
                model, _ = model:Bisect( domePlane, true )
            end

            model.convexes = { model.verts }

            util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
        end
    end

    return model

end, { canThread = true } )


-- TORUS
registerType( "torus", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end
    local numring = param.PrimSUBDIV or 16
    if numring < 3 then numring = 3 elseif numring > 32 then numring = 32 end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( ( param.PrimDT or 1 ) * 0.5, dx, dy )

    if dt == dx or dt == dy then
    end

    local model = simpleton.New()

    if CLIENT then
        for j = 0, numring do
            for i = 0, maxseg do
                local u = i / maxseg * math_tau
                local v = j / numring * math_tau
                model:PushXYZ( ( dx + dt * math_cos( v ) ) * math_cos( u ), ( dy + dt * math_cos( v ) ) * math_sin( u ), dz * math_sin( v ) )
            end
        end

        for j = 1, numring do
            for i = 1, numseg do
                model:PushFace( ( maxseg + 1 ) * j + i, ( maxseg + 1 ) * ( j - 1 ) + i, ( maxseg + 1 ) * ( j - 1 ) + i + 1, ( maxseg + 1 ) * j + i + 1 )
            end
        end

        if numseg ~= maxseg then
            local cap1 = {}
            local cap2 = {}

            for j = 1, numring do
                cap1[#cap1 + 1] = ( maxseg + 1 ) * j + 1
                cap2[#cap2 + 1] = ( maxseg + 1 ) * ( numring - j ) + numseg + 1
            end

            model:PushFace( unpack( cap1 ) )
            model:PushFace( unpack( cap2 ) )
        end

        util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    if physics then
        local numring = math_min( 4, numring ) -- we want a lower detailed convexes model

        local convex = simpleton.New()
        local pverts = convex.verts

        for j = 0, numring do
            for i = 0, maxseg do
                local u = i / maxseg * math_tau
                local v = j / numring * math_tau
                convex:PushXYZ( ( dx + dt * math_cos( v ) ) * math_cos( u ), ( dy + dt * math_cos( v ) ) * math_sin( u ), dz * math_sin( v ) )
            end
        end

        local convexes = {}
        model.convexes = convexes

        for j = 1, numring do
            for i = 1, numseg do
                if not convexes[i] then
                    convexes[i] = {}
                end
                local part = convexes[i]
                part[#part + 1] = pverts[( maxseg + 1 ) * j + i]
                part[#part + 1] = pverts[( maxseg + 1 ) * ( j - 1 ) + i]
                part[#part + 1] = pverts[( maxseg + 1 ) * ( j - 1 ) + i + 1]
                part[#part + 1] = pverts[( maxseg + 1 ) * j + i + 1]
            end
        end

        util_Transform( pverts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    return model
end, { canthread = true } )


-- TUBE
registerType( "tube", function( param, data, threaded, physics )
    local verts, faces, convexes

    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then -- MAY NEED TO REFACTOR THIS IN THE FUTURE IF CYLINDER MODIFIERS ARE CHANGED
        local construct = construct_types.cylinder
        return construct.factory( param, construct.data, threaded, physics )
    end

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )
    local iscone = tx == 0 and ty == 0

    local model = simpleton.New()
    local verts = model.verts

    if iscone then
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
        end
    else
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx * tx ), math_cos( a ) * ( dy * ty ), dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
            model:PushXYZ( math_sin( a ) * ( ( dx - dt ) * tx ), math_cos( a ) * ( ( dy - dt ) * ty ), dz )
        end
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( 0, 0, dz )

    if CLIENT then
        if iscone then
            for i = 1, c0 - 2, 2 do
                model:PushFace( i + 3, i + 2, i + 0, i + 1 ) -- bottom
                model:PushTriangle( i + 0, i + 2, c2 ) -- outside
                model:PushTriangle( i + 3, i + 1, c2 ) -- inside
            end

            if numseg ~= maxseg then
                local i = numseg * 2 + 1
                model:PushTriangle( i, i + 1, c2 )
                model:PushTriangle( 2, 1, c2 )
            end
        else
            for i = 1, c0 - 4, 4 do
                model:PushFace( i + 0, i + 2, i + 6, i + 4 ) -- bottom
                model:PushFace( i + 4, i + 5, i + 1, i + 0 ) -- outside
                model:PushFace( i + 2, i + 3, i + 7, i + 6 ) -- inside
                model:PushFace( i + 5, i + 7, i + 3, i + 1 ) -- top
            end

            if numseg ~= maxseg then
                local i = numseg * 4 + 1
                model:PushFace( i + 2, i + 3, i + 1, i + 0 )
                model:PushFace( 1, 2, 4, 3 )
            end
        end
    end

    if physics then
        local convexes = {}
        model.convexes = convexes

        if iscone then
            for i = 1, c0 - 2, 2 do
                convexes[#convexes + 1] = { verts[c2], verts[i], verts[i + 1], verts[i + 2], verts[i + 3] }
            end
        else
            for i = 1, c0 - 4, 4 do
                convexes[#convexes + 1] = { verts[i], verts[i + 1], verts[i + 2], verts[i + 3], verts[i + 4], verts[i + 5], verts[i + 6], verts[i + 7] }
            end
        end
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- WEDGE
registerType( "wedge", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = util_MapF( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()
    local verts = model.verts

    if ty == 0 then
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, 0, dz )

    else
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, dy * ty, dz )
        model:PushXYZ( -dx * tx, -dy * ty, dz )

    end

    if CLIENT then
        if ty == 0 then
            model:PushTriangle( 1, 2, 5 )
            model:PushTriangle( 2, 4, 5 )
            model:PushTriangle( 4, 3, 5 )
            model:PushTriangle( 3, 1, 5 )
            model:PushFace( 3, 4, 2, 1 )

    else
            model:PushFace( 1, 2, 5, 6 )
            model:PushTriangle( 2, 4, 5 )
            model:PushFace( 4, 3, 6, 5 )
            model:PushTriangle( 3, 1, 6 )
            model:PushFace( 3, 4, 2, 1 )

        end
    end

    if physics then
        model.convexes = { verts }
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- WEDGE_CORNER
registerType( "wedge_corner", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = util_MapF( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = util_MapF( param.PrimTY or 0, -1, 1, 0, 2 )

    local model = simpleton.New()
    local verts = model.verts

    model:PushXYZ( dx, dy, -dz )
    model:PushXYZ( -dx, -dy, -dz )
    model:PushXYZ( -dx, dy, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        model:PushTriangle( 1, 3, 4 )
        model:PushTriangle( 2, 1, 4 )
        model:PushTriangle( 3, 2, 4 )
        model:PushTriangle( 1, 2, 3 )
    end

    if physics then
        model.convexes = { verts }
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- AIRFOIL
local function NACA4DIGIT( distr, points, chord, M, P, T, openEdge, ox, oy, oz )
    ox = ox or 0
    oy = oy or 0
    oz = oz or 0

    M = M * 0.01
    P = P * 0.01 -- should be *0.1 in real MPTT notation, but our value is in 100ths for interface clarity
    T = T * 0.01

    local a4
    if openEdge then a4 = 0.1015 else a4 = 0.1036 end

    local upper, lower = {}, {}

    for i = 0, points do
        local x = distr( i, points )
        local t = ( T / 0.2 ) * ( ( 0.2969 * math_sqrt( x ) ) - ( 0.1260 * x ) - ( 0.3516 * ( x ^ 2 ) ) + ( 0.2843 * ( x ^ 3 ) ) - ( a4 * ( x ^ 4 ) ) )

        local k, y

        if x > P then
            k = M / ( ( 1 - P ) ^ 2 )
            y = k * ( ( 1 - ( 2 * P ) ) + ( 2 * P * x ) - ( x ^ 2 ) )
        end

        if x <= P then
            if P == 0 then k = 0 else k = M / ( P ^ 2 ) end -- divide by zero!!!
            y = k * ( ( 2 * P * x ) - ( x ^ 2 ) )
        end

        local a = math_atan( k * ( ( 2 * P ) - ( 2 * x ) ) )

        local xu = x - ( math_sin( a ) * t )
        local yu = y + ( math_cos( a ) * t )
        local xl = x + ( math_sin( a ) * t )
        local yl = y - ( math_cos( a ) * t )

        upper[#upper + 1] = Vector( -xu * chord + ox, oy, yu * chord + oz )
        lower[#lower + 1] = Vector( -xl * chord + ox, oy, yl * chord + oz )
    end

    return upper, lower
end

registerType( "airfoil", function( param, data, threaded, physics )
    -- parameters
    local m = math_clamp( tonumber( param.PrimAFM ) or 0, 0, 9.5 )
    local p = math_clamp( tonumber( param.PrimAFP ) or 0, 0, 90 )
    local t = math_clamp( tonumber( param.PrimAFT ) or 0, 1, 40 )

    local c0 = math_clamp( tonumber( param.PrimCHORDR ) or 1, 1, 2000 )
    local c1 = math_clamp( tonumber( param.PrimCHORDT ) or 1, 1, 2000 )

    local openEdge = tobool( param.PrimAFOPEN )
    local flipModel = tobool( param.PrimAFFLIP )

    local wingSpan = tonumber( param.PrimSPAN ) or 1
    local wingSweep = math_sin( math_rad( ( tonumber( param.PrimSWEEP ) or 0 ) * 1 ) ) * ( wingSpan + c0)
    local wingDihedral = math_sin( math_rad( ( tonumber( param.PrimDIHEDRAL ) or 0 ) * 1 ) ) * ( wingSpan + c0 )

    local bits = tonumber( param.PrimCSOPT ) or 0
    local controlSurface = bit.band( bits, 1 ) == 1
    local controlSurfaceInvert = bit.band( bits, 2 ) == 2

    -- path
    local points = 15

    local a0u, a0l = NACA4DIGIT( util_Ease.cosine, points, c0, m, p, t, openEdge )
    local a1u, a1l = NACA4DIGIT( util_Ease.cosine, points, c1, m, p, t, openEdge, wingSweep, wingSpan, wingDihedral )

    local pcount = #a0u         -- point count
    local tcount = pcount * 2   -- upper + lower point count
    local scount = 2            -- number of sections, will need to be fixed in the future if i want to add a curve modifier
                                -- currently the left/right clipper cant handle more than 2
    -- model
    local mapHU0 = 1 + tcount
    local mapHU1 = 3 + tcount
    local mapHU2 = 3
    local mapHU3 = 1

    local mapHL0 = 2
    local mapHL1 = 4
    local mapHL2 = 4 + tcount
    local mapHL3 = 2 + tcount

    local function insert( simp, d, fill, side, convex )
        for j = 1, pcount do
            local p0u = a0u[j]
            local p1u = a1u[j]

            local p0l = a0l[j]
            local p1l = a1l[j]

            local pu = ( 1 - d ) * p0u + d * p1u
            local pl = ( 1 - d ) * p0l + d * p1l

            local n = #simp.verts
            simp:PushVertex( pu )
            simp:PushVertex( pl )

            if j < pcount then
                if d < 1 and fill then
                    simp:PushTriangle( mapHU0 + n, mapHU1 + n, mapHU2 + n )
                    simp:PushTriangle( mapHU0 + n, mapHU2 + n, mapHU3 + n )
                    simp:PushTriangle( mapHL0 + n, mapHL1 + n, mapHL2 + n )
                    simp:PushTriangle( mapHL0 + n, mapHL2 + n, mapHL3 + n )
                end
                if side == -1 then
                    simp:PushTriangle( n + 1, n + 3, n + 4 )
                    simp:PushTriangle( n + 1, n + 4, n + 2 )
                elseif side == 1  then
                    simp:PushTriangle( n + 2, n + 4, n + 3 )
                    simp:PushTriangle( n + 2, n + 3, n + 1 )
                end
            else
                if openEdge and d < 1 and fill then -- trailing edge
                    simp:PushTriangle( mapHU0 + n, mapHL3 + n, n + 2 )
                    simp:PushTriangle( mapHU0 + n, n + 2, n + 1 )
                end
            end
        end
    end

    local ypos = param.PrimCSYPOS
    local ylen = param.PrimCSYLEN
    local xlen = param.PrimCSXLEN

    local model

    if controlSurface and ylen > 0 and xlen > 0 then
        local rclipF = ypos
        local lclipF = math_min( ypos + ylen, 1 )

        local rclipI = math_floor( rclipF * scount )
        local lclipI = math_floor( lclipF * scount )

        local a = ( a0u[#a1u] + a0l[#a1l] ) * 0.5
        local b = ( a1u[#a1u] + a1l[#a1l] ) * 0.5

        local clipPos = ( 1 - ypos ) * a + ypos * b
        local clipDir = a - b
        local clipTan = Vector( 1, 0, 0 )

        local x = c0 + ( c1 - c0 ) * math_min(1, ypos + ( c0 > c1 and ylen or 0 ) )
        clipPos = clipPos + clipTan * x * xlen

        if controlSurfaceInvert then
            if ypos < 1 then
                local model_r = simpleton.New()

                insert( model_r, rclipF, true, -1 )
                insert( model_r, lclipF, false, 1 )

                vec_normalize( clipDir )
                clipDir = vec_cross( clipDir, Vector( 0, 0, 1 ) )

                local clipped_model_r, _ = model_r:Bisect( { pos = clipPos, normal = clipDir }, true, false )

                if clipped_model_r then
                    model = clipped_model_r

                    if flipModel then
                         model:Mirror( Vector(), Vector( 0, 1, 0 ) )
                    end

                    --model:Translate( -clipPos )

                    if physics then
                        model.convexes = { model.verts }
                    end
                end
            end
        else
            local model_f = simpleton.New()
            local model_r = simpleton.New()

            for i = 0, scount - 1 do
                local d = i / ( scount - 1 )

                -- leading edge
                local side
                if i == 0 then side = -1 elseif i == scount - 1 then side = 1 end

                insert( model_f, d, true, side )

                -- trailing edge
                if i == rclipI and d > rclipF then insert( model_r, rclipF, false, 1 ) end
                if i == lclipI and d > lclipF then insert( model_r, lclipF, true, -1 ) end

                local side
                if i == 0 then
                    side = -1
                    if rclipF <= 0 then side = nil end
                elseif i == scount - 1 then
                    side = 1
                    if lclipF >= 1 then side = nil end
                end

                insert( model_r, d, rclipF > 0, side )

                if i == rclipI and d < rclipF then insert( model_r, rclipF, false, 1 ) end
                if i == lclipI and d < lclipF then insert( model_r, lclipF, true, -1 ) end
            end

            vec_normalize( clipDir )
            clipDir = vec_cross( clipDir, Vector( 0, 0, 1 ) )

            local clipped_model_f, _ = model_f:Bisect( { pos = clipPos, normal = -clipDir }, true, false )
            local clipped_model_r, _ = model_r:Bisect( { pos = clipPos, normal = clipDir }, false, false )

            if clipped_model_f and clipped_model_r then
                model = simpleton.New()

                if flipModel then
                    clipped_model_f:Mirror( Vector(), Vector( 0, 1, 0 ) )
                    clipped_model_r:Mirror( Vector(), Vector( 0, 1, 0 ) )
                end

                --clipped_model_f:Translate( -clipPos )
                --clipped_model_r:Translate( -clipPos )

                model:Merge( clipped_model_f )
                model:Merge( clipped_model_r )

                if physics then
                    local center = wingSpan * ( ypos + ylen * 0.5 )
                    if flipModel then center = -center end

                    local left, right = {}, {}

                    for i = 1, #clipped_model_r.verts do
                        local v = clipped_model_r.verts[i]
                        if v.y < center then left[#left + 1] = v else right[#right + 1] = v end
                    end

                    model.convexes = { clipped_model_f.verts, left, right }
                end
            end
        end
    end

    if not model then
        model = simpleton.New()

        for i = 0, scount - 1 do
            local d = i / ( scount - 1 )

            local side
            if i == 0 then side = -1 elseif i == scount - 1 then side = 1 end

            insert( model, d, true, side )
        end

        if physics then
            model.convexes = { model.verts }
        end

        if flipModel then
            model:Mirror( Vector(), Vector( 0, 1, 0 ) )
        end
    end

    return model
end )


-- RAIL SLIDER
registerType( "rail_slider", function( param, data, threaded, physics )
    local model = simpleton.New()
    model.convexes = {}

    -- base
    local bpos = isvector( param.PrimBPOS ) and Vector( param.PrimBPOS ) or Vector( 1, 1, 1 )
    local bdim = isvector( param.PrimBDIM ) and Vector( param.PrimBDIM ) or Vector( 1, 1, 1 )

    bpos.z = bpos.z + bdim.z * 0.5

    -- contact point
    local cpos = isvector( param.PrimCPOS ) and Vector( param.PrimCPOS ) or Vector( 1, 1, 1 )
    local crot = isangle( param.PrimCROT ) and Angle( param.PrimCROT ) or Angle()
    local cdim = isvector( param.PrimCDIM ) and Vector( param.PrimCDIM ) or Vector( 1, 1, 1 )

    cpos.y = cpos.y + cdim.y * 0.5
    cpos.z = cpos.z + cdim.z * 0.5

    -- base
    if tobool( param.PrimBASE ) then
        model:PushPrefab( "cube", bpos, nil, bdim, CLIENT, model.convexes )
    end

    -- contact point
    local ctype = tostring( param.PrimCTYPE )
    local cbits = math_floor( tonumber( param.PrimCENUMS ) or 0 )

    local cgap = tonumber( param.PrimCGAP ) or 0
    cgap = cgap + cdim.y

    local flip = {
        Vector( 1, 1, 1 ), -- front left
        Vector( 1, -1, 1 ), -- front right
        Vector( -1, 1, 1 ), -- rear left
        Vector( -1, -1, 1 ), -- rear right
    }

    local ENUM_CDOUBLE = 16
    local double = bit.band( cbits, ENUM_CDOUBLE ) == ENUM_CDOUBLE

    -- flange
    local fbits, getflange = math_floor( tonumber( param.PrimFENUMS ) or 0 )

    local ENUM_FENABLE = bit.bor( 1, 2, 4, 8 )
    if bit.band( fbits, ENUM_FENABLE ) ~= 0 then
        local fdim
        if double then
            fdim = Vector( cdim.x, cgap - cdim.y, cdim.z * 0.25 )
        else
            fdim = Vector( cdim.x, tonumber( param.PrimFGAP ) or 1, cdim.z * 0.25 )
        end

        if fdim.y > 0 then
            local ftype = tostring( param.PrimFTYPE )

            function getflange( i, pos, rot, side )
                local s = bit.lshift( 1, i - 1 )

                if bit.band( fbits, s ) == s then
                    local pos = Vector( pos )

                    pos = pos - ( rot:Right() * ( fdim.y * 0.5 + cdim.y * 0.5 ) * side.y )
                    pos = pos + ( rot:Up() * ( cdim.z * 0.5 - fdim.z * 0.5 ) )

                    model:PushPrefab( ftype, pos, rot, fdim, CLIENT, model.convexes )
                end
            end
        end
    end

    -- builder
    for i = 1, 4 do
        local side = bit.lshift( 1, i - 1 )

        if bit.band( cbits, side ) == side then
            side = flip[i]

            local pos = cpos * side
            local rot = Angle( -crot.p * side.x, crot.y * side.x * side.y, crot.r * side.y )

            pos.x = pos.x + ( cdim.x * side.x * 0.5 )
            model:PushPrefab( ctype, pos, rot, cdim, CLIENT, model.convexes )

            if getflange then getflange( i, pos, rot, side ) end

            if double then
                pos = pos - ( rot:Right() * side.y * cgap )
                model:PushPrefab( ctype, pos, rot, cdim, CLIENT, model.convexes )
            end
        end
    end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, thread )

    return model
end )


-- STAIRCASE
registerType( "staircase", function( param, data, threaded, physics )
    local count = math_clamp( math_floor( tonumber( param.PrimSCOUNT ) or 0 ), 1, 32 )
    local rise = math_clamp( tonumber( param.PrimSRISE ) or 0, 1, 50 )
    local run = math_clamp( tonumber( param.PrimSRUN ) or 0, 1, 50 )
    local width = math_clamp( ( tonumber( param.PrimSWIDTH ) or 0 ) * 0.5, 1, 1000 )

    local model = simpleton.New()
    local verts = model.verts

    if physics then
        model.convexes = {}
    end

    for i = 0, count - 1 do
        local a = model:PushXYZ( run * i, width, rise * i )
        local b = model:PushXYZ( run * i, width, rise * i + rise )
        local c = model:PushXYZ( run * i + run, width, rise * i + rise )

        local d = model:CopyVertex( a, nil, -width, nil )
        local e = model:CopyVertex( b, nil, -width, nil )
        local f = model:CopyVertex( c, nil, -width, nil )

        if physics then
            model.convexes[#model.convexes + 1] = {
                verts[a],
                verts[b],
                verts[c],
                verts[d],
                verts[e],
                verts[f],
            }
        end

        if CLIENT then
            model:PushTriangle( a, b, c ) -- riser
            model:PushTriangle( f, e, d )

            model:PushTriangle( b, a, d ) -- face
            model:PushTriangle( b, d, e )

            model:PushTriangle( c, b, e ) -- tread
            model:PushTriangle( c, e, f )
        end
    end

    local isSolid = bit.band( tonumber( param.PrimSOPT ) or 0, 1 ) == 1

    if isSolid then
        local a = model:PushXYZ( run * count, width,  0 )
        local b = model:PushXYZ( run * count, -width,  0 )

        if physics then
            model.convexes[#model.convexes + 1] = {
                verts[count * 6 - 3],
                verts[count * 6],
                verts[1],
                verts[4],
                verts[a],
                verts[b]
            }
        end

        if CLIENT then
            model:PushTriangle( count * 6 - 3, a, 1 ) -- side
            model:PushTriangle( 4, b, count * 6 )

            model:PushTriangle( b, a, count * 6 - 3 ) -- back
            model:PushTriangle( b, count * 6 - 3, count * 6 )

            model:PushTriangle( 1, a, b ) -- bottom
            model:PushTriangle( 1, b, 4 )
        end
    else
        if CLIENT then
            model:PushTriangle( count * 6 - 3, count * 6, 4 )
            model:PushTriangle( count * 6 - 3, 4, 1 )
        end
    end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- LADDER
registerType( "ladder", function( param, data, threaded, physics )
    local model = simpleton.New()
    local verts = model.verts

    if physics then
        model.convexes = {}
    end

    local isSolid = bit.band( tonumber( param.PrimSOPT ) or 0, 1 ) == 1

    local count = math_clamp( math_floor( tonumber( param.PrimSCOUNT ) or 0 ), 1, 32 )
    local height = math_clamp( tonumber( param.PrimSHEIGHT ) or 0, 1, 50 )

    -- rung
    local rdim = isvector( param.PrimRDIM ) and Vector( param.PrimRDIM ) or Vector( 1, 1, 1 )

    local rx = math_clamp( rdim.x, 1, 1000 )
    local ry = math_clamp( rdim.y, 1, 1000 )
    local rz = math_min( height, math_clamp( rdim.z, 1, 50 ) )

    for i = 0, count - 1 do
        model:PushPrefab( "cube", Vector( 0, 0, height * i ), Angle(), Vector( rx, ry, rz ), CLIENT, not isSolid and model.convexes )
    end

    if isSolid and physics then
        local size = height * ( count - 1 )
        model:PushPrefab( "cube", Vector( 0, 0, size * 0.5 ), Angle(), Vector( rx, ry, size + rz ), nil, model.convexes )
    end

    -- rail
    if count > 1 and bit.band( tonumber( param.PrimSOPT ) or 0, 2 ) == 2 then
        local xdim = isvector( param.PrimXDIM ) and Vector( param.PrimXDIM ) or Vector( 1, 1, 1 )

        local xx = math_clamp( xdim.x, 1, 1000 )
        local xy = math_clamp( xdim.y, 1, 1000 )
        local xz = math_clamp( xdim.z, 1, 50 )

        local xsize = Vector( xx, xy, height * ( count - 1 ) + xz )

        model:PushPrefab( "cube", Vector( 0, ry * 0.5 + xy * 0.5, xsize.z * 0.5 - xz * 0.5 ), Angle(), xsize, CLIENT, model.convexes )
        model:PushPrefab( "cube", Vector( 0, -ry * 0.5 - xy * 0.5, xsize.z * 0.5 - xz * 0.5 ), Angle(), xsize, CLIENT, model.convexes )
    end

    util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- PARALLELOGRAM
-- Ported from the primitive addon. This library is a fork, so a type only the addon knows
-- about falls through to the error model, and its clips then cut up a 24 unit cube instead.
registerType( "parallelogram", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local shift = tonumber( param.PrimSLANT ) or 0

    local model = simpleton.New()
    local verts = model.verts

    -- Bottom face at z=-dz is unshifted; all horizontal offset goes to the top face.
    -- The entity origin sits at the center of the bottom face.
    model:PushXYZ(  dx,          dy, -dz )  -- 1 bottom y+ x+
    model:PushXYZ(  dx,         -dy, -dz )  -- 2 bottom y- x+
    model:PushXYZ( -dx,         -dy, -dz )  -- 3 bottom y- x-
    model:PushXYZ( -dx,          dy, -dz )  -- 4 bottom y+ x-
    model:PushXYZ(  dx + shift,  dy,  dz )  -- 5 top y+ x+
    model:PushXYZ(  dx + shift, -dy,  dz )  -- 6 top y- x+
    model:PushXYZ( -dx + shift, -dy,  dz )  -- 7 top y- x-
    model:PushXYZ( -dx + shift,  dy,  dz )  -- 8 top y+ x-

    if CLIENT then
        model:PushFace( 1, 2, 3, 4 )  -- bottom (-z)
        model:PushFace( 5, 8, 7, 6 )  -- top (+z)
        model:PushFace( 1, 4, 8, 5 )  -- y+ side
        model:PushFace( 2, 6, 7, 3 )  -- y- side
        model:PushFace( 2, 1, 5, 6 )  -- x+ side (slanted)
        model:PushFace( 4, 3, 7, 8 )  -- x- side (slanted)
    end

    if physics then
        model.convexes = { verts }
    end

    util_Transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- DOME_HOLLOW
-- Ported from the primitive addon, see the note on parallelogram above
local function pushHollowRings( model, maxseg2, numseg2, maxseg, numseg, dx, dy, dz, idx, idy, idz )
    for r = 0, numseg2 do
        local t = math_pi * 0.5 * ( 1 - r / maxseg2 )
        local sinT, cosT = math_sin( t ), math_cos( t )
        for v = 0, numseg do
            local p = math_tau * v / maxseg
            model:PushXYZ( -dx  * math_cos( p ) * sinT, dy  * math_sin( p ) * sinT, dz  * cosT )  -- outer
            model:PushXYZ( -idx * math_cos( p ) * sinT, idy * math_sin( p ) * sinT, idz * cosT )  -- inner
        end
    end
end

registerType( "dome_hollow", function( param, data, threaded, physics )
    local maxseg  = param.PrimMAXSEGH or 1
    local numseg  = param.PrimNUMSEGH or 1
    local maxseg2 = param.PrimMAXSEGV or 1
    local numseg2 = param.PrimNUMSEGV or 1

    -- Legacy subdiv param will always come with these set to 1. Backwards compatibility measure.
    -- Normally you wouldn't set these anyways (degenerate cases)
    if maxseg == 1 and numseg == 1 and maxseg2 == 1 and numseg2 == 1 then
        local subdiv = math_clamp( 2 * math_round( ( param.PrimSUBDIV or 8 ) / 2 ), 4, 32 )
        maxseg, numseg = subdiv, subdiv
        maxseg2, numseg2 = subdiv / 2, subdiv / 2
    end

    -- Horizontal (longitude) arc: numseg of maxseg segments around the full 360 degrees.
    maxseg = math_clamp( maxseg, 1, 16 )
    numseg = math_clamp( numseg, 1, maxseg )

    -- Vertical (latitude) arc: numseg2 of maxseg2 segments over the 90 degrees from equator to apex.
    maxseg2 = math_clamp( maxseg2, 1, 8 )
    numseg2 = math_clamp( numseg2, 1, maxseg2 )

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_max( math_min( param.PrimDT or 1, dx - MinSize, dy - MinSize, dz - MinSize ), MinSize )

    local idx = dx - dt
    local idy = dy - dt
    local idz = dz - dt

    local ringSize = numseg + 1     -- verts per ring: numseg segments need numseg+1 verts to span the arc
    local twoRing  = ringSize * 2   -- stride per ring in interleaved layout

    local model = simpleton.New()

    if CLIENT then
        pushHollowRings( model, maxseg2, numseg2, maxseg, numseg, dx, dy, dz, idx, idy, idz )

        -- Emit quad strips between adjacent rings. Each ring occupies twoRing slots,
        -- so adding twoRing to an index moves to the same position one ring toward the apex.
        for r = 1, numseg2 do
            for v = 0, numseg - 1 do
                local a = 1 + ( r - 1 ) * twoRing + v * 2  -- bottom-left outer
                local d = a + twoRing                       -- top-left outer
                model:PushFace( d, d + 2, a + 2, a )           -- outer, outward normals
                model:PushFace( a + 1, a + 3, d + 3, d + 1 )  -- inner, inward normals
            end
        end

        -- Close the open bottom edge with a ring of rim quads connecting outer equator to inner equator.
        for v = 0, numseg - 1 do
            local ao = 1 + v * 2
            model:PushFace( ao, ao + 2, ao + 3, ao + 1 )  -- rim, downward normals
        end

        -- A partial vertical arc stops short of the apex, so close that ring too.
        if numseg2 ~= maxseg2 then
            local top = 1 + numseg2 * twoRing
            for v = 0, numseg - 1 do
                local ao = top + v * 2
                model:PushFace( ao + 1, ao + 3, ao + 2, ao )  -- cap, upward normals
            end
        end

        -- When the arc is partial, cap the two cut edges with wall quads spanning outer to inner.
        if numseg ~= maxseg then
            for r = 1, numseg2 do
                local aStart = 1 + ( r - 1 ) * twoRing
                local dStart = aStart + twoRing
                model:PushFace( aStart, aStart + 1, dStart + 1, dStart )

                local aEnd = aStart + numseg * 2
                local dEnd = aEnd + twoRing
                model:PushFace( aEnd, dEnd, dEnd + 1, aEnd + 1 )
            end
        end

        util_Transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    if physics then
        -- Limit physics to 8 * 4 = 32 convexes at most.
        local physMaxseg  = math_min( maxseg, 8 )
        local physNumseg  = math_max( math_round( numseg * physMaxseg / maxseg ), 1 )
        local physMaxseg2 = math_min( maxseg2, 4 )
        local physNumseg2 = math_max( math_round( numseg2 * physMaxseg2 / maxseg2 ), 1 )
        local physTwoRing = ( physNumseg + 1 ) * 2
        local physModel   = simpleton.New()
        local physVerts   = physModel.verts

        pushHollowRings( physModel, physMaxseg2, physNumseg2, physMaxseg, physNumseg, dx, dy, dz, idx, idy, idz )

        -- One convex per patch: four outer corners + four inner corners of each wall quad.
        -- This approximates the hollow shell as a set of thin wedge-shaped convex hulls.
        local convexes = {}
        for r = 0, physNumseg2 - 1 do
            for v = 0, physNumseg - 1 do
                local oa = 1 + r * physTwoRing + v * 2  -- bottom-left outer
                local od = oa + physTwoRing             -- top-left outer
                convexes[#convexes + 1] = {
                    physVerts[oa],     physVerts[oa + 2], physVerts[od],     physVerts[od + 2],  -- outer quad corners
                    physVerts[oa + 1], physVerts[oa + 3], physVerts[od + 1], physVerts[od + 3],  -- inner quad corners
                }
            end
        end

        model.convexes = convexes
        util_Transform( physVerts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    return model
end )
