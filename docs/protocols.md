# Protocoles

Contrat commun entre l'app iPad (`App/`), l'app iPhone compagnon (`Companion/`) et le module ESP32 (`Firmware/`).

## 1. iPhone compagnon → iPad (GPS)

- **Transport** : UDP sur le réseau local (partage de connexion de l'iPhone).
- **Découverte** : l'iPad publie un service Bonjour `_car3dui._udp` (NWListener, nom = nom de l'iPad). L'iPhone le cherche avec NWBrowser et ouvre une NWConnection UDP vers le premier trouvé.
- **Fréquence** : à chaque mise à jour CoreLocation de l'iPhone (≈ 1 Hz), plus un « heartbeat » toutes les 2 s si rien de neuf.
- **Message** : JSON UTF-8, un datagramme par message.

```json
{
  "v": 1,
  "type": "location",
  "t": 1792175714.52,
  "lat": 48.85661,
  "lon": 2.35222,
  "alt": 35.2,
  "hAcc": 4.9,
  "speed": 13.4,
  "sAcc": 0.6,
  "course": 271.5,
  "cAcc": 3.0
}
```

| Champ | Unité | Note |
|---|---|---|
| `t` | s (epoch) | `CLLocation.timestamp.timeIntervalSince1970` |
| `speed` | m/s | `-1` si invalide |
| `course` | ° (0 = nord) | `-1` si invalide |
| `hAcc`, `sAcc`, `cAcc` | m, m/s, ° | précisions CoreLocation |

`{"v":1,"type":"heartbeat","t":…}` maintient la liaison. L'iPad considère le flux perdu après 5 s sans message.

## 2. Module ESP32 → iPad (OBD / CAN) — Bluetooth Low Energy

- **Nom annoncé** : `3dUiCar-OBD`
- **Service** : `6E3D0001-8C3B-4E4B-9A1F-3D5543415200`

| Caractéristique | UUID | Propriétés | Contenu |
|---|---|---|---|
| Signals | `6E3D0002-8C3B-4E4B-9A1F-3D5543415200` | notify | paquets de signaux (ci-dessous) |
| Command | `6E3D0003-8C3B-4E4B-9A1F-3D5543415200` | write | 1 octet de commande + paramètres |
| Raw | `6E3D0004-8C3B-4E4B-9A1F-3D5543415200` | notify | trames CAN brutes (mode enregistrement) |
| Info | `6E3D0005-8C3B-4E4B-9A1F-3D5543415200` | read | JSON `{"fw":"0.1.0","bus":"ok"|"silent"|"error","hs":500,"ms":125}` |
| DTC | `6E3D0006-8C3B-4E4B-9A1F-3D5543415200` | notify | codes défaut ASCII séparés par `,` (ex. `P0301,P0420`), vide = aucun |

### Paquet Signals (little-endian)

```
[n : u8] puis n × ( [id : u8] [valeur : float32] )      → 1 + 5n octets (n ≤ 48)
```

| id | Signal | Unité | Source |
|---|---|---|---|
| 0x01 | Régime | tr/min | PID 0x0C |
| 0x02 | Vitesse | km/h | PID 0x0D |
| 0x03 | Température eau | °C | PID 0x05 |
| 0x04 | Température admission | °C | PID 0x0F |
| 0x05 | Papillon | % | PID 0x11 |
| 0x06 | Charge moteur | % | PID 0x04 |
| 0x07 | Niveau carburant | % | PID 0x2F |
| 0x08 | Tension batterie | V | ADC / PID 0x42 |
| 0x09 | Pression admission | kPa | PID 0x0B |
| 0x0A | Avance allumage | ° | PID 0x0E |
| 0x0B | Température huile | °C | PID 0x5C (si supporté) |
| 0x20 | Clignotant gauche | 0/1 | CAN Ford (phase 5) |
| 0x21 | Clignotant droit | 0/1 | CAN Ford |
| 0x22 | Feux de croisement | 0/1 | CAN Ford |
| 0x23 | Feux de route | 0/1 | CAN Ford |
| 0x24 | Frein (pédale) | 0/1 | CAN Ford |
| 0x25 | Marche arrière | 0/1 | CAN Ford |
| 0x26 | Porte conducteur | 0/1 | CAN Ford |
| 0x27 | Porte passager | 0/1 | CAN Ford |
| 0x28 | Coffre | 0/1 | CAN Ford |
| 0x29 | Capot | 0/1 | CAN Ford |
| 0x2A | Ceinture conducteur non bouclée | 0/1 | CAN Ford |
| 0x2B | Frein à main | 0/1 | CAN Ford |
| 0x2C | Angle volant | ° (+ = gauche) | CAN Ford |

### Commandes (Command)

| Octet | Paramètres | Effet |
|---|---|---|
| 0x01 | — | Lire les codes défaut (mode 03) → notification DTC |
| 0x02 | — | Effacer les codes défaut (mode 04) |
| 0x10 | `u8` 0/1 | Mode enregistrement brut on/off |
| 0x11 | `u8` bus (0 = HS 500k, 1 = MS 125k) | Bus écouté en mode brut |
| 0x20 | `u8` Hz | Fréquence max d'envoi des signaux (défaut 20) |

### Paquet Raw (mode enregistrement)

```
[n : u8] puis n × ( [ts_ms : u32] [id : u32] [dlc : u8] [data : 8 octets] )   → 1 + 17n octets
```
Bit 31 de `id` = identifiant étendu (29 bits). L'iPad écrit ces trames dans un CSV (`Documents/can-<date>.csv`) partageable pour le décodage des trames Ford.
