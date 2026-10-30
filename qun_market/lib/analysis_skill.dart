import 'package:flutter/services.dart';

class AnalysisSkill {
  const AnalysisSkill(this.id, this.name, this.focus, this.asset);
  final String id, name, focus, asset;
  Future<String> load() => rootBundle.loadString(asset);
}

const analysisSkills = <AnalysisSkill>[
  AnalysisSkill(
    'chenxiaoqun',
    '陈小群',
    '主线题材辨识 · 龙头换手封板 · 预期差与分歧转一致 · 流动性承接',
    'assets/SKILL.md',
  ),
  AnalysisSkill(
    'chaoguyangjia',
    '炒股养家',
    '情绪周期 · 赚钱与亏钱效应 · 主流龙头 · 分歧与一致',
    'assets/skills/chaoguyangjia.md',
  ),
  AnalysisSkill(
    'niepanchongsheng',
    '涅槃重生',
    '情绪变化 · 主流轮动 · 强度确认 · 回撤控制',
    'assets/skills/niepanchongsheng_Internal.md',
  ),
  AnalysisSkill(
    '92biji',
    '92科比',
    '人气与流动性 · 情绪阶段 · 模式一致性 · 反包与二浪',
    'assets/skills/92biji.md',
  ),
  AnalysisSkill(
    'zhaolaoge',
    '赵老哥',
    '强势题材 · 龙头辨识 · 涨停强度 · 执行纪律',
    'assets/skills/zhaolaoge.md',
  ),
  AnalysisSkill(
    'zuoshouxinyi',
    '作手新一',
    '龙头地位 · 分时转折 · 趋势突破 · 纠错纪律',
    'assets/skills/zuoshouxinyi.md',
  ),
  AnalysisSkill(
    'ruihexian',
    '瑞鹤仙',
    '板块轮动 · 量价关系 · 龙头切换 · 风险控制',
    'assets/skills/ruihexian_Internal.md',
  ),
  AnalysisSkill(
    'tuixuechaogu',
    '退学炒股',
    '弱转强确认 · 情绪拐点 · 独立判断 · 交易纪律',
    'assets/skills/tuixuechaogu.md',
  ),
  AnalysisSkill(
    'bjchaojia',
    '北京炒家',
    '首板筛选 · 概率思维 · 分散观察 · 一致性与风控',
    'assets/skills/bjchaojia.md',
  ),
  AnalysisSkill(
    'zhumingcike',
    '著名刺客',
    '板块与人气 · 强弱转换 · 盘口承接 · 风险纪律',
    'assets/skills/zhumingcike.md',
  ),
];

AnalysisSkill skillById(String? id) => analysisSkills.firstWhere(
  (s) => s.id == id,
  orElse: () => analysisSkills.first,
);

String buildSkillSystem(String guard, AnalysisSkill skill, String content) =>
    '$guard\n本次唯一分析框架：${skill.name}。仅借鉴该框架的判断方法，不自称本人。'
    '保留通用证据要求与角色表，以所选框架解释事实、分歧和待验证条件。'
    '\n<selected_skill_reference>\n$content\n</selected_skill_reference>';
