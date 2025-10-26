// ===== UNIVERSAL (ESP8266 & ESP32) – SoftAP provisioning + Supabase + SERVO =====
// - SoftAP "CASA-ESP_xxxx" si no hay credenciales. En modo AP: 192.168.4.1 -> /nets, /provision
// - Tras provisionar: conecta a Wi-Fi, apaga AP, anuncia mDNS _casa._tcp, endpoints locales /info /servo /sensors
// - Guarda también supabase_url, supabase_key, device_id, device_key para operar contra Supabase
// - Consulta Supabase (device_next_command) cada 1 s y actualiza estado con upsert_live_signal
// - Serial: enviar '1' => limpia credenciales y vuelve a SoftAP

struct SupabaseCreds;

#include <ctype.h>

#if defined(ESP32)
  #include <WiFi.h>
  #include <ESPmDNS.h>
  #include <WebServer.h>
  #include <Preferences.h>
  #include <ESP32Servo.h>
  #include <WiFiClientSecure.h>
  #include <HTTPClient.h>
  WebServer http(80);
  Preferences prefs;
  #ifndef SERVO_PIN
    #define SERVO_PIN 13   // ajusta según tu placa ESP32
  #endif
#elif defined(ESP8266)
  #include <ESP8266WiFi.h>
  #include <ESP8266mDNS.h>
  #include <ESP8266WebServer.h>
  #include <EEPROM.h>
  #include <Servo.h>
  #include <WiFiClientSecureBearSSL.h>
  #include <ESP8266HTTPClient.h>
  ESP8266WebServer http(80);
  #ifndef SERVO_PIN
    #define SERVO_PIN 2    // ESP-01: GPIO2
  #endif
#else
  #error "Placa no soportada (requiere ESP8266 o ESP32)"
#endif

// Clave pública (anon) de Supabase como respaldo.
// Si el dispositivo no la recibe durante la provisión, usará este valor.
const char* SUPABASE_ANON_FALLBACK =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxbXlkeWVzYWZuaG9taHpld3NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyNzY0OTgsImV4cCI6MjA3NDg1MjQ5OH0.YFteDpgiU87dwNq2PIaDrm28h5w6nu0T0mLEUjmTrmU";

const char* DEVICE_TYPE = "servo";
String deviceName = "casa-esp";
String hostLabel  = "casa-esp";
const char* ACTUATOR_NAME = "servo_main";
const char* SYSTEM_ACTUATOR_NAME = "system_control";

Servo servo;
int  servoPos = 0;
bool servoOn  = false;

void moveServoTo(int target) {
  target = constrain(target, 0, 180);
  servo.write(target);
  servoPos = target;
  servoOn = (servoPos >= 90);
}

void setServoOn(bool on) {
  servoOn = on;
  moveServoTo(on ? 180 : 0);
}

struct SupabaseCreds {
  String url;
  String anonKey;
  String deviceId;
  String deviceKey;
} supa;

bool actuatorEnsured = false;
bool systemActuatorEnsured = false;
uint32_t lastHeartbeatMs = 0;
uint32_t lastCommandPollMs = 0;
uint32_t lastActuatorEnsureMs = 0;
uint32_t lastSystemEnsureMs = 0;
const uint32_t HEARTBEAT_MS        = 6000;
const uint32_t COMMAND_POLL_MS     = 1000;
const uint32_t ACTUATOR_RETRY_MS   = 10000;
const uint32_t SYSTEM_RETRY_MS     = 10000;
const uint32_t REMOTE_FLAGS_POLL_MS = 10000;

bool pendingSoftAp = false;
uint32_t lastRemoteFlagsPollMs = 0;

void debugLogDeviceKey(const char* source) {
  if (source == nullptr) source = "supabase";
  if (!supa.deviceKey.length()) {
    Serial.printf("[SUPA] %s: device key missing\n", source);
    return;
  }
  const int len = supa.deviceKey.length();
  const int start = len > 6 ? len - 6 : 0;
  String suffix = supa.deviceKey.substring(start);
  Serial.printf("[SUPA] %s: device key present (len=%d, suffix=%s)\n",
                source, len, suffix.c_str());
}

void debugLogAnonKey(const char* source) {
  if (source == nullptr) source = "supabase";
  if (!supa.anonKey.length()) {
    Serial.printf("[SUPA] %s: anon key missing\n", source);
    return;
  }
  const int len = supa.anonKey.length();
  const int start = len > 6 ? len - 6 : 0;
  String suffix = supa.anonKey.substring(start);
  Serial.printf("[SUPA] %s: anon key present (len=%d, suffix=%s)\n",
                source, len, suffix.c_str());
}

String jsonEscape(const String& in) {
  String out;
  out.reserve(in.length() + 8);
  for (size_t i = 0; i < in.length(); ++i) {
    char c = in[i];
    if (c == '"' || c == '\\') {
      out += '\\'; out += c;
    } else if ((uint8_t)c < 0x20) {
      // ignora controles
    } else {
      out += c;
    }
  }
  return out;
}

