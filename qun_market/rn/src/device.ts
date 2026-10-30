import {
  AppState,
  Linking,
  NativeModules,
  Platform,
  Vibration,
} from 'react-native';
import notifee, {
  AndroidImportance,
  AuthorizationStatus,
} from '@notifee/react-native';
import {Mode} from './storage';
export async function notificationPermission(request = false) {
  const s = request
    ? await notifee.requestPermission({sound: true, alert: true, badge: false})
    : await notifee.getNotificationSettings();
  return s.authorizationStatus >= AuthorizationStatus.AUTHORIZED
    ? '已允许'
    : s.authorizationStatus === AuthorizationStatus.NOT_DETERMINED
    ? '尚未申请'
    : '未允许（可打开系统设置）';
}
export async function openSettings() {
  await Linking.openSettings();
}
export async function probe() {
  if (!NativeModules.QunNetwork)
    throw Error('原生探活模块尚未加载，请使用完整原生构建');
  return await NativeModules.QunNetwork.probe();
}
export async function alertResult(mode: Mode, ok: boolean) {
  if (mode === 'silent') return;
  const foreground = AppState.currentState === 'active';
  if (mode === 'vibrate' && foreground) {
    Vibration.vibrate(Platform.OS === 'android' ? [0, 250, 120, 250] : 400);
    return;
  }
  if (mode === 'vibrate' && Platform.OS === 'ios') return;
  const s = await notifee.getNotificationSettings();
  if (s.authorizationStatus < AuthorizationStatus.AUTHORIZED)
    throw Error('结果已保存，但通知权限未允许，无法播放提示声/后台提醒');
  const channelId = await notifee.createChannel({
    id: 'result-' + mode,
    name: mode === 'sound' ? '复盘提示声' : '复盘震动',
    importance: AndroidImportance.HIGH,
    sound: mode === 'sound' ? 'default' : undefined,
    vibration: mode === 'vibrate',
    ...(mode === 'vibrate' ? {vibrationPattern: [250, 120, 250, 120]} : {}),
  });
  await notifee.displayNotification({
    title: '群策复盘' + (ok ? '完成' : '失败'),
    body: ok
      ? '报告已保存，请打开应用查看。'
      : '已保存诊断与草稿，请打开应用查看。',
    android: {
      channelId,
      smallIcon: 'ic_launcher',
      pressAction: {id: 'default'},
    },
    ios: {
      sound: mode === 'sound' ? 'default' : undefined,
      foregroundPresentationOptions: {
        alert: true,
        banner: true,
        list: true,
        sound: mode === 'sound',
        badge: false,
      },
    },
  });
}
