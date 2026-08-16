
-------------------------------
-- PRIMITIVE COMPAT
--
-- prop2mesh no longer bundles its own copy of the primitives construct library.
-- Instead, if the "primitive" addon ( by shadowscion ) is installed, its construct
-- library is reused directly. This avoids maintaining the same ~3000 line file in
-- two places, and means prop2mesh only supports primitive parts when the addon that
-- actually creates them is present.
--
-- If Primitives loads after prop2mesh (might not happen due to legacy addon sorting (pri before pro)
-- but still), then the global table Primitive is not available at this point. This is just for safety.
-------------------------------

prop2mesh.primitive = setmetatable({}, {__index = function(_, key) return Primitive[key] end})