bool jsonFlagTrue(const String& body, const char* key) {
  String pattern = "\"" + String(key) + "\":true";
  if (body.indexOf(pattern) >= 0) return true;
  pattern = "\"" + String(key) + "\": true";
  if (body.indexOf(pattern) >= 0) return true;
  return false;
}

int hexDigit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return 10 + (c - 'a');
  if (c >= 'A' && c <= 'F') return 10 + (c - 'A');
  return -1;
}

void appendCodepointUtf8(String& out, uint16_t code) {
  if (code <= 0x7F) {
    out += char(code);
  } else if (code <= 0x7FF) {
    out += char(0xC0 | ((code >> 6) & 0x1F));
    out += char(0x80 | (code & 0x3F));
  } else {
    out += char(0xE0 | ((code >> 12) & 0x0F));
    out += char(0x80 | ((code >> 6) & 0x3F));
    out += char(0x80 | (code & 0x3F));
  }
}

String jsonExtractString(const String& body, const char* key) {
  String token = "\"";
  token += key;
  token += "\"";
  int keyPos = body.indexOf(token);
  if (keyPos < 0) return "";
  int colon = body.indexOf(':', keyPos + token.length());
  if (colon < 0) return "";
  int i = colon + 1;
  const int len = body.length();
  while (i < len && isspace((unsigned char)body[i])) i++;
  if (i >= len || body[i] != '"') return "";
  ++i; // skip opening quote

  String out;
  bool escape = false;
  for (; i < len; ++i) {
    char c = body[i];
    if (escape) {
      switch (c) {
        case '"': out += '"'; break;
        case '\\': out += '\\'; break;
        case '/': out += '/'; break;
        case 'b': out += '\b'; break;
        case 'f': out += '\f'; break;
        case 'n': out += '\n'; break;
        case 'r': out += '\r'; break;
        case 't': out += '\t'; break;
        case 'u':
          if (i + 4 < len) {
            uint16_t code = 0;
            bool valid = true;
            for (int j = 0; j < 4; ++j) {
              int hv = hexDigit(body[i + 1 + j]);
              if (hv < 0) { valid = false; break; }
              code = (uint16_t)((code << 4) | hv);
            }
            if (valid) {
              appendCodepointUtf8(out, code);
            }
            i += 4;
          }
          break;
        default:
          out += c;
          break;
      }
      escape = false;
    } else if (c == '\\') {
      escape = true;
    } else if (c == '"') {
      break;
    } else {
      out += c;
    }
  }
  return out;
}

String deviceIdHex() {
#if defined(ESP32)
  uint64_t chipid = ESP.getEfuseMac();
  char buf[17];
  sprintf(buf, "%04X%08X",
          (uint16_t)(chipid >> 32),
          (uint32_t)(chipid & 0xFFFFFFFF));
  String s(buf);
  s.toUpperCase();
  return s;
#else
  String s = String(ESP.getChipId(), HEX);
  s.toUpperCase();
  return s;
#endif
}

String toLowerStr(const String& in) {
  String o = in;
  for (size_t i = 0; i < o.length(); ++i) o[i] = (char)tolower(o[i]);
  return o;
}

void makeUniqueHostLabel() {
  String id = deviceIdHex();
  String last6 = id.substring(id.length() > 6 ? id.length() - 6 : 0);
  hostLabel = "casa-esp-" + toLowerStr(last6);
}

String wifiAlias;

#if defined(ESP8266)
struct PersistedData {
  uint16_t magic;
  char ssid[64];
  char pass[64];
  char alias[64];
  char supaUrl[128];
  char supaAnon[256];
  char supaDeviceId[64];
  char supaDeviceKey[128];
};
PersistedData persisted;
const uint16_t CREDS_MAGIC = 0xCA5A;
#endif

void loadSupabaseCreds();

bool loadWifiCreds(String& ssid, String& pass) {
#if defined(ESP32)
  prefs.begin("wifi", true);
  ssid = prefs.getString("ssid", "");
  pass = prefs.getString("pass", "");
  wifiAlias = prefs.getString("alias", "");
  prefs.end();
#else
  EEPROM.begin(sizeof(PersistedData));
  EEPROM.get(0, persisted);
  EEPROM.end();
  if (persisted.magic != CREDS_MAGIC) {
    memset(&persisted, 0, sizeof(persisted));
    return false;
  }
  ssid = String(persisted.ssid);
  pass = String(persisted.pass);
  wifiAlias = String(persisted.alias);
#endif
  if (wifiAlias.length() > 0) deviceName = wifiAlias;
  return ssid.length() > 0;
}

void saveWifiCreds(const String& ssid, const String& pass, const String& alias) {
#if defined(ESP32)
  prefs.begin("wifi");
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.putString("alias", alias);
  prefs.end();
#else
  memset(&persisted, 0, sizeof(persisted));
  persisted.magic = CREDS_MAGIC;
  ssid.toCharArray(persisted.ssid, sizeof(persisted.ssid));
  pass.toCharArray(persisted.pass, sizeof(persisted.pass));
  alias.toCharArray(persisted.alias, sizeof(persisted.alias));
  EEPROM.begin(sizeof(PersistedData));
  EEPROM.put(0, persisted);
  EEPROM.commit();
  EEPROM.end();
#endif
  wifiAlias = alias;
  if (wifiAlias.length() > 0) deviceName = wifiAlias;
}

