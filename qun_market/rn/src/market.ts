const query = (base: string, p: Record<string, string | number>) =>
  base +
  '?' +
  Object.entries(p)
    .map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v))
    .join('&');
async function get(url: string, signal: AbortSignal, json = true) {
  const c = new AbortController();
  const cancel = () => c.abort();
  signal.addEventListener('abort', cancel);
  if (signal.aborted) c.abort();
  const timer = setTimeout(cancel, 12000);
  try {
    const r = await fetch(url, {signal: c.signal});
    if (!r.ok) throw Error('HTTP ' + r.status);
    return json ? await r.json() : await r.text();
  } finally {
    clearTimeout(timer);
    signal.removeEventListener('abort', cancel);
  }
}
export function dayKey(d: Date) {
  return d.toISOString().slice(0, 10).replace(/-/g, '');
}
const epochDay = (v: any) =>
  Number(v) > 0 ? dayKey(new Date(Number(v) * 1000 + 28800000)) : '';
export function parsePool(d: any, date: string) {
  if (
    String(d?.qdate) !== date ||
    !Array.isArray(d?.pool) ||
    Number(d.tc) !== d.pool.length ||
    new Set(d.pool.map((r: any) => r.c)).size !== d.pool.length
  )
    throw Error('股票池日期或完整性校验失败');
  return d.pool as any[];
}
export async function gather(question: string, signal: AbortSignal) {
  const out: string[] = [],
    gaps: string[] = [];
  const now = new Date(Date.now() + 28800000);
  const raw = await get(
    'https://qt.gtimg.cn/q=sh000001,sz399001,sz399006',
    signal,
    false,
  );
  const indices = String(raw)
    .split(';')
    .map(l => l.split('~'))
    .filter(
      f => f.length > 37 && ['000001', '399001', '399006'].includes(f[2]),
    );
  const dates = new Set(
    indices.map(f => (/^\d{14}$/.test(f[30]) ? f[30].slice(0, 8) : '')),
  );
  if (indices.length !== 3 || dates.size !== 1 || dates.has(''))
    throw Error('指数日期不完整，停止生成无依据复盘');
  const date = Array.from(dates)[0];
  if (date > dayKey(now)) throw Error('行情日期晚于设备日期');
  out.push(
    `行情日期：${date}，北京时间。${
      date === dayKey(now)
        ? now.getUTCHours() < 15
          ? '当日盘中快照，不是收盘复盘'
          : '当日快照，各源可能修订'
        : '历史快照，未接入节假日日历，不得称为今日实时行情'
    }。检索时间：${new Date().toISOString()}。`,
  );
  indices.forEach(f =>
    out.push(
      `${
        (
          {
            '000001': '上证指数',
            '399001': '深证成指',
            '399006': '创业板指',
          } as any
        )[f[2]]
      } 点位${f[3]} 涨幅${f[32]}% 成交额${f[37]}万元 时间${f[30]}（腾讯财经）`,
    ),
  );
  out.push(
    '沪深成交额合计' +
      (
        (Number(indices.find(f => f[2] === '000001')![37]) +
          Number(indices.find(f => f[2] === '399001')![37])) /
        10000
      ).toFixed(2) +
      '亿元；创业板不得重复加总。',
  );
  const data = async (url: string) => {
    const j = await get(url, signal);
    if (!j.data) throw Error('数据缺失');
    return j.data;
  };
  const list = (fs: string, size: number, fid = 'f3') =>
    data(
      query('https://push2.eastmoney.com/api/qt/clist/get', {
        pn: 1,
        pz: size,
        po: 1,
        np: 1,
        fltt: 2,
        fid,
        fs,
        fields: 'f12,f14,f2,f3,f6,f8,f104,f105,f124',
      }),
    );
  const section = async (name: string, fn: () => Promise<void>) => {
    try {
      await fn();
    } catch (e) {
      if (signal.aborted) throw Error('已中止');
      gaps.push(name + '：' + String(e));
    }
  };
  await Promise.all([
    section('涨停与炸板池', async () => {
      const poolResults = await Promise.all(
        ['getTopicZTPool', 'getTopicZBPool', 'getYesterdayZTPool'].map(
          async (name, i) => {
            try {
              const rows = parsePool(
                await data(
                  query('https://push2ex.eastmoney.com/' + name, {
                    ut: '7eea3edcaed734bea9cbfc24409ed989',
                    dpt: 'wz.ztzt',
                    Pageindex: 0,
                    pagesize: 1000,
                    sort: i === 2 ? 'zs:desc' : 'fbt:asc',
                    date,
                  }),
                ),
                date,
              );
              out.push(
                `【${
                  ['涨停池', '炸板池', '昨日涨停表现'][i]
                }】东方财富 日期${date} 完整池${
                  rows.length
                }家，不保证覆盖全部市场；明细最多120家。`,
              );
              rows.sort((a, b) => Number(b.lbc || 0) - Number(a.lbc || 0));
              out.push(
                ...rows
                  .slice(0, 120)
                  .map(
                    r =>
                      `${r.n}(${r.c}) 涨幅${r.zdp}% 连板${
                        r.lbc ?? r.ylbc ?? '缺失'
                      } 行业${r.hybk} 换手${r.hs}% 成交额${r.amount}元 首封${
                        r.fbt
                      } 最后封板${r.lbt} 开板${r.zbc}`,
                  ),
              );
              if (
                i === 2 &&
                rows.length &&
                rows.every(r => Number.isFinite(Number(r.zdp)))
              )
                out.push(
                  '昨日涨停样本今日等权平均涨幅' +
                    (
                      rows.reduce((a, r) => a + Number(r.zdp), 0) / rows.length
                    ).toFixed(2) +
                    '%',
                );
              return rows;
            } catch (e) {
              gaps.push(name + '：' + String(e));
              return null;
            }
          },
        ),
      );
      const [a, b] = poolResults;
      if (a && b && a.length + b.length)
        out.push(
          `两池封板比例${((100 * a.length) / (a.length + b.length)).toFixed(
            2,
          )}%，非官方全市场封板率`,
        );
    }),
    section('板块榜单', async () => {
      const results = await Promise.all([
        list('m:90+t:3', 30),
        list('m:90+t:2', 15),
      ]);
      const rows = results.flatMap((d, i) =>
        (d.diff || []).map((r: any) => ({
          ...r,
          category: i === 0 ? '概念' : '行业',
        })),
      );
      const valid = rows.filter(r => epochDay(r.f124) === date);
      if (rows.length !== valid.length) gaps.push('部分板块日期不一致，已排除');
      out.push('【板块涨幅样本】东方财富 概念前30+行业前15，不代表全市场主线');
      out.push(
        ...valid.map(
          r =>
            `${r.category} ${r.f14}(${r.f12}) 涨幅${r.f3}% 成交额${r.f6}元 上涨${r.f104}/下跌${r.f105} 时间${r.f124}`,
        ),
      );
      await Promise.all(
        valid
          .filter(
            r =>
              !/昨日|连板|百元|高价|低价|历史新高|融资|证金|沪股通|深股通|MSCI|富时|上证|深证|标普|央视|大盘|价值|题材股|破净|红利/.test(
                r.f14,
              ),
          )
          .slice(0, 6)
          .map(b =>
            section(b.f14 + '成分', async () => {
              const ds = await Promise.all([
                list('b:' + b.f12, 5, 'f6'),
                list('b:' + b.f12, 5, 'f3'),
              ]);
              const map = new Map<string, any>();
              ds.forEach(d =>
                (d.diff || []).forEach((s: any) => {
                  if (epochDay(s.f124) === date) map.set(s.f12, s);
                }),
              );
              out.push(
                `【${b.f14}成分样本】成交额前5与涨幅前5去重；不能仅凭成交额认定中军、单日涨幅认定总龙。`,
              );
              out.push(
                ...Array.from(map.values()).map(
                  s =>
                    `${s.f14}(${s.f12}) 价格${s.f2} 涨幅${s.f3}% 成交额${s.f6}元 换手${s.f8}% 时间${s.f124}`,
                ),
              );
            }),
          ),
      );
    }),
    section('同源量能对比', async () => {
      if (date === dayKey(now) && now.getUTCHours() < 16)
        throw Error('盘中与收盘修订期，不与前日全天直接比较');
      const bars = await Promise.all(
        ['1.000001', '0.399001'].map(secid =>
          data(
            query('https://push2his.eastmoney.com/api/qt/stock/kline/get', {
              secid,
              klt: 101,
              fqt: 0,
              lmt: 5,
              end: date,
              fields1: 'f1,f2,f3,f4,f5,f6',
              fields2: 'f51,f52,f53,f54,f55,f56,f57',
            }),
          ),
        ),
      );
      const maps = bars.map(
        d =>
          new Map<string, number>(
            (d.klines || []).map((s: string) => {
              const f = s.split(',');
              return [f[0].replace(/-/g, ''), Number(f[6])];
            }),
          ),
      );
      const days = maps.map(m =>
        Array.from(m.keys())
          .filter(d => d <= date)
          .sort(),
      );
      if (
        days.some(d => d.length < 2 || d[d.length - 1] !== date) ||
        days[0][days[0].length - 2] !== days[1][days[1].length - 2]
      )
        throw Error('两市日线日期不一致');
      const prev = days[0][days[0].length - 2],
        cur = maps.reduce((s, m) => s + m.get(date)!, 0),
        old = maps.reduce((s, m) => s + m.get(prev)!, 0);
      if (!(cur > 0 && old > 0)) throw Error('成交额无效');
      out.push(
        `东方财富同源日线 ${date} ${(cur / 1e8).toFixed(2)}亿元 前日${prev} ${(
          old / 1e8
        ).toFixed(2)}亿元 变化${((cur / old - 1) * 100).toFixed(2)}%`,
      );
    }),
    ...Array.from(new Set(question.match(/\b\d{6}\b/g) || []))
      .slice(0, 5)
      .map(code =>
        section(code + '个股行情', async () => {
          try {
            const d = await data(
              query('https://push2.eastmoney.com/api/qt/stock/get', {
                secid: (code.startsWith('6') ? '1.' : '0.') + code,
                fields: 'f57,f58,f43,f44,f45,f46,f47,f48,f60,f86,f170',
                fltt: 2,
              }),
            );
            if (d.f57 !== code || !(Number(d.f43) > 0) || !Number(d.f86))
              throw Error('个股数据缺失');
            out.push(
              `【个股】东方财富 ${JSON.stringify(
                d,
              )}；f57代码 f58名称 f43价格 f170涨幅 f86时间戳，行情日期${epochDay(
                d.f86,
              )}，与复盘日期不同必须分开陈述。`,
            );
          } catch {
            const s = String(
              await get(
                'https://qt.gtimg.cn/q=' +
                  (code.startsWith('6') ? 'sh' : 'sz') +
                  code,
                signal,
                false,
              ),
            ).split('~');
            if (s[2] !== code || !(Number(s[3]) > 0) || !/^\d{14}$/.test(s[30]))
              throw Error('个股备用行情也无效');
            out.push(
              `腾讯个股 ${code} 价格${s[3]} 涨幅${s[32]}% 时间${s[30]}，日期不一致需分开陈述`,
            );
          }
        }),
      ),
  ]);
  if (signal.aborted) throw Error('已中止');
  gaps.push(
    '未提供可靠全市场上涨下跌家数，不能从榜单样本推算；未提供新闻、公告和龙虎榜',
  );
  return (
    out.join('\n') +
    '\n【证据缺口】\n' +
    gaps.join('\n') +
    '\n来源：腾讯财经 qt.gtimg.cn；东方财富 push2.eastmoney.com、push2ex.eastmoney.com、push2his.eastmoney.com'
  );
}
