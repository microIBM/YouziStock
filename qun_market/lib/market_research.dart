import 'dart:convert';
import 'package:http/http.dart' as http;

String dayKey(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
DateTime beijingNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
String epochDay(dynamic value) {
  final n = int.tryParse('$value');
  if (n == null || n <= 0) return '';
  return dayKey(
    DateTime.fromMillisecondsSinceEpoch(
      n * 1000,
      isUtc: true,
    ).add(const Duration(hours: 8)),
  );
}

/// Date equality is evidence alignment, not an exchange holiday calendar.
String freshnessNotice(String date, DateTime now) {
  if (!RegExp(r'^\d{8}$').hasMatch(date)) return '日期无效，不能用于当日结论';
  if (date.compareTo(dayKey(now)) > 0) return '未来日期异常，不能使用';
  if (date == dayKey(now)) {
    return now.hour >= 15 ? '当日行情快照；各数据源可能尚在修订' : '当日盘中快照，不是收盘复盘';
  }
  return '历史快照：$date；尚未接入交易所节假日日历，不能确认是最近交易日，不得称为今日实时数据';
}

List<Map<String, dynamic>> parsePool(Map data, String date) {
  if ('${data['qdate']}' != date) throw const FormatException('股票池交易日期不匹配');
  if (data['pool'] is! List) throw const FormatException('股票池缺失，不等于零家');
  final rows = (data['pool'] as List)
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  final total = int.tryParse('${data['tc']}');
  if (total == null || total != rows.length) {
    throw const FormatException('股票池不完整，禁止计算全量统计');
  }
  if (rows.map((r) => r['c']).toSet().length != rows.length) {
    throw const FormatException('股票池证券重复');
  }
  return rows;
}

String beijingStamp(DateTime now) =>
    '${now.toIso8601String().replaceAll('Z', '')}+08:00';

String turnoverComparison(List<dynamic> sh, List<dynamic> sz, String date) {
  Map<String, double> parse(List<dynamic> rows) {
    final result = <String, double>{};
    for (final row in rows) {
      final f = '$row'.split(',');
      if (f.length < 7) continue;
      final amount = double.tryParse(f[6]);
      final day = f[0].replaceAll('-', '');
      if (amount != null && amount.isFinite && amount > 0) result[day] = amount;
    }
    return result;
  }

  final a = parse(sh), b = parse(sz);
  final ad = a.keys.where((d) => d.compareTo(date) <= 0).toList()..sort();
  final bd = b.keys.where((d) => d.compareTo(date) <= 0).toList()..sort();
  if (ad.length < 2 ||
      bd.length < 2 ||
      ad.last != date ||
      bd.last != date ||
      ad[ad.length - 2] != bd[bd.length - 2]) {
    throw const FormatException('两市相邻日线日期缺失或不一致，不计算缩放量');
  }
  final prev = ad[ad.length - 2];
  final current = a[date]! + b[date]!;
  final previous = a[prev]! + b[prev]!;
  final delta = current - previous;
  return '【同源日线量能对比】东方财富沪深指数日线；日期$date，前一共同日线$prev。'
      '沪深成交额${(current / 1e8).toStringAsFixed(2)}亿元，前日${(previous / 1e8).toStringAsFixed(2)}亿元；'
      '${delta >= 0 ? '放量' : '缩量'}${(delta.abs() / 1e8).toStringAsFixed(2)}亿元，变化${(delta / previous * 100).toStringAsFixed(2)}%。'
      '仅同源日线比较，创业板不重复加总；日线日期不代替交易所日历。';
}

class MarketResearch {
  MarketResearch(this.client);
  final http.Client client;
  Future<Map<String, dynamic>> jsonGet(Uri uri) async {
    final r = await client.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is! Map || j['data'] is! Map) throw const FormatException('数据结构缺失');
    return Map<String, dynamic>.from(j['data'] as Map);
  }

  Future<Map<String, dynamic>> list(
    String fs, {
    int size = 20,
    String fid = 'f3',
  }) => jsonGet(
    Uri.https('push2.eastmoney.com', '/api/qt/clist/get', {
      'pn': '1',
      'pz': '$size',
      'po': '1',
      'np': '1',
      'fltt': '2',
      'fid': fid,
      'fs': fs,
      'fields': 'f12,f14,f2,f3,f6,f8,f104,f105,f124',
    }),
  );

  Future<List<Map<String, dynamic>>> pool(
    String name,
    String date, {
    String sort = 'fbt:asc',
  }) async => parsePool(
    await jsonGet(
      Uri.https('push2ex.eastmoney.com', '/$name', {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'Pageindex': '0',
        'pagesize': '1000',
        'sort': sort,
        'date': date,
      }),
    ),
    date,
  );

  Future<Map<String, String>> gather() async {
    final now = beijingNow();
    final out = StringBuffer();
    final gaps = <String>[];
    final sources = <String>[];
    String date = '';
    // Tencent numeric fields are ASCII; labels are fixed to avoid GBK corruption.
    final r = await client
        .get(Uri.parse('https://qt.gtimg.cn/q=sh000001,sz399001,sz399006'))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw Exception('交易日期锚获取失败：HTTP ${r.statusCode}');
    final indices = <String, List<String>>{};
    for (final line in latin1.decode(r.bodyBytes).split(';')) {
      final f = line.split('~');
      if (f.length > 37 && ['000001', '399001', '399006'].contains(f[2])) {
        indices[f[2]] = f;
      }
    }
    if (indices.length != 3) throw Exception('三个指数数据不完整，无法建立统一交易日期');
    final dates = indices.values
        .map(
          (f) =>
              RegExp(r'^\d{14}$').hasMatch(f[30]) ? f[30].substring(0, 8) : '',
        )
        .toSet();
    if (dates.length != 1 || dates.first.isEmpty) {
      throw Exception('指数日期缺失或互相不一致，已停止分析');
    }
    date = dates.first;
    if (date.compareTo(dayKey(now)) > 0) {
      throw Exception('指数日期晚于设备日期，请检查行情源和设备时间');
    }
    out.writeln(
      '【研究日期与口径】\n行情日期：$date（北京时间）。${freshnessNotice(date, now)}。\n检索时间：${beijingStamp(now)}。检索时间不等于行情更新时间。',
    );
    const labels = {'000001': '上证指数', '399001': '深证成指', '399006': '创业板指'};
    out.writeln('【指数】来源：腾讯财经 https://qt.gtimg.cn');
    for (final e in indices.entries) {
      final f = e.value;
      out.writeln(
        '${labels[e.key]}：点位${f[3]}，涨跌${f[32]}%，成交额${f[37]}万元，行情时间${f[30]}',
      );
    }
    final sh = double.tryParse(indices['000001']![37]);
    final sz = double.tryParse(indices['399001']![37]);
    if (sh != null && sz != null) {
      out.writeln(
        '沪深两市成交额合计：${((sh + sz) / 10000).toStringAsFixed(2)}亿元（上证+深证，创业板已包含，不能重复加总）；缩放量见下方同源日线对比，若缺失则不判断。',
      );
    }
    sources.add('腾讯财经指数');
    if (date != dayKey(now) || now.hour >= 16) {
      try {
        final bars = await Future.wait(
          ['1.000001', '0.399001'].map(
            (secid) => jsonGet(
              Uri.https('push2his.eastmoney.com', '/api/qt/stock/kline/get', {
                'secid': secid,
                'klt': '101',
                'fqt': '0',
                'lmt': '5',
                'end': date,
                'fields1': 'f1,f2,f3,f4,f5,f6',
                'fields2': 'f51,f52,f53,f54,f55,f56,f57',
              }),
            ),
          ),
        );
        out.writeln(
          turnoverComparison(
            bars[0]['klines'] as List,
            bars[1]['klines'] as List,
            date,
          ),
        );
        sources.add('东方财富沪深日线');
      } catch (e) {
        gaps.add('前日成交额与量能对比：$e');
      }
    } else {
      gaps.add('盘中或收盘数据修订期，不将部分时段成交额与前日全天直接比较');
    }

    List<Map<String, dynamic>>? zt;
    List<Map<String, dynamic>>? zb;
    List<Map<String, dynamic>>? yz;
    await Future.wait([
      () async {
        try {
          yz = await pool('getYesterdayZTPool', date, sort: 'zs:desc');
        } catch (e) {
          gaps.add('昨日涨停表现：$e');
        }
      }(),
      () async {
        try {
          zt = await pool('getTopicZTPool', date);
        } catch (e) {
          gaps.add('涨停池：$e');
        }
      }(),
      () async {
        try {
          zb = await pool('getTopicZBPool', date);
        } catch (e) {
          gaps.add('炸板池：$e');
        }
      }(),
    ]);
    for (final entry in {'涨停池': zt, '炸板池': zb}.entries) {
      final rows = entry.value;
      if (rows == null) continue;
      sources.add('东方财富${entry.key}');
      out.writeln(
        '\n【${entry.key}】日期$date；共${rows.length}家；东方财富池口径，不保证覆盖ST、北交所或所有证券；日内快照不等于最终收盘统计。来源：https://push2ex.eastmoney.com',
      );
      rows.sort(
        (a, b) => (num.tryParse('${b['lbc']}') ?? 0).compareTo(
          num.tryParse('${a['lbc']}') ?? 0,
        ),
      );
      for (final x in rows.take(120)) {
        out.writeln(
          '${x['n']}(${x['c']})：涨幅${x['zdp']}%，连板${x['lbc'] ?? '未提供'}；行业${x['hybk'] ?? '未提供'}；换手${x['hs']}%；成交额${x['amount']}元；首次封板${x['fbt']}；最后封板${x['lbt'] ?? '未提供'}；开板次数${x['zbc']}。',
        );
      }
      if (rows.length > 120) out.writeln('明细截取前120家，统计数量为完整池数量。');
    }
    if (zt != null && zb != null && zt!.length + zb!.length > 0) {
      out.writeln(
        '同日同源两池封板比例：${(zt!.length / (zt!.length + zb!.length) * 100).toStringAsFixed(2)}% = 涨停池/(涨停池+炸板池)，不冒充全市场官方封板率。',
      );
    }
    final y = yz;
    if (y != null) {
      final vals = y
          .map((x) => num.tryParse('${x['zdp']}'))
          .whereType<num>()
          .toList();
      if (y.isEmpty ||
          vals.length != y.length ||
          vals.any((v) => !v.isFinite)) {
        gaps.add('昨日涨停表现：空池或涨跌幅缺失，未计算平均值');
      } else {
        sources.add('东方财富昨日涨停表现');
        final avg = vals.isEmpty
            ? 0
            : vals.reduce((a, b) => a + b) / vals.length;
        final down = vals.where((v) => v < 0).length;
        final up = vals.where((v) => v > 0).length;
        out.writeln(
          '\n【昨日涨停股今日表现】日期$date；共${y.length}只；等权平均涨幅${avg.toStringAsFixed(2)}%；上涨$up只，下跌$down只，平盘${y.length - up - down}只。东方财富池口径，不含未收录证券，且不是成交额加权，不能当作官方指数。',
        );
        final ranked = [...y]
          ..sort(
            (a, b) => (num.tryParse('${a['zdp']}') ?? 0).compareTo(
              num.tryParse('${b['zdp']}') ?? 0,
            ),
          );
        for (final x in [...ranked.take(8), ...ranked.reversed.take(8)]) {
          out.writeln(
            '${x['n']}(${x['c']})：今日${x['zdp']}%，昨日连板${x['ylbc'] ?? '未提供'}；行业${x['hybk'] ?? '未提供'}；成交额${x['amount']}元；换手${x['hs']}%。',
          );
        }
      }
    }
    try {
      final boards = await Future.wait([
        list('m:90+t:3', size: 30),
        list('m:90+t:2', size: 15),
      ]);
      final rows = <Map>[
        for (var i = 0; i < boards.length; i++)
          for (final b in boards[i]['diff'] as List)
            {...b as Map, 'category': i == 0 ? '概念' : '行业'},
      ];
      final valid = rows.where((x) => epochDay(x['f124']) == date).toList();
      out.writeln(
        '\n【概念与行业板块涨幅榜样本】东方财富；概念前30项、行业前15项，含风格/昨日表现指数，不能直接视为产业主线；同日条目${valid.length}/${rows.length}。',
      );
      for (final b in valid) {
        out.writeln(
          '[${b['category']}]${b['f14']}(${b['f12']})：${b['f3']}%，成交额${b['f6']}元，上涨${b['f104']}家/下跌${b['f105']}家，时间戳${b['f124']}',
        );
      }
      if (valid.length != rows.length) gaps.add('部分板块日期缺失或不匹配，已排除');
      if (valid.isNotEmpty) sources.add('东方财富概念榜单及成分样本');
      final candidates = valid
          .where(
            (b) => !RegExp(
              '昨日|连板|百元|高价|低价|历史新高|融资|证金|沪股通|深股通|MSCI|富时|上证|深证|标普|央视|大盘|价值|题材股|破净|红利',
            ).hasMatch('${b['f14']}'),
          )
          .take(6)
          .toList();
      final details = await Future.wait(
        candidates.map((b) async {
          try {
            final samples = await Future.wait([
              list('b:${b['f12']}', size: 5, fid: 'f6'),
              list('b:${b['f12']}', size: 5, fid: 'f3'),
            ]);
            final stocks = <String, Map>{};
            for (final d in samples) {
              for (final s in (d['diff'] as List).cast<Map>()) {
                if (epochDay(s['f124']) == date) stocks['${s['f12']}'] = s;
              }
            }
            if (stocks.isEmpty) throw const FormatException('无同日有效成分');
            return '【${b['f14']}成分样本】成交额前5与涨幅前5去重；仅作容量与弹性观察，未证明龙头身份；板块成分可能重复。\n${stocks.values.map((s) => '${s['f14']}(${s['f12']}) 涨幅${s['f3']}%，成交额${s['f6']}元，换手${s['f8']}%，时间戳${s['f124']}').join('\n')}';
          } catch (e) {
            return '【缺失】${b['f14']}成分数据：$e';
          }
        }),
      );
      for (final d in details) {
        out.writeln(d);
      }
    } catch (e) {
      gaps.add('概念板块与成分：$e');
    }
    gaps.addAll([
      '全市场上涨/下跌家数未采集，不能用板块样本家数代替',
      '新闻催化、公告、龙虎榜未联网核验',
      '未接入交易所交易日历；历史日期不得自动宣称为最近交易日',
    ]);
    out.writeln(
      '\n【证据缺口】\n${gaps.map((g) => '- $g').join('\n')}\n只基于有日期的证据分析；缺项不得补造，行业不等于题材，成交额领先不等于中军或总龙。',
    );
    return {
      'time': beijingStamp(now),
      'source': sources.join(' + '),
      'data': out.toString(),
      'date': date,
    };
  }
}
