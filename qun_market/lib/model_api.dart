import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

const reasoningEfforts = <String, String>{
  'default': '默认（由服务决定）',
  'none': '关闭（none）',
  'minimal': '极低（minimal）',
  'low': '低（low）',
  'medium': '中（medium）',
  'high': '高（high）',
  'xhigh': '极高（xhigh）',
  'max': '最大（max）',
};

Uri modelUrl(String endpoint, String protocol) {
  final uri = Uri.tryParse(endpoint.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const FormatException('接口地址需以 http:// 或 https:// 开头');
  }
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  path = path.replaceFirst(
    RegExp(r'/(chat/completions|responses|messages)$'),
    '',
  );
  if (path.isEmpty) path = '/v1';
  final suffix = switch (protocol) {
    'responses' => '/responses',
    'anthropic' => '/messages',
    _ => '/chat/completions',
  };
  return uri.replace(path: '$path$suffix', fragment: '');
}

String safeError(Object error, String key) {
  var text = error.toString().replaceFirst('Exception: ', '');
  if (key.isNotEmpty) text = text.replaceAll(key, '[密钥已隐藏]');
  text = text.replaceAll(
    RegExp(r'Bearer\s+[^\s"<>]+', caseSensitive: false),
    'Bearer [已隐藏]',
  );
  text = text.replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), '[密钥已隐藏]');
  text = text.replaceAllMapped(RegExp(r'https?://[^\s<>]+'), (match) {
    final uri = Uri.tryParse(match[0]!);
    if (uri == null || uri.host.isEmpty) return '[请求地址已隐藏]';
    return '${uri.scheme}://${uri.host}:${uri.port}/[路径及参数已隐藏]';
  });
  return text.length > 1200 ? '${text.substring(0, 1200)}…' : text;
}

