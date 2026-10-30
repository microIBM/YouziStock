# 群策（qun_market）

基于游资交易思维框架（Skill）的 A 股行情复盘 App。每次选择一个 Skill 视角，自动联网获取行情数据，调用你配置的大模型生成复盘报告。

本目录是 **Flutter 版**（Android 优先，已适配 iOS 15 / iPhone 7）。React Native 版位于 `rn/`。

> 仅为研究与学习工具，输出内容不构成任何投资建议。

## 功能

- 多 Skill 视角：陈小群、炒股养家、涅槃重生、92科比、赵老哥、作手新一、瑞鹤仙、退学炒股、北京炒家、著名刺客，每次分析选择一个。
- 自动取数：全市场涨跌、涨停池、炸板池、昨日涨停、概念与行业板块。
- 角色化输出：按板块给出总龙、20cm 弹性、中军、补涨，以及个股灯、板块灯、能否出手、风险锚和纪律。
- 大模型接入：HTTP 接口，支持 OpenAI Chat / Responses 等兼容协议，推理强度、连接测试、流式接收、中途中止。
- 报告管理：详情页跳转、回到顶部、历史档案、删除与清理。
- 红金牛市主题。

## 目录

| 路径 | 说明 |
|---|---|
| `lib/` | Dart 源码（`main.dart` 界面，`model_api.dart` 模型请求，`market_*.dart` 行情与研究） |
| `assets/skills/` | 内置 Skill 资料 |
| `test/` | 单元与界面测试 |
| `android/`、`ios/` | 原生工程 |
| `rn/` | React Native 版 |

## 运行

```bash
flutter pub get
flutter test
flutter run
```

构建：

```bash
flutter build apk --release
flutter build ios --release   # 需 macOS 与开发签名
```

## 模型配置

在“模型配置”页填写接口地址、协议、模型名称和 API Key，先点“测试连接”再保存。密钥只保存在本机，请勿提交到仓库。

## iOS 注意事项

- 最低系统 iOS 15.0。
- 真机需在 Xcode 的 Signing & Capabilities 选择自己的 Team。
- 使用 HTTP 接口时需保留 App Transport Security 例外配置。
- 虚拟机中的 macOS 通常无 Metal，模拟器可能黑屏，建议真机验证。

## 免责声明

股市有风险。复盘内容仅供研究参考，不构成买卖建议。
