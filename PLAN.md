# 3dUiCar — Plan de l'application iPad « Tesla UI »

> Statut : v3 (16/10/2026) — décisions intégrées : voiture à gauche / carte à droite, GPS via app compagnon iPhone, iPad de test **iPad Pro 12,9" 3ᵉ gén. (A12X, 2018)**, build via GitHub Actions **sans signature** (signature gérée plus tard par toi), OBD via **ESP32 maison**, design = librairie Figma « Tesla Dashboard UI Component Library » (§9).

## 1. Objectif

App iPad native (Swift / SwiftUI) qui reproduit l'UI/UX de l'interface Tesla actuelle (Model 3/Y « Highland ») en mode paysage, montée dans une **Ford Fiesta ST 2019** :

- **Panneau gauche (côté conducteur)** : modèle 3D de la voiture, vivant (roulis, tangage, roues qui tournent et braquent), vitesse, rapport, alertes.
- **Panneau droit** : carte + navigation guidée.
- **Dock bas** : lanceur d'apps, climatisation, volume, accès rapide.
- Données : capteurs iPad (gyro/accéléro) + GPS de l'iPhone (app compagnon) aujourd'hui, **module ESP32 branché sur la prise OBD-II** en BLE demain (régime, températures, clignotants…).

## 2. Ce que contient le dossier

`2019_ford_fiesta_st.glb` (17 Mo, Sketchfab) — analyse :

| Élément | Valeur | Conséquence |
|---|---|---|
| Triangles | ~309 000 | Trop lourd pour un A12X « toujours allumé » → cible **60–100 k** |
| Meshes / matériaux / textures | 105 / 21 / 26 PNG | Fusionner les meshes par matériau, textures → 1–2K compressées |
| Pièces séparées | 4 roues + étriers, portes AV G/D, vitre AV G, capot, coffre, feux AV/AR, rétros | **Animables** : roues (rotation + braquage), portes, capot, coffre, feux (émissif) |
| Extensions | clearcoat, transmission, specular | Clearcoat = peinture carrosserie OK en RealityKit ; transmission → remplacer par verre simple |
| Animations / squelette | aucune | On anime nous-mêmes par transforms de nœuds |

**Pipeline modèle** (Blender, une fois) : décimer (garder silhouette/jantes), supprimer l'habitacle invisible, renommer les pivots (`Wheel_FL`, `Door_FL`, `Hood`, `Trunk`, `Light_F`, `Light_B`, `Blinker_L/R`…), recentrer les pivots des roues/portes, exporter **USDZ** (Reality Converter / Blender USD). Le style Tesla étant une voiture **gris/blanc mat stylisé**, on pourra proposer un matériau « clay » en plus de la vraie peinture.

## 3. Choix techniques

| Sujet | Choix | Pourquoi |
|---|---|---|
| Langage / UI | Swift 6, SwiftUI, `@Observable` | Natif, animations fluides, iPadOS 18+ |
| 3D | **RealityKit** (`RealityView`) | SceneKit est déprécié depuis WWDC25 ; RealityKit gère PBR, clearcoat, ombres, IBL |
| Carte / navigation | **MapKit** (SwiftUI `Map`, `MKDirections`, `MKLocalSearch`) | Gratuit, mode sombre, 3D, itinéraires + étapes. (Mapbox en option si on veut le style Tesla exact) |
| Capteurs | CoreMotion (`CMDeviceMotion` 60 Hz), CoreLocation | Attitude, accélérations, lacet |
| OBD | CoreBluetooth (BLE) ↔ ESP32 | Service GATT maison, protocole binaire compact (voir §5 bis) |
| Lien iPhone ↔ iPad | Network.framework (Bonjour/UDP sur le hotspot) ou MultipeerConnectivity | Faible latence, pas de serveur |
| Média | MusicKit / `MPMusicPlayerController` + `MPNowPlayingInfoCenter` | Lecteur type Tesla |
| Persistance | SwiftData (favoris, trajets, réglages, calibration) | |
| Min. | iPadOS 18 ; cible test iPad Pro 12,9" 3ᵉ gén. (A12X, 2732×2048 = 1366×1024 pt, ProMotion 120 Hz) | 3D adaptative : 60 fps en mouvement, 30 fps à l'arrêt (économie thermique) |
| Build / install | **GitHub Actions** (runner macOS) | Pas de Mac : voir §3 bis |

