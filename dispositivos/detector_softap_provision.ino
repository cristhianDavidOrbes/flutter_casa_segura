#if !defined(ESP32)
  #error "Este firmware de detector requiere ESP32"
#endif

#include <WiFi.h>
#include <ESPmDNS.h>
#include <WebServer.h>
#include <Preferences.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

// ===== Pines =====
const int PIN_US_TRIG  = 4;   // D4  -> Trigger del HC-SR04
const int PIN_US_ECHO  = 21;  // D21 -> Echo del HC-SR04 (usar divisor a 3.3V)

// ===== Identidad =====
const char* DEVICE_TYPE = "detector";
const char* SUPABASE_ANON_FALLBACK =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxbXlkeWVzYWZuaG9taHpld3NxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTkyNzY0OTgsImV4cCI6MjA3NDg1MjQ5OH0.YFteDpgiU87dwNq2PIaDrm28h5w6nu0T0mLEUjmTrmU";

String deviceName = "casa-esp";
String hostLabel  = "casa-esp";

WebServer http(80);
Preferences prefs;

struct SupabaseCreds {
  String url;
  String anonKey;
  String deviceId;
  String deviceKey;
} supa;

bool supabaseReady = false;
uint32_t lastHeartbeatMs = 0;

const uint32_t HEARTBEAT_MS = 1000;
const uint32_t SENSOR_REFRESH_MS = 400;
const uint32_t COMMAND_POLL_MS = 1500;
const uint32_t ACTUATOR_ENSURE_MS = 10000;
const uint32_t REMOTE_FLAGS_POLL_MS = 10000;

bool pendingSoftAp = false;
bool systemActuatorEnsured = false;
uint32_t lastCommandPollMs = 0;
uint32_t lastActuatorEnsureMs = 0;
uint32_t lastRemoteFlagsPollMs = 0;
const char* SYSTEM_ACTUATOR_NAME = "system_control";

// ===== Forward declarations =====
void updateSensors(bool forceNow = false);
void supabaseHeartbeat(bool forceNow);

