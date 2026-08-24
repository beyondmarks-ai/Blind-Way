# Camera Vision Assistant

This project keeps the ESP32 camera firmware as a local camera server and runs
the AI/navigation logic on a laptop.

## Architecture

1. `CameraWebServer.ino` connects the ESP32 camera to Wi-Fi.
2. The ESP32 serves a JPEG frame at `http://<esp32-ip>/capture`.
3. `vision_assistant.py` runs on the laptop, fetches that JPEG, sends it to
   OpenAI or Azure OpenAI, prints a short navigation cue, and speaks it using
   Windows text-to-speech.

The API key stays on the laptop. Do not put it in the ESP32 sketch.

## Hardware Check

The current selected camera in `board_config.h` is:

```cpp
#define CAMERA_MODEL_ESP_EYE
```

If your module is an AI Thinker ESP32-CAM, comment that line and enable:

```cpp
#define CAMERA_MODEL_AI_THINKER
```

Only one camera model should be enabled at a time.

## ESP32 Setup

1. Open `CameraWebServer.ino` in Arduino IDE.
2. Set your Wi-Fi credentials:

```cpp
const char *ssid = "your_wifi_name";
const char *password = "your_wifi_password";
```

3. Select an ESP32 board with PSRAM enabled when your camera board supports it.
4. Use the custom partition scheme from this project if available.
5. Upload the sketch and open Serial Monitor at `115200`.
6. Note the printed URL, for example:

```text
Camera Ready! Use 'http://192.168.1.50' to connect
```

7. Test the camera frame in a browser:

```text
http://192.168.1.50/capture
```

## Laptop Setup With OpenAI

Use Python 3.10 or newer.

Set your OpenAI API key in PowerShell:

```powershell
$env:OPENAI_API_KEY = "your_api_key_here"
```

Run one test analysis without speech:

```powershell
python .\vision_assistant.py --camera http://192.168.1.50 --once --no-speech
```

Run continuous spoken assistance:

```powershell
python .\vision_assistant.py --camera http://192.168.1.50
```

By default the script uses `gpt-5-mini`. To use a different model exposed in
your account:

```powershell
$env:OPENAI_MODEL = "gpt-5.1-mini"
python .\vision_assistant.py --camera http://192.168.1.50
```

## Laptop Setup With Azure OpenAI

Azure OpenAI uses your resource endpoint, an API key, and a deployment name.
The deployment name is the name you gave the deployed vision-capable model in
Azure AI Foundry or the Azure portal.

Set these values in PowerShell:

```powershell
$env:AZURE_OPENAI_ENDPOINT = "https://your-resource.openai.azure.com"
$env:AZURE_OPENAI_API_KEY = "your_azure_key_here"
$env:AZURE_OPENAI_DEPLOYMENT_NAME = "your_deployment_name"
```

Run one test analysis without speech:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --once --no-speech
```

Run continuous spoken assistance:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50
```

## Bluetooth Audio

The script plays speech through the Windows default output device.

1. Pair your Bluetooth speaker, headset, or earphones in Windows settings.
2. Set it as the default output device:
   `Settings > System > Sound > Output`.
3. Test Windows audio first with any normal sound.
4. Run the assistant with speech enabled.

If Windows audio plays through Bluetooth, the assistant audio will also play
through Bluetooth.

## Sarvam AI Voice

Sarvam AI can be used instead of the built-in Windows voice.

Set your Sarvam API key:

```powershell
$env:SARVAM_API_KEY = "your_sarvam_key_here"
```

Run with Sarvam English voice:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --tts-provider sarvam --cue-language English --sarvam-language-code en-IN
```

Run with Hindi speech:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --tts-provider sarvam --cue-language Hindi --sarvam-language-code hi-IN
```

Run with Tamil speech:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --tts-provider sarvam --cue-language Tamil --sarvam-language-code ta-IN
```

Change the voice:

```powershell
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --tts-provider sarvam --sarvam-speaker ritu
```

If your Azure resource requires a specific API version:

```powershell
$env:AZURE_OPENAI_API_VERSION = "2024-07-01-preview"
python .\vision_assistant.py --provider azure --camera http://192.168.1.50
```

## Useful Options

```powershell
python .\vision_assistant.py --camera http://192.168.1.50 --interval 3
python .\vision_assistant.py --camera http://192.168.1.50 --model gpt-5-mini
python .\vision_assistant.py --camera http://192.168.1.50 --no-speech
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --interval 3
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --max-output-tokens 1000
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --once --no-speech --debug-raw
python .\vision_assistant.py --provider azure --camera http://192.168.1.50 --tts-provider sarvam --sarvam-pace 0.95
```

## Safety Notes

This is a prototype assistive cue system, not a certified navigation device.
The AI can miss obstacles, hallucinate objects, fail in poor lighting, or lag
behind fast movement. For any military or field use, add non-AI sensors such as
ultrasonic/LiDAR distance sensing, haptic alerts, offline fallback behavior,
battery monitoring, rugged mounting, and supervised field testing.