Future<String> requestModel({
  required http.Client client,
  required String endpoint,
  required String protocol,
  required String model,
  required String key,
  required String system,
  required String prompt,
  String reasoningEffort = 'default',
  void Function(String text)? onText,
  void Function(Map<String, dynamic> event)? onDiagnostic,
  Duration firstTimeout = const Duration(seconds: 60),
  Duration idleTimeout = const Duration(seconds: 120),
  Duration totalTimeout = const Duration(minutes: 8),
}) async {
  if (model.trim().isEmpty) throw const FormatException('请填写模型名称');
  if (!reasoningEfforts.containsKey(reasoningEffort)) {
    throw const FormatException('未知推理强度，请重新选择');
  }
  if (protocol == 'anthropic' && reasoningEffort != 'default') {
    throw const FormatException('Claude 原生协议暂不支持此推理强度参数，请选择默认');
  }
  final url = modelUrl(endpoint, protocol);
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (protocol == 'anthropic') {
    headers['x-api-key'] = key;
    headers['anthropic-version'] = '2023-06-01';
  } else if (key.isNotEmpty) {
    headers['Authorization'] = 'Bearer $key';
  }
  final payload = <String, dynamic>{'model': model.trim()};
  if (protocol == 'responses') {
    payload.addAll({
      'instructions': system,
      'input': prompt,
      'stream': true,
      'store': false,
    });
  } else {
    payload['messages'] = [
      if (protocol != 'anthropic') {'role': 'system', 'content': system},
      {'role': 'user', 'content': prompt},
    ];
    if (protocol == 'anthropic') {
      payload.addAll({'system': system, 'max_tokens': 4000});
    } else {
      payload['stream'] = false;
    }
  }
  if (reasoningEffort != 'default') {
    if (protocol == 'responses') {
      payload['reasoning'] = {'effort': reasoningEffort};
    } else {
      payload['reasoning_effort'] = reasoningEffort;
    }
  }
  late http.StreamedResponse response;
  final watch = Stopwatch()..start();
  final request = http.Request('POST', url)
    ..headers.addAll(headers)
    ..body = jsonEncode(payload);
  try {
    response = await client
        .send(request)
        .timeout(firstTimeout < totalTimeout ? firstTimeout : totalTimeout);
  } on TimeoutException {
    throw Exception(
      '模型首响应超时：未在 ${firstTimeout.inSeconds} 秒内返回响应头（目标：${url.host}:${url.port}）',
    );
  } on http.ClientException catch (e) {
    final detail = safeError(e, key);
    throw Exception('模型网络连接失败（目标：${url.host}:${url.port}）：$detail');
  } catch (e) {
    final detail = safeError(e, key);
    throw Exception('网络请求异常（目标：${url.host}:${url.port}）：$detail');
  }
  onDiagnostic?.call({
    'httpStatus': response.statusCode,
    'headerMs': watch.elapsedMilliseconds,
  });
  final content = StringBuffer();
  final iterator = StreamIterator<String>(
    response.stream
        .timeout(idleTimeout)
        .transform(const Utf8Decoder(allowMalformed: true)),
  );
  var pending = '';
  var partial = '';
  var isSse = (response.headers['content-type'] ?? '').contains(
    'text/event-stream',
  );
  final success = response.statusCode >= 200 && response.statusCode < 300;
  try {
    while (true) {
      final remaining = totalTimeout - watch.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('总时长');
      final hasNext = await iterator.moveNext().timeout(remaining);
      if (!hasNext) break;
      final chunk = iterator.current;
      content.write(chunk);
      if (protocol != 'responses' || !success) continue;
      pending += chunk;
      isSse = isSse || RegExp(r'(^|\n)(event:|data:)').hasMatch(pending);
      if (!isSse) continue;
      var completed = false;
      while (true) {
        final boundary = RegExp(r'\r?\n\r?\n').firstMatch(pending);
        if (boundary == null) break;
        final block = pending.substring(0, boundary.start);
        pending = pending.substring(boundary.end);
        final lines = block.split(RegExp(r'\r?\n'));
        final data = lines
            .where((l) => l.startsWith('data:'))
            .map((l) => l.substring(5).trimLeft())
            .join('\n');
        if (data.isEmpty || data.trim() == '[DONE]') continue;
        dynamic event;
        try {
          event = jsonDecode(data);
        } catch (_) {
          throw Exception('Responses 流事件格式错误');
        }
        if (event is! Map) throw Exception('Responses 流事件格式错误');
        final types = lines.where((l) => l.startsWith('event:'));
        final type =
            event['type'] ??
            (types.isEmpty ? '' : types.first.substring(6).trim());
        final responseData = event['response'];
        final responseId = responseData is Map
            ? responseData['id']
            : event['response_id'];
        final errorData = responseData is Map
            ? responseData['error']
            : event['error'];
        onDiagnostic?.call({
          'lastEvent': safeError(type.toString(), key),
          'lastEventMs': watch.elapsedMilliseconds,
          if (responseId is String) 'responseId': safeError(responseId, key),
          if (errorData is Map && errorData['code'] != null)
            'errorCode': safeError(errorData['code'].toString(), key),
        });
        if (type == 'error' ||
            type == 'response.failed' ||
            type == 'response.incomplete' ||
            event['error'] != null) {
          throw Exception(
            safeError(
              'Responses 未完成：$type；${errorData ?? (responseData is Map ? responseData['incomplete_details'] : null) ?? '服务未提供详情'}',
              key,
            ),
          );
        }
        if (type == 'response.output_text.delta' && event['delta'] is String) {
          partial += event['delta'] as String;
          onText?.call(partial);
        }
        if (type == 'response.completed') completed = true;
      }
      if (completed) break;
    }
  } on TimeoutException {
    final reason = watch.elapsed >= totalTimeout
        ? '超过总时长 ${totalTimeout.inSeconds} 秒'
        : '连续 ${idleTimeout.inSeconds} 秒未收到数据';
    throw Exception('模型响应超时：$reason；已收到正文 ${partial.length} 字，未完成内容不作为完整报告');
  } on http.ClientException catch (e) {
    throw Exception(
      '模型接收中断（目标：${url.host}:${url.port}，已收到 ${partial.length} 字）：${safeError(e, key)}',
    );
  } finally {
    await iterator.cancel();
  }
  final raw = content.toString();
  dynamic body;
  try {
    body = jsonDecode(raw);
  } catch (_) {
    body = null;
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final hint = switch (response.statusCode) {
      400 || 422 =>
        reasoningEffort == 'default'
            ? '请求参数或模型与所选协议不兼容'
            : '请求参数不兼容：当前推理强度 $reasoningEffort 可能不受支持，请改为默认后重试（未自动降级）',
      401 => '密钥无效、过期或认证方式不匹配',
      403 => '服务拒绝访问，请检查账号权限或服务区域限制',
      404 || 405 => '接口路径、协议或模型名称不匹配',
      408 || 504 => '服务端或网关超时',
      429 => '触发频率限制或账户额度不足',
      >= 500 => '模型服务端异常',
      _ => '请求被服务拒绝',
    };
    final detail = body is Map
        ? (body['error'] ?? body['message'] ?? '无错误详情').toString()
        : '服务返回非 JSON 内容';
    throw Exception(
      safeError('HTTP ${response.statusCode}：$hint\n服务详情：$detail', key),
    );
  }
  if (protocol == 'responses' &&
      ((response.headers['content-type'] ?? '').toLowerCase().contains(
            'text/event-stream',
          ) ||
          RegExp(r'(^|\n)(event:|data:)').hasMatch(raw))) {
    try {
      body = parseResponsesSse(raw);
    } catch (error) {
      throw Exception(safeError(error, key));
    }
  }
  if (body is! Map) throw Exception('服务返回非 JSON 内容，请检查接口地址是否指向 API');
  if (body['error'] != null) {
    throw Exception(safeError('服务错误：${body['error']}', key));
  }
  final texts = <String>[];
  if (protocol == 'responses') {
    if (body['status'] == 'failed' || body['status'] == 'incomplete') {
      throw Exception(
        'Responses 未完成：${body['status']}，${body['incomplete_details'] ?? '服务未提供详情'}',
      );
    }
    if (body['output_text'] is String) texts.add(body['output_text'] as String);
    if (texts.isEmpty && body['output'] is List) {
      for (final item in body['output'] as List) {
        if (item is Map && item['content'] is List) {
          for (final part in item['content'] as List) {
            if (part is Map &&
                part['type'] == 'output_text' &&
                part['text'] is String) {
              texts.add(part['text'] as String);
            }
            if (part is Map && part['type'] == 'refusal') {
              throw Exception('模型拒绝回答：${part['refusal']}');
            }
          }
        }
      }
    }
  } else if (protocol == 'anthropic') {
    if (body['content'] is List) {
      for (final part in body['content'] as List) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          texts.add(part['text'] as String);
        }
      }
    }
  } else {
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      final content = choices.first['message']?['content'];
      if (content is String) texts.add(content);
    }
  }
  final result = texts.join('\n').trim();
  if (result.isEmpty) throw Exception('模型未返回可用文本：请核对所选协议，或检查服务是否仅返回推理/工具调用');
  return result;
}

