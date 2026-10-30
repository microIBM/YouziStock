import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qun_market/main.dart';

void main() {
  testWidgets('重启读取未完成草稿并展示失败原因', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'history':
          '[{"title":"全市场复盘","created":"2026-10-29","model":"test","status":"incomplete","report":"已收到的半份正文","error":"模型响应超时"}]',
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('复盘档案'));
    await tester.pumpAndSettle();
    expect(find.text('【未完成草稿】全市场复盘'), findsOneWidget);
    await tester.tap(find.text('查看详细分析报告'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未完成草稿，不作为完整报告。'), findsOneWidget);
    expect(find.text('已收到的半份正文'), findsOneWidget);
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('首页展示陈小群核心与自动搜索分析按钮', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(find.text('陈小群 · 顶级游资复盘体系'), findsOneWidget);
    expect(find.text('自动搜索并用陈小群 Skill 分析'), findsOneWidget);
  });

  testWidgets('配置页面展示多模型支持与协议切换', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    // 切换到底部设置
    await tester.tap(find.text('模型配置'));
    await tester.pumpAndSettle();

    expect(find.text('配置自定义大模型'), findsOneWidget);
    expect(find.text('DeepSeek'), findsOneWidget);
    expect(find.text('OpenAI / OpenGPT'), findsOneWidget);
    expect(find.text('Claude (Anthropic)'), findsOneWidget);
    expect(find.text('智谱 GLM'), findsOneWidget);
    expect(find.text('小米 MiMo'), findsOneWidget);
    expect(find.text('MiniMax'), findsOneWidget);
    expect(find.text('自定义 HTTP / HTTPS'), findsOneWidget);
  });

  testWidgets('切换模型不立即生效，各模型设置分别保留', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('模型配置'));
    await tester.pumpAndSettle();
    final store = const FlutterSecureStorage();

    // 修改 DeepSeek 的模型名后切到 OpenAI，不保存。
    await tester.enterText(
      find.widgetWithText(TextField, '模型名称 (Model ID)'),
      'my-deepseek',
    );
    await tester.tap(find.text('OpenAI / OpenGPT'));
    await tester.pumpAndSettle();
    expect(await store.read(key: 'config'), isNull);
    expect(find.text('gpt-4o'), findsOneWidget);

    // 保存 OpenAI 后才生效；切回 DeepSeek 仍是未保存的草稿。
    await tester.ensureVisible(find.text('保存配置'));
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(await store.read(key: 'active_profile'), 'OpenAI / OpenGPT');
    await tester.ensureVisible(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek'));
    await tester.pumpAndSettle();
    expect(find.text('my-deepseek'), findsOneWidget);
    expect(await store.read(key: 'active_profile'), 'OpenAI / OpenGPT');
  });

  testWidgets('可以删除单条与清空复盘记录', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'history':
          '[{"title":"A","created":"x","model":"m","status":"completed","report":"r"},{"title":"B","created":"x","model":"m","status":"incomplete","report":"r"}]',
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('复盘档案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清理未完成草稿'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('【未完成草稿】B'), findsNothing);
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.byTooltip('删除这条记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    expect(find.textContaining('暂无复盘记录'), findsOneWidget);
  });
}
