import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qun_market/main.dart';
import 'package:qun_market/analysis_skill.dart';

void main() {
  testWidgets('全部Skill资源可加载，系统提示词使用唯一所选框架', (tester) async {
    for (final skill in analysisSkills) {
      final content = await skill.load();
      expect(content.length, greaterThan(500));
      final system = buildSkillSystem('证据规则', skill, content);
      expect(system, contains('本次唯一分析框架：${skill.name}'));
      expect(system, contains(content));
    }
    expect(analysisSkills.length, 10);
    expect(analysisSkills.map((s) => s.id).toSet().length, 10);
  });

  testWidgets('Skill单选持久化，重启恢复并更新分析按钮', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(10));
    await tester.tap(find.widgetWithText(ChoiceChip, '炒股养家'));
    await tester.pumpAndSettle();
    expect(find.text('炒股养家 · 游资复盘框架'), findsOneWidget);
    expect(find.text('自动搜索并用炒股养家 Skill 分析'), findsOneWidget);
    expect(
      await const FlutterSecureStorage().read(key: 'selected_skill'),
      'chaoguyangjia',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('炒股养家 · 游资复盘框架'), findsOneWidget);
  });

  testWidgets('历史报告显示原Skill，不被当前选择覆盖', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'selected_skill': 'bjchaojia',
      'history':
          '[{"title":"复盘测试","created":"2026-10-30","model":"test","status":"completed","report":"历史正文","skillId":"zhaolaoge","skillName":"赵老哥"}]',
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(const MarketApp());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(find.text('北京炒家 · 游资复盘框架'), findsOneWidget);
    await tester.tap(find.text('复盘档案'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Skill: 赵老哥'), findsOneWidget);
    await tester.tap(find.text('查看详细分析报告'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Skill: 赵老哥'), findsOneWidget);
    expect(find.text('历史正文'), findsOneWidget);
  });

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

    expect(find.text('陈小群 · 游资复盘框架'), findsOneWidget);
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

  testWidgets('多种屏幕比例与大字体下页面无溢出', (tester) async {
    const sizes = [
      Size(320, 568),
      Size(360, 800),
      Size(375, 667), // iPhone 7
      Size(412, 915),
      Size(800, 1280),
      Size(915, 412),
    ];
    for (final size in sizes) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.runAsync(() async {
          await tester.pumpWidget(const MarketApp());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        for (final tab in ['Skill 分析', '复盘档案', '模型配置']) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size x$scale $tab');
        }
      }
    }
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAllTestValues();
    });
  });
}
