import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qun_market/model_api.dart';

void main() {
  test('推理强度按协议映射，默认省略参数', () async {
    for (final protocol in ['responses', 'openai']) {
      for (final effort in reasoningEfforts.keys) {
        late Map<String, dynamic> sent;
        await requestModel(
          client: MockClient((r) async {
            sent = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(
                protocol == 'responses'
                    ? {'output_text': 'OK'}
                    : {
                        'choices': [
                          {
                            'message': {'content': 'OK'},
                          },
                        ],
                      },
              ),
              200,
            );
          }),
          endpoint: 'https://x.test',
          protocol: protocol,
          model: 'm',
          key: '',
          system: 's',
          prompt: 'p',
          reasoningEffort: effort,
        );
        if (effort == 'default') {
          expect(sent.containsKey('reasoning'), isFalse);
          expect(sent.containsKey('reasoning_effort'), isFalse);
        } else if (protocol == 'responses') {
          expect(sent['reasoning'], {'effort': effort});
          expect(sent.containsKey('reasoning_effort'), isFalse);
        } else {
          expect(sent['reasoning_effort'], effort);
          expect(sent.containsKey('reasoning'), isFalse);
        }
      }
    }
  });
  test('Claude 不发送不兼容的推理参数', () async {
    var called = false;
    await expectLater(
      requestModel(
        client: MockClient((r) async {
          called = true;
          return http.Response('{}', 200);
        }),
        endpoint: 'https://x.test',
        protocol: 'anthropic',
        model: 'm',
        key: '',
        system: 's',
        prompt: 'p',
        reasoningEffort: 'high',
      ),
      throwsFormatException,
    );
    expect(called, isFalse);
  });
  test('不支持推理档位时明确提示且不自动降级', () async {
    var calls = 0;
    await expectLater(
      requestModel(
        client: MockClient((r) async {
          calls++;
          return http.Response('{"error":"unsupported effort"}', 400);
        }),
        endpoint: 'https://x.test',
        protocol: 'responses',
        model: 'm',
        key: '',
        system: 's',
        prompt: 'p',
        reasoningEffort: 'xhigh',
      ),
      throwsA(predicate((e) => e.toString().contains('未自动降级'))),
    );
    expect(calls, 1);
  });
  String event(String type, Map<String, dynamic> data) =>
      'event: $type\r\ndata: ${jsonEncode({'type': type, ...data})}\r\n\r\n';
  Future<String> sse(String raw, {String contentType = 'text/event-stream'}) =>
      requestModel(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(raw),
            200,
            headers: {'content-type': contentType},
          ),
        ),
        endpoint: 'http://x.test',
        protocol: 'responses',
        model: 'm',
        key: 'sk-secret123',
        system: 's',
        prompt: 'p',
      );

  test('SSE 中文完成全文优先，不重复增量', () async {
    final raw =
        ': heartbeat\r\n\r\n${event('response.output_text.delta', {'delta': '中文'})}'
        '${event('response.completed', {
          'response': {
            'status': 'completed',
            'output': [
              {
                'content': [
                  {'type': 'output_text', 'text': '中文回答'},
                ],
              },
            ],
          },
        })}data: [DONE]\r\n\r\n';
    expect(await sse(raw), '中文回答');
    expect(await sse(raw, contentType: 'text/plain'), '中文回答');
  });
  test('完成事件省略全文时拼接增量', () async {
    expect(
      await sse(
        event('response.output_text.delta', {'delta': '你'}) +
            event('response.output_text.delta', {'delta': '好'}) +
            event('response.completed', {
              'response': {'status': 'completed'},
            }),
      ),
      '你好',
    );
  });
  test('截断及只有 DONE 不能视为成功', () async {
    for (final raw in [
      event('response.output_text.delta', {'delta': '半份'}),
      'data: [DONE]\n\n',
    ]) {
      await expectLater(
        sse(raw),
        throwsA(predicate((e) => e.toString().contains('流中断'))),
      );
    }
  });
  test('失败和不完整事件隐藏密钥', () async {
    for (final type in ['error', 'response.failed', 'response.incomplete']) {
      await expectLater(
        sse(
          event(type, {
            'message': 'sk-secret123',
            'response': {'error': 'sk-secret123'},
          }),
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('未完成') &&
                !e.toString().contains('secret123'),
          ),
        ),
      );
    }
  });
  test('多行 data 和 event 类型回退', () {
    expect(
      parseResponsesSse(
        'event: response.completed\ndata: {"response":\ndata: {"status":"completed","output_text":"OK"}}\n\n',
      )['output_text'],
      'OK',
    );
  });
  test('损坏事件不能忽略', () async {
    await expectLater(
      sse('data: {broken}\n\n'),
      throwsA(predicate((e) => e.toString().contains('格式错误'))),
    );
  });
  test('Responses 地址与解析正确', () async {
    late Uri seen;
    late Map body;
    final client = MockClient((r) async {
      seen = r.url;
      body = jsonDecode(r.body) as Map;
      return http.Response(
        jsonEncode({
          'output': [
            {
              'content': [
                {'type': 'output_text', 'text': 'OK'},
              ],
            },
          ],
        }),
        200,
      );
    });
    final out = await requestModel(
      client: client,
      endpoint: 'http://x.test/v1/',
      protocol: 'responses',
      model: 'm',
      key: 'k',
      system: 's',
      prompt: 'p',
    );
    expect(out, 'OK');
    expect(seen.path, '/v1/responses');
    expect(body['instructions'], 's');
  });

  test('Chat 与 Claude 协议可解析', () async {
    final chat = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'A'},
            },
          ],
        }),
        200,
      ),
    );
    final claude = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'B'},
          ],
        }),
        200,
      ),
    );
    expect(
      await requestModel(
        client: chat,
        endpoint: 'https://x.test/v1',
        protocol: 'openai',
        model: 'm',
        key: '',
        system: 's',
        prompt: 'p',
      ),
      'A',
    );
    expect(
      await requestModel(
        client: claude,
        endpoint: 'https://x.test/v1',
        protocol: 'anthropic',
        model: 'm',
        key: 'k',
        system: 's',
        prompt: 'p',
      ),
      'B',
    );
  });

  test('401 给出原因且隐藏密钥', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'bad sk-secret123'},
        }),
        401,
      ),
    );
    expect(
      () => requestModel(
        client: client,
        endpoint: 'https://x.test/v1',
        protocol: 'openai',
        model: 'm',
        key: 'sk-secret123',
        system: 's',
        prompt: 'p',
      ),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('密钥无效') &&
              !e.toString().contains('secret123'),
        ),
      ),
    );
  });
}
