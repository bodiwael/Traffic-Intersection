/*
 * Smart Parking Gate + Traffic Light Control System
 * ESP32 + 8x Servos + 4x Traffic Lights + Firebase
 * 
 * Firebase Path: Park2/
 * Features:
 * - Real-time gate control with ANY angle (0-180°)
 * - Traffic light management (4 modules, 12 LEDs)
 * - Remote Firebase commands
 * - Individual and group control
 */

#include <WiFi.h>
#include <FirebaseESP32.h>
#include <ESP32Servo.h>

// WiFi Credentials
const char* WIFI_SSID = "ITIDA";
const char* WIFI_PASSWORD = "12345678";

// Firebase Credentials
const char* FIREBASE_HOST = "stem-53cdc-default-rtdb.firebaseio.com";
const char* FIREBASE_AUTH = "UlqdAaYSCRjTcqFBRVW0df1Y513SLgoJ2vuZ2lZO";

// Firebase objects
FirebaseData fbData;
FirebaseData fbStream;
FirebaseAuth auth;
FirebaseConfig config;

// Servo Motor Pins (8 Gates)
#define SERVO_PIN_1 13
#define SERVO_PIN_2 12
#define SERVO_PIN_3 14
#define SERVO_PIN_4 27
#define SERVO_PIN_5 26
#define SERVO_PIN_6 25
#define SERVO_PIN_7 33
#define SERVO_PIN_8 32

// Traffic Light Pins
#define TRAFFIC1_RED    23
#define TRAFFIC1_YELLOW 22
#define TRAFFIC1_GREEN  21

#define TRAFFIC2_RED    19
#define TRAFFIC2_YELLOW 18
#define TRAFFIC2_GREEN  5

#define TRAFFIC3_RED    17
#define TRAFFIC3_YELLOW 16
#define TRAFFIC3_GREEN  4

#define TRAFFIC4_RED    15
#define TRAFFIC4_YELLOW 2
#define TRAFFIC4_GREEN  0

// Servo objects
Servo servo1, servo2, servo3, servo4;
Servo servo5, servo6, servo7, servo8;

// Variables
int gatePositions[8] = {0, 0, 0, 0, 0, 0, 0, 0};
String gateStatus[8] = {"closed", "closed", "closed", "closed",
                        "closed", "closed", "closed", "closed"};

bool trafficLights[4][3] = {
  {true, false, false},
  {true, false, false},
  {true, false, false},
  {true, false, false}
};

unsigned long lastGateCheck = 0;
unsigned long lastTrafficCheck = 0;
unsigned long sendDataPrevMillis = 0;
bool firebaseReady = false;

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n╔════════════════════════════════════════╗");
  Serial.println("║  GATE + TRAFFIC CONTROL - FULL RANGE  ║");
  Serial.println("║  Servo: 0-180° | Traffic: RGB Control ║");
  Serial.println("╚════════════════════════════════════════╝\n");
  
  // Setup traffic lights
  pinMode(TRAFFIC1_RED, OUTPUT);
  pinMode(TRAFFIC1_YELLOW, OUTPUT);
  pinMode(TRAFFIC1_GREEN, OUTPUT);
  pinMode(TRAFFIC2_RED, OUTPUT);
  pinMode(TRAFFIC2_YELLOW, OUTPUT);
  pinMode(TRAFFIC2_GREEN, OUTPUT);
  pinMode(TRAFFIC3_RED, OUTPUT);
  pinMode(TRAFFIC3_YELLOW, OUTPUT);
  pinMode(TRAFFIC3_GREEN, OUTPUT);
  pinMode(TRAFFIC4_RED, OUTPUT);
  pinMode(TRAFFIC4_YELLOW, OUTPUT);
  pinMode(TRAFFIC4_GREEN, OUTPUT);
  
  Serial.println("→ Initializing traffic lights...");
  setTrafficLight(1, true, false, false);
  setTrafficLight(2, true, false, false);
  setTrafficLight(3, true, false, false);
  setTrafficLight(4, true, false, false);
  Serial.println("✓ All traffic lights RED");
  
  // Attach servos
  Serial.println("\n→ Attaching servos...");
  servo1.attach(SERVO_PIN_1);
  servo2.attach(SERVO_PIN_2);
  servo3.attach(SERVO_PIN_3);
  servo4.attach(SERVO_PIN_4);
  servo5.attach(SERVO_PIN_5);
  servo6.attach(SERVO_PIN_6);
  servo7.attach(SERVO_PIN_7);
  servo8.attach(SERVO_PIN_8);
  
  // Initialize all gates to 0°
  for(int i = 1; i <= 8; i++) {
    moveGate(i, 0);
    delay(100);
  }
  Serial.println("✓ All gates at 0°");
  
  // Connect WiFi
  connectToWiFi();
  
  // Setup Firebase
  Serial.println("\n→ Configuring Firebase...");
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  fbData.setBSSLBufferSize(1024, 1024);
  fbData.setResponseSize(1024);
  
  Serial.println("→ Connecting to Firebase...");
  delay(2000);
  
  if (Firebase.ready()) {
    Serial.println("✓ Firebase Connected!");
    firebaseReady = true;
    initializeFirebase();
  } else {
    Serial.println("✗ Firebase Connection Failed!");
  }
  
  Serial.println("\n✓ System Ready!");
  Serial.println("📍 Set gate position: /Park2/gates/gate1/position (0-180)");
  Serial.println("🚦 Set traffic: /Park2/traffic/module1/ {red, yellow, green}\n");
}