void clearWifiCreds() {
#if defined(ESP32)
  prefs.begin("wifi");
  prefs.clear();
  prefs.end();
  WiFi.persistent(true);
  WiFi.disconnect(true, true);
  WiFi.persistent(false);
#else
  memset(&persisted, 0, sizeof(persisted));
  EEPROM.begin(sizeof(PersistedData));
  EEPROM.put(0, persisted);
  EEPROM.commit();
  EEPROM.end();
  WiFi.disconnect(true);
#endif
  wifiAlias = "";
}

void saveSupabaseCreds(const SupabaseCreds& c) {
#if defined(ESP32)
  prefs.begin("supa");
  prefs.putString("url",  c.url);
  prefs.putString("anon", c.anonKey);
  prefs.putString("id",   c.deviceId);
  prefs.putString("key",  c.deviceKey);
  prefs.end();
#else
  persisted.magic = CREDS_MAGIC;
  c.url.toCharArray(persisted.supaUrl, sizeof(persisted.supaUrl));
  c.anonKey.toCharArray(persisted.supaAnon, sizeof(persisted.supaAnon));
  c.deviceId.toCharArray(persisted.supaDeviceId, sizeof(persisted.supaDeviceId));
  c.deviceKey.toCharArray(persisted.supaDeviceKey, sizeof(persisted.supaDeviceKey));
  EEPROM.begin(sizeof(PersistedData));
  EEPROM.put(0, persisted);
  EEPROM.commit();
  EEPROM.end();
#endif
  supa = c;
  debugLogDeviceKey("saveSupabaseCreds");
  ensureAnonFallback();
  debugLogAnonKey("saveSupabaseCreds");
}

void clearSupabaseCreds() {
#if defined(ESP32)
  prefs.begin("supa");
  prefs.clear();
  prefs.end();
#else
  persisted.magic = CREDS_MAGIC;
  memset(persisted.supaUrl, 0, sizeof(persisted.supaUrl));
  memset(persisted.supaAnon, 0, sizeof(persisted.supaAnon));
  memset(persisted.supaDeviceId, 0, sizeof(persisted.supaDeviceId));
  memset(persisted.supaDeviceKey, 0, sizeof(persisted.supaDeviceKey));
  EEPROM.begin(sizeof(PersistedData));
  EEPROM.put(0, persisted);
  EEPROM.commit();
  EEPROM.end();
#endif
  supa = SupabaseCreds{};
  actuatorEnsured = false;
  lastActuatorEnsureMs = 0;
}

void ensureAnonFallback() {
  if (!supa.anonKey.length() && SUPABASE_ANON_FALLBACK[0] != '\0') {
    supa.anonKey = SUPABASE_ANON_FALLBACK;
  }
}

void loadSupabaseCreds() {
#if defined(ESP32)
  prefs.begin("supa", true);
  supa.url      = prefs.getString("url", "");
  supa.anonKey  = prefs.getString("anon", "");
  supa.deviceId = prefs.getString("id", "");
  supa.deviceKey= prefs.getString("key", "");
  prefs.end();
#else
  if (persisted.magic == CREDS_MAGIC) {
    supa.url      = String(persisted.supaUrl);
    supa.anonKey  = String(persisted.supaAnon);
    supa.deviceId = String(persisted.supaDeviceId);
    supa.deviceKey= String(persisted.supaDeviceKey);
  } else {
    supa = SupabaseCreds{};
  }
#endif
  debugLogDeviceKey("loadSupabaseCreds");
  ensureAnonFallback();
  debugLogAnonKey("loadSupabaseCreds");
}

void startMdns(uint16_t portHttp) {
#if defined(ESP32)
  if (MDNS.begin(hostLabel.c_str())) {
    MDNS.setInstanceName(deviceName.c_str());
    MDNS.addService("casa", "tcp", portHttp);
    MDNS.addServiceTxt("casa", "tcp", "name", deviceName.c_str());
    MDNS.addServiceTxt("casa", "tcp", "type", DEVICE_TYPE);
    MDNS.addServiceTxt("casa", "tcp", "id", deviceIdHex().c_str());
    MDNS.addServiceTxt("casa", "tcp", "host", hostLabel.c_str());
    MDNS.addServiceTxt("casa", "tcp", "http", String(portHttp).c_str());
  }
#elif defined(ESP8266)
  if (MDNS.begin(hostLabel.c_str())) {
    MDNS.setInstanceName(deviceName.c_str());
    MDNS.addService("casa", "tcp", portHttp);
    MDNS.addServiceTxt("casa", "tcp", "name", deviceName.c_str());
    MDNS.addServiceTxt("casa", "tcp", "type", DEVICE_TYPE);
    MDNS.addServiceTxt("casa", "tcp", "id", deviceIdHex().c_str());
    MDNS.addServiceTxt("casa", "tcp", "host", hostLabel.c_str());
    MDNS.addServiceTxt("casa", "tcp", "http", String(portHttp).c_str());
  }
#endif
}

