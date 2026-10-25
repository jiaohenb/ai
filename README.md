# KSU AI Bridge — LSPosed 模块

给 Operit AI 用的 KSU / root 语义桥。模块以 LSPosed 形式注入 Operit 进程，
在进程内起一个只监听 127.0.0.1 的 HTTP 服务，把 ksud 的原始输出与
/data/adb/ksu 下的状态整理成结构化 JSON，供 Operit 的 Agent 工具直接调用。

## 为什么是 LSPosed 而不是普通 App

- 普通 App 调 KernelSU 官方 Java API 需要 KSU 白名单签名，第三方签名调不通。
- 注入 Operit 进程后，服务与 Operit 同进程，无需跨进程 binder，
  也不需要把 root 能力暴露给任何外部 App。
- 作用域只勾 com.ai.assistance.operit，不污染其他应用。

## 实测环境（本机已验证）

| 项 | 值 |
|---|---|
| 内核 | 6.6.30-android15-8 aarch64 |
| Android | 15 / PKR110 |
| KSU | SukiSU Ultra v4.1.1（com.sukisu.ultra，versionCode 40514）|
| ksud | 4.1.1-21-g65ea912f |
| ksud 路径 | /data/adb/ksu/bin/ksud（软链 /data/adb/ksud）|
| LSPosed | v2.1.0 (7769) zygisk_lsposed |
| Zygisk | Zygisk Next 1.3.2 |
| 目标进程 | com.ai.assistance.operit |

## 本机不可编译，请按下面任一路线出包

本机（手机端）没有 javac / d8 / aapt2，Ubuntu 环境只有 apt 且缺 curl 与 python3，
无法在设备上直接产出 APK。两条可行路线：

### 路线 A GitHub Actions（零环境，推荐）

1. 把本目录推到 GitHub 仓库。
2. 仓库自带 .github/workflows/build.yml，push 后自动编译。
3. 在 Actions 的 artifact 里下载 KsuAiBridge-debug.apk。

### 路线 B PC 本地

```
cd KsuAiBridge
gradle :app:assembleDebug
# 产物 app/build/outputs/apk/debug/app-debug.apk
```

需要 JDK 17 与 Android SDK Platform 34。

## 安装与启用

1. 安装编译出的 APK。
2. 打开 LSPosed 管理器 → 模块 → KSU AI Bridge → 启用。
3. 作用域只勾选 Operit（com.ai.assistance.operit）。
4. 强制停止并重启 Operit。
5. 回到 LSPosed 点开本模块，记录显示的端口与 Token。

## Operit 侧接入

把 operit_tools.js 里的 HOST 端口与 TOKEN 改成 SettingsActivity 显示的值，
在 Operit 自定义工具里注册。工具分三档：

- L0 只读：ksu_ping / ksu_status / ksu_list_modules / ksu_superuser / ksu_features
- L1 低危写：ksu_toggle_module / ksu_module_action
- L2 高危：ksu_install_module / ksu_uninstall_module / ksu_root_exec / ksu_reboot

L2 必须由 Bridge 侧或 Operit 侧弹二次确认，不要交给模型自己判断。

## HTTP 端点

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /ping | 存活探测 |
| GET | /status | 内核 / ksud / SUSFS / 机型 / root 可用性 |
| GET | /modules | ksud module list 原始 JSON 透传 |
| GET | /superuser | 解析 .allowlist（启发式，见下）|
| GET | /feature | ksud feature list |
| POST | /module/enable | body {"id":"xxx"} |
| POST | /module/disable | body {"id":"xxx"} |
| POST | /module/uninstall | body {"id":"xxx"} |
| POST | /module/undo | body {"id":"xxx"} |
| POST | /module/action | body {"id":"xxx"} |
| POST | /module/install | body {"path":"/abs/x.zip"} |
| POST | /root/exec | body {"cmd":"...","timeout":30} |
| POST | /reboot | body {"mode":"normal"} |

所有请求必须带 X-Token 头，否则 401。

## 已知注意点

1. /superuser 的 .allowlist 解析是启发式。本机 dump 显示文件头为 magic USK\177、
   version=3、count=2，条目含包名与 uid 但步长随版本变化。代码里对候选步长做打分
   选最自洽的一个。若解析为空，用 /root/exec 直接跑 od 自查，不要当成没有授权记录。
2. ksud 路径做了探测与缓存，SukiSU 的 ksud 在 /data/adb/ksu/bin/ksud，
   与官方 KernelSU 的 /data/adb/ksud 不同，代码里两者都试。
3. 模块本身不申请 root，所有特权操作都走 su -c，最终仍受 KSU 授权管理。
4. reboot 属于高危，代码里只做透传，是否加二次确认由上层决定。
5. token 存在模块自己的 SharedPreferences 里，重装模块会重置，需要重新填 operit_tools.js。

## 目录

```
KsuAiBridge/
├── app/
│   ├── build.gradle
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── assets/xposed_init
│       └── java/com/operit/ksubridge/
│           ├── MainHook.java        LSPosed 入口与作用域判断
│           ├── LocalHttpServer.java 本地 HTTP 与 token 校验
│           ├── KsuApi.java          ksud 封装与 allowlist 解析
│           ├── SettingsActivity.java 端口与 token 展示
│           └── Json.java            极简 JSON 工具
├── operit_tools.js                  Operit 侧工具封装
├── build.gradle / settings.gradle / gradle.properties
└── .github/workflows/build.yml
```