void loop() {
  if (!firebaseReady) {
    delay(1000);
    return;
  }
  
  // Check gate positions every 300ms
  if (millis() - lastGateCheck > 300) {
    lastGateCheck = millis();
    checkGatePositions();
  }
  
  // Check traffic lights every 300ms
  if (millis() - lastTrafficCheck > 300) {
    lastTrafficCheck = millis();
    checkTrafficStates();
  }
  
  // Send status every 10 seconds (optional - doesn't overwrite commands)
  if (millis() - sendDataPrevMillis > 10000 || sendDataPrevMillis == 0) {
    sendDataPrevMillis = millis();
    sendStatusToFirebase();
  }
  
  delay(50);
}

// ═══════════════════════════════════════════════════════════
// SERVO CONTROL
// ═══════════════════════════════════════════════════════════

void moveGate(int gateNum, int angle) {
  if(gateNum < 1 || gateNum > 8) return;
  
  angle = constrain(angle, 0, 180);
  
  switch(gateNum) {
    case 1: servo1.write(angle); break;
    case 2: servo2.write(angle); break;
    case 3: servo3.write(angle); break;
    case 4: servo4.write(angle); break;
    case 5: servo5.write(angle); break;
    case 6: servo6.write(angle); break;
    case 7: servo7.write(angle); break;
    case 8: servo8.write(angle); break;
  }
  
  gatePositions[gateNum - 1] = angle;
  gateStatus[gateNum - 1] = (angle >= 45) ? "open" : "closed";
  
  Serial.print("→ Gate ");
  Serial.print(gateNum);
  Serial.print(" → ");
  Serial.print(angle);
  Serial.println("°");
}

// ═══════════════════════════════════════════════════════════
// TRAFFIC LIGHTS
// ═══════════════════════════════════════════════════════════

void setTrafficLight(int module, bool red, bool yellow, bool green) {
  if(module < 1 || module > 4) return;
  
  switch(module) {
    case 1:
      digitalWrite(TRAFFIC1_RED, red ? HIGH : LOW);
      digitalWrite(TRAFFIC1_YELLOW, yellow ? HIGH : LOW);
      digitalWrite(TRAFFIC1_GREEN, green ? HIGH : LOW);
      break;
    case 2:
      digitalWrite(TRAFFIC2_RED, red ? HIGH : LOW);
      digitalWrite(TRAFFIC2_YELLOW, yellow ? HIGH : LOW);
      digitalWrite(TRAFFIC2_GREEN, green ? HIGH : LOW);
      break;
    case 3:
      digitalWrite(TRAFFIC3_RED, red ? HIGH : LOW);
      digitalWrite(TRAFFIC3_YELLOW, yellow ? HIGH : LOW);
      digitalWrite(TRAFFIC3_GREEN, green ? HIGH : LOW);
      break;
    case 4:
      digitalWrite(TRAFFIC4_RED, red ? HIGH : LOW);
      digitalWrite(TRAFFIC4_YELLOW, yellow ? HIGH : LOW);
      digitalWrite(TRAFFIC4_GREEN, green ? HIGH : LOW);
      break;
  }
  
  trafficLights[module - 1][0] = red;
  trafficLights[module - 1][1] = yellow;
  trafficLights[module - 1][2] = green;
  
  Serial.print("→ Traffic ");
  Serial.print(module);
  Serial.print(": ");
  if(red) Serial.print("🔴");
  if(yellow) Serial.print("🟡");
  if(green) Serial.print("🟢");
  if(!red && !yellow && !green) Serial.print("⚫OFF");
  Serial.println();
}

