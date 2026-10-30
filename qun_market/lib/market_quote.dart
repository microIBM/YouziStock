import 'dart:convert';
import 'package:http/http.dart' as http;

Future<String> fetchStockQuote(http.Client client, String code) async {
  if (!RegExp(r'^\d{6}$').hasMatch(code)) throw Exception('证券代码格式无效');
  final sh = code.startsWith('6');
  final failures = <String>[];
  try {
    final uri = Uri.https('push2.eastmoney.com', '/api/qt/stock/get', {
      'secid': '${sh ? 1 : 0}.$code',
      'fields': 'f57,f58,f43,f44,f45,f46,f47,f48,f60,f86,f170',
      'fltt': '2',
    });
    final res = await client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(utf8.decode(res.bodyBytes))['data'];
    if (data is! Map || data['f57'] != code || !_price(data['f43'])) {
      throw Exception('个股价格缺失或证券不匹配');
    }
    final epoch = int.tryParse('${data['f86']}');
    if (epoch == null || epoch <= 0) throw Exception('行情时间缺失');
    final stamp = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true)
        .add(const Duration(hours: 8))
        .toIso8601String()
        .replaceFirst('Z', '+08:00');
    return '〔个股行情〕东方财富 ${data['f58']}($code)\n行情时间：$stamp（北京时间；非交易时段可能为最近收盘数据）\n现价：${data['f43']}；涨跌幅：${data['f170']}%；最高：${data['f44']}；最低：${data['f45']}\n成交量：${data['f47']}手；成交额：${data['f48']}元';
  } catch (e) {
    failures.add('东方财富：$e');
  }
  try {
    final symbol = '${sh ? 'sh' : 'sz'}$code';
    final res = await client
        .get(Uri.parse('https://qt.gtimg.cn/q=$symbol'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    // Numeric quote fields are ASCII; omit the GBK name rather than misdecode it.
    final raw = latin1.decode(res.bodyBytes);
    final fields = raw.split('~');
    if (fields.length < 38 || fields[2] != code || !_price(fields[3])) {
      throw Exception('个股价格缺失或证券不匹配');
    }
    final t = fields[30];
    if (!RegExp(r'^\d{14}$').hasMatch(t)) throw Exception('行情时间缺失');
    final stamp =
        '${t.substring(0, 4)}-${t.substring(4, 6)}-${t.substring(6, 8)} ${t.substring(8, 10)}:${t.substring(10, 12)}:${t.substring(12, 14)}';
    return '〔个股行情〕腾讯财经 $code\n行情时间：$stamp（北京时间；非交易时段可能为最近收盘数据）\n现价：${fields[3]}；昨收：${fields[4]}；涨跌幅：${fields[32]}%；最高：${fields[33]}；最低：${fields[34]}\n成交量：${fields[36]}手；成交额：${fields[37]}万元\n数据源回退说明：${failures.join('；')}';
  } catch (e) {
    failures.add('腾讯财经：$e');
  }
  throw Exception('指定个股 $code 行情缺失，已停止模型分析，不能用市场榜单替代。\n${failures.join('\n')}');
}

bool _price(dynamic value) {
  final number = num.tryParse('$value');
  return number != null && number.isFinite && number > 0;
}
