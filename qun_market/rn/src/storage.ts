import FS from 'react-native-fs';
import * as Keychain from 'react-native-keychain';
import {Config, defaults} from './model';
export type Mode = 'silent' | 'sound' | 'vibrate';
export type Preferences = {mode: Mode; limitGB: number; skillId: string};
export type Report = {
  id: string;
  created: string;
  question: string;
  skill: string;
  text: string;
  status: 'success' | 'failed' | 'cancelled';
  error?: string;
};
export const initialPreferences: Preferences = {
  mode: 'silent',
  limitGB: 1,
  skillId: 'chenxiaoqun',
};
const base = FS.DocumentDirectoryPath + '/qunce-rn',
  reports = base + '/reports';
export async function initStore() {
  await FS.mkdir(reports, {NSURLIsExcludedFromBackupKey: true});
}
export async function loadConfig(): Promise<Config> {
  try {
    const s = await Keychain.getGenericPassword({service: 'qunce.rn.model'});
    return s ? {...defaults, ...JSON.parse(s.password)} : {...defaults};
  } catch {
    throw new Error('无法读取安全存储中的模型配置，请解锁设备后重试；若仍失败，请检查应用签名和钥匙串授权。原配置未删除。');
  }
}
export async function saveConfig(c: Config) {
  try {
    const saved = await Keychain.setGenericPassword('model', JSON.stringify(c), {
      service: 'qunce.rn.model',
      accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
    });
    if (!saved) throw new Error('保存未完成');
  } catch {
    throw new Error('模型配置未保存：安全存储不可用，请解锁设备或检查应用签名和钥匙串授权。密钥不会写入普通文件。');
  }
}
export async function loadPreferences(): Promise<Preferences> {
  const p = base + '/preferences.json';
  if (!(await FS.exists(p))) return initialPreferences;
  const v = JSON.parse(await FS.readFile(p, 'utf8'));
  return {
    ...initialPreferences,
    ...v,
    limitGB: Number(v.limitGB) > 0 ? Number(v.limitGB) : 1,
  };
}
export async function savePreferences(p: Preferences) {
  await FS.writeFile(base + '/preferences.json', JSON.stringify(p), 'utf8');
}
export async function saveReport(r: Report) {
  await FS.writeFile(reports + '/' + r.id + '.json', JSON.stringify(r), 'utf8');
}
export async function listReports() {
  const entries = (await FS.readDir(reports)).filter(
    f => f.isFile() && f.name.endsWith('.json'),
  );
  return entries.sort((a, b) => b.name.localeCompare(a.name));
}
export async function readReport(path: string): Promise<Report> {
  if (!path.startsWith(reports + '/')) throw Error('无效报告路径');
  return JSON.parse(await FS.readFile(path, 'utf8'));
}
export async function removeReport(path: string) {
  if (!path.startsWith(reports + '/') || !path.endsWith('.json'))
    throw Error('无效报告路径');
  await FS.unlink(path);
}
export async function clearReports() {
  for (const f of await listReports()) await removeReport(f.path);
}
export async function cacheSize() {
  return (await listReports()).reduce((s, f) => s + Number(f.size || 0), 0);
}
export const exceedsLimit = (bytes: number, gb: number) =>
  bytes > gb * 1024 ** 3;
