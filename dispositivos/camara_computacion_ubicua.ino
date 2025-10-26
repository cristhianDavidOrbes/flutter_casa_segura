/**
 * ESP32-CAM (AI Thinker) + Supabase remoto + SoftAP provisioning.
 *
 * Capacidades:
 *  - SoftAP "CASA-ESP_xxxx" con /nets y /provision para recibir credenciales.
 *  - Guarda SSID/clave/alias y también supabase_url, supabase_key, device_id, device_key.
 *  - Tras provisionar: conecta a la red doméstica, anuncia mDNS (_casa._tcp) y expone /ping, /info,
 *    /status, /nets, /provision, /photo, /stream.
 *  - Heartbeat a Supabase (upsert_live_signal) con IP/RSSI.
 *  - Subida de snapshot cada segundo a Storage + metadata en live_signals.extra.
 *  - Serial ‘1’ fuerza factory reset (borra credenciales y vuelve a SoftAP).
 *
 * Requisitos:
 *  - ESP32-CAM AI Thinker (PSRAM habilitada).
 *  - Librería esp32cam + helper WifiCam.hpp con addCameraHandlers().
 */

#include <WiFi.h>
#include <ESPmDNS.h>
#include <WebServer.h>
#include <Preferences.h>
#include <esp32cam.h>
#include <esp_camera.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

#include "WifiCam.hpp"

using namespace esp32cam;

// ---------- Estado global ----------
WebServer http(80);
Preferences prefs;

static const char* DEVICE_TYPE = "esp32cam";
String deviceName = "casa-esp-cam";
String hostLabel  = "casa-esp-cam";

static const char* SNAPSHOT_BUCKET = "camera_frames";
static const uint32_t SNAPSHOT_INTERVAL_MS = 1000;

struct WifiCreds { String ssid, pass, alias; };
struct SupabaseCreds { String url, anonKey, deviceId, deviceKey; };

WifiCreds wifiCreds;
SupabaseCreds supaCreds;

constexpr const char* PREF_WIFI = "wifi";
constexpr const char* PREF_SUPA = "supa";

uint32_t lastSnapshotSentMs = 0;
bool pendingSoftAp = false;
const uint32_t COMMAND_POLL_MS = 1500;
const uint32_t ACTUATOR_ENSURE_MS = 10000;
bool systemActuatorEnsured = false;
uint32_t lastCommandPollMs = 0;
uint32_t lastActuatorEnsureMs = 0;
const uint32_t REMOTE_FLAGS_POLL_MS = 10000;
uint32_t lastRemoteFlagsPollMs = 0;
const char* SYSTEM_ACTUATOR_NAME = "system_control";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
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
  String o;
  o.reserve(in.length() + 8);
  for (char c : in) {
    if (c == '"' || c == '\\') {
      o += '\\'; o += c;
    } else if ((uint8_t)c < 0x20) {
      // ignora caracteres de control
    } else {
      o += c;
    }
  }
  return o;
}

bool jsonFlagTrue(const String& body, const char* key) {
  String pattern = "\"" + String(key) + "\":true";
  if (body.indexOf(pattern) >= 0) return true;
  pattern = "\"" + String(key) + "\": true";
  if (body.indexOf(pattern) >= 0) return true;
  return false;
}

void sendJson(int code, const String& payload) {
  http.sendHeader("Access-Control-Allow-Origin", "*");
  http.sendHeader("Access-Control-Allow-Headers", "Content-Type");
  http.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  http.send(code, "application/json", payload);
}

void sendOkJson() { sendJson(200, "{\"ok\":true}"); }

// ---------------------------------------------------------------------------
// Persistencia de credenciales
// ---------------------------------------------------------------------------
void loadWifiCreds() {
  prefs.begin(PREF_WIFI, true);
  wifiCreds.ssid  = prefs.getString("ssid", "");
  wifiCreds.pass  = prefs.getString("pass", "");
  wifiCreds.alias = prefs.getString("alias", "");
  prefs.end();
  if (!wifiCreds.alias.isEmpty()) deviceName = wifiCreds.alias;
}

void saveWifiCreds(const WifiCreds& c) {
  prefs.begin(PREF_WIFI);
  prefs.putString("ssid",  c.ssid);
  prefs.putString("pass",  c.pass);
  prefs.putString("alias", c.alias);
  prefs.end();
}

