#include <Arduino.h>
#include "esp_camera.h"
#include <WiFi.h>
#include <WiFiProv.h>
#include <ESPmDNS.h>
#include <Preferences.h>

// ===========================
// Select camera model in board_config.h
// ===========================
#include "board_config.h"

static Preferences devicePreferences;
static String provisioningPop;
static String cameraApiToken;
static String provisioningName;

static String randomHex(size_t bytes) {
  static const char alphabet[] = "0123456789abcdef";
  String value;
  value.reserve(bytes * 2);
  for (size_t index = 0; index < bytes; index++) {
    const uint8_t randomByte = static_cast<uint8_t>(esp_random());
    value += alphabet[randomByte >> 4];
    value += alphabet[randomByte & 0x0f];
  }
  return value;
}

static String persistentSecret(const char *key, size_t bytes) {
  String value = devicePreferences.getString(key, "");
  if (value.isEmpty()) {
    value = randomHex(bytes);
    devicePreferences.putString(key, value);
  }
  return value;
}

const char *getCameraApiToken() {
  return cameraApiToken.c_str();
}

void startCameraServer();
void setupLedFlash();

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  Serial.println();

  devicePreferences.begin("blind-way", false);
  provisioningPop = persistentSecret("prov-pop", 6);
  cameraApiToken = persistentSecret("api-token", 16);
  const uint64_t chipId = ESP.getEfuseMac();
  provisioningName = "PROV_BW_" + String(static_cast<uint32_t>(chipId), HEX);

  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.frame_size = FRAMESIZE_UXGA;
  config.pixel_format = PIXFORMAT_JPEG;  // for streaming
  //config.pixel_format = PIXFORMAT_RGB565; // for face detection/recognition
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_PSRAM;
  config.jpeg_quality = 12;
  config.fb_count = 1;

  // if PSRAM IC present, init with UXGA resolution and higher JPEG quality
  //                      for larger pre-allocated frame buffer.
  if (config.pixel_format == PIXFORMAT_JPEG) {
    if (psramFound()) {
      config.jpeg_quality = 10;
      config.fb_count = 2;
      config.grab_mode = CAMERA_GRAB_LATEST;
    } else {
      // Limit the frame size when PSRAM is not available
      config.frame_size = FRAMESIZE_SVGA;
      config.fb_location = CAMERA_FB_IN_DRAM;
    }
  } else {
    // Best option for face detection/recognition
    config.frame_size = FRAMESIZE_240X240;
#if CONFIG_IDF_TARGET_ESP32S3
    config.fb_count = 2;
#endif
  }

#if defined(CAMERA_MODEL_ESP_EYE)
  pinMode(13, INPUT_PULLUP);
  pinMode(14, INPUT_PULLUP);
#endif

  // camera init
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    return;
  }

  sensor_t *s = esp_camera_sensor_get();
  // initial sensors are flipped vertically and colors are a bit saturated
  if (s->id.PID == OV3660_PID) {
    s->set_vflip(s, 1);        // flip it back
    s->set_brightness(s, 1);   // up the brightness just a bit
    s->set_saturation(s, -2);  // lower the saturation
  }
  // drop down frame size for higher initial frame rate
  if (config.pixel_format == PIXFORMAT_JPEG) {
    s->set_framesize(s, FRAMESIZE_QVGA);
  }

#if defined(CAMERA_MODEL_M5STACK_WIDE) || defined(CAMERA_MODEL_M5STACK_ESP32CAM)
  s->set_vflip(s, 1);
  s->set_hmirror(s, 1);
#endif

#if defined(CAMERA_MODEL_ESP32S3_EYE)
  s->set_vflip(s, 1);
#endif

// Setup LED FLash if LED pin is defined in camera_pins.h
#if defined(LED_GPIO_NUM)
  setupLedFlash();
#endif

  WiFi.setSleep(false);
  WiFi.begin();
  Serial.printf("Provisioning device: %s\n", provisioningName.c_str());
  Serial.printf("Proof of possession: %s\n", provisioningPop.c_str());
  Serial.printf("Camera API token: %s\n", cameraApiToken.c_str());

  uint8_t serviceUuid[16] = {
    0xb4, 0xdf, 0x5a, 0x1c, 0x3f, 0x6b, 0xf4, 0xbf,
    0xea, 0x4a, 0x82, 0x03, 0x04, 0x90, 0x1a, 0x02
  };
  WiFiProv.beginProvision(
    NETWORK_PROV_SCHEME_BLE,
    NETWORK_PROV_SCHEME_HANDLER_FREE_BLE,
    NETWORK_PROV_SECURITY_1,
    provisioningPop.c_str(),
    provisioningName.c_str(),
    nullptr,
    serviceUuid,
    false
  );
  WiFiProv.printQR(provisioningName.c_str(), provisioningPop.c_str(), "ble");
  WiFi.setSleep(false);

  Serial.print("WiFi connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("");
  Serial.println("WiFi connected");

  if (!MDNS.begin("blindway-camera")) {
    Serial.println("mDNS startup failed; use the printed IP address instead");
  } else {
    MDNS.addService("http", "tcp", 80);
  }

  startCameraServer();

  Serial.print("Camera Ready! Use 'http://");
  Serial.print(WiFi.localIP());
  Serial.println("' to connect");
  Serial.println("Or use http://blindway-camera.local with the camera API token");
}

void loop() {
  // Do nothing. Everything is done in another task by the web server
  delay(10000);
}
