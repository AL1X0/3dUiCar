/**
 * @file main.cpp
 * @brief Firmware ESP32 pour module OBD/CAN '3dUiCar'.
 *
 * Implémente le protocole décrit dans docs/protocols.md (Section 2) :
 * - BLE GATT (NimBLE) : Service 3dUiCar-OBD, caractéristiques Signals, Command, Raw, Info, DTC.
 * - Pilote TWAI (ESP32 CAN) : GPIO 4 (RX), GPIO 5 (TX).
 * - Poller OBD-II prioritaire (Mode 01) avec support PIDs 0x00/0x20/0x40.
 * - Décodage DTC (Mode 03 ISO-TP SF/FF/CF) et effacement (Mode 04).
 * - Enregistrement brut (Raw CAN).
 * - Mesure de tension batterie via ADC (GPIO 34, pont 100k/22k).
 * - Veille profonde (Deep Sleep) sur inactivité CAN & BLE avec réveil sur front dominant CAN (GPIO 4).
 *
 * NOTE MATÉRIELLE SUR LE BUS MS-CAN FORD :
 * Sur les véhicules Ford (Focus, Fiesta, etc.), le bus MS-CAN (125 kbit/s) se situe
 * sur les broches 3 (CAN+) et 11 (CAN-) de la prise OBD-II, tandis que le HS-CAN (500 kbit/s)
 * est sur les broches standard 6 et 14. Pour écouter le MS-CAN avec ce firmware,
 * un commutateur physique (interrupteur / relais) ou un second transceiver SN65HVD230
 * est nécessaire pour aiguiller les lignes vers le contrôleur TWAI.
 */

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <driver/twai.h>
#include <esp_sleep.h>
#include <vector>
#include <string>
#include <cstring>

// --- Broches Matérielles ---
static const gpio_num_t PIN_CAN_TX = GPIO_NUM_5;
static const gpio_num_t PIN_CAN_RX = GPIO_NUM_4; // RTC GPIO pour réveil ext0
static const uint8_t PIN_ADC_BATTERY = 34;

// --- Constantes UUID BLE ---
#define SERVICE_UUID           "6E3D0001-8C3B-4E4B-9A1F-3D5543415200"
#define CHAR_SIGNALS_UUID      "6E3D0002-8C3B-4E4B-9A1F-3D5543415200"
#define CHAR_COMMAND_UUID      "6E3D0003-8C3B-4E4B-9A1F-3D5543415200"
#define CHAR_RAW_UUID          "6E3D0004-8C3B-4E4B-9A1F-3D5543415200"
#define CHAR_INFO_UUID         "6E3D0005-8C3B-4E4B-9A1F-3D5543415200"
#define CHAR_DTC_UUID          "6E3D0006-8C3B-4E4B-9A1F-3D5543415200"

// --- IDs des Signaux (protocols.md) ---
enum SignalId : uint8_t {
    SIG_RPM          = 0x01,
    SIG_SPEED        = 0x02,
    SIG_COOLANT_TEMP = 0x03,
    SIG_INTAKE_TEMP  = 0x04,
    SIG_THROTTLE     = 0x05,
    SIG_ENGINE_LOAD  = 0x06,
    SIG_FUEL_LEVEL   = 0x07,
    SIG_BATTERY_VOLT = 0x08,
    SIG_MAP          = 0x09,
    SIG_TIMING_ADV   = 0x0A,
    SIG_OIL_TEMP     = 0x0B,
    // Signaux Ford spécifiques (0x20..0x2C)
    SIG_TURN_LEFT    = 0x20,
    SIG_TURN_RIGHT   = 0x21,
    SIG_LOW_BEAM     = 0x22,
    SIG_HIGH_BEAM    = 0x23,
    SIG_BRAKE_PEDAL  = 0x24,
    SIG_REVERSE_GEAR = 0x25,
    SIG_DOOR_DRIVER  = 0x26,
    SIG_DOOR_PASS    = 0x27,
    SIG_TRUNK        = 0x28,
    SIG_HOOD         = 0x29,
    SIG_SEATBELT_DRV = 0x2A,
    SIG_HANDBRAKE    = 0x2B,
    SIG_STEER_ANGLE  = 0x2C
};

// Structure table des signaux
struct SignalValue {
    float value;
    bool dirty;
};
static SignalValue g_signals[0x30];
static portMUX_TYPE g_sigMux = portMUX_INITIALIZER_UNLOCKED;

// --- Paramètres Système & État ---
static const char* FW_VERSION = "0.3.0";
static volatile bool g_bleConnected = false;
static uint16_t g_negotiatedMtu = 247;
static volatile uint8_t g_signalSendRateHz = 20;
static volatile bool g_rawRecordingEnabled = false;
static volatile uint8_t g_currentBus = 0; // 0 = HS (500k), 1 = MS (125k)
static volatile uint32_t g_lastCanActivityMs = 0;
static volatile bool g_twaiInstalled = false;
// Compteurs de diagnostic remontés dans Info
static volatile uint32_t g_rxFrames = 0;
static volatile uint32_t g_txFails = 0;
static volatile uint32_t g_busOffs = 0;

