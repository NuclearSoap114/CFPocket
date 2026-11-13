# 开发说明

## 目录

```text
TrainingLedger/
  TrainingLedger.xcodeproj   # 打开此工程，选择 CFPocket scheme
  CFPocket/                  # iOS App 与随包运行资源
  TrainingCore/              # Swift 核心模块和测试
  TrainingLedger/            # 复用的统计、账号和展示模块
CFPocketAndroid/             # Android 工程、前端资源、测试、生成工具
```

iOS 工程保留历史 TrainingLedger target 及共享统计模块。开发本 App 时选择 **CFPocket**，不需要另建项目。

## iOS 运行

- 最低部署版本：iOS 18.4。
- 此版本已在 Xcode 27.2 环境构建；首次构建需要下载 Swift Package 依赖。
- 用 Xcode 打开 `TrainingLedger/TrainingLedger.xcodeproj`，选择 `CFPocket`，运行到 iPhone 模拟器。
- 真机运行：在 Signing & Capabilities 中选择自己的 Team，并设置可用的 Bundle Identifier。仓库不包含个人签名、证书或描述文件。

在仓库根目录构建：

```sh
xcodebuild -project TrainingLedger/TrainingLedger.xcodeproj \
  -scheme CFPocket -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/CFPocketDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

若默认开发工具不是完整 Xcode，可为该命令设置 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## Android 运行

- Android 10 / API 29 及以上；compileSdk / targetSdk 35。
- JDK 17 及以上，Android SDK 35。用 Android Studio 打开 `CFPocketAndroid`，或配置 `ANDROID_HOME` 后使用 Gradle wrapper。
- 工程和运行资源完整附带；不需要先安装 Node 才能构建 App。

```sh
cd CFPocketAndroid
./gradlew assembleDebug
```

产物位于 `app/build/outputs/apk/debug/`。Release 签名由开发者自行配置，不包含任何私人 keystore。

## 测试与资源生成

```sh
swift test --package-path TrainingLedger/TrainingCore
npm ci --prefix CFPocketAndroid
npm test --prefix CFPocketAndroid
```

更新共享编辑规则、提交检查与高亮资源：

```sh
npm run build:editor --prefix CFPocketAndroid
npm run build:submission --prefix CFPocketAndroid
npm run build:reader --prefix CFPocketAndroid
```

两端的提交脚本由 `CFWebForm.swift` 统一生成；测试会核对副本一致性。个人账号的历史抓取样本不随仓库分发，依赖它们的回归检查会跳过。测试夹具中保留的账号名称均为明确示例，不预装到 App 中。

## 最新修复与验证边界

0.10 / 0.5 加入编辑器增强；0.10.1 / 0.5.1 统一了“表单就绪”和实际发送时的校验，兼容带题号的官方提交地址，增加具体失败提示和重新准备入口。

本地回归覆盖表单地址、题号、账号、编译器、验证信息、网络失败及重复发送防护。模拟器验证了准备和恢复流程。真实网站可能调整表单或要求验证；本轮提交修复没有向真实账号发送测试代码，不将本地夹具验收当作线上提交成功。

C++ 运行环境是 WASI / libc++，与 Codeforces 的 GNU Linux 环境不同；PBDS、线程及部分平台专用功能不支持。样例 AC 不代表官网 AC。关键词／片段补全不提供完整 C++ 类型分析。

## 数据与许可

账号、登录会话、Key、题单进度、草稿与个人提交记录保存在用户设备中，不包含在本仓库。新安装不预置开发者个人账号。AI 是可选功能，费用由用户选择的服务决定。

当前仓库公开可见，但尚未为项目自有代码授予开源许可证。第三方运行环境、字体及库遵循各自许可，详见 [iOS 第三方说明](../TrainingLedger/CFPocket/THIRD-PARTY-NOTICES.md) 和 [Android 第三方说明](../CFPocketAndroid/THIRD-PARTY-NOTICES.md)。Codeforces、洛谷的内容与商标属于各自权利人。
