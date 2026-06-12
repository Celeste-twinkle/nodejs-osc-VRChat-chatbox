# VRC Chatbox OSC

A tiny Windows native tool that uses a browser UI to send text to the VRChat chatbox, with optional translation before sending.

This version has been rewritten from Node.js to 32-bit Win32 assembly and is built with FASM. The release is a single executable: it starts a local HTTP server and opens the system default browser. It does not package Node.js, Chromium, WebView, or any browser runtime.

[中文 README](README.md)

## Features

- Single executable release, currently about 51 KB.
- Uses the system default browser for the UI.
- UI copy supports automatic Chinese, English, Japanese, and Korean adaptation, and can be changed manually in Settings.
- Creates a Windows notification-area tray icon after startup. Right-click it to open the UI, toggle LAN access, toggle Windows startup and minimized startup, or exit the background service.
- Settings can enable current-user startup on Windows. Turning startup off removes the matching startup registry value.
- Optional minimized startup keeps the browser UI closed only when Windows starts the app automatically.
- By default, access is local-only and the server listens on `127.0.0.1:19001`.
- The page provides an "Allow LAN access" button. Only after the user explicitly enables it does the server listen on `0.0.0.0:19001`.
- After LAN access is enabled, the page shows the LAN access URL and a QR button. Clicking it opens a floating QR code that phones can scan to open the LAN URL directly.
- LAN address choices are listed from the system IPv4 address table and do not depend on adapter names. The default prefers `192.168.*`, then `10.*`, then `172.16-31.*`, and finally falls back to other non-loopback IPv4 addresses.
- Sends OSC to VRChat at `127.0.0.1:9000` with address `/chatbox/input`.
- Sends VRChat typing state through `/chatbox/typing` while the user is typing. The page tries to turn typing off when text is sent, cleared, or the page is left.
- Default source language is Chinese, default target language is English.
- Use the controls above the input box to change source language, target language, and send format: original + translation, translation only, and original only. Click "Settings" to change startup, translation, provider, and API settings.
- Free public translation through MyMemory.
- Optional MyMemory email for a higher free quota, and optional MyMemory key for private TM/authenticated usage.
- Optional AI translation through OpenAI-compatible chat completion APIs.
- Page heartbeat: each page creates its own session id and sends periodic heartbeats.
- The background service does not exit automatically when pages are closed or heartbeats stop; use the tray menu to exit it.
- If an old service is already running, launching the exe again skips server startup and only opens the existing page.
- The page keeps sent history in browser localStorage and in `history.json` beside the executable. The history limit is configurable in Settings. The history sits below the send status text and scrolls when it exceeds its maximum height. Click a history item to restore the original text. Long-press a history item to restore the content to be sent, then click Send manually, or export the history to a text file.

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

AI settings, MyMemory email, MyMemory key, send format, UI language, and startup options are saved beside the executable in:

```text
settings.json
```

This file may contain your API key or MyMemory key. Do not copy it, upload it, commit it, or send it to anyone.

## Usage

1. Enable OSC in VRChat.
2. Run `vrc-chatbox-osc.exe`.
3. Windows opens `http://127.0.0.1:19001` in your default browser.
4. Right-click the tray icon in the Windows notification area to choose "Open UI" or "Exit".
5. Use the controls above the input box to change languages and send format. Click "Settings" to change UI language, translation, provider, API settings, startup, and minimized startup.
6. Type text and press `Enter` to send or translate and send.
7. Press `Shift + Enter` for a newline.
8. Click "Clear" to clear the input box and turn typing state off.
9. Click a history item to restore its original text, or long-press it to resend it.

To use phones or other LAN devices, click "Allow LAN access" at the top of the page first. After it is enabled, the page shows the access URL and a QR button. Scan it or open this manually on another device in the same network. If the QR address points to a virtual or wrong adapter, use the QR dialog dropdown to choose a detected LAN address, current-access address, or saved address, or manually enter the correct IP, host name, or full URL; the page remembers the last selected or entered value:

```text
http://<this-pc-lan-ip>:19001
```

Windows Firewall may ask for network permission when LAN access is first enabled. Allow it if you need LAN access.

Startup uses the current-user Windows Run registry key:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

When "Startup" is turned off, the app deletes the `VRC Chatbox OSC` value from that key.

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
  INCLUDE/        FASM Win32 include files
```

## Release Packaging

The release asset should contain only:

```text
vrc-chatbox-osc.exe
```

Do not include `settings.json` in a release package.

## License

MIT License. See [LICENSE](LICENSE).