// Instance BLE
static NimBLEServer* g_pServer = nullptr;
static NimBLECharacteristic* g_pCharSignals = nullptr;
static NimBLECharacteristic* g_pCharCommand = nullptr;
static NimBLECharacteristic* g_pCharRaw = nullptr;
static NimBLECharacteristic* g_pCharInfo = nullptr;
static NimBLECharacteristic* g_pCharDtc = nullptr;

// File de trames brutes pour l'enregistrement
static QueueHandle_t g_rawFrameQueue = nullptr;
#define RAW_QUEUE_SIZE 128

// --- Structure Décodage Passif Ford ---
// Les identifiants CAN et les masques sont identifiés lors de rétro-ingénierie via les logs bruts (CSV).
struct FordSignal {
    uint32_t id;
    uint8_t byteIndex;
    uint8_t mask;
    uint8_t signalId;
};

// Tableau de mapping Ford.
// Exemple : Clignotant gauche sur ID 0x210, octet 0, bit 0 (0x01)
static const FordSignal FORD_SIGNALS[] = {
    // { 0x210, 0, 0x01, SIG_TURN_LEFT },
    // { 0x210, 0, 0x02, SIG_TURN_RIGHT },
};
static const size_t FORD_SIGNALS_COUNT = sizeof(FORD_SIGNALS) / sizeof(FORD_SIGNALS[0]);

// --- Gestion des PIDs OBD-II ---
struct ObdPidConfig {
    uint8_t pid;
    uint32_t intervalMs;
    uint32_t lastRunMs;
    bool supported;
};

static ObdPidConfig g_pidConfigs[] = {
    // Priorité 1 : 50 ms
    { 0x0C, 50, 0, false }, // Régime moteur
    { 0x0D, 50, 0, false }, // Vitesse véhicule
    // Priorité 2 : 100 ms
    { 0x11, 100, 0, false }, // Position papillon
    { 0x04, 100, 0, false }, // Charge moteur
    // Priorité 3 : 200 ms
    { 0x0B, 200, 0, false }, // Pression admission (MAP)
    { 0x0E, 200, 0, false }, // Avance à l'allumage
    // Priorité 4 : 1000 ms
    { 0x05, 1000, 0, false }, // Température liquide de refroidissement
    { 0x0F, 1000, 0, false }, // Température admission
    { 0x2F, 1000, 0, false }, // Niveau carburant
    { 0x42, 1000, 0, false }, // Tension module de commande (ECU)
    { 0x5C, 1000, 0, false }, // Température huile moteur
};
static const size_t PID_CONFIG_COUNT = sizeof(g_pidConfigs) / sizeof(g_pidConfigs[0]);

// PIDs d'interrogation de support (Mode 01)
static bool g_supportQueried00 = false;
static bool g_supportQueried20 = false;
static bool g_supportQueried40 = false;

// Flags commandes asynchrones
static volatile bool g_triggerDtcRead = false;
static volatile bool g_triggerDtcClear = false;
static volatile bool g_reinstallTwaiRequested = false;
static volatile uint8_t g_newBusBitrate = 0;

// --- Déclarations des fonctions ---
bool installTwaiDriver(uint8_t busType);
void uninstallTwaiDriver();
float readBatteryAdcVoltage();
void setSignalValue(uint8_t id, float value);
void updateInfoCharacteristic();
void processReceivedFrame(const twai_message_t& rxMsg);

// ============================================================================
// PILOTE TWAI (CAN)
// ============================================================================

bool installTwaiDriver(uint8_t busType) {
    if (g_twaiInstalled) {
        uninstallTwaiDriver();
    }

    twai_general_config_t g_config = TWAI_GENERAL_CONFIG_DEFAULT(PIN_CAN_TX, PIN_CAN_RX, TWAI_MODE_NORMAL);
    g_config.rx_queue_len = 32;

    twai_timing_config_t t_config;
    if (busType == 1) {
        // MS-CAN 125 kbit/s
        t_config = TWAI_TIMING_CONFIG_125KBITS();
        Serial.println("[CAN] Configuration pour MS-CAN (125 kbit/s)");
    } else {
        // HS-CAN 500 kbit/s (par défaut)
        t_config = TWAI_TIMING_CONFIG_500KBITS();
        Serial.println("[CAN] Configuration pour HS-CAN (500 kbit/s)");
    }

    // Réception de tous les identifiants
    twai_filter_config_t f_config = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    if (twai_driver_install(&g_config, &t_config, &f_config) != ESP_OK) {
        Serial.println("[CAN] Échec installation pilote TWAI");
        return false;
    }

    if (twai_start() != ESP_OK) {
        Serial.println("[CAN] Échec démarrage TWAI");
        twai_driver_uninstall();
        return false;
    }

    g_twaiInstalled = true;
    g_currentBus = busType;
    g_lastCanActivityMs = millis();
    Serial.println("[CAN] Pilote TWAI installé et démarré avec succès.");
    updateInfoCharacteristic();
    return true;
}

