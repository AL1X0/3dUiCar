# Module ESP32 OBD-II / CAN — Firmware 3dUiCar

Firmware embarqué pour ESP32 assurant l'interface entre le bus CAN automobile (prise OBD-II) et l'application iPad **3dUiCar** via Bluetooth Low Energy (BLE).

Il assure :
- L'interrogation périodique des PIDs standard OBD-II (vitesse, régime, températures, etc.).
- La lecture et l'effacement des codes défaut DTC (modes OBD 03 et 04).
- L'écoute passive des trames propriétaires Ford (clignotants, ouvrants, feux).
- Le streaming BLE des signaux décodés et le transfert de trames brutes pour rétro-ingénierie.
- La mesure de la tension batterie du véhicule via ADC.

---

## 1. Liste des composants (BOM)

| Composant | Référence conseillée | Rôle |
|---|---|---|
| **Microcontrôleur** | ESP32 DevKit v1 (ESP-WROOM-32) ou ESP32-S3 | Cœur applicatif, contrôleur TWAI (CAN) et pile BLE |
| **Transceiver CAN** | Module **SN65HVD230** (3,3 V) | Interface physique CAN bus (3,3 V natif, pas besoin de shifter) |
| **Convertisseur Buck** | Step-Down DC-DC **MP1584** (ou LM2596) | Abaisseur 12 V véhicule → 5 V ESP32 (régler à 5,0 V, courant ≥ 1 A) |
| **Fusible** | Porte-fusible + fusible rapide **1 A** | Protection contre les courts-circuits sur le 12 V permanent |
| **Diode TVS** | **SMBJ24A** ou SMBJ26A (unidirectionnelle) | Protection contre les surtensions et le load-dump automobile |
| **Pont diviseur** | Résistances film métal **100 kΩ** et **22 kΩ** (1%) | Mesure de tension batterie (rapport ≈ 0,1803, supporte jusqu'à ~18 V) |
| **Connecteur OBD** | Prise mâle OBD-II 16 broches (câble ou boîtier à souder) | Raccordement direct sur la prise diagnostic du véhicule |
| *Option MS-CAN* | Commutateur DPDT ou second module MCP2515 | Bascule ou écoute simultanée du bus confort Ford (125 kbps) |

---

## 2. Schéma de câblage

### Broche à broche

| Source (OBD / Alim) | Destination | Signal / Rôle | Notes |
|---|---|---|---|
| **OBD Broche 16** | Fusible 1 A → Anode TVS → **IN+ Buck** | +12 V Batterie permanent | La diode TVS (cathode sur 12 V, anode à la masse) protège des transitoires |
| **OBD Broche 4 & 5** | Cathode TVS, **IN- Buck**, **GND ESP32**, **GND SN65HVD230** | Masse châssis & signal | Relier les masses OBD 4 et 5 ensemble au plan de masse commun |
| **OUT+ Buck (5 V)** | Broche **VIN / 5V** de l'ESP32 | Alimentation régulée | Vérifier impérativement les 5,0 V au voltmètre avant raccordement |
| **OUT- Buck (GND)** | Broche **GND** de l'ESP32 | Référence masse | Commun |
| **OBD Broche 6** | Broche **CANH** du SN65HVD230 | HS-CAN High (500 kbps) | Paire différentielle standard diagnostic |
| **OBD Broche 14** | Broche **CANL** du SN65HVD230 | HS-CAN Low (500 kbps) | Paire différentielle standard diagnostic |
| **ESP32 3V3** | Broche **3V3** du SN65HVD230 | Alimentation transceiver | 3,3 V fourni par le régulateur interne de l'ESP32 |
| **ESP32 GND** | Broche **GND** du SN65HVD230 | Masse transceiver | Commun |
| **ESP32 GPIO 5** | Broche **CTX** (TX) du SN65HVD230 | CAN TX (TWAI TX) | Sortie émission ESP32 |
| **ESP32 GPIO 4** | Broche **CRX** (RX) du SN65HVD230 | CAN RX (TWAI RX) | Entrée réception ESP32 |
| **Pont 12 V / 100 kΩ** | Noeud milieu pont → **GPIO 34** (ADC1) | Entrée mesure batterie | GPIO34 = ADC1_CH6 (entrée seule, tolérance max 3,3 V) |
| **Pont 22 kΩ** | Noeud milieu pont → **GND** | Pied du pont diviseur | Placer un condensateur céramique de 100 nF en parallèle sur la 22 kΩ |

> **Résistance de terminaison** : Les modules SN65HVD230 intègrent souvent une résistance R120 (120 Ω) soudée entre CANH et CANL. Sur le bus OBD d'un véhicule complet, les terminaisons sont déjà en place dans l'ECU. Si la communication est perturbée, dessouder la résistance de 120 Ω du module transceiver.

### Spécificité Ford : Bus Confort (MS-CAN)

Sur les plateformes Ford (Focus, Fiesta, Kuga, Transit...) :
- **HS-CAN (500 kbps)** sur broches OBD **6 (H)** et **14 (L)** : gestion moteur, boîte, ESP, ABS.
- **MS-CAN (125 kbps)** sur broches OBD **3 (H)** et **11 (L)** : carrosserie, combiné, clignotants, portes, feux.

Pour écouter le MS-CAN, vous pouvez intercaler un commutateur mécanique DPDT (deux pôles, deux directions) pour basculer les lignes CANH/CANL du transceiver entre les broches 6/14 et 3/11, ou ajouter un second contrôleur SPI (MCP2515 + TJA1050/SN65HVD230).

---

## 3. Compilation et Flash (PlatformIO)

Le projet s'appuie sur l'écosystème [PlatformIO](https://platformio.org/).

### Commandes principales