void clearWifiCreds() {
  prefs.begin(PREF_WIFI); prefs.clear(); prefs.end();
  WiFi.persistent(true); WiFi.disconnect(true, true); WiFi.persistent(false);
}

void loadSupabaseCreds() {
  prefs.begin(PREF_SUPA, true);
  supaCreds.url       = prefs.getString("url", "");
  supaCreds.anonKey   = prefs.getString("anon", "");
  supaCreds.deviceId  = prefs.getString("id", "");
  supaCreds.deviceKey = prefs.getString("key", "");
  prefs.end();
}

void saveSupabaseCreds(const SupabaseCreds& c) {
  prefs.begin(PREF_SUPA);
  prefs.putString("url",  c.url);
  prefs.putString("anon", c.anonKey);
  prefs.putString("id",   c.deviceId);
  prefs.putString("key",  c.deviceKey);
  prefs.end();
}

void clearSupabaseCreds() {
  prefs.begin(PREF_SUPA); prefs.clear(); prefs.end();
  supaCreds = SupabaseCreds{};
}

// ---------------------------------------------------------------------------
// SoftAP
// ---------------------------------------------------------------------------
String buildSoftApName() {
  uint8_t mac[6]; WiFi.macAddress(mac);
  char ssid[32];
  snprintf(ssid, sizeof(ssid), "CASA-ESP_%02X%02X%02X", mac[3], mac[4], mac[5]);
  return String(ssid);
}

// ---------------------------------------------------------------------------
// IP única (estática derivada)
// ---------------------------------------------------------------------------
uint8_t deriveHostOctetFromMac() {
  uint8_t mac[6]; WiFi.macAddress(mac);
  uint8_t h = mac[3] ^ mac[4] ^ mac[5];
  uint8_t oct = (h % 200) + 20;
  if (oct == 255) oct = 254;
  if (oct <= 1) oct = 20;
  if (oct == 16) oct = 21;
  return oct;
}

bool applyUniqueStaticIP() {
  IPAddress dhcpIP = WiFi.localIP();
  IPAddress gateway = WiFi.gatewayIP();
  IPAddress subnet = WiFi.subnetMask();
  IPAddress dns1 = WiFi.dnsIP(0);
  IPAddress dns2 = WiFi.dnsIP(1);

  if (dhcpIP == INADDR_NONE || gateway == INADDR_NONE || subnet == INADDR_NONE) {
    Serial.println("[IP-UNICA] DHCP incompleto; manteniendo DHCP.");
    return false;
  }

  uint8_t uniqueOct = deriveHostOctetFromMac();
  IPAddress candidate(dhcpIP[0], dhcpIP[1], dhcpIP[2], uniqueOct);

  IPAddress bcast(
    (dhcpIP[0] & subnet[0]) | (~subnet[0]),
    (dhcpIP[1] & subnet[1]) | (~subnet[1]),
    (dhcpIP[2] & subnet[2]) | (~subnet[2]),
    (dhcpIP[3] & subnet[3]) | (~subnet[3])
  );
  if (candidate == gateway || candidate == bcast) {
    uniqueOct = uniqueOct == 254 ? 253 : uniqueOct + 1;
    candidate = IPAddress(dhcpIP[0], dhcpIP[1], dhcpIP[2], uniqueOct);
  }

  if (candidate == dhcpIP) {
    Serial.printf("[IP-UNICA] DHCP = %s (ya es única)\n", dhcpIP.toString().c_str());
    return false;
  }

  Serial.printf("[IP-UNICA] DHCP %s -> estática %s\n",
                dhcpIP.toString().c_str(), candidate.toString().c_str());

  WiFi.disconnect(true, false);
  delay(100);
  if (!WiFi.config(candidate, gateway, subnet, dns1, dns2)) {
    Serial.println("[IP-UNICA] WiFi.config falló, vuelvo a DHCP.");
    WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
    WiFi.begin(wifiCreds.ssid.c_str(), wifiCreds.pass.c_str());
    return false;
  }

  WiFi.begin(wifiCreds.ssid.c_str(), wifiCreds.pass.c_str());
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 7000) delay(200);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("[IP-UNICA] Conectado con %s\n", WiFi.localIP().toString().c_str());
    return true;
  }

  Serial.println("[IP-UNICA] Falla reconexión, regreso a DHCP.");
  WiFi.disconnect(true, false);
  delay(100);
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
  WiFi.begin(wifiCreds.ssid.c_str(), wifiCreds.pass.c_str());
  return false;
}