void uninstallTwaiDriver() {
    if (g_twaiInstalled) {
        twai_stop();
        twai_driver_uninstall();
        g_twaiInstalled = false;
        Serial.println("[CAN] Pilote TWAI désinstallé.");
    }
}

// ============================================================================
// MESURE DE TENSION BATTERIE (ADC)
// ============================================================================

float readBatteryAdcVoltage() {
    // GPIO 34 connecté au diviseur R1=100k, R2=22k -> Facteur = (100 + 22) / 22 = 5.545
    // Atténuation 11dB (pleine échelle ~3.3V)
    analogSetPinAttenuation(PIN_ADC_BATTERY, ADC_11db);
    uint32_t raw = analogRead(PIN_ADC_BATTERY);
    // V_adc = raw / 4095.0 * 3.3V
    float vAdc = (static_cast<float>(raw) / 4095.0f) * 3.3f;
    return vAdc * (122.0f / 22.0f);
}

// ============================================================================
// GESTION DES SIGNAUX
// ============================================================================

void setSignalValue(uint8_t id, float value) {
    if (id >= 0x30) return;
    portENTER_CRITICAL(&g_sigMux);
    g_signals[id].value = value;
    g_signals[id].dirty = true;
    portEXIT_CRITICAL(&g_sigMux);
}

void updateInfoCharacteristic() {
    if (!g_pCharInfo) return;
    const char* busState = "error";
    twai_status_info_t status = {};
    if (g_twaiInstalled && twai_get_status_info(&status) == ESP_OK) {
        if (status.state == TWAI_STATE_BUS_OFF || status.state == TWAI_STATE_RECOVERING) {
            busState = "busoff";
        } else if (status.state == TWAI_STATE_RUNNING) {
            busState = (millis() - g_lastCanActivityMs < 3000) ? "ok" : "silent";
        }
    }

    char json[200];
    snprintf(json, sizeof(json),
             "{\"fw\":\"%s\",\"bus\":\"%s\",\"kbps\":%u,\"rx\":%lu,\"txf\":%lu,\"tec\":%lu,\"rec\":%lu,\"boff\":%lu}",
             FW_VERSION, busState, g_currentBus == 1 ? 125 : 500,
             (unsigned long)g_rxFrames, (unsigned long)g_txFails,
             (unsigned long)status.tx_error_counter, (unsigned long)status.rx_error_counter,
             (unsigned long)g_busOffs);
    g_pCharInfo->setValue(reinterpret_cast<const uint8_t*>(json), strlen(json));
    if (g_bleConnected) g_pCharInfo->notify();
}

// Relance le contrôleur après un bus-off (sinon il ne reçoit plus rien jusqu'au redémarrage)
// et vide la file de réception même quand l'émission échoue.
void serviceTwai() {
    twai_status_info_t status;
    if (twai_get_status_info(&status) == ESP_OK) {
        if (status.state == TWAI_STATE_BUS_OFF) {
            g_busOffs++;
            Serial.println("[CAN] Bus-off, relance du contrôleur.");
            twai_initiate_recovery();
        } else if (status.state == TWAI_STATE_STOPPED) {
            twai_start();
        }
    }
    twai_message_t rxMsg;
    while (twai_receive(&rxMsg, 0) == ESP_OK) {
        processReceivedFrame(rxMsg);
    }
}

void notifyDtc(const std::string& s) {
    if (!g_pCharDtc) return;
    g_pCharDtc->setValue(reinterpret_cast<const uint8_t*>(s.c_str()), s.length());
    g_pCharDtc->notify();
}

// ============================================================================
// CALLBACKS BLE GATT
// ============================================================================

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, ble_gap_conn_desc* desc) override {
        Serial.printf("[BLE] Client connecté : %s\n", NimBLEAddress(desc->peer_ota_addr).toString().c_str());
        g_bleConnected = true;
        pServer->updateConnParams(desc->conn_handle, 12, 24, 0, 400); // Latence faible
    }

    void onDisconnect(NimBLEServer* pServer) override {
        Serial.println("[BLE] Client déconnecté, relance advertising.");
        g_bleConnected = false;
        NimBLEDevice::startAdvertising();
    }

    void onMTUChange(uint16_t MTU, ble_gap_conn_desc* desc) override {
        Serial.printf("[BLE] Négociation MTU : %u octets\n", MTU);
        g_negotiatedMtu = MTU;
    }
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pCharacteristic) override {
        std::string val = pCharacteristic->getValue();
        if (val.empty()) return;

        uint8_t cmd = static_cast<uint8_t>(val[0]);
        Serial.printf("[BLE CMD] Commande reçue : 0x%02X\n", cmd);

        switch (cmd) {
            case 0x01: // Lecture DTC (Mode 03)
                g_triggerDtcRead = true;
                break;

            case 0x02: // Effacement DTC (Mode 04)
                g_triggerDtcClear = true;
                break;

            case 0x10: // Mode enregistrement brut
                if (val.size() >= 2) {
                    g_rawRecordingEnabled = (val[1] == 1);
                    Serial.printf("[BLE CMD] Enregistrement brut : %s\n", g_rawRecordingEnabled ? "ON" : "OFF");
                }
                break;

            case 0x11: // Sélection du bus
                if (val.size() >= 2) {
                    g_newBusBitrate = val[1];
                    g_reinstallTwaiRequested = true;
                    Serial.printf("[BLE CMD] Demande bascule bus vers : %u\n", g_newBusBitrate);
                }
                break;

            case 0x20: // Fréquence d'envoi des signaux (Hz)
                if (val.size() >= 2) {
                    uint8_t hz = val[1];
                    if (hz >= 1 && hz <= 100) {
                        g_signalSendRateHz = hz;
                        Serial.printf("[BLE CMD] Fréquence signaux : %u Hz\n", hz);
                    }
                }
                break;

            default:
                Serial.printf("[BLE CMD] Commande inconnue : 0x%02X\n", cmd);
                break;
        }
    }
};