// ═══════════════════════════════════════════════════════════
// FIREBASE - READ GATE POSITIONS
// ═══════════════════════════════════════════════════════════

void checkGatePositions() {
  for(int i = 1; i <= 8; i++) {
    String path = "/Park2/gates/gate" + String(i) + "/position";
    
    if(Firebase.getInt(fbData, path)) {
      int newAngle = fbData.intData();
      
      // Only move if angle changed and is valid
      if(newAngle != gatePositions[i-1] && newAngle >= 0 && newAngle <= 180) {
        Serial.print("🔔 Firebase: Gate ");
        Serial.print(i);
        Serial.print(" → ");
        Serial.print(newAngle);
        Serial.println("°");
        moveGate(i, newAngle);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════
// FIREBASE - READ TRAFFIC STATES
// ═══════════════════════════════════════════════════════════

void checkTrafficStates() {
  for(int i = 1; i <= 4; i++) {
    String path = "/Park2/traffic/module" + String(i) + "/";
    
    bool r = false, y = false, g = false;
    bool validRead = false;
    
    if(Firebase.getBool(fbData, path + "red")) {
      r = fbData.boolData();
      if(Firebase.getBool(fbData, path + "yellow")) {
        y = fbData.boolData();
        if(Firebase.getBool(fbData, path + "green")) {
          g = fbData.boolData();
          validRead = true;
        }
      }
    }
    
    // Only update if state changed
    if(validRead && (r != trafficLights[i-1][0] || 
                     y != trafficLights[i-1][1] || 
                     g != trafficLights[i-1][2])) {
      Serial.print("🔔 Firebase: Traffic ");
      Serial.println(i);
      setTrafficLight(i, r, y, g);
    }
  }
}

// ═══════════════════════════════════════════════════════════
// FIREBASE - INITIALIZE & SEND STATUS
// ═══════════════════════════════════════════════════════════

void initializeFirebase() {
  Serial.println("\n→ Initializing Firebase...");
  
  // Set initial gate positions (all at 0)
  for(int i = 1; i <= 8; i++) {
    String path = "/Park2/gates/gate" + String(i) + "/";
    Firebase.setInt(fbData, path + "position", 0);
  }
  
  // Set initial traffic states (all RED)
  for(int i = 1; i <= 4; i++) {
    String path = "/Park2/traffic/module" + String(i) + "/";
    Firebase.setBool(fbData, path + "red", true);
    Firebase.setBool(fbData, path + "yellow", false);
    Firebase.setBool(fbData, path + "green", false);
  }
  
  Firebase.setString(fbData, "/Park2/info/system", "Gate_Traffic_Control_v2");
  Firebase.setInt(fbData, "/Park2/info/gates", 8);
  Firebase.setInt(fbData, "/Park2/info/traffic_modules", 4);
  
  Serial.println("✓ Firebase initialized!");
}

void sendStatusToFirebase() {
  // Send current angles to a separate "current_angle" field
  // This way we don't overwrite the "position" command field
  for(int i = 1; i <= 8; i++) {
    String path = "/Park2/gates/gate" + String(i) + "/";
    Firebase.setInt(fbData, path + "current_angle", gatePositions[i-1]);
    Firebase.setString(fbData, path + "status", gateStatus[i-1]);
  }
  
  Firebase.setInt(fbData, "/Park2/summary/uptime", millis() / 1000);
  
  Serial.println("✓ Status updated");
}

// ═══════════════════════════════════════════════════════════
// WIFI
// ═══════════════════════════════════════════════════════════

void connectToWiFi() {
  Serial.print("\n→ Connecting to WiFi: ");
  Serial.println(WIFI_SSID);
  
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✓ WiFi Connected!");
    Serial.print("→ IP: ");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("\n✗ WiFi Failed!");
  }
}