// ---------------------------------------------------------------------------
// Conexión STA
// ---------------------------------------------------------------------------
bool connectSta(uint32_t timeoutMs = 20000) {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  makeUniqueHostLabel();
  WiFi.config(INADDR_NONE, INADDR_NONE, INADDR_NONE);
  WiFi.setHostname(hostLabel.c_str());
  WiFi.begin(wifiCreds.ssid.c_str(), wifiCreds.pass.c_str());
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < timeoutMs) {
    delay(250);
  }
  if (WiFi.status() != WL_CONNECTED) return false;
  applyUniqueStaticIP();
  return true;
}

// ---------------------------------------------------------------------------
// mDNS
// ---------------------------------------------------------------------------
void startMdns(uint16_t portHttp = 80) {
  if (MDNS.begin(hostLabel.c_str())) {
    MDNS.setInstanceName(deviceName.c_str());
    MDNS.addService("casa", "tcp", 8266);
    MDNS.addServiceTxt("casa", "tcp", "name", deviceName.c_str());
    MDNS.addServiceTxt("casa", "tcp", "type", DEVICE_TYPE);
    MDNS.addServiceTxt("casa", "tcp", "id",   deviceIdHex().c_str());
    MDNS.addServiceTxt("casa", "tcp", "host", hostLabel.c_str());
    MDNS.addServiceTxt("casa", "tcp", "http", String(portHttp).c_str());
  }
}

// ---------------------------------------------------------------------------
// HTTP handlers
// ---------------------------------------------------------------------------
String buildInfoJson() {
  String json = "{";
  json += "\"deviceId\":\"" + jsonEscape(deviceIdHex()) + "\",";
  json += "\"name\":\"" + jsonEscape(deviceName) + "\",";
  json += "\"type\":\"" + jsonEscape(DEVICE_TYPE) + "\",";
  json += "\"host\":\"" + jsonEscape(hostLabel) + "\",";
  json += "\"ip\":\"" + jsonEscape(WiFi.isConnected() ? WiFi.localIP().toString() : "0.0.0.0") + "\",";
  json += "\"photo\":\"/photo\",";
  json += "\"stream\":\"/stream\",";
  json += "\"supabaseUrl\":\"" + jsonEscape(supaCreds.url) + "\"";
  json += "}";
  return json;
}

void handleRoot() { sendOkJson(); }
void handleInfo() { sendJson(200, buildInfoJson()); }

void handleNets() {
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
  sendJson(200, out);
}

void handleOptions() { sendJson(204, "{}"); }

void handleFactoryResetHttp() {
  sendJson(200, "{\"ok\":true,\"action\":\"softap\"}");
  pendingSoftAp = true;
}

class JsonExtractor {
public:
  explicit JsonExtractor(const String& body) : _body(body) {}
  String str(const char* key) const {
    String k = "\"" + String(key) + "\"";
    int keyPos = _body.indexOf(k);
    if (keyPos < 0) return "";
    int colon = _body.indexOf(':', keyPos + k.length());
    if (colon < 0) return "";
    int startQuote = _body.indexOf('"', colon + 1);
    if (startQuote < 0) return "";
    int endQuote = _body.indexOf('"', startQuote + 1);
    if (endQuote < 0) return "";
    return _body.substring(startQuote + 1, endQuote);
  }
private:
  const String& _body;
};

void handleProvision() {
  if (!http.hasArg("plain")) {
    sendJson(400, "{\"error\":\"no-body\"}");
    return;
  }
  const String& body = http.arg("plain");
  JsonExtractor j(body);

  WifiCreds newWifi;
  newWifi.ssid  = j.str("ssid");
  newWifi.pass  = j.str("pass");
  newWifi.alias = j.str("name");

  SupabaseCreds newSupa;
  newSupa.url       = j.str("supabase_url");
  newSupa.anonKey   = j.str("supabase_key");
  newSupa.deviceId  = j.str("device_id");
  newSupa.deviceKey = j.str("device_key");

  if (!newWifi.ssid.length()) {
    sendJson(400, "{\"error\":\"ssid-empty\"}");
    return;
  }
  if (!newWifi.alias.isEmpty()) deviceName = newWifi.alias;

  wifiCreds = newWifi;
  supaCreds = newSupa;

  saveWifiCreds(wifiCreds);
  saveSupabaseCreds(supaCreds);

  sendJson(200, "{\"ok\":true,\"message\":\"credentials-received\"}");
  delay(300);
  ESP.restart();
}

