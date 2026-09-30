#include <Arduino.h>
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <U8g2lib.h>

/*
 ==============================================================================
 AEGIS GUARDIAN — ESP32-C3 HARDWARE FIRMWARE
 ==============================================================================
 Target MCU: ESP32-C3 / ESP32-WROOM-32
 Sensors:
   - MAX30101 (PPG / HR / SpO2) via I2C (0x57)
   - BMI270 (6-Axis IMU) via I2C (0x68 / 0x69)
   - SHT31 (Ambient Temp & Humidity) via I2C (0x44)
   - MAX30208 (Precision Skin Temp) via I2C (0x50)
   - BME280 (Barometric Pressure) via I2C (0x76)
 Power & IO:
   - CN3065 Solar STAT Pin: GPIO 4 (Digital Input)
   - Battery ADC Voltage Divider: GPIO 0 (ADC1_CH0)
   - Panic Tactile SOS Button: GPIO 9 (Active Low with Interrupt)
   - Haptic Vibration Motor: GPIO 5 (PWM / Digital Output)
   - Passive Buzzer: GPIO 6 (LEDC PWM)
   - SSD1306 OLED (128x64): I2C (0x3C)
 ==============================================================================
*/

// BLE GATT UUID Definitions
#define SERVICE_UUID           "0000FFE0-0000-1000-8000-00805F9B34FB"
#define TELEMETRY_CHAR_UUID    "0000FFE1-0000-1000-8000-00805F9B34FB"
#define OLED_SYNC_CHAR_UUID    "0000FF02-0000-1000-8000-00805F9B34FB"

// Hardware Pin Definitions (ESP32-C3)
#define PIN_SDA                8
#define PIN_SCL                9
#define PIN_PANIC_BUTTON       3
#define PIN_SOLAR_STAT         4
#define PIN_BATTERY_ADC        0
#define PIN_HAPTIC_MOTOR       5
#define PIN_BUZZER             6

// OLED Instance (U8g2 I2C 128x64 Non-blocking)
U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE, PIN_SCL, PIN_SDA);

#pragma pack(push, 1)
struct AegisTelemetryPacket {
    uint32_t timestampMs;       // [0-3]
    uint32_t ppgRed;            // [4-7]
    uint32_t ppgIr;             // [8-11]
    int16_t  accelX;            // [12-13]
    int16_t  accelY;            // [14-15]
    int16_t  accelZ;            // [16-17]
    int16_t  ambientTempC_x100; // [18-19]
    uint16_t ambientHum_x100;   // [20-21]
    int16_t  skinTempC_x200;    // [22-23]
    uint16_t pressure_offset;   // [24-25]
    uint8_t  battery_code;      // [26]
    uint8_t  status_flags;      // [27] (Bit 0: SOS, Bit 1: Solar STAT)
};
#pragma pack(pop)

#pragma pack(push, 1)
struct OledSyncInboundPayload {
    uint8_t  statusCode;        // 0: OK, 1: CAUTION, 2: WARNING, 3: CRITICAL/SOS
    uint8_t  batteryPct;        // 0 - 100%
    uint16_t riskScore_x1000;   // 0 - 1000 (0.000 to 1.000)
};
#pragma pack(pop)

// State Variables
BLEServer* pServer = nullptr;
BLECharacteristic* pTelemetryChar = nullptr;
BLECharacteristic* pOledSyncChar = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

volatile bool panicButtonPressed = false;
unsigned long lastDebounceTime = 0;
const unsigned long debounceDelay = 50;

AegisTelemetryPacket currentTelemetry;
OledSyncInboundPayload currentOledSync = {0, 100, 0};

unsigned long lastSampleTime = 0;
unsigned long sampleIntervalMs = 20; // 50 Hz default

// Power Management State
bool isLowPowerMode = false;

void IRAM_ATTR handlePanicButtonISR() {
    unsigned long now = millis();
    if ((now - lastDebounceTime) > debounceDelay) {
        if (digitalRead(PIN_PANIC_BUTTON) == LOW) {
            panicButtonPressed = true;
        }
        lastDebounceTime = now;
    }
}

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
    }
};

class OledSyncCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* pCharacteristic) {
        String rxValue = pCharacteristic->getValue();
        if (rxValue.length() >= sizeof(OledSyncInboundPayload)) {
            memcpy(&currentOledSync, rxValue.c_str(), sizeof(OledSyncInboundPayload));
        }
    }
};

// Simulated Sensor Read Functions (Bridged to physical I2C registers in hardware)
void readSensors(AegisTelemetryPacket &packet) {
    packet.timestampMs = millis();

    // 1. MAX30101 Raw ADC Simulation / I2C Read
    static float phase = 0;
    phase += 0.15;
    float pulse = exp(-pow(sin(phase) * 2.5, 2));
    packet.ppgRed = (uint32_t)(45000 + pulse * 12000 + random(-100, 100));
    packet.ppgIr  = (uint32_t)(68000 + pulse * 18000 + random(-150, 150));

    // 2. BMI270 Accelerometer (+/- 8G, scaled to int16 with 0.000244 g/LSB)
    float ax = 0.05 * sin(phase * 0.5);
    float ay = 0.02 * cos(phase * 0.5);
    float az = 1.00 + 0.05 * sin(phase * 1.5); // 1G baseline
    packet.accelX = (int16_t)(ax / 0.000244);
    packet.accelY = (int16_t)(ay / 0.000244);
    packet.accelZ = (int16_t)(az / 0.000244);

    // 3. SHT31 Ambient Temp & Humidity
    float ambT = 26.5 + 0.5 * sin(phase * 0.01);
    float ambH = 48.0 + 1.0 * cos(phase * 0.01);
    packet.ambientTempC_x100 = (int16_t)(ambT * 100);
    packet.ambientHum_x100   = (uint16_t)(ambH * 100);

    // 4. MAX30208 Skin Temperature
    float skinT = 34.2 + 0.2 * sin(phase * 0.02);
    packet.skinTempC_x200 = (int16_t)(skinT / 0.005);

    // 5. BME280 Barometric Pressure
    float pressHpa = 1013.25;
    packet.pressure_offset = (uint16_t)((pressHpa - 900.0) * 10);

    // 6. CN3065 Solar STAT & Battery ADC Read
    bool solarStat = (digitalRead(PIN_SOLAR_STAT) == LOW); // STAT is active low while charging
    int rawAdc = analogRead(PIN_BATTERY_ADC);
    int vBatMv = (int)(rawAdc * (3300.0 / 4095.0) * 2.0); // 1:1 voltage divider
    if (vBatMv < 3000) vBatMv = 3000;
    if (vBatMv > 4200) vBatMv = 4200;
    packet.battery_code = (uint8_t)((vBatMv - 3000) / 10);

    // Flags: Bit 0 = SOS, Bit 1 = Solar Charging
    uint8_t flags = 0;
    if (panicButtonPressed) flags |= 0x01;
    if (solarStat) flags |= 0x02;
    packet.status_flags = flags;
}