> ⚠️ **Point clé GPS** : un iPad Wi-Fi connecté au partage de connexion d'un iPhone **ne récupère pas le GPS du téléphone** — il n'a que la géolocalisation Wi-Fi (imprécise/absente en roulant). **Retenu : app compagnon iPhone** qui envoie position + cap + vitesse + précision (1–10 Hz) à l'iPad via le hotspot (Bonjour + UDP), avec mise en arrière-plan autorisée (`location` background mode). Repli : géoloc Wi-Fi iPad + estimation à l'estime par les capteurs.

## 3 bis. Chaîne de build sans Mac

- Repo GitHub → workflow `macos-15` : `xcodebuild` (projet généré par **XcodeGen** pour éviter les conflits de `.pbxproj` édité sous Windows) + tests unitaires.
- **Retenu pour l'instant : pas de signature.** Le CI compile avec `CODE_SIGNING_ALLOWED=NO`, empaquette `Payload/3dUiCar.app` en **`.ipa` non signé** (iPad) et `.ipa` compagnon (iPhone), publiés comme artefacts GitHub. Tu signes/installes toi-même (Sideloadly, AltStore, ou ton compte dev).
- Plus tard, si compte payant : ajout d'un job fastlane (certificats en secrets) + upload TestFlight, sans toucher au reste.
- Pas de simulateur ni de SwiftUI Previews en local → boucle de dev plus lente : le `SimulatorSource` et un mode démo intégré dans l'app deviennent essentiels pour tester sur l'iPad lui-même.
- Le firmware ESP32 se compile en local sous Windows (PlatformIO) et aussi en CI.

## 4. Architecture

```
3dUiCar (Xcode workspace)
├── App/                    — point d'entrée, scène paysage, plein écran, idle timer off
├── DesignSystem/           — couleurs, typo, icônes SF Symbols, composants Tesla (cards, sliders, toggles)
├── Features/
│   ├── CarView/            — panneau gauche : RealityView + HUD (vitesse, PRND, alertes, boutons capot/coffre/portes)
│   ├── Navigation/         — carte, recherche, itinéraire, bandeau virage, carte ETA, suivi
│   ├── Dock/               — barre basse : voiture, clim, apps, volume
│   ├── Controls/           — panneau « Contrôles » (feux, verrous, rétros, essuie-glaces → visuel/simulé)
│   ├── Media/              — lecteur (carte compacte + plein)
│   ├── Climate/            — popup clim (UI, simulée)
│   ├── Apps/               — lanceur : Énergie/Conso, Calendrier, Dashcam, Toybox, Réglages
│   └── Settings/           — calibration, sources de données, unités, thème
├── Core/
│   ├── VehicleState/       — modèle unique observable de l'état véhicule
│   ├── DataSources/        — protocole + implémentations (voir §5)
│   ├── Motion/             — fusion capteurs, filtres, calibration montage
│   └── Location/           — CoreLocation local ou flux iPhone
├── CompanionPhone/         — cible iOS iPhone : envoi GPS + mouvement
└── Tests/
```

**Flux de données** : `DataSource(s)` → `VehicleStateStore` (fusion, priorités, horodatage) → vues SwiftUI + `CarSceneController` (RealityKit, mis à jour à chaque frame via `SceneEvents.Update`).

## 5. Sources de données (pensé pour l'OBD dès le départ)

```swift
protocol VehicleDataSource {
    var capabilities: Set<VehicleSignal> { get }   // speed, rpm, coolantTemp, blinkerLeft, …
    func start() -> AsyncStream<VehicleSample>
}
```

