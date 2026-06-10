# VRC Chatbox OSC

一个极小体积的 Windows 原生工具，用浏览器界面把翻译后的文字发送到 VRChat Chatbox。

当前版本已从 Node.js 重写为 32 位 Win32 汇编程序，使用 FASM 构建。Release 是单个 exe：它只启动本地 HTTP 服务，并调用系统默认浏览器打开页面，不打包 Node.js、Chromium、WebView 或任何浏览器内核。

[English README](README.en.md)

## 功能

- 单 exe 发布，当前约 15 KB。
- UI 直接使用系统默认浏览器。
- 允许局域网访问，监听 `0.0.0.0:19001`。
- 页面会显示局域网访问地址，方便手机或其他局域网设备连接。
- 局域网地址只从常见 IPv4 私网网段中选择：`192.168.0.0/16`、`10.0.0.0/8`、`172.16.0.0/12`。
- 通过 OSC 发送到 VRChat：`127.0.0.1:9000`，地址 `/chatbox/input`。
- 默认源语言是中文，目标语言是英文。
- 自动翻译并发送以下格式：

  ```text
  原文
  译文
  ```

- 默认使用 MyMemory 免费公开翻译 API。
- 可填写 MyMemory email 提升免费额度，也可填写 MyMemory key 使用私有 TM/认证能力。
- 可选接入 OpenAI-compatible AI 大模型 API。
- 页面心跳：每个页面会创建独立 session id 并定时发送心跳。
- 多个页签或局域网设备同时打开时，只有所有页面都停止心跳超过约 10 秒，后台服务才退出。
- 该机制不依赖页面关闭后继续执行 JavaScript，因此刷新页面不会让后台服务立刻退出。
- 如果旧服务已经在运行，再次启动 exe 会跳过启动服务流程，只打开已有页面。

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

AI 设置、MyMemory email 和 MyMemory key 会保存在 exe 同目录下：

```text
settings.json
```

这个文件可能包含你的 API Key 或 MyMemory key。不要复制、上传、提交到 Git，或发送给任何人。

## 使用方法

1. 在 VRChat 中启用 OSC。
2. 运行 `vrc-chatbox-osc.exe`。
3. 程序会用系统默认浏览器打开 `http://127.0.0.1:19001`。
4. 默认“源语言中文、目标语言英文”，也可以在页面中切换。
5. 输入文字后按 `Enter` 翻译并发送。
6. 按 `Ctrl + Enter` 输入换行。

局域网设备访问地址会显示在页面顶部，也可以手动输入：

```text
http://<本机局域网 IP>:19001
```

首次运行时 Windows 防火墙可能会询问网络权限。如果需要手机或其他局域网设备访问，请允许。

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