// ============================================================================
// DÉCODAGE PASSIF CAN FORD & TRAMES RAW
// ============================================================================

void processReceivedFrame(const twai_message_t& rxMsg) {
    g_lastCanActivityMs = millis();
    g_rxFrames++;

    // 1. Décodage passif spécifique Ford
    if (!rxMsg.rtr) {
        for (size_t i = 0; i < FORD_SIGNALS_COUNT; ++i) {
            const FordSignal& fs = FORD_SIGNALS[i];
            if (rxMsg.identifier == fs.id && fs.byteIndex < rxMsg.data_length_code) {
                float val = (rxMsg.data[fs.byteIndex] & fs.mask) ? 1.0f : 0.0f;
                setSignalValue(fs.signalId, val);
            }
        }
    }

    // 2. Bufferisation si mode RAW activé
    if (g_rawRecordingEnabled && g_rawFrameQueue != nullptr) {
        if (xQueueSend(g_rawFrameQueue, &rxMsg, 0) != pdPASS) {
            // File saturée, trame ignorée pour éviter de bloquer
        }
    }
}

// ============================================================================
// TRANSMISSION ISO-15765 / CAN REQUÊTE & ATTENTE
// ============================================================================

bool sendObdRequest(uint8_t mode, uint8_t pid, twai_message_t& outResponse, uint32_t timeoutMs = 50) {
    twai_message_t txMsg;
    memset(&txMsg, 0, sizeof(txMsg));
    txMsg.identifier = 0x7DF; // Requête fonctionnelle standard
    txMsg.data_length_code = 8;
    txMsg.data[0] = 0x02; // Taille données : 2 octets
    txMsg.data[1] = mode;
    txMsg.data[2] = pid;
    for (int i = 3; i < 8; ++i) txMsg.data[i] = 0x55; // Padding ISO standard

    if (twai_transmit(&txMsg, pdMS_TO_TICKS(10)) != ESP_OK) {
        g_txFails++;
        twai_clear_transmit_queue(); // pas d'acquittement : on n'empile pas les requêtes
        return false;
    }

    uint32_t startMs = millis();
    while ((millis() - startMs) < timeoutMs) {
        twai_message_t rxMsg;
        if (twai_receive(&rxMsg, pdMS_TO_TICKS(5)) == ESP_OK) {
            processReceivedFrame(rxMsg);

            // Vérification si réponse de l'ECU (0x7E8..0x7EF)
            if (rxMsg.identifier >= 0x7E8 && rxMsg.identifier <= 0x7EF) {
                // Single Frame (0x0_) avec confirmation (Mode + 0x40)
                if ((rxMsg.data[0] & 0xF0) == 0x00 && rxMsg.data[1] == (mode + 0x40) && rxMsg.data[2] == pid) {
                    memcpy(&outResponse, &rxMsg, sizeof(twai_message_t));
                    return true;
                }
            }
        }
    }
    return false;
}

// ============================================================================
// GESTION DES DTC (MODES 03 & 04)
// ============================================================================

void executeDtcClear() {
    Serial.println("[OBD] Effacement des codes défaut (Mode 04)...");
    twai_message_t txMsg;
    memset(&txMsg, 0, sizeof(txMsg));
    txMsg.identifier = 0x7DF;
    txMsg.data_length_code = 8;
    txMsg.data[0] = 0x01; // 1 octet de données
    txMsg.data[1] = 0x04; // Mode 04
    for (int i = 2; i < 8; ++i) txMsg.data[i] = 0x55;

    twai_transmit(&txMsg, pdMS_TO_TICKS(50));
    vTaskDelay(pdMS_TO_TICKS(100));
}

std::string formatDtcCode(uint8_t b1, uint8_t b2) {
    if (b1 == 0x00 && b2 == 0x00) return "";
    char typeChar = 'P';
    switch ((b1 & 0xC0) >> 6) {
        case 0: typeChar = 'P'; break;
        case 1: typeChar = 'C'; break;
        case 2: typeChar = 'B'; break;
        case 3: typeChar = 'U'; break;
    }
    char buf[8];
    snprintf(buf, sizeof(buf), "%c%X%02X", typeChar, (b1 & 0x3F), b2);
    return std::string(buf);
}