| Source | Phase | Fournit |
|---|---|---|
| `SimulatorSource` | 1 | Tout (trajet scripté, clignotants, régime) — indispensable pour développer à la maison |
| `DeviceMotionSource` (iPad) | 2 | Roulis/tangage/lacet, accél. long./lat. |
| `LocationSource` (iPad ou iPhone compagnon) | 2 | Position, vitesse, cap, altitude |
| `ESP32Source` — PID OBD standard | 4 | Vitesse réelle, régime, temp. eau/admission, papillon, charge, niveau carburant, tension batterie, codes défaut |
| `ESP32Source` — trames CAN Ford (écoute passive) | 5 | Clignotants, feux, portes, frein à main, marche arrière, angle volant… |

Le store choisit pour chaque signal la meilleure source disponible (ex. vitesse : OBD > GPS > simu). L'UI affiche uniquement les signaux disponibles (ex. compte-tours caché sans OBD).

> **OBD, réalité terrain** : les PID standards (Mode 01) donnent régime `0C`, vitesse `0D`, temp. eau `05`, admission `0F`, papillon `11`, carburant `2F`, etc. **Les clignotants, portes, feux ne sont pas des PID standards** : il faut écouter les trames CAN propriétaires Ford. Gros avantage de l'ESP32 : il lit le bus CAN **directement** (pas de couche ELM327 lente), donc écoute passive à pleine vitesse.

## 5 bis. Module ESP32 (firmware dans `Firmware/`)

**Matériel**
- ESP32 avec BLE (ESP32 classique, S3 ou C3) + transceiver CAN 3,3 V **SN65HVD230** (ou TJA1051T/3) sur le contrôleur **TWAI** intégré.
- Prise OBD : HS-CAN 500 kbit/s = broches **6/14**. Sur Ford, une partie des infos confort (clignotants, portes, feux) circule sur le **MS-CAN 125 kbit/s = broches 3/11** → prévoir un 2ᵉ transceiver + contrôleur (MCP2515) ou un commutateur, à confirmer par sniffing sur la Fiesta.
- Alim : broche 16 (+12 V permanent) → régulateur buck 5 V/3,3 V ; **veille profonde** quand le bus CAN est silencieux (sinon batterie vidée), réveil sur activité CAN.
- Fusible + protection (TVS) sur l'entrée 12 V.

**Firmware** (PlatformIO, Arduino-ESP32 ou ESP-IDF)
- Tâche « poller » : requêtes PID Mode 01 sur `0x7DF`, réponses `0x7E8`, fréquence par priorité (régime/vitesse 10–20 Hz, températures 1 Hz).
- Tâche « sniffer » : filtres TWAI sur les ID Ford utiles, décodage → signaux.
- Mode **dump brut** activable depuis l'app (enregistrement des trames pour faire le reverse-engineering des clignotants/portes).
- Lecture/effacement codes défaut (Mode 03/04) à la demande.

**Protocole BLE (GATT maison)**
- Service `3DUC-OBD` : caractéristique *Signals* (notify) = paquets binaires `[id signal u8][valeur f16/i16]…` regroupés, ~20 Hz ; *Command* (write) = demander DTC, activer dump, régler fréquences ; *Info* = version firmware, état bus.
- Côté iPad : `ESP32Source` (CoreBluetooth), reconnexion automatique, état affiché dans la barre de statut.
- Le même protocole est émulé par `SimulatorSource` → l'app est développée avant que le module existe.

## 6. Le modèle 3D « qui bouge vraiment »

