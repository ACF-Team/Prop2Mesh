
-------------------------------
-- PRIMITIVE COMPAT
--
-- prop2mesh no longer bundles its own copy of the primitives construct library.
-- Instead, if the "primitive" addon ( by shadowscion ) is installed, its construct
-- library is reused directly. This avoids maintaining the same ~3000 line file in
-- two places, and means prop2mesh only supports primitive parts when the addon that
-- actually creates them is present.
--
-- The primitive addon defines its Primitive global before prop2mesh loads ( autorun
-- files include alphabetically, and "primitive" sorts before "prop2mesh" ), so the
-- alias below is populated whenever the addon is installed. All prop2mesh code that
-- touches primitives must nil-check prop2mesh.primitive first, since it stays nil
-- when the addon is absent.
-------------------------------

prop2mesh.primitive = Primitive