void executeDtcRead() {
    Serial.println("[OBD] Interrogation des DTCs (Mode 03)...");
    twai_message_t txMsg;
    memset(&txMsg, 0, sizeof(txMsg));
    txMsg.identifier = 0x7DF;
    txMsg.data_length_code = 8;
    txMsg.data[0] = 0x01;
    txMsg.data[1] = 0x03; // Mode 03
    for (int i = 2; i < 8; ++i) txMsg.data[i] = 0x55;

    if (twai_transmit(&txMsg, pdMS_TO_TICKS(20)) != ESP_OK) {
        Serial.println("[OBD] Échec émission requête DTC.");
        g_txFails++;
        twai_clear_transmit_queue();
        notifyDtc("!Émission CAN impossible (bus absent ou non acquitté)");
        return;
    }

    std::vector<uint8_t> dtcBytes;
    uint32_t startMs = millis();
    bool isMultiFrame = false;
    bool answered = false;
    uint16_t totalLength = 0;
    uint32_t ecuResponseId = 0x7E8;

    while (millis() - startMs < 250) {
        twai_message_t rx;
        if (twai_receive(&rx, pdMS_TO_TICKS(10)) == ESP_OK) {
            processReceivedFrame(rx);

            if (rx.identifier >= 0x7E8 && rx.identifier <= 0x7EF) {
                uint8_t pci = rx.data[0] & 0xF0;

                // Single Frame (PCI = 0x0X)
                if (pci == 0x00 && rx.data[1] == 0x43) {
                    answered = true;
                    uint8_t count = rx.data[0] & 0x0F;
                    for (int i = 2; i < 1 + count && i < 8; ++i) {
                        dtcBytes.push_back(rx.data[i]);
                    }
                    break;
                }
                // First Frame ISO-TP (PCI = 0x1X)
                else if (pci == 0x10 && rx.data[2] == 0x43) {
                    isMultiFrame = true;
                    answered = true;
                    totalLength = ((rx.data[0] & 0x0F) << 8) | rx.data[1];
                    ecuResponseId = rx.identifier;
                    for (int i = 3; i < 8; ++i) {
                        dtcBytes.push_back(rx.data[i]);
                    }

                    // Envoi Flow Control (0x30 0x00 0x00 ...) vers l'ECU correspondant (ID - 8)
                    twai_message_t fc;
                    memset(&fc, 0, sizeof(fc));
                    fc.identifier = ecuResponseId - 8; // ex: 0x7E8 -> 0x7E0
                    fc.data_length_code = 8;
                    fc.data[0] = 0x30; // Flow Control Continue
                    fc.data[1] = 0x00; // Block Size = 0 (tout envoyer)
                    fc.data[2] = 0x00; // STmin = 0 ms
                    for (int i = 3; i < 8; ++i) fc.data[i] = 0x55;
                    twai_transmit(&fc, pdMS_TO_TICKS(10));
                }
                // Consecutive Frame ISO-TP (PCI = 0x2X)
                else if (pci == 0x20 && isMultiFrame) {
                    for (int i = 1; i < 8; ++i) {
                        if (dtcBytes.size() + 1 <= totalLength) {
                            dtcBytes.push_back(rx.data[i]);
                        }
                    }
                    if (dtcBytes.size() + 1 >= totalLength) {
                        break;
                    }
                }
            }
        }
    }

    // Décodage des paires d'octets DTC
    std::string dtcResult = "";
    for (size_t i = 0; i + 1 < dtcBytes.size(); i += 2) {
        std::string code = formatDtcCode(dtcBytes[i], dtcBytes[i + 1]);
        if (!code.empty()) {
            if (!dtcResult.empty()) dtcResult += ",";
            dtcResult += code;
        }
    }

    Serial.printf("[OBD] Résultat DTCs : '%s'\n", dtcResult.c_str());
    notifyDtc(answered ? dtcResult : std::string("!Aucune réponse du calculateur (contact mis ?)"));
}

// ============================================================================
// DÉCODAGE FORMULES OBD-II (MODE 01)
// ============================================================================

