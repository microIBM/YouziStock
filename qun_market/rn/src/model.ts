export type Config = {
  endpoint: string;
  model: string;
  key: string;
  protocol: 'responses' | 'openai' | 'anthropic';
  effort: string;
  minutes: number;
};
export const defaults: Config = {
  endpoint: '',
  model: '',
  key: '',
  protocol: 'responses',
  effort: 'default',
  minutes: 30,
};
export function safeError(error: unknown, key = ''): string {
  let s = String(error);
  if (key) s = s.split(key).join('[密钥已隐藏]');
  return s
    .replace(/Bearer\s+[^\s"<>]+/gi, 'Bearer [隐藏]')
    .replace(/sk-[\w-]+/g, '[密钥已隐藏]')
    .replace(/https?:\/\/[^\s<>]+/g, u => {
      try {
        return new URL(u).origin + '/[路径已隐藏]';
      } catch {
        return '[地址隐藏]';
      }
    })
    .slice(0, 1200);
}
export function modelUrl(c: Config) {
  const u = new URL(c.endpoint.trim());
  if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password)
    throw Error('请输入有效的 HTTP/HTTPS 接口地址，不要在地址中放账号密码');
  u.pathname =
    (u.pathname
      .replace(/\/+$/, '')
      .replace(/\/(chat\/completions|responses|messages)$/, '') || '/v1') +
    {
      responses: '/responses',
      anthropic: '/messages',
      openai: '/chat/completions',
    }[c.protocol];
  u.hash = '';
  return u.toString();
}
export function payload(c: Config, system: string, prompt: string) {
  if (!c.model.trim()) throw Error('请填写模型名称');
  if (c.protocol === 'anthropic' && c.effort !== 'default')
    throw Error('Claude 原生协议请使用默认推理强度');
  const p: any = {model: c.model.trim(), stream: true};
  if (c.protocol === 'responses')
    Object.assign(p, {instructions: system, input: prompt, store: false});
  else
    Object.assign(p, {
      messages: [
        ...(c.protocol === 'anthropic'
          ? []
          : [{role: 'system', content: system}]),
        {role: 'user', content: prompt},
      ],
      ...(c.protocol === 'anthropic' ? {system, max_tokens: 16000} : {}),
    });
  if (c.effort !== 'default') {
    if (c.protocol === 'responses') p.reasoning = {effort: c.effort};
    else p.reasoning_effort = c.effort;
  }
  return p;
}
export class StreamDecoder {
  pending = '';
  text = '';
  done = false;
  push(s: string) {
    this.pending += s;
    let m: RegExpExecArray | null;
    while ((m = /\r?\n\r?\n/.exec(this.pending))) {
      const block = this.pending.slice(0, m.index);
      this.pending = this.pending.slice(m.index + m[0].length);
      this.event(block);
    }
  }
  finish() {
    if (this.pending.trim()) this.event(this.pending);
    this.pending = '';
    if (!this.done) throw Error('流中断：未收到完成事件，已保留草稿');
    if (!this.text.trim()) throw Error('模型未返回报告正文');
    return this.text;
  }
  event(block: string) {
    const data = block
      .split(/\r?\n/)
      .filter(l => l.startsWith('data:'))
      .map(l => l.slice(5).trimStart())
      .join('\n');
    if (!data) return;
    if (data === '[DONE]') {
      this.done = true;
      return;
    }
    const e = JSON.parse(data);
    const type = e.type || '';
    if (
      e.error ||
      ['error', 'response.failed', 'response.incomplete'].includes(type)
    )
      throw Error(
        '服务错误：' +
          JSON.stringify(
            e.error || e.response?.error || e.response?.incomplete_details || e,
          ),
      );
    if (type === 'response.output_text.delta') this.text += e.delta || '';
    if (type === 'content_block_delta') this.text += e.delta?.text || '';
    if (e.choices?.[0]?.delta?.content) this.text += e.choices[0].delta.content;
    if (type === 'response.completed') {
      if (['failed', 'incomplete'].includes(e.response?.status))
        throw Error('模型响应未完成');
      this.done = true;
      if (!this.text) this.text = extract(e.response);
    }
    if (type === 'message_stop') this.done = true;
  }
}
export function extract(j: any): string {
  if (j?.error) throw Error(JSON.stringify(j.error));
  if (['failed', 'incomplete'].includes(j?.status))
    throw Error('模型响应未完成');
  return (
    j?.output_text ||
    j?.choices?.[0]?.message?.content ||
    j?.content?.map((x: any) => x.text || '').join('') ||
    j?.output
      ?.flatMap((x: any) => x.content || [])
      .map((x: any) => x.text || '')
      .join('') ||
    ''
  );
}
export function requestModel(
  c: Config,
  system: string,
  prompt: string,
  signal: AbortSignal,
  onText: (text: string) => void,
  test = false,
): Promise<string> {
  return new Promise((resolve, reject) => {
    let url: string;
    let body: any;
    try {
      url = modelUrl(c);
      body = payload(c, system, prompt);
    } catch (e) {
      reject(e);
      return;
    }
    const xhr = new XMLHttpRequest();
    const decoder = new StreamDecoder();
    let offset = 0,
      finished = false,
      stream = false;
    let idle: ReturnType<typeof setTimeout>;
    const total = setTimeout(
      () => fail(Error('分析达到总时限，已保留草稿')),
      test ? 90000 : c.minutes * 60000,
    );
    const reset = (ms: number) => {
      clearTimeout(idle);
      idle = setTimeout(() => fail(Error('等待模型响应超时，已保留草稿')), ms);
    };
    const clean = () => {
      clearTimeout(total);
      clearTimeout(idle);
      signal.removeEventListener('abort', cancel);
    };
    const fail = (e: unknown) => {
      if (finished) return;
      finished = true;
      clean();
      xhr.abort();
      reject(e);
    };
    const cancel = () => fail(Error('已中止'));
    signal.addEventListener('abort', cancel);
    if (signal.aborted) {
      cancel();
      return;
    }
    xhr.open('POST', url);
    xhr.setRequestHeader('Content-Type', 'application/json');
    if (c.protocol === 'anthropic') {
      xhr.setRequestHeader('x-api-key', c.key);
      xhr.setRequestHeader('anthropic-version', '2023-06-01');
    } else if (c.key) xhr.setRequestHeader('Authorization', 'Bearer ' + c.key);
    xhr.onprogress = () => {
      if (finished) return;
      reset(120000);
      if (xhr.status < 200 || xhr.status >= 300) return;
      stream =
        stream ||
        /event-stream/i.test(xhr.getResponseHeader('content-type') || '') ||
        /^\s*(event:|data:)/.test(xhr.responseText);
      if (stream) {
        try {
          decoder.push(xhr.responseText.slice(offset));
          offset = xhr.responseText.length;
          onText(decoder.text);
        } catch (e) {
          fail(e);
        }
      }
    };
    xhr.onload = () => {
      if (finished) return;
      try {
        if (xhr.status < 200 || xhr.status >= 300)
          throw Error(
            'HTTP ' +
              xhr.status +
              '：' +
              safeError(xhr.responseText.slice(0, 1000), c.key),
          );
        stream =
          stream ||
          /event-stream/i.test(xhr.getResponseHeader('content-type') || '') ||
          /^\s*(event:|data:)/.test(xhr.responseText);
        let text;
        if (stream) {
          decoder.push(xhr.responseText.slice(offset));
          text = decoder.finish();
        } else {
          text = extract(JSON.parse(xhr.responseText));
          if (!text.trim()) throw Error('模型返回空正文');
        }
        finished = true;
        clean();
        onText(text);
        resolve(text);
      } catch (e) {
        fail(e);
      }
    };
    xhr.onerror = () =>
      fail(
        Error(
          '模型网络请求失败（目标 ' +
            new URL(url).host +
            '）。请在权限与网络页面运行原生探活，检查系统对本 App 的无线数据限制。',
        ),
      );
    reset(test ? 30000 : 60000);
    xhr.send(JSON.stringify(body));
  });
}