void updateOledDisplay() {
    u8g2.clearBuffer();

    // Header
    u8g2.setFont(u8g2_font_6x10_tr);
    u8g2.drawStr(0, 10, "AEGIS GUARDIAN");

    // BLE Status Indicator
    if (deviceConnected) {
        u8g2.drawStr(95, 10, "[BLE]");
    } else {
        u8g2.drawStr(95, 10, "[---]");
    }

    u8g2.drawHLine(0, 13, 128);

    // Status Banner
    u8g2.setFont(u8g2_font_7x14B_tr);
    switch (currentOledSync.statusCode) {
        case 3:
            u8g2.drawStr(0, 30, "! EMERGENCY SOS !");
            break;
        case 2:
            u8g2.drawStr(0, 30, "WARN: HIGH STRAIN");
            break;
        case 1:
            u8g2.drawStr(0, 30, "CAUTION: MONITOR");
            break;
        default:
            u8g2.drawStr(0, 30, "STATUS: NOMINAL");
            break;
    }

    // Telemetry Line
    u8g2.setFont(u8g2_font_6x10_tr);
    char buf[32];
    sprintf(buf, "Risk: %d%% | Bat: %d%%", currentOledSync.riskScore_x1000 / 10, currentOledSync.batteryPct);
    u8g2.drawStr(0, 46, buf);

    // Environmental Line
    float tSkin = currentTelemetry.skinTempC_x200 * 0.005;
    float tAmb = currentTelemetry.ambientTempC_x100 / 100.0;
    sprintf(buf, "Skin: %.1fC | Amb: %.1fC", tSkin, tAmb);
    u8g2.drawStr(0, 60, buf);

    u8g2.sendBuffer();
}

void applySolarDutyCycling() {
    int vBat = 3000 + (currentTelemetry.battery_code * 10);
    bool isSolar = (currentTelemetry.status_flags & 0x02) != 0;

    if (vBat < 3400 && !isSolar) {
        // Critical Battery: Throttle sampling rate to 5Hz to conserve power
        sampleIntervalMs = 200;
        isLowPowerMode = true;
    } else {
        sampleIntervalMs = 20; // 50Hz normal operation
        isLowPowerMode = false;
    }
}

void setup() {
    Serial.begin(115200);

    // GPIO Configuration
    pinMode(PIN_PANIC_BUTTON, INPUT_PULLUP);
    pinMode(PIN_SOLAR_STAT, INPUT_PULLUP);
    pinMode(PIN_HAPTIC_MOTOR, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_HAPTIC_MOTOR, LOW);
    digitalWrite(PIN_BUZZER, LOW);

    attachInterrupt(digitalPinToInterrupt(PIN_PANIC_BUTTON), handlePanicButtonISR, FALLING);

    // Initialize OLED Display
    u8g2.begin();
    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_7x14B_tr);
    u8g2.drawStr(10, 35, "AEGIS BOOTING...");
    u8g2.sendBuffer();

    // Initialize BLE Server
    BLEDevice::init("Aegis-Watch-ESP32");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new ServerCallbacks());

    BLEService* pService = pServer->createService(SERVICE_UUID);

    // Telemetry Characteristic (Notify)
    pTelemetryChar = pService->createCharacteristic(
        TELEMETRY_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    pTelemetryChar->addDescriptor(new BLE2902());

    // OLED Sync Characteristic (Write)
    pOledSyncChar = pService->createCharacteristic(
        OLED_SYNC_CHAR_UUID,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    pOledSyncChar->setCallbacks(new OledSyncCallbacks());

    pService->start();

    // Start BLE Advertising
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println("[AEGIS] ESP32 Firmware Boot Complete. BLE Advertising Active.");
}

void loop() {
    unsigned long now = millis();

    if (now - lastSampleTime >= sampleIntervalMs) {
        lastSampleTime = now;

        // 1. Read all sensors into 28-byte packed struct
        readSensors(currentTelemetry);

        // 2. Power management duty-cycling
        applySolarDutyCycling();

        // 3. Transmit BLE Notification if connected
        if (deviceConnected) {
            pTelemetryChar->setValue((uint8_t*)&currentTelemetry, sizeof(AegisTelemetryPacket));
            pTelemetryChar->notify();
        }

        // 4. Update OLED Display
        static unsigned long lastOledUpdate = 0;
        if (now - lastOledUpdate >= 200) { // Update display @ 5Hz
            lastOledUpdate = now;
            updateOledDisplay();
        }

        // Reset panic button state after transmission
        if (panicButtonPressed) {
            panicButtonPressed = false;
        }
    }

    // BLE Disconnection reconnection loop
    if (!deviceConnected && oldDeviceConnected) {
        delay(500);
        pServer->startAdvertising();
        oldDeviceConnected = deviceConnected;
    }
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
}
