"""Finalise l'export Blender : upAxis Y, defaultPrim Car, contrôle des pivots, empaquetage USDZ.

Usage : python Tools/model/package_usdz.py <Car.usdc> <Car.usdz>   (pip install usd-core)
"""
import sys

from pxr import Gf, Usd, UsdGeom, UsdUtils

src, dst = sys.argv[1], sys.argv[2]
stage = Usd.Stage.Open(src)
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
UsdGeom.SetStageMetersPerUnit(stage, 1.0)
stage.SetDefaultPrim(stage.GetPrimAtPath("/Car"))

# Les nœuds animés doivent être sans rotation : le code les oriente directement.
NAMED = ["Car", "Sprung", "Body", "Door_FL", "Door_FR", "Hood", "Trunk"] + [
    f"Wheel_{w}_{k}" for w in ("FL", "FR", "RL", "RR") for k in ("Steer", "Spin")
]
found = {}
for prim in stage.Traverse():
    if prim.GetName() in NAMED and prim.IsA(UsdGeom.Xformable):
        m = UsdGeom.Xformable(prim).GetLocalTransformation()
        rot = m.ExtractRotationMatrix()
        assert Gf.IsClose(rot, Gf.Matrix3d(1), 1e-5), f"{prim.GetPath()} a une rotation"
        found[prim.GetName()] = prim.GetPath()
missing = sorted(set(NAMED) - set(found))
assert not missing, f"nœuds manquants : {missing}"
for name in NAMED:
    world = UsdGeom.Xformable(stage.GetPrimAtPath(found[name])).ComputeLocalToWorldTransform(0)
    t = world.ExtractTranslation()
    print(f"{str(found[name]):32s} ({t[0]:+.2f}, {t[1]:+.2f}, {t[2]:+.2f})")

stage.GetRootLayer().Save()
assert UsdUtils.CreateNewARKitUsdzPackage(src, dst), "échec empaquetage"
print("USDZ ->", dst)