void handleCors() {
  http.sendHeader("Access-Control-Allow-Origin", "*");
  http.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  http.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
}
void handleOptions() { handleCors(); http.send(204); }
void handleRoot()    { handleCors(); http.send(200, "application/json", "{\"ok\":true}"); }

void handleFactoryResetHttp() {
  handleCors();
  http.send(200, "application/json", "{\"ok\":true,\"action\":\"softap\"}");
  pendingSoftAp = true;
}

void handleNets() {
  handleCors();
  int n = WiFi.scanNetworks();
  String out = "[";
  for (int i = 0; i < n; ++i) {
    if (i) out += ",";
    out += "{";
    out += "\"ssid\":\"" + jsonEscape(WiFi.SSID(i)) + "\",";
    out += "\"rssi\":" + String(WiFi.RSSI(i));
    out += "}";
  }
  out += "]";
  http.send(200, "application/json", out);
}

void stopSoftAP() {
  WiFi.softAPdisconnect(true);
#if defined(ESP8266)
  delay(50);
#endif
}

void setHostnameAndDhcp() {
  makeUniqueHostLabel();
#if defined(ESP32)
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
  WiFi.setHostname(hostLabel.c_str());
#else
  WiFi.config(IPAddress(0,0,0,0), IPAddress(0,0,0,0), IPAddress(0,0,0,0));
  WiFi.hostname(hostLabel.c_str());
#endif
}

bool connectSta(const String& ssid, const String& pass, uint32_t timeoutMs = 15000) {
  WiFi.mode(WIFI_STA);
#if defined(ESP32)
  WiFi.setSleep(false);
#endif
  setHostnameAndDhcp();
  WiFi.begin(ssid.c_str(), pass.c_str());

  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < timeoutMs) {
    delay(300);
  }
  return WiFi.status() == WL_CONNECTED;
}

void handleInfo() {
  handleCors();
  String json = "{";
  json += "\"deviceId\":\"" + jsonEscape(deviceIdHex()) + "\",";
  json += "\"name\":\""     + jsonEscape(deviceName)    + "\",";
  json += "\"type\":\""     + jsonEscape(DEVICE_TYPE)   + "\",";
  json += "\"host\":\""     + jsonEscape(hostLabel)     + "\",";
  json += "\"ip\":\""       + jsonEscape(WiFi.isConnected()? WiFi.localIP().toString() : "0.0.0.0") + "\"";
  json += "}";
  http.send(200, "application/json", json);
}

void handleSensors() {
  handleCors();
  String json = "{";
  json += "\"servo\":{";
  json += "\"on\":"  + String(servoOn ? "true":"false") + ",";
  json += "\"pos\":" + String(servoPos);
  json += "}}";
  http.send(200, "application/json", json);
}

void handleServoGet() {
  handleCors();
  String json = "{";
  json += "\"ok\":true,";
  json += "\"on\":"  + String(servoOn ? "true":"false") + ",";
  json += "\"pos\":" + String(servoPos);
  json += "}";
  http.send(200, "application/json", json);
}

void supabaseHeartbeat(bool forceNow);

void handleServoPost() {
  handleCors();
  if (!http.hasArg("plain")) {
    http.send(400, "application/json", "{\"error\":\"no-body\"}");
    return;
  }
  String body = http.arg("plain");

  int idxOn  = body.indexOf("\"on\"");
  int idxPos = body.indexOf("\"pos\"");
  bool hasOn = (idxOn >= 0);
  bool onVal = servoOn;
  if (hasOn) {
    String sub = body.substring(idxOn);
    int t = sub.indexOf("true");
    int f = sub.indexOf("false");
    if (t >= 0 && (f < 0 || t < f)) onVal = true;
    else if (f >= 0) onVal = false;
  }

  int newPos = servoPos;
  if (idxPos >= 0) {
    int c = body.indexOf(':', idxPos);
    if (c > 0) {
      int e = c + 1;
      while (e < (int)body.length() && isspace((unsigned char)body[e])) e++;
      int s = e;
      while (e < (int)body.length() && isdigit((unsigned char)body[e])) e++;
      if (e > s) newPos = constrain(body.substring(s, e).toInt(), 0, 180);
    }
  }

  if (idxPos >= 0) {
    moveServoTo(newPos);
  } else if (hasOn) {
    setServoOn(onVal);
  }

  supabaseHeartbeat(true);

  String json = "{";
  json += "\"ok\":true,";
  json += "\"on\":"  + String(servoOn ? "true":"false") + ",";
  json += "\"pos\":" + String(servoPos);
  json += "}";
  http.send(200, "application/json", json);
}

bool ensureSupabaseCredsPresent() {
  return supa.url.length() && supa.anonKey.length() &&
         supa.deviceId.length() && supa.deviceKey.length();
}

