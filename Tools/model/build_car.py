"""Prépare Car.usdz pour RealityKit à partir du GLB Sketchfab.

Usage : blender -b --python Tools/model/build_car.py -- <in.glb> <out_dir>
Puis : python Tools/model/package_usdz.py <out_dir>/Car.usdc App/Resources/Car.usdz

Sortie (USD, Y-up, mètres, AUCUNE rotation sur les nœuds) : origine au sol au centre,
avant = +Z, gauche = +X. Hiérarchie :
  Car
  ├─ Sprung (masse suspendue, pivot au centre de gravité)
  │   ├─ Body
  │   ├─ Door_FL, Door_FR   (pivot = charnière avant)
  │   ├─ Hood                (pivot = bord arrière haut)
  │   └─ Trunk               (pivot = bord avant haut)
  └─ Wheel_{FL,FR,RL,RR}_Steer (pivot = centre roue) └─ Wheel_*_Spin
Carrosserie en pleine résolution ; seul l'intérieur et le moteur sont décimés.
Peinture carrosserie : blanc nacré.
"""
import os
import sys

import bpy
import mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
MAX_TEX = 1024
INTERIOR_RATIO = 0.2
PAINT = "FiestaMI_1080040001_004"
INTERIOR = ("Cabin", "Engine", "Dashboard")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    if o.data.users > 1:
        o.data = o.data.copy()

# 1. Cuire transforms monde, x100 (modèle en 1/100 m) et passage Z-up -> Y-up :
#    (x, y, z)_blender -> (x, z, -y)  => avant (-Y blender) devient +Z, haut devient +Y.
TO_YUP = mathutils.Matrix(((1, 0, 0, 0), (0, 0, 1, 0), (0, -1, 0, 0), (0, 0, 0, 1)))
S = TO_YUP @ mathutils.Matrix.Scale(100.0, 4)
for o in meshes:
    mw = S @ o.matrix_world
    o.parent = None
    o.data.transform(mw)
    if mw.determinant() < 0:
        o.data.flip_normals()
    o.matrix_world = mathutils.Matrix.Identity(4)
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o)


def bounds(objs):
    vs = [v.co for o in objs for v in o.data.vertices]
    mn = mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


# 2. Recentrer : sol y=0, centre x/z
mn, mx = bounds(meshes)
off = mathutils.Vector((-(mn.x + mx.x) / 2, -mn.y, -(mn.z + mx.z) / 2))
for o in meshes:
    o.data.transform(mathutils.Matrix.Translation(off))
mn, mx = bounds(meshes)
print(f"CAR SIZE (m) w={mx.x-mn.x:.3f} h={mx.y-mn.y:.3f} l={mx.z-mn.z:.3f}")


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def is_interior(o):
    return any(s.material and any(k in s.material.name for k in INTERIOR) for s in o.material_slots)


# 3. Décimation de l'intérieur / moteur uniquement
print(f"TRIS before={sum(tris(o) for o in meshes)}")
for o in meshes:
    if is_interior(o) and tris(o) > 500:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = INTERIOR_RATIO
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=m.name)
print(f"TRIS after={sum(tris(o) for o in meshes)}")


# 4. Groupes (repère Y-up : gauche = +X, avant = +Z)
def group_of(n):
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


def node(name, world_pos, parent=None):
    """Empty sans rotation à une position monde ; parent_inverse = identité."""
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent is not None:
        e.parent = parent
        e.matrix_parent_inverse = mathutils.Matrix.Identity(4)
    e.matrix_world = mathutils.Matrix.Translation(world_pos)
    bpy.context.view_layer.update()
    return e


def attach(objs, parent):
    for o in objs:
        o.parent = parent
        o.matrix_parent_inverse = mathutils.Matrix.Identity(4)
        o.matrix_world = mathutils.Matrix.Identity(4)  # la géométrie est déjà en monde
    bpy.context.view_layer.update()


car = node("Car", mathutils.Vector())
sprung = node("Sprung", mathutils.Vector((0, 0.5, 0)), car)
attach(groups.get("Body", []), node("Body", mathutils.Vector((0, 0.5, 0)), sprung))

