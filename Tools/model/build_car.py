"""Simplifie le GLB Sketchfab et exporte Car.usdz pour RealityKit.

Usage : blender -b --python Tools/model/build_car.py -- <in.glb> <out.usdz> [target_tris]

Repère de sortie (USD, Y-up, mètres) : origine au sol au centre de la voiture,
avant = +Z, gauche = +X. Pivots animables :
  Wheel_FL_Steer/Wheel_FL_Spin, Wheel_FR_Steer/Wheel_FR_Spin,
  Wheel_RL_Steer/Wheel_RL_Spin, Wheel_RR_Steer/Wheel_RR_Spin,
  Door_FL, Door_FR, Hood, Trunk, Body
"""
import sys, bpy, bmesh, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
TARGET = int(argv[2]) if len(argv) > 2 else 100_000
MAX_TEX = 1024

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:  # données partagées -> uniques avant de cuire les transforms
    if o.data.users > 1:
        o.data = o.data.copy()

# 1. Cuire les transforms monde (x100 : le modèle est en 1/100 m), supprimer les empties
S = mathutils.Matrix.Scale(100.0, 4)
for o in meshes:
    mw = S @ o.matrix_world
    o.parent = None
    o.data.transform(mw)
    o.matrix_world = mathutils.Matrix.Identity(4)
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o)

# 2. Recentrer : sol à z=0, centre en x/y
def bounds(objs):
    vs = [v.co for o in objs for v in o.data.vertices]
    mn = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx

mn, mx = bounds(meshes)
off = mathutils.Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
for o in meshes:
    o.data.transform(mathutils.Matrix.Translation(off))
mn, mx = bounds(meshes)
print(f"CAR SIZE (m) w={mx.x-mn.x:.3f} l={mx.y-mn.y:.3f} h={mx.z-mn.z:.3f}")

# 3. Décimation proportionnelle
def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
total = sum(tris(o) for o in meshes)
ratio = min(1.0, TARGET / total)
print(f"TRIS before={total} ratio={ratio:.3f}")
for o in meshes:
    if tris(o) > 1500 and ratio < 1.0:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
print(f"TRIS after={sum(tris(o) for o in meshes)}")

# 4. Classement en groupes animables (Blender : avant = -Y, gauche = +X)
def group_of(name):
    n = name
    if "Ani_Wheel_FL" in n: return "Wheel_FL_Spin"
    if "Ani_Disc_Scale_FR" in n: return "Wheel_FR_Spin"
    if "Ani_Wheel_BL" in n: return "Wheel_RL_Spin"
    if "Ani_Disc_Scale_BR" in n: return "Wheel_RR_Spin"
    if "Caliper_FL" in n: return "Wheel_FL_Steer"
    if "Caliper_FR" in n: return "Wheel_FR_Steer"
    if "Caliper_BR" in n: return "Wheel_RR_Steer"
    if "SK_Door_FL" in n or "Carwindow_FL" in n: return "Door_FL"
    if "SK_Door_FR" in n or "Ani_Door_FR" in n: return "Door_FR"
    if "SK_Hood" in n: return "Hood"
    if "SK_Trunk" in n: return "Trunk"
    return "Body"

groups = {}
for o in meshes:
    groups.setdefault(group_of(o.name), []).append(o)

def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.matrix_parent_inverse = parent.matrix_world.inverted()
    e.location = loc if parent is None else parent.matrix_world.inverted() @ loc
    return e

root = empty("Car", mathutils.Vector())

def attach(objs, parent):
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
        o.matrix_world = mw

attach(groups.get("Body", []), empty("Body", mathutils.Vector(), root))

# Roues : pivot de braquage + pivot de rotation au centre de la roue
for w in ("FL", "FR", "RL", "RR"):
    spin = groups.get(f"Wheel_{w}_Spin", [])
    if not spin:
        print("WARN missing wheel", w); continue
    a, b = bounds(spin)
    c = (a + b) / 2
    steer = empty(f"Wheel_{w}_Steer", c, root)
    bpy.context.view_layer.update()
    attach(groups.get(f"Wheel_{w}_Steer", []), steer)
    sp = empty(f"Wheel_{w}_Spin", c, steer)
    bpy.context.view_layer.update()
    attach(spin, sp)

def hinge(name, pick):
    objs = groups.get(name, [])
    if not objs:
        print("WARN missing", name); return
    a, b = bounds(objs)
    e = empty(name, pick(a, b), root)
    bpy.context.view_layer.update()
    attach(objs, e)

# Portes : charnière bord avant, côté extérieur ; capot : bord arrière haut ; coffre : bord avant haut
hinge("Door_FL", lambda a, b: mathutils.Vector((b.x, a.y, (a.z + b.z) / 2)))
hinge("Door_FR", lambda a, b: mathutils.Vector((a.x, a.y, (a.z + b.z) / 2)))
hinge("Hood", lambda a, b: mathutils.Vector((0, b.y, b.z)))
hinge("Trunk", lambda a, b: mathutils.Vector((0, a.y, b.z)))

# 5. Textures réduites, verres translucides
for img in bpy.data.images:
    if img.size[0] > MAX_TEX or img.size[1] > MAX_TEX:
        f = MAX_TEX / max(img.size)
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
        img.pack()
for mat in bpy.data.materials:
    if not mat.use_nodes: continue
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf and "glass" in mat.name.lower():
        bsdf.inputs["Alpha"].default_value = 0.6 if "red" in mat.name.lower() else 0.3
        for l in list(bsdf.inputs["Alpha"].links):
            mat.node_tree.links.remove(l)
        tr = bsdf.inputs.get("Transmission Weight")
        if tr: tr.default_value = 0.0

# 6. Export USDZ (Y-up, avant Blender -Y -> USD +Z)
bpy.ops.wm.usd_export(
    filepath=DST,
    export_materials=True,
    generate_preview_surface=True,
    export_textures_mode="NEW",
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y",
    root_prim_path="",
)
print("EXPORTED", DST)