/// Some gateways return SSE even for stream:false. Never accept a partial stream.
Map<String, dynamic> parseResponsesSse(String raw) {
  final chunks = <String, StringBuffer>{};
  Map<String, dynamic>? completed;
  final normalized = raw
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  for (final block in normalized.split(RegExp(r'\n\n+'))) {
    final data = <String>[];
    String? event;
    for (final line in block.split('\n')) {
      if (line.startsWith('data:')) {
        var value = line.substring(5);
        if (value.startsWith(' ')) value = value.substring(1);
        data.add(value);
      } else if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      }
    }
    if (data.isEmpty) continue;
    final text = data.join('\n');
    if (text.trim() == '[DONE]') continue;
    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw Exception('Responses 流事件格式错误：事件数据不是有效 JSON');
    }
    if (decoded is! Map) throw Exception('Responses 流事件格式错误');
    final type = decoded['type'] ?? event;
    if (type == 'error' ||
        type == 'response.failed' ||
        type == 'response.incomplete' ||
        decoded['error'] != null) {
      final response = decoded['response'];
      final detail = response is Map
          ? (response['error'] ??
                response['incomplete_details'] ??
                response['status'])
          : (decoded['error'] ?? decoded['message']);
      throw Exception('Responses 未完成：$type，${detail ?? '服务未提供详情'}');
    }
    if (type == 'response.output_text.delta' && decoded['delta'] is String) {
      final index =
          '${decoded['output_index'] ?? 0}:${decoded['content_index'] ?? 0}';
      (chunks[index] ??= StringBuffer()).write(decoded['delta']);
    }
    if (type == 'response.completed') {
      final response = decoded['response'];
      if (response is! Map) throw Exception('Responses 完成事件缺少 response 数据');
      completed = Map<String, dynamic>.from(response);
      if (completed['error'] != null ||
          completed['status'] == 'failed' ||
          completed['status'] == 'incomplete') {
        throw Exception(
          'Responses 未完成：${completed['error'] ?? completed['incomplete_details'] ?? completed['status']}',
        );
      }
    }
  }
  if (completed == null) {
    throw Exception('Responses 流中断：未收到 response.completed 完成事件，请重试');
  }
  // Use deltas only when the terminal event omits its output entirely.
  if (completed['output'] == null &&
      completed['output_text'] == null &&
      chunks.isNotEmpty) {
    completed['output_text'] = chunks.values
        .map((value) => value.toString())
        .join('\n');
  }
  return completed;
}