void parseObdResponse(uint8_t pid, const uint8_t* data) {
    // data[0]=dlc, data[1]=0x41, data[2]=pid, data[3]=A, data[4]=B...
    uint8_t A = data[3];
    uint8_t B = data[4];

    switch (pid) {
        case 0x0C: { // RPM: ((A * 256) + B) / 4
            float rpm = static_cast<float>((A * 256) + B) / 4.0f;
            setSignalValue(SIG_RPM, rpm);
            break;
        }
        case 0x0D: { // Vitesse: A (km/h)
            setSignalValue(SIG_SPEED, static_cast<float>(A));
            break;
        }
        case 0x05: { // Temp liquide refroidissement: A - 40 (°C)
            setSignalValue(SIG_COOLANT_TEMP, static_cast<float>(A) - 40.0f);
            break;
        }
        case 0x0F: { // Temp admission: A - 40 (°C)
            setSignalValue(SIG_INTAKE_TEMP, static_cast<float>(A) - 40.0f);
            break;
        }
        case 0x11: { // Papillon: A * 100 / 255 (%)
            setSignalValue(SIG_THROTTLE, (static_cast<float>(A) * 100.0f) / 255.0f);
            break;
        }
        case 0x04: { // Charge moteur: A * 100 / 255 (%)
            setSignalValue(SIG_ENGINE_LOAD, (static_cast<float>(A) * 100.0f) / 255.0f);
            break;
        }
        case 0x2F: { // Niveau carburant: A * 100 / 255 (%)
            setSignalValue(SIG_FUEL_LEVEL, (static_cast<float>(A) * 100.0f) / 255.0f);
            break;
        }
        case 0x0B: { // MAP: A (kPa)
            setSignalValue(SIG_MAP, static_cast<float>(A));
            break;
        }
        case 0x0E: { // Avance à l'allumage: (A / 2) - 64 (°)
            setSignalValue(SIG_TIMING_ADV, (static_cast<float>(A) / 2.0f) - 64.0f);
            break;
        }
        case 0x42: { // Tension ECU: ((A * 256) + B) / 1000 (V)
            float vEcu = static_cast<float>((A * 256) + B) / 1000.0f;
            setSignalValue(SIG_BATTERY_VOLT, vEcu);
            break;
        }
        case 0x5C: { // Temp huile: A - 40 (°C)
            setSignalValue(SIG_OIL_TEMP, static_cast<float>(A) - 40.0f);
            break;
        }
        default:
            break;
    }
}

void parseSupportedPids(uint8_t basePid, const uint8_t* data) {
    // data[3..6] = Bitmask de 32 bits
    uint32_t mask = (data[3] << 24) | (data[4] << 16) | (data[5] << 8) | data[6];
    Serial.printf("[OBD] Support PIDs base 0x%02X : mask 0x%08X\n", basePid, mask);

    for (size_t i = 0; i < PID_CONFIG_COUNT; ++i) {
        uint8_t p = g_pidConfigs[i].pid;
        if (p > basePid && p <= basePid + 32) {
            uint8_t offset = p - basePid;
            bool supp = (mask & (1UL << (32 - offset))) != 0;
            g_pidConfigs[i].supported = supp;
            Serial.printf("  -> PID 0x%02X %s\n", p, supp ? "supporté" : "non-supporté");
        }
    }
}

// ============================================================================
// TÂCHES FREERTOS
// ============================================================================

/**
 * @brief Tâche de scrutation OBD-II (priorités & round-robin).
 */
void obdPollerTask(void* pvParameters) {
    Serial.println("[OBD] Démarrage tâche Poller.");
    vTaskDelay(pdMS_TO_TICKS(1000));

    while (true) {
        // Changement de bus demandé
        if (g_reinstallTwaiRequested) {
            g_reinstallTwaiRequested = false;
            installTwaiDriver(g_newBusBitrate);
            g_supportQueried00 = false;
            g_supportQueried20 = false;
            g_supportQueried40 = false;
        }

        // Exécution des commandes prioritaires
        if (g_triggerDtcClear) {
            g_triggerDtcClear = false;
            executeDtcClear();
        }
        if (g_triggerDtcRead) {
            g_triggerDtcRead = false;
            executeDtcRead();
        }

        if (!g_twaiInstalled) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }
        serviceTwai();

        twai_message_t rxMsg;

        // Étape 1 : Interrogation des bitmasks de support (0x00, 0x20, 0x40)
        if (!g_supportQueried00) {
            if (sendObdRequest(0x01, 0x00, rxMsg, 60)) {
                parseSupportedPids(0x00, rxMsg.data);
                g_supportQueried00 = true;
            }
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }
        if (!g_supportQueried20) {
            if (sendObdRequest(0x01, 0x20, rxMsg, 60)) {
                parseSupportedPids(0x20, rxMsg.data);
            }
            g_supportQueried20 = true;
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }
        if (!g_supportQueried40) {
            if (sendObdRequest(0x01, 0x40, rxMsg, 60)) {
                parseSupportedPids(0x40, rxMsg.data);
            }
            g_supportQueried40 = true;
            vTaskDelay(pdMS_TO_TICKS(20));
            continue;
        }

        // Étape 2 : Ordonnancement prioritaire des PIDs supportés
        uint32_t now = millis();
        bool queriedAny = false;

        for (size_t i = 0; i < PID_CONFIG_COUNT; ++i) {
            if (!g_pidConfigs[i].supported) continue;

            if (now - g_pidConfigs[i].lastRunMs >= g_pidConfigs[i].intervalMs) {
                g_pidConfigs[i].lastRunMs = now;
                if (sendObdRequest(0x01, g_pidConfigs[i].pid, rxMsg, 50)) {
                    parseObdResponse(g_pidConfigs[i].pid, rxMsg.data);
                }
                queriedAny = true;
                vTaskDelay(pdMS_TO_TICKS(5)); // Relâchement bref du bus
                break; // Round-robin : une seule requête en vol
            }
        }

        // Mise à jour de la tension batterie mesurée par ADC si le PID 0x42 n'est pas supporté
        static uint32_t lastAdcMs = 0;
        if (now - lastAdcMs >= 1000) {
            lastAdcMs = now;
            if (!g_pidConfigs[9].supported) { // PID 0x42 non présent
                float batt = readBatteryAdcVoltage();
                setSignalValue(SIG_BATTERY_VOLT, batt);
            }
        }

        // Vidage des autres messages reçus sur le bus (écoute passive)
        while (twai_receive(&rxMsg, 0) == ESP_OK) {
            processReceivedFrame(rxMsg);
        }

        if (!queriedAny) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }
    }
}