bool supabaseRequest(const String& method,
                     const String& path,
                     const String& payload,
                     int& outCode,
                     String& outBody,
                     const char* prefer = nullptr) {
  if (!ensureSupabaseCredsPresent()) {
    debugLogDeviceKey("supabaseRequest/missing");
    return false;
  }
  if (WiFi.status() != WL_CONNECTED) return false;

  String url = supa.url + path;

#if defined(ESP32)
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient httpc;
  if (!httpc.begin(client, url)) {
    Serial.print("[SUPA] http.begin failed url=");
    Serial.println(url);
    return false;
  }
#else
  BearSSL::WiFiClientSecure client;
  client.setInsecure();
  HTTPClient httpc;
  if (!httpc.begin(client, url)) {
    Serial.print("[SUPA] http.begin failed url=");
    Serial.println(url);
    return false;
  }
#endif

  httpc.addHeader("Content-Type", "application/json");
  httpc.addHeader("apikey", supa.anonKey);
  httpc.addHeader("Authorization", "Bearer " + supa.anonKey);
  httpc.addHeader("x-device-key", supa.deviceKey);
  static bool loggedKeyHeader = false;
  if (!loggedKeyHeader) {
    loggedKeyHeader = true;
    debugLogDeviceKey("supabaseRequest/header");
  }
  if (prefer) httpc.addHeader("Prefer", prefer);

  if (method == "POST")      outCode = httpc.POST(payload);
  else if (method == "GET")  outCode = httpc.GET();
  else if (method == "PATCH")outCode = httpc.PATCH(payload);
  else if (method == "PUT")  outCode = httpc.PUT(payload);
  else                       outCode = httpc.sendRequest(method.c_str(), (uint8_t*)payload.c_str(), payload.length());

  if (outCode <= 0) {
    Serial.print("[SUPA] http request failed code=");
    Serial.println(outCode);
  }
  outBody = httpc.getString();
  httpc.end();
  return outCode > 0;
}

void supabaseHeartbeat(bool forceNow) {
  if (!ensureSupabaseCredsPresent()) return;
  uint32_t now = millis();
  if (!forceNow && (now - lastHeartbeatMs) < HEARTBEAT_MS) return;
  if (WiFi.status() != WL_CONNECTED) return;

  lastHeartbeatMs = now;

  String extra = "{";
  extra += "\"servo\":{";
  extra += "\"on\":"  + String(servoOn ? "true":"false") + ",";
  extra += "\"pos\":" + String(servoPos);
  extra += "},";
  extra += "\"ip\":\""   + jsonEscape(WiFi.localIP().toString()) + "\",";
  extra += "\"host\":\"" + jsonEscape(hostLabel) + "\"";
  extra += "}";

  String payload = "{";
  payload += "\"_device_name\":\"" + jsonEscape(deviceName) + "\",";
  payload += "\"_sensor_name\":\"" + jsonEscape("servo_state") + "\",";
  payload += "\"_kind\":\"servo\",";
  payload += "\"_value_numeric\":" + String(servoPos) + ",";
  payload += "\"_value_text\":\"" + String(servoOn ? "on" : "off") + "\",";
  payload += "\"_extra\":" + extra;
  payload += "}";

  int code; String body;
  supabaseRequest("POST", "/rest/v1/rpc/upsert_live_signal", payload, code, body, "return=minimal");
}

void supabaseAcknowledgeCommand(long commandId, bool ok, const String& errorMsg) {
  if (commandId <= 0) return;
  String payload = "{";
  payload += "\"_command_id\":" + String(commandId) + ",";
  payload += "\"_ok\":" + String(ok ? "true" : "false") + ",";
  if (ok) payload += "\"_error\":null";
  else    payload += "\"_error\":\"" + jsonEscape(errorMsg) + "\"";
  payload += "}";

  int code; String body;
  supabaseRequest("POST", "/rest/v1/rpc/device_command_done", payload, code, body, "return=minimal");
}

void supabaseEnsureActuator() {
  if (actuatorEnsured) return;
  if (!ensureSupabaseCredsPresent()) {
    Serial.println("[SUPA] missing credentials, skip actuator ensure");
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[SUPA] WiFi disconnected, skip actuator ensure");
    return;
  }

  uint32_t now = millis();
  if (now - lastActuatorEnsureMs < ACTUATOR_RETRY_MS) return;
  lastActuatorEnsureMs = now;

  Serial.println("[SUPA] ensuring servo actuator...");
  debugLogAnonKey("ensure_actuator");

  int code; String body;

  String rpcPayload = "{";
  rpcPayload += "\"_name\":\"" + jsonEscape(ACTUATOR_NAME) + "\",";
  rpcPayload += "\"_kind\":\"servo\",";
  rpcPayload += "\"_meta\":{\"pin\":" + String(SERVO_PIN) + "}";
  rpcPayload += "}";

  if (supabaseRequest("POST",
                      "/rest/v1/rpc/device_upsert_actuator",
                      rpcPayload,
                      code,
                      body)) {
    Serial.print("[SUPA] device_upsert_actuator -> HTTP ");
    Serial.println(code);
    if (code >= 200 && code < 300) {
      actuatorEnsured = true;
      Serial.println("[SUPA] actuator ensured via RPC");
      return;
    }
    Serial.print("[SUPA] device_upsert_actuator error body: ");
    Serial.println(body);
  } else {
    Serial.println("[SUPA] device_upsert_actuator request error");
  }

  Serial.println("[SUPA] falling back to REST actuators insert...");

  String payload = "[{";
  payload += "\"device_id\":\"" + jsonEscape(supa.deviceId) + "\",";
  payload += "\"name\":\"" + jsonEscape(ACTUATOR_NAME) + "\",";
  payload += "\"kind\":\"servo\",";
  payload += "\"meta\":{\"pin\":" + String(SERVO_PIN) + "}";
  payload += "}]";

  if (supabaseRequest("POST",
                      "/rest/v1/actuators?on_conflict=device_id,name",
                      payload,
                      code,
                      body,
                      "resolution=merge-duplicates,return=minimal")) {
    Serial.print("[SUPA] actuators POST -> HTTP ");
    Serial.println(code);
    if (code >= 200 && code < 300) {
      actuatorEnsured = true;
      Serial.println("[SUPA] actuator ensured successfully");
    } else {
      Serial.print("[SUPA] actuator ensure error body: ");
      Serial.println(body);
    }
  } else {
    Serial.println("[SUPA] actuators POST failed (request error)");
  }
}

