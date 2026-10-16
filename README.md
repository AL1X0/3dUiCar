# 3dUiCar

App iPad (SwiftUI + RealityKit) qui reproduit l'interface des Tesla actuelles pour une Ford Fiesta ST 2019 : voiture 3D animée à gauche, navigation à droite, dock en bas. Données : capteurs iPad, GPS de l'iPhone (app compagnon), puis module OBD ESP32 en Bluetooth.

Plan complet : [PLAN.md](PLAN.md).

## Installer avec SideStore

Dans SideStore → **Sources** → **+**, ajoute :

```
https://raw.githubusercontent.com/AL1X0/3dUiCar/main/sidestore/source.json
```

L'identifiant d'app est fixe (`com.al1x0.car3dui`) : chaque nouvelle version apparaît comme une **mise à jour** de l'app installée.

## Publier une version

```bash
git tag -a v0.1.0 -m "Notes de version"
git push origin v0.1.0
```

GitHub Actions compile l'`.ipa` **non signé** (SideStore le signe avec ton Apple ID), crée la Release et ajoute la version à `sidestore/source.json`. Chaque push sur `main` produit aussi l'`.ipa` en artefact du workflow.

## Structure

| Dossier | Contenu |
|---|---|
| `App/Sources` | Code Swift (Core, DesignSystem, Features) |
| `App/Resources` | `Car.usdz`, icône, couleurs |
| `project.yml` | Projet Xcode (XcodeGen) |
| `Tools/model` | Modèle source + script Blender de simplification |
| `Tools/sidestore` | Mise à jour de la source SideStore |
| `sidestore/source.json` | Source SideStore |

Régénérer le modèle 3D :

```bash
blender -b --python Tools/model/build_car.py -- Tools/model/2019_ford_fiesta_st.glb App/Resources/Car.usdz 75000
```

## Crédits

- Modèle 3D « 2019 Ford Fiesta ST » par [Ddiaz Design](https://sketchfab.com/ddiaz-design), [CC BY-NC-SA 4.0](http://creativecommons.org/licenses/by-nc-sa/4.0/) — source : [Sketchfab](https://sketchfab.com/3d-models/2019-ford-fiesta-st-890f9f3c4e2444f58658d3e3e58ed556). `App/Resources/Car.usdz` en est une version simplifiée, sous la même licence.
- UI inspirée de la librairie Figma communautaire « Tesla Dashboard UI Component Library ».
- Projet personnel, non commercial, sans lien avec Tesla ni Ford.
