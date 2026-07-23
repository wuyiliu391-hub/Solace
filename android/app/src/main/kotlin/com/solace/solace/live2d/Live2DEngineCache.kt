package com.solace.solace.live2d

import android.app.Application
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.EventChannel

/**
 * 预缓存 Live2D 悬浮窗的 FlutterEngine
 *
 * 在应用启动时就把 live2d_entry 跑起来，悬浮窗服务直接复用，避免第一次启动卡顿。
 *
 * 关键设计：EventChannel 必须注册在【独立引擎】的 BinaryMessenger 上，
 * 因为悬浮窗 Dart (live2d_entry.dart) 运行在这个独立引擎中。
 * 之前错误地注册在主引擎上，导致事件推送到主引擎，
 * 悬浮窗 Dart 永远收不到 → 换装/捏脸/化妆变更无法实时同步。
 */
object Live2DEngineCache {

    private const val TAG = "Live2DEngineCache"
    private const val ENGINE_ID = "live2d_overlay_engine"

    fun prepare(application: Application) {
        if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) return

        try {
            // 注意：FlutterLoader 的 startInitialization / ensureInitializationComplete 通常
            // 由 Flutter Application 自动完成。这里 try/catch 兜底以防 Application 没用 FlutterApplication。
            try {
                FlutterLoader().startInitialization(application)
                FlutterLoader().ensureInitializationComplete(application, null)
            } catch (e: Exception) {
                // 已初始化过会抛异常，正常情况，吞掉
                Log.d(TAG, "FlutterLoader already initialized: ${e.message}")
            }

            val engine = FlutterEngine(application)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterLoader().findAppBundlePath(),
                    "live2d_entry"
                )
            )

            // ═══ 关键修复：在独立引擎上注册 EventChannel ═══
            // 悬浮窗 Dart (live2d_entry.dart) 的 EventChannel('com.solace.solace/live2d_events')
            // .receiveBroadcastStream().listen(...) 监听的就是这个独立引擎的 BinaryMessenger。
            // 必须在这里注册，否则主 App 调用 Live2DStateManager.syncAvatarConfig() 推送的事件
            // 永远到不了悬浮窗 Dart。
            EventChannel(
                engine.dartExecutor.binaryMessenger,
                Live2DStateManager.getEventChannelName()
            ).setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "EventChannel sink attached on overlay engine")
                    Live2DStateManager.setEventSink(events)
                    // 立即推送当前配置，让悬浮窗 Dart 启动时就能收到（覆盖默认配置）
                    Live2DStateManager.pushCurrentConfig()
                }
                override fun onCancel(args: Any?) {
                    Log.i(TAG, "EventChannel sink detached from overlay engine")
                    Live2DStateManager.setEventSink(null)
                }
            })

            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            Log.i(TAG, "Live2D engine cached + EventChannel registered on overlay engine")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cache Live2D engine", e)
        }
    }

    fun getEngine(application: Application): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: run {
                prepare(application)
                FlutterEngineCache.getInstance().get(ENGINE_ID)
            }
    }
}