1. **Calibration du montage** : iPad fixé dans un support, voiture à l'arrêt sur sol plat → on enregistre la gravité de référence = « voiture à plat ». Matrice de passage repère iPad → repère voiture (orientation quelconque du support gérée). Bouton « Recalibrer » dans Réglages.
2. **Roulis / tangage** : accélération latérale et longitudinale (repère voiture) → angle de caisse simulé (ressort-amortisseur, ex. 1 g lat. ≈ 3° de roulis, freinage → plongée avant). Filtre passe-bas + modèle masse-ressort pour un mouvement naturel, pas l'inclinaison brute du capteur.
3. **Pente de la route** : composante basse fréquence de la gravité → inclinaison globale de la voiture (+ altitude GPS en recoupement).
4. **Roues** : rotation = vitesse / circonférence (205/40 R18 ≈ 1,95 m). Braquage = vitesse de lacet (gyro) × empattement / vitesse (modèle bicyclette), borné ±35°.
5. **Feux** : clignotants (émissif orange, 1,5 Hz), feux stop au freinage (décélération > seuil ou OBD), phares selon heure/luminosité.
6. **Caméra** : vue 3/4 arrière type Tesla, légère suspension de caméra ; tap sur la voiture → vue rapprochée + boutons « Ouvrir capot / coffre » (animations de nœuds), pinch/rotation libre en stationnement.
7. **Environnement** : sol sombre avec ombre de contact, lignes de route qui défilent à la vitesse (option : marquages type Autopilot, *plus tard* détection de voies via caméra iPad + Vision).

## 7. Navigation (panneau droit)