void startApProvision() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(buildSoftApName().c_str());
  delay(100);

  http.on("/",           HTTP_GET,      handleRoot);
  http.on("/info",       HTTP_GET,      handleInfo);
  http.on("/nets",       HTTP_GET,      handleNets);
  http.on("/provision",  HTTP_OPTIONS,  handleOptions);
  http.on("/provision",  HTTP_POST,     handleProvision);
  http.on("/apmode",     HTTP_GET,      handleFactoryResetHttp);
  http.on("/factory",    HTTP_GET,      handleFactoryResetHttp);
  http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
  http.on("/factory_reset", HTTP_POST,  handleFactoryResetHttp);

  addCameraHandlers();

  http.onNotFound(handleRoot);
  http.begin();

  Serial.println("[AP] SoftAP listo en 192.168.4.1");
}

void performRemoteReset() {
  Serial.println("[SUPABASE] limpiando credenciales y reiniciando...");
  clearWifiCreds();
  clearSupabaseCreds();
  delay(200);
  ESP.restart();
}

void enterSoftApNow() {
  Serial.println(">> Limpiando credenciales y cambiando a SoftAP...");
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

// ---------------------------------------------------------------------------
// Supabase helpers
// ---------------------------------------------------------------------------
bool ensureSupabaseCredsPresent() {
  return supaCreds.url.length()
      && supaCreds.anonKey.length()
      && supaCreds.deviceId.length()
      && supaCreds.deviceKey.length();
}

String snapshotObjectKey() {
  return supaCreds.deviceId.length()
    ? supaCreds.deviceId + "/latest.jpg"
    : hostLabel + "/latest.jpg";
}

String snapshotObjectPath() {
  return "/storage/v1/object/" + String(SNAPSHOT_BUCKET) + "/" + snapshotObjectKey();
}

bool httpPostJson(const String& path,
                  const String& payload,
                  int& outCode,
                  String& outBody,
                  bool preferMinimal = false) {
  if (!ensureSupabaseCredsPresent()) return false;
  if (WiFi.status() != WL_CONNECTED) return false;

  String url = supaCreds.url + path;

  WiFiClientSecure client;
  client.setTimeout(12000);
  client.setInsecure();

  HTTPClient httpc;
  if (!httpc.begin(client, url)) {
    Serial.println("[SUPABASE] begin() falló");
    return false;
  }

  httpc.addHeader("Content-Type", "application/json");
  httpc.addHeader("apikey", supaCreds.anonKey);
  httpc.addHeader("Authorization", "Bearer " + supaCreds.anonKey);
  httpc.addHeader("x-device-key", supaCreds.deviceKey);
  if (preferMinimal) {
    httpc.addHeader("Prefer", "return=minimal");
  }

  outCode = httpc.POST(payload);
  outBody = httpc.getString();
  httpc.end();
  return outCode > 0;
}

bool supabasePublishSnapshotMeta(const String& objectPath, size_t byteCount) {
  String extra = "{";
  extra += "\"snapshot\":\"" + jsonEscape(objectPath) + "\",";
  extra += "\"bytes\":" + String(byteCount);
  extra += "}";

  String payload = "{";
  payload += "\"_device_name\":\"" + jsonEscape(deviceName) + "\",";
  payload += "\"_sensor_name\":\"" + jsonEscape("camera_" + hostLabel) + "\",";
  payload += "\"_kind\":\"camera\",";
  payload += "\"_value_numeric\":null,";
  payload += "\"_value_text\":\"online\",";
  payload += "\"_extra\":" + extra;
  payload += "}";

  int code; String body;
  if (!httpPostJson("/rest/v1/rpc/upsert_live_signal", payload, code, body, true)) {
    Serial.println("[SUPABASE] snapshot meta POST falló");
    return false;
  }
  if (code < 200 || code >= 300) {
    Serial.printf("[SUPABASE] snapshot meta HTTP %d: %s\n", code, body.c_str());
    return false;
  }
  return true;
}

bool uploadSnapshot() {
  if (!ensureSupabaseCredsPresent()) return false;
  if (WiFi.status() != WL_CONNECTED) return false;

  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) return false;

  WiFiClientSecure client;
  client.setTimeout(12000);
  client.setInsecure();

  HTTPClient httpc;
  const String objectKey = snapshotObjectKey();
  const String url = supaCreds.url + "/storage/v1/object/" + SNAPSHOT_BUCKET + "/" + objectKey;

  if (!httpc.begin(client, url)) {
    esp_camera_fb_return(fb);
    Serial.println("[SUPABASE] begin() snapshot falló");
    return false;
  }

  httpc.addHeader("Content-Type", "image/jpeg");
  httpc.addHeader("apikey", supaCreds.anonKey);
  httpc.addHeader("Authorization", "Bearer " + supaCreds.anonKey);
  httpc.addHeader("x-upsert", "true");
  httpc.addHeader("x-device-key", supaCreds.deviceKey);

  int code = httpc.PUT(fb->buf, fb->len);
  String body = httpc.getString();
  httpc.end();

  if (code < 0) {
    Serial.printf("[SUPABASE] snapshot error %s\n", httpc.errorToString(code).c_str());
    esp_camera_fb_return(fb);
    return false;
  }

  if (code < 200 || code >= 300) {
    Serial.printf("[SUPABASE] snapshot HTTP %d -> %s\n", code, body.c_str());
    esp_camera_fb_return(fb);
    return false;
  }

  const String path = snapshotObjectPath();
  supabasePublishSnapshotMeta(path, fb->len);

  esp_camera_fb_return(fb);
  return true;
}

