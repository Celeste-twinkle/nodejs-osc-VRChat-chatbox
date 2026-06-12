# VRC Chatbox OSC

一个极小体积的 Windows 原生工具，用浏览器界面把文字发送到 VRChat Chatbox，并可在发送前翻译。

当前版本已从 Node.js 重写为 32 位 Win32 汇编程序，使用 FASM 构建。Release 是单个 exe：它只启动本地 HTTP 服务，并调用系统默认浏览器打开页面，不打包 Node.js、Chromium、WebView 或任何浏览器内核。

[English README](README.en.md)

## 功能

- 单 exe 发布，当前约 51 KB。
- UI 直接使用系统默认浏览器。
- UI 文案支持自动适配中文、英文、日文、韩文，也可在“设置”里手动选择 UI 语言。
- 程序启动后会在 Windows 通知区域创建托盘图标，右键可选择“打开 UI”或“退出”。
- 开启“常驻模式”后，设置中可开启当前用户的开机自启动；关闭常驻模式会自动关闭开机自启动并清理对应的 Windows 自启动注册表项。
- 可开启“最小化自启动”，仅在开机自启动拉起时不自动打开浏览器页面。
- 默认仅允许本机访问，监听 `127.0.0.1:19001`。
- 页面提供“允许局域网连接”按钮，用户显式开启后才监听 `0.0.0.0:19001`。
- 开启后页面会显示局域网访问地址，并提供二维码按钮；点击后浮出二维码，手机扫码可直接打开该局域网地址。
- 局域网地址只从常见 IPv4 私网网段中选择：`192.168.0.0/16`、`10.0.0.0/8`、`172.16.0.0/12`。
- 通过 OSC 发送到 VRChat：`127.0.0.1:9000`，地址 `/chatbox/input`。
- 输入时会发送 VRChat 打字状态：`/chatbox/typing`。发送、清空、页面离开时会尽量发送关闭状态。
- 默认源语言是中文，目标语言是英文。
- 点击“设置”后可切换常驻模式、翻译开关和发送格式：原文 + 译文、仅译文、仅原文。
- 默认使用 MyMemory 免费公开翻译 API。
- 可填写 MyMemory email 提升免费额度，也可填写 MyMemory key 使用私有 TM/认证能力。
- 可选接入 OpenAI-compatible AI 大模型 API。
- 页面心跳：每个页面会创建独立 session id 并定时发送心跳。
- 多个页签或局域网设备同时打开时，所有页面停止心跳超过约 30 秒后，后台服务会退出。
- 可开启“常驻模式”阻止后台服务自动退出。
- 如果旧服务已经在运行，再次启动 exe 会跳过启动服务流程，只打开已有页面。
- 页面保留最近 20 条发送历史；历史列表位于发送状态文案下方，超过容器高度后滚动。长按历史项可按当次实际发送内容重发，点击历史项会填回输入框。

## 支持的 AI API

AI 模式使用 OpenAI-compatible Chat Completions 请求格式：

```text
POST <base-url>/chat/completions
Authorization: Bearer <api-key>
```

内置预设：

| 服务 | Base URL | 默认模型 |
| --- | --- | --- |
| ChatGPT / OpenAI | `https://api.openai.com/v1` | `gpt-4o-mini` |
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` |
| 腾讯混元 | `https://api.hunyuan.cloud.tencent.com/v1` | `hunyuan-turbos-latest` |
| 自定义 | 用户填写 | 用户填写 |

如果你说的“元宝”是腾讯元宝 App，它通常不是面向第三方直接调用的通用 API。如果你有腾讯大模型 API Key，请使用“腾讯混元”预设或“自定义 OpenAI 兼容 API”。

## MyMemory 限制

MyMemory 官方文档说明，它按字符量限制使用，而不是简单按请求次数限制：

- 匿名免费：5000 字符/天。
- 提供有效 email，也就是请求里的 `de` 参数：50000 字符/天。
- CAT 工具白名单：150000 字符/天。
- 更大用量需要查看 RapidAPI 付费计划。

匿名额度通常应按请求来源 IP/最终用户 IP 相关口径理解。MyMemory 文档没有把匿名额度规则明确写成“按 IP 计数”，但 API 规格提供了 `ip` 参数用于传递最终用户 IP，并说明如果设置了 `X-Forwarded-For`，来源 IP 会被它覆盖。浏览器直连 MyMemory 时，匿名请求暴露给 MyMemory 的就是当前网络的公网出口 IP。

页面里提供了两个 MyMemory 可选字段：

- `MyMemory email`：会作为 `de` 参数发送，主要用于提升免费额度。
- `MyMemory key`：会作为 `key` 参数发送，适合已有 MyMemory 私有翻译记忆库或认证 key 的用户。

MyMemory key 获取页面：

```text
https://mymemory.translated.net/doc/keygen.php
```

如果只是日常少量聊天，通常不需要填写 MyMemory key。建议优先填写 email；遇到额度不够或你有私有 TM 需求时再填写 key。

## 安全提醒

AI 设置、MyMemory email、MyMemory key、翻译格式、UI 语言、常驻模式和自启动选项会保存在 exe 同目录下：

```text
settings.json
```

这个文件可能包含你的 API Key 或 MyMemory key。不要复制、上传、提交到 Git，或发送给任何人。

## 使用方法

1. 在 VRChat 中启用 OSC。
2. 运行 `vrc-chatbox-osc.exe`。
3. 程序会用系统默认浏览器打开 `http://127.0.0.1:19001`。
4. 右键 Windows 通知区域中的托盘图标，可以选择“打开 UI”或“退出”后台服务。
5. 点击“设置”可以切换 UI 语言、翻译、语言、翻译服务、发送格式、常驻模式、开机自启动和最小化自启动；开机自启动必须先开启常驻模式。
6. 输入文字后按 `Enter` 发送或翻译发送。
7. 按 `Shift + Enter` 输入换行。
8. 点击“清空”会清空输入框并关闭打字状态。
9. 点击历史项可填回输入框；长按历史项可重发。

如需手机或其他局域网设备访问，请先点击页面顶部的“允许局域网连接”。开启后页面会显示访问地址和二维码按钮，可扫码访问，也可以手动输入：

```text
http://<本机局域网 IP>:19001
```

首次开启局域网连接时 Windows 防火墙可能会询问网络权限。如果需要手机或其他局域网设备访问，请允许。

开机自启动使用当前用户的 Windows Run 注册表项：

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
```

关闭“开机自启动”或关闭“常驻模式”后，程序会删除其中的 `VRC Chatbox OSC` 值。

## 构建

仓库内置便携 FASM 工具链：

```bat
cd native-asm
release.bat
```

输出：

```text
native-asm\release\vrc-chatbox-osc.exe
```

## 项目结构

```text
native-asm/
  server.asm      Win32 汇编源码，包含内嵌浏览器 UI
  build.bat       构建 dist\vrc-chatbox-osc-asm.exe
  release.bat     构建并复制 release\vrc-chatbox-osc.exe
  README.md       原生构建说明

tools/fasm/
  FASM.EXE        便携汇编器
  INCLUDE/        FASM Win32 include 文件
```

## Release 打包

Release 附件只需要包含：

```text
vrc-chatbox-osc.exe
```

不要把 `settings.json` 放进发布包。
