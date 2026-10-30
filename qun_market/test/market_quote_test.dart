import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qun_market/market_quote.dart';

void main() {
  test('东方财富失败后使用腾讯并校验代码与时间', () async {
    final fields = List.filled(40, '0');
    fields[2] = '000063';
    fields[3] = '10.5';
    fields[30] = '20261029150000';
    final client = MockClient(
      (r) async => r.url.host.contains('eastmoney')
          ? http.Response('{}', 200)
          : http.Response(fields.join('~'), 200),
    );
    final out = await fetchStockQuote(client, '000063');
    expect(out, contains('腾讯财经'));
    expect(out, contains('2026-10-29 15:00:00'));
  });

  test('两个源都缺失时抛出明确错误', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({}), 200));
    await expectLater(
      fetchStockQuote(client, '000063'),
      throwsA(predicate((e) => e.toString().contains('行情缺失'))),
    );
  });
}
