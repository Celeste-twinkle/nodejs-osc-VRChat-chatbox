# VRC Chatbox OSC

A tiny Windows native tool that uses a browser UI to send translated text to the VRChat chatbox through OSC.

This version has been rewritten from Node.js to 32-bit Win32 assembly and is built with FASM. The release is a single executable: it starts a local HTTP server and opens the system default browser. It does not package Node.js, Chromium, WebView, or any browser runtime.

[中文 README](README.md)

## Features

- Single executable release, currently about 15 KB.
- Uses the system default browser for the UI.
- LAN access: the server listens on `0.0.0.0:19001`.
- The page shows the LAN access URL for phones or other devices on the same network.
- The LAN address is selected only from common private IPv4 ranges: `192.168.0.0/16`, `10.0.0.0/8`, and `172.16.0.0/12`.
- Sends OSC to VRChat at `127.0.0.1:9000` with address `/chatbox/input`.
- Default source language is Chinese, default target language is English.
- Auto-translates text and sends:

  ```text
  original text
  translated text
  ```

- Free public translation through MyMemory.
- Optional MyMemory email for a higher free quota, and optional MyMemory key for private TM/authenticated usage.
- Optional AI translation through OpenAI-compatible chat completion APIs.
- Page heartbeat: each page creates its own session id and sends periodic heartbeats.
- If multiple tabs or LAN devices are open, the background service exits only after all pages stop heartbeating for about 10 seconds.
- This mechanism does not rely on JavaScript continuing to run after page close, so refreshing the page does not immediately kill the service.
- If an old service is already running, launching the exe again skips server startup and only opens the existing page.

## Supported AI APIs

The AI mode uses the OpenAI-compatible Chat Completions request shape:

```text
POST <base-url>/chat/completions
Authorization: Bearer <api-key>
```

Built-in presets:

| Provider | Base URL | Default model |
| --- | --- | --- |
| ChatGPT / OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| Tencent Hunyuan | `https://api.hunyuan.cloud.tencent.com/v1` | `hunyuan-turbos-latest` |
| Custom | user supplied | user supplied |

Tencent Yuanbao itself is usually a consumer app, not a general third-party API. If you have Tencent model API access, use the Tencent Hunyuan preset or the custom OpenAI-compatible option.

## MyMemory Limits

According to the official MyMemory documentation, usage is limited by character volume, not simply by request count:

- Free anonymous usage: 5000 characters/day.
- With a valid email, sent as the `de` request parameter: 50000 characters/day.
- CAT tool whitelist: 150000 characters/day.
- Larger volumes require RapidAPI plans.

Anonymous quota should generally be understood as tied to the request source IP / end-user IP. The MyMemory docs do not explicitly say "anonymous quota is counted by IP", but the API spec provides an `ip` parameter for the end-user IP and says the originating IP is overridden by `X-Forwarded-For` when present. When the browser calls MyMemory directly, MyMemory sees the current network's public egress IP.

The page provides two optional MyMemory fields:

- `MyMemory email`: sent as the `de` parameter, mainly to increase the free quota.
- `MyMemory key`: sent as the `key` parameter, useful if you already have a private MyMemory TM or authenticated key.

MyMemory key generation page:

```text
https://mymemory.translated.net/doc/keygen.php
```

For normal casual chat, you usually do not need a MyMemory key. Prefer adding an email first, and add a key only if you need private TM access or more advanced MyMemory usage.

## Security Note

AI settings, MyMemory email, and MyMemory key are saved beside the executable in:

```text
settings.json
```

This file may contain your API key or MyMemory key. Do not copy it, upload it, commit it, or send it to anyone.

## Usage

1. Enable OSC in VRChat.
2. Run `vrc-chatbox-osc.exe`.
3. Windows opens `http://127.0.0.1:19001` in your default browser.
4. The default direction is Chinese to English. You can change it on the page.
5. Type text and press `Enter` to translate and send.
6. Press `Ctrl + Enter` for a newline.

The LAN URL is shown at the top of the page. You can also open this manually on another device in the same network:

```text
http://<this-pc-lan-ip>:19001
```

Windows Firewall may ask for network permission on first run. Allow it if you need LAN access.

## Build

The repository includes a small portable FASM toolchain under `tools/fasm`.

```bat
cd native-asm
release.bat
```

Output:

```text
native-asm\release\vrc-chatbox-osc.exe
```

## Project Layout

```text
native-asm/
  server.asm      Main Win32 assembly source, including the embedded browser UI
  build.bat       Builds dist\vrc-chatbox-osc-asm.exe
  release.bat     Builds and copies release\vrc-chatbox-osc.exe
  README.md       Native build notes

tools/fasm/
  FASM.EXE        Portable assembler
  INCLUDE/        Win32 include files used by FASM
```

## Release Packaging

The release asset should contain only:

```text
vrc-chatbox-osc.exe
```

Do not include `settings.json` in a release package.