/**
 * @brief Tâche de transmission des signaux vers l'iPad via BLE.
 * Paquet : [n : u8] puis n * ( [id : u8] [valeur : float32 LE] ) -> 1 + 5n octets
 */
void signalsSenderTask(void* pvParameters) {
    Serial.println("[SIGNALS] Démarrage tâche d'envoi.");
    uint8_t buffer[256];

    while (true) {
        uint32_t delayMs = 1000 / (g_signalSendRateHz > 0 ? g_signalSendRateHz : 20);
        vTaskDelay(pdMS_TO_TICKS(delayMs));

        if (!g_bleConnected || g_pCharSignals == nullptr || g_pCharSignals->getSubscribedCount() == 0) {
            continue;
        }

        uint16_t maxPayload = g_negotiatedMtu - 3;
        uint8_t maxSignalsPerPacket = (maxPayload - 1) / 5;
        if (maxSignalsPerPacket > 48) maxSignalsPerPacket = 48;

        uint8_t count = 0;
        uint8_t* ptr = &buffer[1];

        portENTER_CRITICAL(&g_sigMux);
        for (uint8_t id = 0x01; id < 0x30; ++id) {
            if (g_signals[id].dirty) {
                *ptr++ = id;
                memcpy(ptr, &g_signals[id].value, sizeof(float));
                ptr += sizeof(float);
                g_signals[id].dirty = false;
                count++;

                if (count >= maxSignalsPerPacket) {
                    break;
                }
            }
        }
        portEXIT_CRITICAL(&g_sigMux);

        if (count > 0) {
            buffer[0] = count;
            size_t packetSize = 1 + (count * 5);
            g_pCharSignals->setValue(buffer, packetSize);
            g_pCharSignals->notify();
        }
    }
}

/**
 * @brief Tâche de transmission des trames CAN brutes (Mode enregistrement).
 * Paquet : [n : u8] puis n * ( [ts_ms : u32] [id : u32 (bit31=ext)] [dlc : u8] [data : 8 octets] ) -> 1 + 17n
 */
void rawRecorderTask(void* pvParameters) {
    Serial.println("[RAW] Démarrage tâche Raw Recorder.");
    uint8_t buffer[256];

    while (true) {
        if (!g_rawRecordingEnabled || !g_bleConnected || g_pCharRaw == nullptr || g_pCharRaw->getSubscribedCount() == 0) {
            vTaskDelay(pdMS_TO_TICKS(100));
            continue;
        }

        uint16_t maxPayload = g_negotiatedMtu - 3;
        uint8_t maxFramesPerPacket = (maxPayload - 1) / 17;

        twai_message_t msg;
        if (xQueueReceive(g_rawFrameQueue, &msg, pdMS_TO_TICKS(50)) == pdPASS) {
            uint8_t count = 0;
            uint8_t* ptr = &buffer[1];

            do {
                uint32_t ts = millis();
                uint32_t canId = msg.identifier;
                if (msg.extd) {
                    canId |= (1UL << 31); // Bit 31 = extended
                }

                // ts_ms : u32
                memcpy(ptr, &ts, 4); ptr += 4;
                // id : u32
                memcpy(ptr, &canId, 4); ptr += 4;
                // dlc : u8
                *ptr++ = msg.data_length_code;
                // data : 8 octets
                memset(ptr, 0, 8);
                memcpy(ptr, msg.data, msg.data_length_code);
                ptr += 8;

                count++;

                if (count >= maxFramesPerPacket) break;
            } while (xQueueReceive(g_rawFrameQueue, &msg, 0) == pdPASS);

            buffer[0] = count;
            size_t packetSize = 1 + (count * 17);
            g_pCharRaw->setValue(buffer, packetSize);
            g_pCharRaw->notify();
        }
    }
}

#ifdef RGB_BUILTIN
/**
 * @brief LED RGB de la carte = état du bus, visible sans l'app.
 * Vert qui clignote : trames CAN reçues. Rouge : contrôleur en défaut (bus-off, câblage).
 * Bleu : iPad connecté mais bus muet. Orange faible : en attente.
 */