- Carte sombre MapKit, suivi cap (« heading up ») + mode nord, zoom auto selon vitesse.
- Recherche (barre en haut, style Tesla), favoris Maison/Travail, récents.
- Itinéraire : tracé bleu, alternatives, **bandeau de virage** (distance + flèche + nom de rue), **carte ETA** (heure d'arrivée, durée, distance), recalcul hors-route.
- Guidage vocal (`AVSpeechSynthesizer`), limitations de vitesse si dispo, trafic (MapKit).
- Carte rétractable / plein écran (glisser le séparateur comme sur Tesla), voiture plein écran quand la carte est réduite.

## 8. Autres écrans / fonctionnalités Tesla

| Fonction Tesla | Adaptation Fiesta | Phase |
|---|---|---|
| Barre de statut (heure, temp. ext., profil, réseau) | Heure, météo (WeatherKit), état sources (GPS/OBD) | 1 |
| Vitesse + PRND | Vitesse GPS/OBD ; rapport estimé (régime/vitesse) en OBD | 1 / 4 |
| Dock (voiture, clim, apps, volume) | Identique ; clim = UI factice ou réglage cible | 1 |
| Panneau Contrôles | Ouverture capot/coffre/portes **sur la 3D**, choix couleur/clay, luminosité | 2 |
| Lecteur média | Apple Music / lecture en cours | 3 |
| App Énergie | Conso instantanée/moyenne (OBD : MAF/charge + vitesse), carburant restant, autonomie | 4 |
| Jauges sport (bonus Fiesta ST) | Régime, temp. eau/huile, boost (si PID), G-mètre, chrono 0-100 | 4 |
| Dashcam | Caméra arrière iPad en boucle (si support le permet) | 5 |
| Toybox | Easter eggs (mode arc-en-ciel, klaxon…), pour le fun | 5 |
| Alertes | Clignotants, ceinture/portes (CAN), température moteur, codes défaut (Mode 03) | 4–5 |

## 9. Design system (depuis Figma)

Source : *Tesla Dashboard UI Component Library (Community)* — librairie basée sur la Model 3 (mise à jour 2024). Pages utiles : **Patterns – Drive / Parked**, **Menu Screens**, **Music**, **Typography**, **tesla_light_dark_mode**, icônes (nav tree, apps, carte), toggles, onglets, curseurs de luminosité.

**Disposition relevée (écran Figma 1920×1200)**
- **Panneau gauche ≈ 33 %** : en haut `P R N D` + batterie (→ jauge carburant), vitesse en gros (« 29 MPH ») + panneau limitation, colonne de témoins à gauche (feux de croisement vert, auto-feux, antibrouillards vert, ceinture rouge). En **Drive** : voiture vue de derrière entre deux lignes bleues (voies) ; en **Parked** : voiture 3/4 avant avec étiquettes « Frunk Open / Trunk Open », cadenas, éclair de charge → chez nous « Capot / Coffre / Verrou ». Lecteur média compact en bas.
- **Panneau droit ≈ 67 %** : barre de statut flottante sur la carte (verrou, heure, temp. ext., profil, badge airbag), carte en fond ; le panneau **Réglages** se superpose : arbre de navigation à gauche (Search, Controls, Pedals & Steering, Charging, Autopilot, Locks, Lights, Display, Trips, Navigation, Safety, Service, Software, Upgrades) + contenu à droite (en-tête profil « Easy Entry », recherche, toggles avec description, onglets segmentés Off/On/Auto, boutons-tuiles, curseur luminosité, liens bleus « Display »).
- **Dock bas (≈ 6 % de haut, noir)** : icône voiture, température conducteur `‹ 68 ›`, apps (téléphone, audio, Bluetooth, Spotify, caméra, théâtre, Toybox), température passager, volume `‹ 🔊 ›`.

**Adaptation iPad 12,9" (4:3 au lieu de 16:10)**
- Layout en proportions, pas en pixels : 1 px Figma ≈ 0,71 pt en largeur (1920 → 1366 pt). La hauteur supplémentaire (1024 pt vs ~853) profite à la carte et à la vue 3D ; dock gardé à ~72 pt de haut.
- Séparateur gauche/droite déplaçable (comme Tesla) : voiture plein écran ↔ carte plein écran.
- Safe areas iPad respectées (pas d'encoche, coins arrondis + Face ID en paysage).

**Tokens extraits (variables Figma)**

| Token | Valeur | Usage |
|---|---|---|
| `accent` (func/blue dark) | `#005AFF` | Toggles actifs, boutons « Auto », liens, lignes de voie |
| `teal` | `#2FCCBB` | Accent secondaire (icône Toybox, états) |
| `neutral/171717`, `414141` | `#171717`, `#414141` | Texte clair / fonds mode sombre |
| `neutral/757575` (G50 Dark) | `#757575` | Texte secondaire |
| `neutral/A2A3A5` (G40 Inactive) | `#A2A3A5` | Inactif |
| `neutral/D0D1D2` (G30 Outline) | `#D0D1D2` | Bordures onglets/tuiles |
| `neutral/E0E0E0`, `F0F0F0`, `FFFFFF` | — | Fonds panneaux mode clair |
| Ombre carte | flou d'arrière-plan 20 + ombre `#00000040` (2,4) r4 | Cartes flottantes sur la carte → `.ultraThinMaterial` + shadow |
| Typo | **Inter** (Medium 14/18, SemiBold 18/20/22/28, Bold 24) ; page Typo : Source Sans 3 (45/36/28 titres, 12–18 carte) | Embarquer Inter (licence OFL) |

- **Mode clair / sombre** : les deux existent dans le Figma (même layout, fond `#414141`/`#171717`) → bascule auto lever/coucher du soleil + manuelle.
- Icônes : export SVG du Figma (nav tree, témoins, apps) → Asset Catalog en vecteurs ; SF Symbols en secours.
- **Carte** : le Figma utilise un style Snazzy Maps (Google). MapKit n'accepte pas de style personnalisé → MapKit `mutedStandard` clair/sombre en v1 ; **Mapbox** (style personnalisé proche Tesla) en option si le rendu ne convient pas.
- **Témoins Fiesta** à ajouter dans le même style : clignotants G/D, feux de route, frein à main, température moteur, check engine, niveau carburant.
- Grandes cibles tactiles (≥ 60 pt) — usage en roulant.

## 10. Roadmap

| Phase | Contenu | Livrable |
|---|---|---|
| **0. Setup** ✅ | Repo + XcodeGen + workflow GitHub Actions (`.ipa` non signé), modèle 3D simplifié en USDZ, tokens + police Inter + icônes exportés du Figma | `.ipa` qui affiche la voiture sur l'iPad Pro |
| **1. Coquille UI** ✅ | Panneau gauche (PRND, vitesse, témoins), barre de statut, dock, panneau Réglages (arbre + Controls/Lights/Display…), lecteur média compact, clair/sombre, `SimulatorSource` | UI complète en données simulées |
| **2. Voiture vivante + capteurs** ✅ (à valider sur route) | CoreMotion, calibration, roulis/tangage/roues/braquage/feux, contrôles capot/coffre | Ça bouge pour de vrai en voiture |
| **3. Navigation + GPS** | MapKit complet, app compagnon iPhone, guidage vocal, média | Utilisable au quotidien |
| **4. ESP32 + OBD standard** | Montage ESP32 + transceiver, firmware poller PID, GATT, `ESP32Source`, jauges, conso, codes défaut | Données moteur réelles |
| **5. CAN Ford** | Dump/sniffing sur la Fiesta, identification des trames, décodage clignotants/feux/portes/marche AR | Voiture 3D synchronisée à 100 % |
| **6. Finitions** | Perfs (thermique iPad au soleil !), dashcam, toybox, tests route | v1.0 |

### Fait en phase 0 (16/10/2026)
- Repo public [AL1X0/3dUiCar](https://github.com/AL1X0/3dUiCar), source SideStore `sidestore/source.json`, bundle ID fixe `com.al1x0.car3dui`.
- `Car.usdz` : ~101 k triangles, textures 1K, pivots `Wheel_*_Steer/Spin`, `Door_FL/FR`, `Hood`, `Trunk`, `Body` (script `Tools/model/build_car.py`).
- Scène 3D via `ARView` non-AR (API la plus éprouvée) plutôt que `RealityView`.
- Typo système (SF Pro) en attendant Inter ; icônes SF Symbols en attendant l'export Figma (phase 1).

### Fait en phase 1 (16/10/2026, v0.2.0)
- Correctif 3D : pivots dédiés (l'orientation des nœuds USD était écrasée → portes/coffre tournés de 90°), sol uni + ombre de contact.
- Panneau Réglages 14 sections (icône voiture du dock), composants Figma, réglages persistés (UserDefaults).
- Lecteur Apple Music (MPMusicPlayerController), police Inter embarquée, 40 icônes extraites du Figma.
- CI : échoue désormais réellement si `xcodebuild` échoue.

### Fait en phase 2 (16/10/2026, v0.3.0)
- Modèle refait : géométrie Y-up, hiérarchie finale `Car/Sprung/{Body,Door_*,Hood,Trunk}` + `Wheel_*_Steer/Spin`, nœuds sans rotation (contrôlé par `Tools/model/package_usdz.py`), carrosserie pleine résolution (~202 k triangles), peinture blanche.
- `SensorHub` : CoreMotion 50 Hz, calibration du niveau + apprentissage automatique de l'axe avant, G long./lat., lacet, pente ; vitesse GPS si fix GNSS ; P/D déduits.
- Musique : Spotify via SDK App Remote (Client ID à saisir dans Réglages › Logiciel).

## 11. Risques

- **Thermique / batterie** : iPad + 3D + carte + écran max en plein soleil → limiter à 30 fps quand rien ne bouge, LOD, alimenter l'iPad (USB-C PD).
- **Vibrations** : bruit capteurs important en voiture → filtrage solide ; support rigide indispensable.
- **GPS** : dépend de l'app compagnon (iPhone doit rester allumé, app en arrière-plan).
- **A12X (2018)** : GPU correct mais vieillissant → modèle 60–100 k triangles, une seule ombre, fps adaptatif ; surveiller `ProcessInfo.thermalState`.
- **CAN** : brancher un montage maison sur le bus de la voiture — n'émettre que des requêtes OBD standard, jamais de trames sur le bus confort ; écoute passive sinon.
- **Sans Mac** : erreurs de build vues seulement en CI → pousser souvent, garder le projet simple.
- **Marque** : « Tesla » ne peut pas être utilisé pour une publication App Store ; OK en usage perso (sideload / TestFlight).
- **Sécurité routière** : interactions limitées en roulant (grosses cibles, pas de saisie clavier en mouvement).

## 12. Questions ouvertes

1. Ton iPad Pro est-il **Wi-Fi ou Cellular** ? (en Cellular il a son propre GPS → l'app compagnon devient optionnelle)
2. Unités : km/h et °C partout (je suppose oui).
3. Quelle carte ESP32 (classique / S3 / C3) — à voir en phase 4, pas bloquant.
