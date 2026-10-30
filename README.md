# YouziStock（群策）

基于游资交易思维框架（Skill）的 A 股行情复盘 App。每次选择一个 Skill 视角，自动联网获取行情数据，调用你配置的大模型生成复盘报告。

> 本项目仅为研究与学习工具，输出内容不构成任何投资建议。Skill 为基于公开资料提炼的分析框架，不代表本人观点。

## 项目结构

| 目录 | 说明 |
|---|---|
| `qun_market/` | Flutter 版（Android 优先，已适配 iOS 15 / iPhone 7） |
| `qun_market/rn/` | React Native 0.76 版（Android 与 iOS） |
| `qun_market/assets/skills/` | 内置的游资 Skill 资料 |

## 主要功能

- **多 Skill 视角**：陈小群、炒股养家、涅槃重生、92科比、赵老哥、作手新一、瑞鹤仙、退学炒股、北京炒家、著名刺客；每次分析只选一个。
- **自动取数**：自动获取全市场涨跌、涨停池、炸板池、昨日涨停、概念与行业板块等数据，无需手动填写材料。
- **角色化输出**：按板块给出总龙、20cm 弹性、中军、补涨，以及个股灯、板块灯、能否出手、风险锚和纪律。
- **大模型接入**：HTTP 接口，兼容 OpenAI Chat、OpenAI Responses 及其他兼容服务；支持推理强度、连接测试、流式接收、中途中止。
- **报告管理**：详情页跳转、回到顶部、历史档案、删除与清理；缓存超过设定阈值（默认 1 GB）时提醒清理。
- **完成提醒（RN 版）**：复盘成功或失败后可选无声、提示声、震动。
- **权限申请（RN 版）**：通知等运行时权限的申请与跳转系统设置。
- **安全存储（RN 版）**：模型接口与密钥保存在系统钥匙串 / Keystore，不写入普通文件。
- **界面适配**：红金牛市主题，适配主流手机分辨率与大字体。

## 环境要求

| 项目 | 版本 |
|---|---|
| Flutter 版 | 最新稳定版 Flutter，iOS 最低 15.0 |
| RN 版 | Node 18+、React Native 0.76.9 |
| Android | Android Studio / SDK，JDK 17 |
| iOS | macOS、Xcode、CocoaPods，需自己的开发签名 |

## 运行

### Flutter 版

```bash
cd qun_market
flutter pub get
flutter test
flutter run
```

### RN 版

```bash
cd qun_market/rn
npm install
npx tsc --noEmit
npm run android
# iOS
cd ios && pod install && cd ..
npm run ios
```

## 模型配置

在 App 的“模型”页填写接口地址、协议、模型名称和 API Key，先点“测试连接”再保存。
密钥只保存在本机，请勿提交到仓库或写入代码。

## iOS 注意事项

- 真机运行需要在 Xcode 的 Signing & Capabilities 中选择自己的 Team。
- 钥匙串存储需要签名和 Keychain 授权，未签名构建会读取失败。
- 虚拟机中的 macOS 通常没有 Metal，iOS 模拟器可能黑屏，建议用真机验证。
- 接口使用 HTTP 时，需要保留 App Transport Security 的例外配置。

## 免责声明

股市有风险。本项目输出的复盘内容仅供研究参考，不构成买卖建议，使用者需自行承担投资风险。