void ledTask(void* pvParameters) {
    // La DevKitC-1 a la LED sur GPIO 48 (v1.0) ou GPIO 38 (v1.1) : on pilote les deux.
    static const uint8_t LED_PINS[] = { 48, 38 };
    bool phase = false;
    while (true) {
        uint8_t r = 0, g = 0, b = 0;
        twai_status_info_t st;
        bool running = g_twaiInstalled && twai_get_status_info(&st) == ESP_OK && st.state == TWAI_STATE_RUNNING;
        phase = !phase;
        if (!running) {
            r = 40;
        } else if (millis() - g_lastCanActivityMs < 300) {
            g = phase ? 40 : 0;
        } else if (g_bleConnected) {
            b = 30;
        } else {
            r = 12; g = 4;
        }
        for (uint8_t pin : LED_PINS) neopixelWrite(pin, r, g, b);
        vTaskDelay(pdMS_TO_TICKS(80));
    }
}
#endif

/**
 * @brief Tâche de gestion d'énergie et mise en veille profonde.
 */
void powerManagementTask(void* pvParameters) {
    while (true) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        updateInfoCharacteristic();
        if (g_pCharInfo) Serial.printf("[ETAT] %s\n", g_pCharInfo->getValue().c_str());

        uint32_t now = millis();
        // Condition d'endormissement : 60s sans trame CAN et aucun client BLE connecté
        if (!g_bleConnected && (now - g_lastCanActivityMs > 60000)) {
            Serial.println("[PWR] Inactivité détectée (> 60s sans CAN ni BLE). Passage en veille...");

            uninstallTwaiDriver();
            NimBLEDevice::deinit(true);

            // Réveil par front dominant sur le bus CAN (GPIO 4 RX passe à 0V à l'état dominant)
            esp_sleep_enable_ext0_wakeup(PIN_CAN_RX, 0);

            // Réveil périodique de contrôle après 10 minutes
            esp_sleep_enable_timer_wakeup(10ULL * 60ULL * 1000000ULL);

            Serial.flush();
            esp_deep_sleep_start();
        }
    }
}

// ============================================================================
// CONFIGURATION ET SETUP
// ============================================================================

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("\n=== Démarrage Module OBD 3dUiCar ===");

    // Initialisation de la table des signaux
    for (int i = 0; i < 0x30; ++i) {
        g_signals[i].value = 0.0f;
        g_signals[i].dirty = false;
    }

    // Création file de trames brutes
    g_rawFrameQueue = xQueueCreate(RAW_QUEUE_SIZE, sizeof(twai_message_t));

    // Initialisation TWAI (HS-CAN 500 kbit/s par défaut)
    installTwaiDriver(0);

    // Initialisation NimBLE
    NimBLEDevice::init("3dUiCar-OBD");
    NimBLEDevice::setMTU(247);

    g_pServer = NimBLEDevice::createServer();
    g_pServer->setCallbacks(new ServerCallbacks());

    NimBLEService* pService = g_pServer->createService(SERVICE_UUID);

    // Caractéristique Signals (notify)
    g_pCharSignals = pService->createCharacteristic(
        CHAR_SIGNALS_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    // Caractéristique Command (write)
    g_pCharCommand = pService->createCharacteristic(
        CHAR_COMMAND_UUID,
        NIMBLE_PROPERTY::WRITE
    );
    g_pCharCommand->setCallbacks(new CommandCallbacks());

    // Caractéristique Raw (notify)
    g_pCharRaw = pService->createCharacteristic(
        CHAR_RAW_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    // Caractéristique Info (read)
    g_pCharInfo = pService->createCharacteristic(
        CHAR_INFO_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    updateInfoCharacteristic();

    // Caractéristique DTC (notify)
    g_pCharDtc = pService->createCharacteristic(
        CHAR_DTC_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    pService->start();

    // Configuration de l'Advertising BLE
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    NimBLEDevice::startAdvertising();
    Serial.println("[BLE] Advertising démarré ('3dUiCar-OBD').");

    // Création des tâches FreeRTOS
    xTaskCreatePinnedToCore(obdPollerTask, "ObdPoller", 4096, nullptr, 3, nullptr, 1);
    xTaskCreatePinnedToCore(signalsSenderTask, "SigSender", 3072, nullptr, 2, nullptr, 0);
    xTaskCreatePinnedToCore(rawRecorderTask, "RawRecorder", 3072, nullptr, 1, nullptr, 0);
    xTaskCreatePinnedToCore(powerManagementTask, "PowerMgmt", 4096, nullptr, 1, nullptr, 0);
#ifdef RGB_BUILTIN
    xTaskCreatePinnedToCore(ledTask, "Led", 2048, nullptr, 1, nullptr, 0);
#endif

    Serial.println("[SYS] Système prêt et opérationnel.");
}

void loop() {
    // Les traitements s'exécutent entièrement au sein des tâches FreeRTOS
    vTaskDelay(pdMS_TO_TICKS(1000));
}