static const uint32_t HEARTBEAT_MS = 6000;
static uint32_t lastBeat = 0;

void supabaseHeartbeat(bool forceNow) {
  if (!ensureSupabaseCredsPresent()) return;
  uint32_t now = millis();
  if (!forceNow && (now - lastBeat) < HEARTBEAT_MS) return;
  lastBeat = now;
  if (WiFi.status() != WL_CONNECTED) return;

  String extra = "{";
  extra += "\"ip\":\"" + jsonEscape(WiFi.localIP().toString()) + "\",";
  extra += "\"host\":\"" + jsonEscape(hostLabel) + "\",";
  extra += "\"rssi\":" + String(WiFi.RSSI()) + ",";
  extra += "\"chip\":\"" + jsonEscape(deviceIdHex()) + "\"";
  extra += "}";

  String payload = "{";
  payload += "\"_device_name\":\"" + jsonEscape(deviceName) + "\",";
  payload += "\"_sensor_name\":\"" + jsonEscape("camera_" + hostLabel) + "\",";
  payload += "\"_kind\":\"camera\",";
  payload += "\"_value_numeric\":null,";
  payload += "\"_value_text\":\"online\",";
  payload += "\"_extra\":" + extra;
  payload += "}";

  int code; String body;
  if (!httpPostJson("/rest/v1/rpc/upsert_live_signal", payload, code, body, true)) {
    Serial.println("[SUPABASE] heartbeat POST falló");
    return;
  }
  if (code < 200 || code >= 300) {
    Serial.printf("[SUPABASE] heartbeat HTTP %d: %s\n", code, body.c_str());
  }
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
  httpPostJson("/rest/v1/rpc/device_command_done", payload, code, body, true);
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

  if (httpPostJson("/rest/v1/rpc/device_upsert_actuator", rpcPayload, code, body)) {
    if (code >= 200 && code < 300) {
      systemActuatorEnsured = true;
      return;
    }
  }

  String payload = "[{";
  payload += "\"device_id\":\"" + jsonEscape(supaCreds.deviceId) + "\",";
  payload += "\"name\":\"" + jsonEscape(SYSTEM_ACTUATOR_NAME) + "\",";
  payload += "\"kind\":\"system\",";
  payload += "\"meta\":{\"role\":\"factory-reset\"}";
  payload += "}]";

  if (httpPostJson("/rest/v1/actuators?on_conflict=device_id,name",
                   payload,
                   code,
                   body,
                   true)) {
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
  if (!httpPostJson("/rest/v1/rpc/device_next_command",
                    "{}",
                    code,
                    body,
                    false)) {
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
  httpPostJson("/rest/v1/rpc/device_mark_remote_forget_done",
               "{}",
               code,
               body,
               true);
}

void supabasePollRemoteFlags() {
  if (!ensureSupabaseCredsPresent()) return;
  if (WiFi.status() != WL_CONNECTED) return;

  const uint32_t now = millis();
  if (now - lastRemoteFlagsPollMs < REMOTE_FLAGS_POLL_MS) return;
  lastRemoteFlagsPollMs = now;

  int code; String body;
  if (!httpPostJson("/rest/v1/rpc/device_take_remote_flags",
                    "{}",
                    code,
                    body,
                    false)) {
    return;
  }
  if (code < 200 || code >= 300) return;
  if (body.indexOf('{') < 0) return;

  if (jsonFlagTrue(body, "ping_requested")) {
    Serial.println("[SUPABASE] ping remoto solicitado (ack enviado)");
  }

  if (jsonFlagTrue(body, "forget_requested")) {
    Serial.println("[SUPABASE] remote forget flag ignored (disabled).");
  }
}

// ---------------------------------------------------------------------------
// Cámara
// ---------------------------------------------------------------------------
bool startCamera() {
  Config cfg;
  cfg.setPins(pins::AiThinker);
  cfg.setResolution(Resolution::find(800, 600));
  cfg.setJpeg(80);
  cfg.setBufferCount(2);
  if (!Camera.begin(cfg)) {
    Serial.println("Camera.begin FAILED");
    return false;
  }
  Serial.println("Camera OK");
  return true;
}

// ---------------------------------------------------------------------------
// Setup / Loop
// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(200);
  makeUniqueHostLabel();
  startCamera();
  loadWifiCreds();
  loadSupabaseCreds();
  Serial.printf("[DEBUG] deviceId=%s\n", supaCreds.deviceId.c_str());
  Serial.printf("[DEBUG] deviceKey=%s\n", supaCreds.deviceKey.c_str());

  uint8_t mac[6]; WiFi.macAddress(mac);
  Serial.printf("DeviceID: %s | Hostname: %s | MAC: %02X:%02X:%02X:%02X:%02X:%02X\n",
                deviceIdHex().c_str(), hostLabel.c_str(),
                mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
  Serial.println("Serial: '1' => factory reset / SoftAP");

  if (wifiCreds.ssid.length()) {
    const int maxAttempts = 3;
    bool connected = false;
    for (int attempt = 1; attempt <= maxAttempts && !connected; ++attempt) {
      Serial.printf("[STA] Intento %d/%d\n", attempt, maxAttempts);
      connected = connectSta();
      if (!connected) delay(1000);
    }
    if (connected) {
      Serial.printf("Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
      startMdns();
      http.on("/",           HTTP_GET,      [](){ sendJson(200, "{\"ok\":true,\"mode\":\"sta\"}"); });
      http.on("/info",       HTTP_GET,      handleInfo);
      http.on("/status",     HTTP_GET,      [](){
        String st = "{";
        st += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
        st += "\"alias\":\"" + jsonEscape(deviceName) + "\",";
        st += "\"supabaseReady\":" + String(ensureSupabaseCredsPresent() ? "true":"false");
        st += "}";
        sendJson(200, st);
      });
      http.on("/nets",       HTTP_GET,      handleNets);
      http.on("/provision",  HTTP_OPTIONS,  handleOptions);
      http.on("/provision",  HTTP_POST,     handleProvision);
      http.on("/apmode",     HTTP_GET,      handleFactoryResetHttp);
      http.on("/factory",    HTTP_GET,      handleFactoryResetHttp);
      http.on("/factory_reset", HTTP_OPTIONS, handleOptions);
      http.on("/factory_reset", HTTP_POST,  handleFactoryResetHttp);

      addCameraHandlers();
      http.begin();

      supabaseHeartbeat(true);
      systemActuatorEnsured = false;
      lastActuatorEnsureMs = 0;
      lastCommandPollMs = 0;
      supabaseEnsureSystemActuator();
      uploadSnapshot();
    } else {
      Serial.println("Fallo STA -> modo AP");
      startApProvision();
    }
  } else {
    Serial.println("Sin credenciales -> modo AP");
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

  if (Serial.available()) {
    if (Serial.read() == '1') enterSoftApNow();
  }

  supabaseHeartbeat(false);
  supabaseEnsureSystemActuator();
  supabasePollCommands();
  supabasePollRemoteFlags();

  uint32_t nowMs = millis();
  if (nowMs - lastSnapshotSentMs >= SNAPSHOT_INTERVAL_MS) {
    lastSnapshotSentMs = nowMs;
    uploadSnapshot();
  }
}