void supabaseEnsureSystemActuator() {
  if (systemActuatorEnsured) return;
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  uint32_t now = millis();
  if (now - lastSystemEnsureMs < SYSTEM_RETRY_MS) return;
  lastSystemEnsureMs = now;

  int code; String body;
  String rpcPayload = "{";
  rpcPayload += "\"_name\":\"" + jsonEscape(SYSTEM_ACTUATOR_NAME) + "\",";
  rpcPayload += "\"_kind\":\"system\",";
  rpcPayload += "\"_meta\":{\"role\":\"factory-reset\"}";
  rpcPayload += "}";

  if (supabaseRequest("POST",
                      "/rest/v1/rpc/device_upsert_actuator",
                      rpcPayload,
                      code,
                      body)) {
    if (code >= 200 && code < 300) {
      systemActuatorEnsured = true;
      return;
    }
  }

  String payload = "[{";
  payload += "\"device_id\":\"" + jsonEscape(supa.deviceId) + "\",";
  payload += "\"name\":\"" + jsonEscape(SYSTEM_ACTUATOR_NAME) + "\",";
  payload += "\"kind\":\"system\",";
  payload += "\"meta\":{\"role\":\"factory-reset\"}";
  payload += "}]";

  if (supabaseRequest("POST",
                      "/rest/v1/actuators?on_conflict=device_id,name",
                      payload,
                      code,
                      body,
                      "resolution=merge-duplicates,return=minimal")) {
    if (code >= 200 && code < 300) {
      systemActuatorEnsured = true;
    }
  }
}

void supabaseApplyCommand(const String& commandJson,
                          bool& executed,
                          String& error) {
  executed = false;
  error = "";

  if (commandJson.indexOf("\"factory_reset\"") >= 0) {
    error = "factory_reset disabled";
    return;
  }

  bool targetOn  = servoOn;
  bool hasTarget = false;
  int  targetPos = servoPos;
  bool hasPos    = false;

  if (commandJson.indexOf("\"set_servo\"") < 0) {
    error = "unsupported action";
    return;
  }

  int idxOn = commandJson.indexOf("\"on\"");
  if (idxOn >= 0) {
    String sub = commandJson.substring(idxOn);
    int t = sub.indexOf("true");
    int f = sub.indexOf("false");
    if (t >= 0 && (f < 0 || t < f)) { targetOn = true; hasTarget = true; }
    else if (f >= 0) { targetOn = false; hasTarget = true; }
  }

  int idxPos = commandJson.indexOf("\"pos\"");
  if (idxPos >= 0) {
    int c = commandJson.indexOf(':', idxPos);
    if (c > 0) {
      int e = c + 1;
      while (e < (int)commandJson.length() && isspace((unsigned char)commandJson[e])) e++;
      int s = e;
      while (e < (int)commandJson.length() && isdigit((unsigned char)commandJson[e])) e++;
      if (e > s) {
        targetPos = constrain(commandJson.substring(s, e).toInt(), 0, 180);
        hasPos = true;
      }
    }
  }

  if (!hasTarget && !hasPos) {
    error = "missing payload";
    return;
  }

  if (hasPos) {
    moveServoTo(targetPos);
  } else if (hasTarget) {
    setServoOn(targetOn);
  }

  executed = true;
  supabaseHeartbeat(true);
}