// ===== Utilidades =====
String deviceIdHex() {
  uint64_t chipid = ESP.getEfuseMac();
  char buf[17];
  sprintf(buf, "%04X%08X",
          (uint16_t)(chipid >> 32),
          (uint32_t)(chipid & 0xFFFFFFFF));
  String s(buf);
  s.toUpperCase();
  return s;
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

String jsonEscape(const String& in) {
  String out;
  out.reserve(in.length() + 8);
  for (size_t i = 0; i < in.length(); ++i) {
    char c = in[i];
    if (c == '"' || c == '\\') {
      out += '\\'; out += c;
    } else if (c == '\n') {
      out += "\\n";
    } else if ((uint8_t)c < 0x20) {
      // ignora controles restantes
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
  ++i;  // skip opening quote

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

// ===== Almacenamiento de credenciales =====
bool loadWifiCreds(String& ssid, String& pass) {
  prefs.begin("wifi", true);
  ssid = prefs.getString("ssid", "");
  pass = prefs.getString("pass", "");
  String alias = prefs.getString("alias", "");
  prefs.end();
  if (alias.length() > 0) deviceName = alias;
  return ssid.length() > 0;
}

void saveWifiCreds(const String& ssid, const String& pass, const String& alias) {
  prefs.begin("wifi");
  prefs.putString("ssid", ssid);
  prefs.putString("pass", pass);
  prefs.putString("alias", alias);
  prefs.end();
  if (alias.length() > 0) deviceName = alias;
}

void clearWifiCreds() {
  prefs.begin("wifi");
  prefs.clear();
  prefs.end();
  WiFi.persistent(true);
  WiFi.disconnect(true, true);
  WiFi.persistent(false);
}

void ensureAnonFallback() {
  if (!supa.anonKey.length() && SUPABASE_ANON_FALLBACK[0] != '\0') {
    supa.anonKey = SUPABASE_ANON_FALLBACK;
  }
}

void saveSupabaseCreds(const SupabaseCreds& c) {
  prefs.begin("supa");
  prefs.putString("url",  c.url);
  prefs.putString("anon", c.anonKey);
  prefs.putString("id",   c.deviceId);
  prefs.putString("key",  c.deviceKey);
  prefs.end();
  supa = c;
  ensureAnonFallback();
}

void loadSupabaseCreds() {
  prefs.begin("supa", true);
  supa.url      = prefs.getString("url", "");
  supa.anonKey  = prefs.getString("anon", "");
  supa.deviceId = prefs.getString("id", "");
  supa.deviceKey= prefs.getString("key", "");
  prefs.end();
  ensureAnonFallback();
}

void clearSupabaseCreds() {
  prefs.begin("supa");
  prefs.clear();
  prefs.end();
  supa = SupabaseCreds{};
  ensureAnonFallback();
  supabaseReady = false;
}

bool ensureSupabaseCredsPresent() {
  return supa.url.length() && supa.anonKey.length() &&
         supa.deviceId.length() && supa.deviceKey.length();
}

// ===== Wi-Fi =====
void stopSoftAP() { WiFi.softAPdisconnect(true); }

void setHostnameAndDhcp() {
  makeUniqueHostLabel();
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
  WiFi.setHostname(hostLabel.c_str());
}

bool connectSta(const String& ssid, const String& pass, uint32_t timeoutMs = 15000) {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  setHostnameAndDhcp();
  WiFi.begin(ssid.c_str(), pass.c_str());

  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < timeoutMs) {
    delay(300);
  }
  return WiFi.status() == WL_CONNECTED;
}

// ===== HTTP helpers =====
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

// ===== mDNS =====
void startMdns(uint16_t portHttp) {
  if (MDNS.begin(hostLabel.c_str())) {
    MDNS.setInstanceName(deviceName.c_str());
    MDNS.addService("casa", "tcp", portHttp);
    MDNS.addServiceTxt("casa", "tcp", "name", deviceName.c_str());
    MDNS.addServiceTxt("casa", "tcp", "type", DEVICE_TYPE);
    MDNS.addServiceTxt("casa", "tcp", "id", deviceIdHex().c_str());
    MDNS.addServiceTxt("casa", "tcp", "host", hostLabel.c_str());
    MDNS.addServiceTxt("casa", "tcp", "http", String(portHttp).c_str());
  }
}

// ===== Supabase =====
bool supabaseRequest(const String& method,
                     const String& path,
                     const String& payload,
                     int& outCode,
                     String& outBody,
                     const char* prefer = nullptr) {
  if (!ensureSupabaseCredsPresent()) return false;
  if (WiFi.status() != WL_CONNECTED) return false;

  String url = supa.url + path;

  for (int attempt = 0; attempt < 2; ++attempt) {
    WiFiClientSecure client;
    client.setInsecure();
    HTTPClient httpc;
    if (!httpc.begin(client, url)) {
      Serial.print("[SUPA] http.begin failed url=");
      Serial.println(url);
      return false;
    }

    httpc.addHeader("Content-Type", "application/json");
    httpc.addHeader("apikey", supa.anonKey);
    httpc.addHeader("Authorization", "Bearer " + supa.anonKey);
    httpc.addHeader("x-device-key", supa.deviceKey);
    if (prefer) httpc.addHeader("Prefer", prefer);

    if (method == "POST")      outCode = httpc.POST(payload);
    else if (method == "GET")  outCode = httpc.GET();
    else if (method == "PATCH")outCode = httpc.PATCH(payload);
    else if (method == "PUT")  outCode = httpc.PUT(payload);
    else                       outCode = httpc.sendRequest(method.c_str(), (uint8_t*)payload.c_str(), payload.length());

    outBody = httpc.getString();
    httpc.end();

    if (outCode > 0) {
      return true;
    }

    Serial.print("[SUPA] http request failed code=");
    Serial.println(outCode);
    if (attempt == 0) {
      delay(150);
      continue;
    }
    break;
  }
  return false;
}

// ===== Sensores =====
struct SensorSnapshot {
  long ultraCm     = -1;
  bool ultraOk     = false;
  uint32_t updated = 0;
} sensorState;

long readUltrasonicCM(uint32_t timeoutUs = 30000UL) {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);

  unsigned long dur = pulseIn(PIN_US_ECHO, HIGH, timeoutUs);
  if (dur == 0) return -1;
  return (long)(dur / 58.0);  // ida y vuelta en cm
}

void updateSensors(bool forceNow) {
  uint32_t now = millis();
  if (!forceNow && (now - sensorState.updated) < SENSOR_REFRESH_MS) return;

  long cm = readUltrasonicCM();

  sensorState.ultraCm = cm;
  sensorState.ultraOk = (cm >= 0);
  sensorState.updated = now;

  Serial.printf("[SENS] ultra_cm=%ld ultra_ok=%s\n",
                sensorState.ultraOk ? sensorState.ultraCm : -1,
                sensorState.ultraOk ? "true" : "false");
}

void supabaseHeartbeat(bool forceNow) {
  if (!ensureSupabaseCredsPresent()) return;
  uint32_t now = millis();
  if (!forceNow && (now - lastHeartbeatMs) < HEARTBEAT_MS) return;
  if (WiFi.status() != WL_CONNECTED) return;

  updateSensors(true);
  lastHeartbeatMs = now;

  String extra = "{";
  extra += "\"ultra_cm\":"  + String(sensorState.ultraOk ? sensorState.ultraCm : -1) + ",";
  extra += "\"ultra_ok\":"  + String(sensorState.ultraOk ? "true" : "false") + ",";
  extra += "\"host\":\""   + jsonEscape(hostLabel) + "\",";
  extra += "\"ip\":\""     + jsonEscape(WiFi.localIP().toString()) + "\"";
  extra += "}";

  double numeric = sensorState.ultraOk ? (double)sensorState.ultraCm : -1.0;
  String textState = sensorState.ultraOk ? "distance" : "no-data";

  String payload = "{";
  payload += "\"_device_name\":\"" + jsonEscape(deviceName) + "\",";
  payload += "\"_sensor_name\":\"" + jsonEscape("detector_state") + "\",";
  payload += "\"_kind\":\"other\",";
  payload += "\"_value_numeric\":" + String(numeric, 2) + ",";
  payload += "\"_value_text\":\"" + jsonEscape(textState) + "\",";
  payload += "\"_extra\":" + extra;
  payload += "}";

  int code; String body;
  if (!supabaseRequest("POST", "/rest/v1/rpc/upsert_live_signal", payload, code, body, "return=minimal")) {
    Serial.println("[SUPA] heartbeat request error");
    return;
  }
  if (code < 200 || code >= 300) {
    Serial.print("[SUPA] heartbeat HTTP ");
    Serial.println(code);
    Serial.println(body);
  }
}

void supabaseAcknowledgeCommand(long commandId, bool ok, const String& errorMsg) {
  if (commandId <= 0) return;
  String payload = "{";
  payload += "\"_command_id\":" + String(commandId) + ",";
  payload += "\"_ok\":" + String(ok ? "true" : "false") + ",";
  if (ok) {
    payload += "\"_error\":null";
  } else {
    payload += "\"_error\":\"" + jsonEscape(errorMsg) + "\"";
  }
  payload += "}";

  int code; String body;
  supabaseRequest("POST",
                  "/rest/v1/rpc/device_command_done",
                  payload,
                  code,
                  body,
                  "return=minimal");
}

void supabaseEnsureSystemActuator() {
  if (systemActuatorEnsured) return;
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  uint32_t now = millis();
  if (now - lastActuatorEnsureMs < ACTUATOR_ENSURE_MS) return;
  lastActuatorEnsureMs = now;

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

void supabasePollCommands() {
  if (!systemActuatorEnsured) return;
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  uint32_t now = millis();
  if (now - lastCommandPollMs < COMMAND_POLL_MS) return;
  lastCommandPollMs = now;

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
    supabaseAcknowledgeCommand(commandId, false, "invalid command payload");
    return;
  }
  String commandJson = obj.substring(start, end + 1);

  bool executed = false;
  String error = "";
  if (commandJson.indexOf("\"factory_reset\"") >= 0) {
    error = "factory_reset disabled";
  } else {
    error = "unsupported action";
  }

  supabaseAcknowledgeCommand(commandId, executed, error);
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

  uint32_t now = millis();
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

// ===== HTTP endpoints =====
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
  updateSensors(true);

  String json = "{";
  json += "\"ultrasonic\":{";
  json += "\"ok\":" + String(sensorState.ultraOk ? "true" : "false") + ",";
  json += "\"cm\":" + String(sensorState.ultraOk ? sensorState.ultraCm : -1);
  json += "}";
  json += "}";
  http.send(200, "application/json", json);
}

// ===== Provisionamiento =====
void handleProvision() {
  handleCors();
  if (!http.hasArg("plain")) {
    http.send(400, "application/json", "{\"error\":\"no-body\"}");
    return;
  }
  const String& body = http.arg("plain");

  String ssid  = jsonExtractString(body, "ssid");
  String pass  = jsonExtractString(body, "pass");
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

  saveWifiCreds(ssid, pass, alias);
  saveSupabaseCreds(newSupa);

  bool ok = connectSta(ssid, pass);
  if (ok) {
    stopSoftAP();
    supa = newSupa;
    supabaseReady = ensureSupabaseCredsPresent();
    lastHeartbeatMs = 0;
    supabaseHeartbeat(true);
    systemActuatorEnsured = false;
    lastActuatorEnsureMs = 0;
    lastCommandPollMs = 0;
    supabaseEnsureSystemActuator();

    startMdns(80);

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
  char ssidAp[32];
  snprintf(ssidAp, sizeof(ssidAp), "CASA-ESP_%02X%02X%02X", mac[3], mac[4], mac[5]);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(ssidAp);
  delay(120);

  http.on("/",           HTTP_GET,     handleRoot);
  http.on("/nets",       HTTP_GET,     handleNets);
  http.on("/provision",  HTTP_OPTIONS, handleOptions);
  http.on("/provision",  HTTP_POST,    handleProvision);
  http.on("/info",       HTTP_GET,     handleInfo);
  http.on("/sensors",    HTTP_GET,     handleSensors);
  http.on("/apmode",     HTTP_GET,     handleFactoryResetHttp);
  http.on("/factory",    HTTP_GET,     handleFactoryResetHttp);
  http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
  http.on("/factory_reset", HTTP_POST,  handleFactoryResetHttp);
  http.onNotFound(handleRoot);
  http.begin();

  Serial.print("AP listo: "); Serial.println(ssidAp);
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
  systemActuatorEnsured = false;
  lastActuatorEnsureMs = 0;
  lastCommandPollMs = 0;
  delay(150);
  MDNS.end();
  http.stop();
  delay(100);
  startApProvision();
}

// ===== Handlers de API STA =====
void configureStaHttp() {
  http.on("/",        HTTP_GET,  [](){ handleCors(); http.send(200,"text/plain","ok"); });
  http.on("/info",    HTTP_GET,  handleInfo);
  http.on("/sensors", HTTP_GET,  handleSensors);
  http.on("/apmode",  HTTP_GET,  handleFactoryResetHttp);
  http.on("/factory", HTTP_GET,  handleFactoryResetHttp);
  http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
  http.on("/factory_reset", HTTP_POST, handleFactoryResetHttp);
  http.on("/reset",   HTTP_GET,  [](){
    handleCors();
    http.send(200,"application/json","{\"ok\":true,\"mode\":\"ap\"}");
    delay(150);
    enterSoftApNow();
  });
  http.begin();
}

// ===== Setup & Loop =====
void setup() {
  Serial.begin(115200);
  delay(150);
  makeUniqueHostLabel();

  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  digitalWrite(PIN_US_TRIG, LOW);

  String ssid, pass;
  bool hasWifi = loadWifiCreds(ssid, pass);
  loadSupabaseCreds();
  supabaseReady = ensureSupabaseCredsPresent();

  Serial.printf("[DEBUG] deviceId=%s | host=%s\n", deviceIdHex().c_str(), hostLabel.c_str());
  Serial.println("Serial: enviar '1' -> factory reset / SoftAP");

  if (hasWifi && connectSta(ssid, pass)) {
    Serial.print("Conectado. IP: "); Serial.println(WiFi.localIP());
    startMdns(80);
    configureStaHttp();
    lastHeartbeatMs = 0;
    supabaseHeartbeat(true);
    systemActuatorEnsured = false;
    lastActuatorEnsureMs = 0;
    lastCommandPollMs = 0;
    supabaseEnsureSystemActuator();
  } else {
    Serial.println("Sin credenciales o fallo STA -> modo AP");
    startApProvision();
  }
}

void loop() {
  http.handleClient();
  if (pendingSoftAp) {
    pendingSoftAp = false;
    enterSoftApNow();
    return;
  }
  updateSensors(false);
  supabaseHeartbeat(false);
  supabaseEnsureSystemActuator();
  supabasePollCommands();
  supabasePollRemoteFlags();

  if (Serial.available()) {
    int ch = Serial.read();
    if (ch == '1') {
      enterSoftApNow();
    }
  }
}
