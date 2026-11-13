# CF Pocket Android

当前版本 0.5.2 (7)。完整功能与运行说明见[仓库 README](../README.md)。

用 Android Studio 打开本目录，或配置 JDK 与 Android SDK 后运行 `./gradlew assembleDebug`。

前端位于 `app/src/main/assets/web`，原生桥接与存储位于 `app/src/main/java/com/codex/cfpocket`。`npm ci && npm test` 运行本地回归。共享编辑规则与提交脚本使用 tools 中的生成工具更新，保持与 iOS 一致。

调试 APK 由 Gradle 本机签名；Release 需要自己的签名配置。
