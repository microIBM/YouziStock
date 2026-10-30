package com.quncern

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.*
import com.facebook.react.uimanager.ViewManager
import java.net.HttpURLConnection
import java.net.URL

class QunNetworkModule(context: ReactApplicationContext): ReactContextBaseJavaModule(context) {
  override fun getName() = "QunNetwork"
  @ReactMethod fun probe(promise: Promise) {
    Thread {
      var connection: HttpURLConnection? = null
      try {
        connection = URL("https://captive.apple.com/hotspot-detect.html").openConnection() as HttpURLConnection
        connection.connectTimeout = 10000
        connection.readTimeout = 10000
        connection.useCaches = false
        promise.resolve("原生 HTTPS 探活 HTTP ${connection.responseCode}；仅验证该探活地址，不等同于模型接口已连通。")
      } catch (e: Exception) {
        promise.reject("NETWORK_PROBE", "原生联网失败：${e.javaClass.simpleName} ${e.message}")
      } finally { connection?.disconnect() }
    }.start()
  }
}
class QunNetworkPackage: ReactPackage {
  override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> = listOf(QunNetworkModule(context))
  override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}
