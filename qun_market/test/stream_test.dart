import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:qun_market/model_api.dart';

class StreamingClient extends http.BaseClient {
  final Stream<List<int>> bytes;
  StreamingClient(this.bytes);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        bytes,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
}

void main() {
  test('上游失败记录响应ID与错误码，不泄露密钥', () async {
    final records = <String, dynamic>{};
    final client = StreamingClient(
      Stream.value(
        utf8.encode(
          'data: {"type":"response.created","response":{"id":"resp_test"}}\n\n'
          'data: {"type":"response.failed","response":{"id":"resp_test","error":{"code":"upstream_error","message":"sk-private"}}}\n\n',
        ),
      ),
    );
    await expectLater(
      requestModel(
        client: client,
        endpoint: 'http://test',
        protocol: 'responses',
        model: 'm',
        key: 'sk-private',
        system: '',
        prompt: '',
        onDiagnostic: records.addAll,
      ),
      throwsA(predicate((e) => !e.toString().contains('sk-private'))),
    );
    expect(records['httpStatus'], 200);
    expect(records['responseId'], 'resp_test');
    expect(records['errorCode'], 'upstream_error');
    expect(records['lastEvent'], 'response.failed');
    expect(jsonEncode(records), isNot(contains('sk-private')));
  });
  test('增量先显示，完成后不等待连接关闭', () async {
    final controller = StreamController<List<int>>();
    final seen = <String>[];
    final result = requestModel(
      client: StreamingClient(controller.stream),
      endpoint: 'http://test',
      protocol: 'responses',
      model: 'm',
      key: '',
      system: '',
      prompt: '',
      onText: seen.add,
    );
    final bytes = utf8.encode(
      'data: {"type":"response.output_text.delta","delta":"中文"}\n\ndata: {"type":"response.completed","response":{"status":"completed","output_text":"中文全文"}}\n\n',
    );
    for (final byte in bytes) {
      controller.add([byte]);
    }
    expect(await result.timeout(const Duration(seconds: 2)), '中文全文');
    expect(seen, ['中文']);
    await controller.close();
  });
  test('无数据流触发空闲超时', () async {
    final controller = StreamController<List<int>>();
    await expectLater(
      requestModel(
        client: StreamingClient(controller.stream),
        endpoint: 'http://test',
        protocol: 'responses',
        model: 'm',
        key: '',
        system: '',
        prompt: '',
        idleTimeout: const Duration(milliseconds: 30),
      ),
      throwsA(predicate((e) => e.toString().contains('未收到数据'))),
    );
    await controller.close();
  });
  test('持续输出超过总时限时保留片段并提示未完成', () async {
    final controller = StreamController<List<int>>();
    final seen = <String>[];
    final result = requestModel(
      client: StreamingClient(controller.stream),
      endpoint: 'http://test',
      protocol: 'responses',
      model: 'm',
      key: '',
      system: '',
      prompt: '',
      onText: seen.add,
      idleTimeout: const Duration(seconds: 1),
      totalTimeout: const Duration(milliseconds: 80),
    );
    controller.add(
      utf8.encode(
        'data: {"type":"response.output_text.delta","delta":"半份"}\n\n',
      ),
    );
    await expectLater(
      result,
      throwsA(predicate((e) => e.toString().contains('已收到正文 2 字'))),
    );
    expect(seen, ['半份']);
    await controller.close();
  });
}
