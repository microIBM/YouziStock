import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qun_market/main.dart';

void main() {
  testWidgets('报告 Markdown 渲染标题、加粗和表格', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportBody(
              data:
                  '## 主线定性\n\n**重点**：通信\n\n| 项目 | 结论 |\n|---|---|\n| 龙头 | 待验证 |',
            ),
          ),
        ),
      ),
    );
    expect(find.text('主线定性'), findsOneWidget);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('**'), findsNothing);
    expect(find.text('龙头'), findsOneWidget);
    expect(find.textContaining('|---'), findsNothing);
  });
}