for w in ("FL", "FR", "RL", "RR"):
    spin = groups.get(f"Wheel_{w}_Spin", [])
    if not spin:
        print("WARN missing wheel", w)
        continue
    a, b = bounds(spin)
    c = (a + b) / 2
    steer = node(f"Wheel_{w}_Steer", c, car)
    attach(groups.get(f"Wheel_{w}_Steer", []), steer)
    attach(spin, node(f"Wheel_{w}_Spin", c, steer))


def hinge(name, pick):
    objs = groups.get(name, [])
    if not objs:
        print("WARN missing", name)
        return
    a, b = bounds(objs)
    attach(objs, node(name, pick(a, b), sprung))


hinge("Door_FL", lambda a, b: mathutils.Vector((b.x, (a.y + b.y) / 2, b.z)))
hinge("Door_FR", lambda a, b: mathutils.Vector((a.x, (a.y + b.y) / 2, b.z)))
hinge("Hood", lambda a, b: mathutils.Vector((0, b.y, a.z)))
hinge("Trunk", lambda a, b: mathutils.Vector((0, b.y, b.z)))

# 4 ter. Emplacements des clignotants : angle extérieur des vrais feux (phares / feux arrière).
def light_corner(keys, side, front):
    pts = [v.co.copy() for o in meshes if any(k in o.name for k in keys)
           for v in o.data.vertices if (v.co.x > 0) == (side > 0)]
    if not pts:
        print("WARN pas de feux pour", keys, side)
        return None
    outer = max(abs(p.x) for p in pts)
    sel = [p for p in pts if abs(p.x) > outer - 0.10]
    # extrémité avant (phares) ou arrière (feux) parmi la partie extérieure
    zs = sorted(p.z for p in sel)
    zref = zs[-1] if front else zs[0]
    sel = [p for p in sel if abs(p.z - zref) < 0.18] or sel
    c = sum(sel, mathutils.Vector()) / len(sel)
    return c


for key, keys, front in (("F", ("SM_Light_F",), True), ("R", ("SM_Light_B", "red_glass"), False)):
    for side, name in ((1, "L"), (-1, "R")):
        c = light_corner(keys, side, front)
        if c is not None:
            node(f"Blinker_{key}{name}", c, sprung)
            print(f"BLINKER {key}{name} ({c.x:+.2f}, {c.y:+.2f}, {c.z:+.2f})")

# 4 bis. Fusion des maillages par (groupe, matériau) : beaucoup moins d'appels de dessin.
def join_by_material(parent):
    kids = [o for o in parent.children if o.type == "MESH"]
    buckets = {}
    for o in kids:
        mat = o.material_slots[0].material.name if o.material_slots and o.material_slots[0].material else "none"
        buckets.setdefault(mat, []).append(o)
    for mat, objs in buckets.items():
        if len(objs) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for o in objs:
                o.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.object.join()
        objs[0].name = f"{parent.name}_{mat}"
        objs[0].data.name = objs[0].name


for e in [o for o in bpy.data.objects if o.type == "EMPTY"]:
    join_by_material(e)
print("MESHES after join =", sum(1 for o in bpy.data.objects if o.type == "MESH"))

# 5. Matériaux : peinture blanche, verres translucides, textures 1K
for img in bpy.data.images:
    if max(img.size) > MAX_TEX:
        f = MAX_TEX / max(img.size)
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
        img.pack()

for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        continue
    name = mat.name.lower()
    if mat.name == PAINT:
        for l in list(bsdf.inputs["Base Color"].links):
            mat.node_tree.links.remove(l)
        bsdf.inputs["Base Color"].default_value = (0.93, 0.93, 0.93, 1)
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = 0.28
        bsdf.inputs["Coat Weight"].default_value = 1.0
        bsdf.inputs["Coat Roughness"].default_value = 0.05
    elif "glass" in name:
        alpha = 0.55 if "red" in name else (0.18 if "light" in name else 0.35)
        for l in list(bsdf.inputs["Alpha"].links):
            mat.node_tree.links.remove(l)
        bsdf.inputs["Alpha"].default_value = alpha
        tr = bsdf.inputs.get("Transmission Weight")
        if tr:
            tr.default_value = 0.0

# 6. Export USDC (sans conversion d'axes : la géométrie est déjà Y-up)
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.usd_export(
    filepath=os.path.join(OUT, "Car.usdc"),
    export_materials=True,
    generate_preview_surface=True,
    export_textures_mode="NEW",
    convert_orientation=False,
    root_prim_path="",
)
print("EXPORTED", OUT)
