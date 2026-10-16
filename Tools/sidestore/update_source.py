"""Ajoute une version en tête de sidestore/source.json (format source AltStore/SideStore).

Le bundleIdentifier ne change jamais : c'est lui qui permet à SideStore de proposer
la nouvelle version comme mise à jour de l'app installée.
"""
import argparse
import datetime
import json
import pathlib

SOURCE = pathlib.Path(__file__).resolve().parents[2] / "sidestore" / "source.json"

p = argparse.ArgumentParser()
p.add_argument("--bundle", default="com.al1x0.car3dui")
p.add_argument("--version", required=True)
p.add_argument("--build", required=True)
p.add_argument("--size", type=int, required=True)
p.add_argument("--url", required=True)
p.add_argument("--notes", default="")
a = p.parse_args()

src = json.loads(SOURCE.read_text(encoding="utf-8"))
app = next(x for x in src["apps"] if x["bundleIdentifier"] == a.bundle)

entry = {
    "version": a.version,
    "buildVersion": a.build,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": a.notes.strip() or f"Version {a.version}",
    "downloadURL": a.url,
    "size": a.size,
    "minOSVersion": "18.0" if a.bundle == "com.al1x0.car3dui" else "17.0",
}
app["versions"] = [v for v in app.get("versions", []) if v["version"] != a.version]
app["versions"].insert(0, entry)

SOURCE.write_text(json.dumps(src, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"source.json : {a.bundle} -> {a.version} ({a.build})")