void supabasePollCommands() {
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  int code; String body;
  if (!supabaseRequest("POST",
                       "/rest/v1/rpc/device_next_command",
                       "{}",
                       code,
                       body,
                       "return=representation")) {
    return;
  }
  if (code < 200 || code >= 300) return;
  if (body.length() < 5) return;

  int objStart = body.indexOf('{');
  int objEnd   = body.lastIndexOf('}');
  if (objStart < 0 || objEnd <= objStart) return;
  String obj = body.substring(objStart, objEnd + 1);

  long commandId = 0;
  int idxCmd = obj.indexOf("\"command_id\"");
  if (idxCmd >= 0) {
    int colon = obj.indexOf(':', idxCmd);
    if (colon > 0) {
      int e = colon + 1;
      while (e < (int)obj.length() && isspace((unsigned char)obj[e])) e++;
      int s = e;
      while (e < (int)obj.length() && isdigit((unsigned char)obj[e])) e++;
      if (e > s) commandId = obj.substring(s, e).toInt();
    }
  }

  if (commandId <= 0) return;

  int idxCommand = obj.indexOf("\"command\"");
  if (idxCommand < 0) {
    supabaseAcknowledgeCommand(commandId, false, "missing command");
    return;
  }
  int start = obj.indexOf('{', idxCommand);
  int braces = 0;
  int end = -1;
  for (int i = start; i < (int)obj.length(); ++i) {
    if (obj[i] == '{') braces++;
    else if (obj[i] == '}') {
      braces--;
      if (braces == 0) { end = i; break; }
    }
  }
  if (start < 0 || end <= start) {
    supabaseAcknowledgeCommand(commandId, false, "invalid command format");
    return;
  }
  String commandJson = obj.substring(start, end + 1);

  bool executed;
  String error;
  supabaseApplyCommand(commandJson, executed, error);
  supabaseAcknowledgeCommand(commandId, executed, executed ? "" : error);
}

void supabaseMarkRemoteForgetDone() {
  int code; String body;
  supabaseRequest("POST",
                  "/rest/v1/rpc/device_mark_remote_forget_done",
                  "{}",
                  code,
                  body,
                  "return=minimal");
}

void supabasePollRemoteFlags() {
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  const uint32_t now = millis();
  if (now - lastRemoteFlagsPollMs < REMOTE_FLAGS_POLL_MS) return;
  lastRemoteFlagsPollMs = now;

  int code; String body;
  if (!supabaseRequest("POST",
                       "/rest/v1/rpc/device_take_remote_flags",
                       "{}",
                       code,
                       body,
                       "return=representation")) {
    return;
  }
  if (code < 200 || code >= 300) return;
  if (body.indexOf('{') < 0) return;

  if (jsonFlagTrue(body, "ping_requested")) {
    Serial.println("[SUPA] ping remoto solicitado (ack enviado)");
  }

  if (jsonFlagTrue(body, "forget_requested")) {
    Serial.println("[SUPA] remote forget flag ignored (disabled).");
  }
}

void handleSupabase() {
  if (!ensureSupabaseCredsPresent()) return;
  supabaseEnsureActuator();
  supabaseEnsureSystemActuator();
  uint32_t now = millis();
  supabaseHeartbeat(false);
  if (now - lastCommandPollMs >= COMMAND_POLL_MS) {
    lastCommandPollMs = now;
    supabasePollCommands();
  }
  supabasePollRemoteFlags();
}

void handleProvision() {
  handleCors();
  if (!http.hasArg("plain")) {
    http.send(400, "application/json", "{\"error\":\"no-body\"}");
    return;
  }
  const String& body = http.arg("plain");

  String ssid = jsonExtractString(body, "ssid");
  String pass = jsonExtractString(body, "pass");
  String alias = jsonExtractString(body, "name");
  SupabaseCreds newSupa;
  newSupa.url       = jsonExtractString(body, "supabase_url");
  newSupa.anonKey   = jsonExtractString(body, "supabase_key");
  newSupa.deviceId  = jsonExtractString(body, "device_id");
  newSupa.deviceKey = jsonExtractString(body, "device_key");
  Serial.print("[PROVISION] Supabase URL payload: ");
  Serial.println(newSupa.url);

  ssid.trim();
  alias.trim();
  newSupa.url.trim();
  newSupa.anonKey.trim();
  newSupa.deviceId.trim();
  newSupa.deviceKey.trim();

  if (!newSupa.anonKey.length()) {
    newSupa.anonKey = SUPABASE_ANON_FALLBACK;
  }
  debugLogAnonKey("handleProvision");

  if (ssid.length() == 0) {
    http.send(400, "application/json", "{\"error\":\"ssid-empty\"}");
    return;
  }

  if (!newSupa.url.length() ||
      !newSupa.anonKey.length() ||
      !newSupa.deviceId.length() ||
      !newSupa.deviceKey.length()) {
    Serial.println("[PROVISION] Supabase credentials missing in payload.");
    http.send(400, "application/json", "{\"error\":\"supabase-credentials-missing\"}");
    return;
  }

  if (alias.length() > 0) deviceName = alias;

  if (newSupa.deviceKey.length()) {
    const int len = newSupa.deviceKey.length();
    const int start = len > 6 ? len - 6 : 0;
    const String suffix = newSupa.deviceKey.substring(start);
    Serial.printf("[PROVISION] Received device key len=%d suffix=%s\n", len, suffix.c_str());
  } else {
    Serial.println("[PROVISION] Received device key empty.");
  }

  saveWifiCreds(ssid, pass, alias);
  saveSupabaseCreds(newSupa);

  bool ok = connectSta(ssid, pass);
  if (ok) {
    stopSoftAP();
    startMdns(80);
    supa = newSupa;
    actuatorEnsured = false;
    systemActuatorEnsured = false;
    lastActuatorEnsureMs = 0;
    lastSystemEnsureMs = 0;
    supabaseEnsureActuator();
    supabaseEnsureSystemActuator();
    supabaseHeartbeat(true);

    String resp = "{";
    resp += "\"ok\":true,";
    resp += "\"ip\":\""   + jsonEscape(WiFi.localIP().toString()) + "\",";
    resp += "\"host\":\"" + jsonEscape(hostLabel) + "\"";
    resp += "}";
    http.send(200, "application/json", resp);
  } else {
    http.send(200, "application/json", "{\"ok\":false}");
  }
}

