import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qun_market/market_research.dart';

void main() {
  test('量能对比只采用两市对齐的相邻日线', () {
    final sh = [
      '2026-10-28,0,0,0,0,0,100000000',
      '2026-10-29,0,0,0,0,0,80000000',
    ];
    final sz = [
      '2026-10-28,0,0,0,0,0,200000000',
      '2026-10-29,0,0,0,0,0,160000000',
    ];
    expect(turnoverComparison(sh, sz, '20261029'), contains('缩量0.60亿元'));
    expect(turnoverComparison(sh, sz, '20261029'), contains('变化-20.00%'));
    expect(
      () => turnoverComparison(sh, [sz.last], '20261029'),
      throwsFormatException,
    );
    expect(
      () => turnoverComparison(sh, [
        '2026-10-27,0,0,0,0,0,100',
        sz.last,
      ], '20261029'),
      throwsFormatException,
    );
    expect(() => turnoverComparison(sh, sz, '20261030'), throwsFormatException);
  });
  test('北京时间标识没有重复UTC后缀', () {
    expect(
      beijingStamp(DateTime.utc(2026, 10, 30, 0, 20)),
      '2026-10-30T00:20:00.000+08:00',
    );
  });
  test('拒绝错日和不完整池，空池必须明确为零', () {
    expect(
      () => parsePool({'qdate': 20261028, 'tc': 0, 'pool': []}, '20261029'),
      throwsFormatException,
    );
    expect(
      () => parsePool({
        'qdate': 20261029,
        'tc': 2,
        'pool': [
          {'c': '000001'},
        ],
      }, '20261029'),
      throwsFormatException,
    );
    expect(
      parsePool({'qdate': 20261029, 'tc': 0, 'pool': []}, '20261029'),
      isEmpty,
    );
    expect(
      () => parsePool({'qdate': 20261029, 'tc': 0}, '20261029'),
      throwsFormatException,
    );
  });
  test('历史与未来日期不可冒充今日', () {
    expect(
      freshnessNotice('20261028', DateTime(2026, 10, 29, 22)),
      contains('历史快照'),
    );
    expect(
      freshnessNotice('20261030', DateTime(2026, 10, 29, 22)),
      contains('未来日期'),
    );
    expect(
      freshnessNotice('20261029', DateTime(2026, 10, 29, 10)),
      contains('盘中'),
    );
    expect(epochDay(1793259267), '20261029');
  });
  test(
    '真实接口汇总材料冒烟检查',
    () async {
      final client = http.Client();
      try {
        final data = await MarketResearch(client).gather();
        expect(data['data'], contains('【指数】'));
        expect(data['data'], contains('【证据缺口】'));
        expect(data['date'], matches(RegExp(r'^\d{8}$')));
        // Only emit source and counts, never model credentials.
        // ignore: avoid_print
        print(
          '采集成功：日期${data['date']}，来源${data['source']}，材料${data['data']!.length}字',
        );
      } finally {
        client.close();
      }
    },
    skip: const bool.fromEnvironment('LIVE_MARKET') ? false : '仅显式开启时联网',
  );
}
