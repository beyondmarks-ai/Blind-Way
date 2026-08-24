#!/usr/bin/env python3
"""
Laptop-side scene assistant for the ESP32 CameraWebServer sketch.

The ESP32 serves JPEG frames at /capture. This script periodically fetches a
frame, sends it to the OpenAI Responses API, prints a short navigation cue, and
speaks important changes using the local Windows speech engine.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import platform
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


DEFAULT_MODEL = "gpt-5-mini"
OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses"
DEFAULT_AZURE_API_VERSION = "2024-07-01-preview"
SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"

NAVIGATION_PROMPT_TEMPLATE = """
You are helping a blind person understand the space directly in front of them.
Analyze this single camera frame and return only a compact JSON object with:
{
  "cue": "one natural spoken instruction in {cue_language}, max 14 words",
  "risk": "clear|caution|danger|unknown",
  "confidence": 0.0-1.0
}

Prioritize immediate navigation: clear path, obstacles, people, stairs, doors,
beds, vehicles, weapons, drop-offs, or low visibility. Do not invent distances.
Speak like a helpful person giving directions. Prefer action cues like stop,
go left, go right, move slowly, or path is clear. If the image is unclear, say
low visibility or unknown. Keep the cue practical, not descriptive.
""".strip()


@dataclass
class SceneCue:
  cue: str
  risk: str
  confidence: float


def parse_args() -> argparse.Namespace:
  parser = argparse.ArgumentParser(
    description="Fetch ESP32-CAM frames, analyze them with OpenAI vision, and speak navigation cues."
  )
  parser.add_argument(
    "--provider",
    choices=("openai", "azure"),
    default=os.getenv("VISION_PROVIDER", "openai"),
    help="AI provider to call. Defaults to VISION_PROVIDER or openai.",
  )
  parser.add_argument(
    "--camera",
    required=True,
    help="ESP32 base URL or /capture URL, for example http://192.168.1.50",
  )
  parser.add_argument(
    "--model",
    default=os.getenv("OPENAI_MODEL", DEFAULT_MODEL),
    help=f"OpenAI model id. Defaults to OPENAI_MODEL or {DEFAULT_MODEL}.",
  )
  parser.add_argument(
    "--interval",
    type=float,
    default=2.0,
    help="Seconds between frame analyses. Default: 2.0",
  )
  parser.add_argument(
    "--api-key",
    default=os.getenv("OPENAI_API_KEY"),
    help="OpenAI API key for --provider openai. Prefer setting OPENAI_API_KEY.",
  )
  parser.add_argument(
    "--azure-endpoint",
    default=os.getenv("AZURE_OPENAI_ENDPOINT"),
    help="Azure OpenAI endpoint, for example https://your-resource.openai.azure.com.",
  )
  parser.add_argument(
    "--azure-api-key",
    default=os.getenv("AZURE_OPENAI_API_KEY"),
    help="Azure OpenAI API key. Prefer setting AZURE_OPENAI_API_KEY.",
  )
  parser.add_argument(
    "--azure-deployment",
    default=os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME"),
    help="Azure OpenAI deployment name for the vision-capable model.",
  )
  parser.add_argument(
    "--azure-api-version",
    default=os.getenv("AZURE_OPENAI_API_VERSION", DEFAULT_AZURE_API_VERSION),
    help=f"Azure OpenAI API version. Defaults to AZURE_OPENAI_API_VERSION or {DEFAULT_AZURE_API_VERSION}.",
  )
  parser.add_argument(
    "--no-speech",
    action="store_true",
    help="Print cues only; do not use text-to-speech.",
  )
  parser.add_argument(
    "--tts-provider",
    choices=("windows", "sarvam"),
    default=os.getenv("TTS_PROVIDER", "windows"),
    help="Text-to-speech provider. Defaults to TTS_PROVIDER or windows.",
  )
  parser.add_argument(
    "--cue-language",
    default=os.getenv("CUE_LANGUAGE", "English"),
    help="Language for the navigation cue text. Example: English, Hindi, Tamil.",
  )
  parser.add_argument(
    "--sarvam-api-key",
    default=os.getenv("SARVAM_API_KEY"),
    help="Sarvam AI API key. Prefer setting SARVAM_API_KEY.",
  )
  parser.add_argument(
    "--sarvam-language-code",
    default=os.getenv("SARVAM_LANGUAGE_CODE", "en-IN"),
    help="Sarvam target language code. Examples: en-IN, hi-IN, ta-IN, te-IN.",
  )
  parser.add_argument(
    "--sarvam-speaker",
    default=os.getenv("SARVAM_SPEAKER", "shubh"),
    help="Sarvam speaker voice. Default: shubh.",
  )
  parser.add_argument(
    "--sarvam-model",
    default=os.getenv("SARVAM_MODEL", "bulbul:v3"),
    help="Sarvam TTS model. Default: bulbul:v3.",
  )
  parser.add_argument(
    "--sarvam-pace",
    type=float,
    default=float(os.getenv("SARVAM_PACE", "1.05")),
    help="Sarvam speech pace, usually 0.5 to 2.0. Default: 1.05.",
  )
  parser.add_argument(
    "--speak-repeat-after",
    type=float,
    default=10.0,
    help="Speak the same cue again only after this many seconds. Default: 10.",
  )
  parser.add_argument(
    "--timeout",
    type=float,
    default=20.0,
    help="HTTP timeout in seconds for camera and OpenAI calls. Default: 20.",
  )
  parser.add_argument(
    "--max-output-tokens",
    type=int,
    default=500,
    help="Maximum output token budget for the AI response. Default: 500.",
  )
  parser.add_argument(
    "--debug-raw",
    action="store_true",
    help="Print the raw model text before parsing it.",
  )
  parser.add_argument(
    "--once",
    action="store_true",
    help="Analyze one frame and exit.",
  )
  return parser.parse_args()


def navigation_prompt(cue_language: str) -> str:
  return NAVIGATION_PROMPT_TEMPLATE.format(cue_language=cue_language)


def capture_url(camera: str) -> str:
  camera = camera.rstrip("/")
  if camera.endswith("/capture"):
    return camera
  return f"{camera}/capture"


def fetch_frame(url: str, timeout: float) -> bytes:
  req = urllib.request.Request(url, headers={"User-Agent": "CameraWebServer-VisionAssistant/1.0"})
  with urllib.request.urlopen(req, timeout=timeout) as response:
    content_type = response.headers.get("Content-Type", "")
    data = response.read()
  if not data:
    raise RuntimeError("camera returned an empty response")
  if "image" not in content_type.lower() and not data.startswith(b"\xff\xd8"):
    raise RuntimeError(f"camera did not return an image; content-type was {content_type!r}")
  return data


def analyze_frame(
  image_jpeg: bytes,
  api_key: str,
  model: str,
  timeout: float,
  max_output_tokens: int,
  debug_raw: bool,
  cue_language: str,
) -> SceneCue:
  image_b64 = base64.b64encode(image_jpeg).decode("ascii")
  body = {
    "model": model,
    "input": [
      {
        "role": "user",
        "content": [
          {"type": "input_text", "text": navigation_prompt(cue_language)},
          {
            "type": "input_image",
            "image_url": f"data:image/jpeg;base64,{image_b64}",
            "detail": "low",
          },
        ],
      }
    ],
    "max_output_tokens": max_output_tokens,
  }
  payload = json.dumps(body).encode("utf-8")
  req = urllib.request.Request(
    OPENAI_RESPONSES_URL,
    data=payload,
    method="POST",
    headers={
      "Authorization": f"Bearer {api_key}",
      "Content-Type": "application/json",
    },
  )

  try:
    with urllib.request.urlopen(req, timeout=timeout) as response:
      data = json.loads(response.read().decode("utf-8"))
  except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    raise RuntimeError(f"OpenAI API error {exc.code}: {detail}") from exc

  text = extract_output_text(data).strip()
  if debug_raw:
    print(f"[debug raw model output] {text!r}", flush=True)
  return parse_scene_cue(text)


def analyze_frame_azure(
  image_jpeg: bytes,
  api_key: str,
  endpoint: str,
  deployment: str,
  api_version: str,
  timeout: float,
  max_output_tokens: int,
  debug_raw: bool,
  cue_language: str,
) -> SceneCue:
  endpoint = endpoint.rstrip("/")
  url = f"{endpoint}/openai/deployments/{deployment}/chat/completions?api-version={api_version}"
  image_b64 = base64.b64encode(image_jpeg).decode("ascii")
  body = {
    "messages": [
      {"role": "system", "content": "Return only compact JSON for a navigation cue."},
      {
        "role": "user",
        "content": [
          {"type": "text", "text": navigation_prompt(cue_language)},
          {
            "type": "image_url",
            "image_url": {
              "url": f"data:image/jpeg;base64,{image_b64}",
              "detail": "low",
            },
          },
        ],
      },
    ],
    "max_completion_tokens": max_output_tokens,
    "stream": False,
  }
  payload = json.dumps(body).encode("utf-8")
  req = urllib.request.Request(
    url,
    data=payload,
    method="POST",
    headers={
      "api-key": api_key,
      "Content-Type": "application/json",
    },
  )

  try:
    with urllib.request.urlopen(req, timeout=timeout) as response:
      data = json.loads(response.read().decode("utf-8"))
  except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    raise RuntimeError(f"Azure OpenAI API error {exc.code}: {detail}") from exc

  choices = data.get("choices", [])
  if not choices:
    raise RuntimeError("Azure OpenAI response did not contain choices")
  finish_reason = choices[0].get("finish_reason", "unknown")
  message = choices[0].get("message", {})
  content = message.get("content")
  if isinstance(content, list):
    text = "\n".join(part.get("text", "") for part in content if isinstance(part, dict))
  elif isinstance(content, str):
    text = content
  else:
    raise RuntimeError("Azure OpenAI response did not contain message content")
  text = text.strip()
  if debug_raw:
    print(f"[debug raw model output] {text!r}", flush=True)
  if not text:
    raise RuntimeError(
      f"Azure OpenAI returned empty message content; finish_reason={finish_reason}. "
      "Try --max-output-tokens 1000 or use a vision-capable deployment."
    )
  return parse_scene_cue(text)


def extract_output_text(data: dict[str, Any]) -> str:
  if isinstance(data.get("output_text"), str):
    return data["output_text"]

  parts: list[str] = []
  for item in data.get("output", []):
    for content in item.get("content", []):
      text = content.get("text")
      if isinstance(text, str):
        parts.append(text)
  if parts:
    return "\n".join(parts)
  raise RuntimeError("OpenAI response did not contain output text")


def parse_scene_cue(text: str) -> SceneCue:
  cleaned = text.strip()
  if cleaned.startswith("```"):
    cleaned = cleaned.strip("`")
    if cleaned.lower().startswith("json"):
      cleaned = cleaned[4:].strip()

  try:
    data = json.loads(cleaned)
    cue = str(data.get("cue", "")).strip()
    risk = str(data.get("risk", "unknown")).strip().lower()
    confidence = float(data.get("confidence", 0.0))
  except (json.JSONDecodeError, TypeError, ValueError):
    cue = " ".join(cleaned.split())[:120] or "unknown scene"
    risk = "unknown"
    confidence = 0.0

  if risk not in {"clear", "caution", "danger", "unknown"}:
    risk = "unknown"
  confidence = max(0.0, min(1.0, confidence))
  return SceneCue(cue=cue or "unknown scene", risk=risk, confidence=confidence)


def speak(text: str) -> None:
  if platform.system() == "Windows":
    escaped = text.replace("'", "''")
    command = (
      "Add-Type -AssemblyName System.Speech; "
      "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
      "$s.Rate = 0; "
      f"$s.Speak('{escaped}')"
    )
    subprocess.run(
      ["powershell", "-NoProfile", "-Command", command],
      check=False,
      stdout=subprocess.DEVNULL,
      stderr=subprocess.DEVNULL,
    )
  else:
    print(f"[speech unavailable] {text}", file=sys.stderr)


def speak_sarvam(
  text: str,
  api_key: str,
  language_code: str,
  speaker: str,
  model: str,
  pace: float,
  timeout: float,
) -> None:
  body = {
    "text": text,
    "target_language_code": language_code,
    "speaker": speaker,
    "model": model,
    "pace": pace,
    "speech_sample_rate": 24000,
    "output_audio_codec": "wav",
  }
  payload = json.dumps(body).encode("utf-8")
  req = urllib.request.Request(
    SARVAM_TTS_URL,
    data=payload,
    method="POST",
    headers={
      "api-subscription-key": api_key,
      "Content-Type": "application/json",
    },
  )

  try:
    with urllib.request.urlopen(req, timeout=timeout) as response:
      data = json.loads(response.read().decode("utf-8"))
  except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", errors="replace")
    raise RuntimeError(f"Sarvam TTS error {exc.code}: {detail}") from exc

  audios = data.get("audios", [])
  if not audios:
    raise RuntimeError("Sarvam TTS response did not contain audio")

  audio_bytes = base64.b64decode("".join(audios))
  play_wav_bytes(audio_bytes)


def play_wav_bytes(audio_bytes: bytes) -> None:
  if platform.system() != "Windows":
    print("[speech unavailable] Sarvam audio playback is currently implemented for Windows.", file=sys.stderr)
    return

  with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as audio_file:
    audio_file.write(audio_bytes)
    audio_path = audio_file.name

  escaped = audio_path.replace("'", "''")
  command = (
    "Add-Type -AssemblyName System.Media; "
    f"$p = New-Object System.Media.SoundPlayer('{escaped}'); "
    "$p.PlaySync(); "
    f"Remove-Item -LiteralPath '{escaped}' -Force"
  )
  subprocess.run(
    ["powershell", "-NoProfile", "-Command", command],
    check=False,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
  )


def speak_cue(text: str, args: argparse.Namespace) -> None:
  if args.tts_provider == "sarvam":
    speak_sarvam(
      text,
      args.sarvam_api_key,
      args.sarvam_language_code,
      args.sarvam_speaker,
      args.sarvam_model,
      args.sarvam_pace,
      args.timeout,
    )
  else:
    speak(text)


def should_speak(cue: SceneCue, last_cue: str | None, last_spoken_at: float, repeat_after: float) -> bool:
  now = time.monotonic()
  if cue.risk in {"danger", "caution"} and cue.confidence >= 0.35:
    return cue.cue != last_cue or (now - last_spoken_at) >= repeat_after
  if cue.risk == "clear":
    return cue.cue != last_cue and cue.confidence >= 0.55
  return cue.cue != last_cue and cue.confidence >= 0.45


def main() -> int:
  args = parse_args()
  if args.provider == "openai" and not args.api_key:
    print("Missing OpenAI API key. Set OPENAI_API_KEY or pass --api-key.", file=sys.stderr)
    return 2
  if args.provider == "azure":
    missing = []
    if not args.azure_endpoint:
      missing.append("AZURE_OPENAI_ENDPOINT or --azure-endpoint")
    if not args.azure_api_key:
      missing.append("AZURE_OPENAI_API_KEY or --azure-api-key")
    if not args.azure_deployment:
      missing.append("AZURE_OPENAI_DEPLOYMENT_NAME or --azure-deployment")
    if missing:
      print(f"Missing Azure OpenAI setting(s): {', '.join(missing)}.", file=sys.stderr)
      return 2
  if not args.no_speech and args.tts_provider == "sarvam" and not args.sarvam_api_key:
    print("Missing Sarvam API key. Set SARVAM_API_KEY or pass --sarvam-api-key.", file=sys.stderr)
    return 2

  url = capture_url(args.camera)
  print(f"Camera capture: {url}")
  if args.provider == "azure":
    print(f"AI provider: Azure OpenAI")
    print(f"Azure endpoint: {args.azure_endpoint.rstrip('/')}")
    print(f"Azure deployment: {args.azure_deployment}")
    print(f"Azure API version: {args.azure_api_version}")
  else:
    print(f"AI provider: OpenAI")
    print(f"OpenAI model: {args.model}")
  if args.no_speech:
    print("Speech: disabled")
  else:
    print(f"Speech provider: {args.tts_provider}")
    if args.tts_provider == "sarvam":
      print(f"Sarvam language: {args.sarvam_language_code}")
      print(f"Sarvam speaker: {args.sarvam_speaker}")
      print(f"Sarvam model: {args.sarvam_model}")
  print(f"Cue language: {args.cue_language}")
  print("Press Ctrl+C to stop.")

  last_cue: str | None = None
  last_spoken_at = 0.0

  while True:
    started = time.monotonic()
    try:
      frame = fetch_frame(url, args.timeout)
      if args.provider == "azure":
        cue = analyze_frame_azure(
          frame,
          args.azure_api_key,
          args.azure_endpoint,
          args.azure_deployment,
          args.azure_api_version,
          args.timeout,
          args.max_output_tokens,
          args.debug_raw,
          args.cue_language,
        )
      else:
        cue = analyze_frame(
          frame,
          args.api_key,
          args.model,
          args.timeout,
          args.max_output_tokens,
          args.debug_raw,
          args.cue_language,
        )
      line = f"{time.strftime('%H:%M:%S')} [{cue.risk} {cue.confidence:.2f}] {cue.cue}"
      print(line, flush=True)

      if not args.no_speech and should_speak(cue, last_cue, last_spoken_at, args.speak_repeat_after):
        speak_cue(cue.cue, args)
        last_cue = cue.cue
        last_spoken_at = time.monotonic()
    except KeyboardInterrupt:
      print("\nStopped.")
      return 0
    except Exception as exc:
      print(f"{time.strftime('%H:%M:%S')} [error] {exc}", file=sys.stderr, flush=True)
      if not args.no_speech and should_speak(SceneCue("vision unavailable", "unknown", 1.0), last_cue, last_spoken_at, args.speak_repeat_after):
        speak_cue("vision unavailable", args)
        last_cue = "vision unavailable"
        last_spoken_at = time.monotonic()

    if args.once:
      return 0

    elapsed = time.monotonic() - started
    time.sleep(max(0.0, args.interval - elapsed))


if __name__ == "__main__":
  raise SystemExit(main())