void startApProvision() {
  uint8_t mac[6]; WiFi.macAddress(mac);
  char ssid[32];
  snprintf(ssid, sizeof(ssid), "CASA-ESP_%02X%02X%02X", mac[3], mac[4], mac[5]);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssid);
  delay(100);
#if defined(ESP8266)
  IPAddress apIP(192,168,4,1);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255,255,255,0));
#endif

  http.on("/",           HTTP_GET,     handleRoot);
  http.on("/nets",       HTTP_GET,     handleNets);
  http.on("/provision",  HTTP_OPTIONS, handleOptions);
  http.on("/provision",  HTTP_POST,    handleProvision);
  http.on("/info",       HTTP_GET,     handleInfo);
  http.on("/sensors",    HTTP_GET,     handleSensors);
  http.on("/servo",      HTTP_OPTIONS, handleOptions);
  http.on("/servo",      HTTP_GET,     handleServoGet);
  http.on("/servo",      HTTP_POST,    handleServoPost);
  http.on("/apmode",     HTTP_GET,     handleFactoryResetHttp);
  http.on("/factory",    HTTP_GET,     handleFactoryResetHttp);
  http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
  http.on("/factory_reset", HTTP_POST,  handleFactoryResetHttp);
  http.onNotFound(handleRoot);
  http.begin();

  Serial.print("AP listo: "); Serial.println(ssid);
  Serial.println("http://192.168.4.1/nets  |  POST /provision");
}

void performRemoteReset() {
  Serial.println("[SUPA] limpiando credenciales y reiniciando...");
  clearWifiCreds();
  clearSupabaseCreds();
  delay(200);
  ESP.restart();
}

void enterSoftApNow() {
  Serial.println(">> Limpiando credenciales y volviendo a SoftAP...");
  clearWifiCreds();
  clearSupabaseCreds();
  actuatorEnsured = false;
  systemActuatorEnsured = false;
  lastActuatorEnsureMs = 0;
  lastSystemEnsureMs = 0;
  delay(150);
#if defined(ESP32)
  MDNS.end();
#endif
  http.stop();
  delay(100);
  startApProvision();
}

void setup() {
  Serial.begin(115200);
  delay(100);
  makeUniqueHostLabel();

#if defined(ESP32)
  servo.attach(SERVO_PIN, 500, 2400);
#else
  servo.attach(SERVO_PIN);
#endif
  moveServoTo(0);

  String ssid, pass;
  bool hasWifi = loadWifiCreds(ssid, pass);
  loadSupabaseCreds();
  Serial.printf("[DEBUG] deviceId=%s | deviceKey=%s\n",
                supa.deviceId.c_str(),
                supa.deviceKey.c_str());

  uint8_t mac[6]; WiFi.macAddress(mac);
  Serial.printf("DeviceID: %s | Hostname: %s | MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                deviceIdHex().c_str(), hostLabel.c_str(),
                mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
  Serial.println("Serial: enviar '1' -> factory reset / SoftAP");

  if (hasWifi && connectSta(ssid, pass)) {
    Serial.print("Conectado. IP: "); Serial.println(WiFi.localIP());
    startMdns(80);
    http.on("/",        HTTP_GET,  [](){ handleCors(); http.send(200,"text/plain","ok"); });
    http.on("/info",    HTTP_GET,  handleInfo);
    http.on("/sensors", HTTP_GET,  handleSensors);
    http.on("/servo",   HTTP_OPTIONS, handleOptions);
    http.on("/servo",   HTTP_GET,     handleServoGet);
    http.on("/servo",   HTTP_POST,    handleServoPost);
    http.on("/apmode",  HTTP_GET,     handleFactoryResetHttp);
    http.on("/factory", HTTP_GET,     handleFactoryResetHttp);
    http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
    http.on("/factory_reset", HTTP_POST,  handleFactoryResetHttp);
    http.begin();

    actuatorEnsured = false;
    lastActuatorEnsureMs = 0;
    supabaseEnsureActuator();
    systemActuatorEnsured = false;
    lastSystemEnsureMs = 0;
    supabaseEnsureSystemActuator();
    supabaseHeartbeat(true);
  } else {
    Serial.println("Sin credenciales o fallo STA -> modo AP");
    startApProvision();
  }
}

void loop() {
  http.handleClient();
#if defined(ESP8266)
  MDNS.update();
#endif

  if (pendingSoftAp) {
    pendingSoftAp = false;
    enterSoftApNow();
    return;
  }

  handleSupabase();

  if (Serial.available()) {
    int ch = Serial.read();
    if (ch == '1') {
      enterSoftApNow();
    }
  }
}
