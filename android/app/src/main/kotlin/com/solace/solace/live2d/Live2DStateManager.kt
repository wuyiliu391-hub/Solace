package com.solace.solace.live2d

import org.json.JSONObject

/**
 * Live2D 桌宠状态管理器
 *
 * 维护当前 Avatar 配置，通过 EventChannel 同步到悬浮窗中的 Flutter 渲染层。
 * 主 App 里换装/捏脸/化妆，悬浮窗桌宠实时同步变化。
 *
 * 关键架构：
 * - eventSink 由 Live2DEngineCache.kt 在独立引擎注册 EventChannel 时设置
 * - 主 App 通过 MethodChannel 调用 syncAvatarConfig → 触发 notifyConfigChanged → 推送到悬浮窗
 */
object Live2DStateManager {

    private var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null

    // 当前 Avatar 配置 JSON，与 AvatarConfig.toJson() 对应
    private var currentConfigJson: JSONObject = JSONObject()

    private const val EVENT_CHANNEL = "com.solace.solace/live2d_events"

    fun setEventSink(sink: io.flutter.plugin.common.EventChannel.EventSink?) {
        eventSink = sink
    }

    fun getEventChannelName(): String = EVENT_CHANNEL

    /**
     * 同步崽崽角色配置（头像即崽崽新架构）
     *
     * 主 App 选择某个 AI 角色作为悬浮窗崽崽后，把配置 JSON 推送到悬浮窗 Dart。
     * Dart 端 [live2d_entry.dart] 监听 type=="pet_character_changed" 事件。
     */
    fun syncPetCharacter(configJson: String) {
        try {
            val config = JSONObject(configJson)
            // 保存为当前配置，方便 EventChannel 重建时重新推送
            currentConfigJson = config
            notifyPetCharacterChanged(config)
        } catch (e: Exception) {
            android.util.Log.w("Live2DStateManager", "Invalid pet config JSON", e)
        }
    }

    /**
     * 同步整套 Avatar 配置
     */
    fun syncAvatarConfig(configJson: String) {
        try {
            currentConfigJson = JSONObject(configJson)
            notifyConfigChanged()
        } catch (e: Exception) {
            android.util.Log.w("Live2DStateManager", "Invalid config JSON", e)
        }
    }

    fun getCurrentConfigJson(): String = currentConfigJson.toString()

    /**
     * 主动推送当前配置到悬浮窗（用于悬浮窗启动时立即同步状态）
     *
     * 头像崽崽架构下，currentConfigJson 存储的是 PetCharacterConfig JSON，
     * 因此发送 pet_character_changed 事件让 live2d_entry 能正确加载头像。
     */
    fun pushCurrentConfig() {
        if (currentConfigJson.length() == 0) {
            // 还没有配置，跳过
            return
        }
        notifyPetCharacterChanged(currentConfigJson)
    }

    /**
     * 设置部位显隐（兼容旧接口）
     */
    fun setPartVisible(part: String, visible: Boolean) {
        val visibleParts = currentConfigJson.optJSONArray("visibleParts") ?: run {
            val arr = org.json.JSONArray()
            arr.put("body")
            arr.put("head")
            arr.put("face")
            arr.put("hair_back")
            arr.put("hair_front")
            arr.put("eyebrows")
            arr.put("eyes")
            arr.put("mouth")
            arr.put("shirt")
            arr.put("pants")
            arr.put("accessory")
            arr
        }
        val set = mutableSetOf<String>()
        for (i in 0 until visibleParts.length()) {
            set.add(visibleParts.optString(i))
        }
        if (visible) set.add(part) else set.remove(part)
        val newArr = org.json.JSONArray()
        set.forEach { newArr.put(it) }
        currentConfigJson.put("visibleParts", newArr)
        notifyConfigChanged()
    }

    /**
     * 推送点击事件到悬浮窗 Dart
     *
     * 由 [Live2DOverlayService] 的 OnClickListener 调用，
     * Dart 端 [live2d_entry.dart] 监听 type=="tap" 事件并按区域触发不同情绪。
     *
     * @param x 点击 x 坐标（逻辑像素 dp，相对于悬浮窗，0-200）
     * @param y 点击 y 坐标（逻辑像素 dp，相对于悬浮窗，0-250）
     */
    fun sendTap(x: Float, y: Float) {
        val map = mutableMapOf<String, Any?>()
        map["type"] = "tap"
        map["x"] = x
        map["y"] = y
        eventSink?.success(map)
    }

    private fun notifyConfigChanged() {
        val map = mutableMapOf<String, Any?>()
        map["type"] = "config_changed"
        map["config"] = jsonToMap(currentConfigJson)
        eventSink?.success(map)
    }

    private fun notifyPetCharacterChanged(config: JSONObject) {
        val map = mutableMapOf<String, Any?>()
        map["type"] = "pet_character_changed"
        map["config"] = jsonToMap(config)
        eventSink?.success(map)
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                org.json.JSONObject.NULL -> null
                else -> value
            }
        }
        return map
    }

    private fun jsonArrayToList(array: org.json.JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until array.length()) {
            val value = array.get(i)
            list.add(when (value) {
                is JSONObject -> jsonToMap(value)
                is org.json.JSONArray -> jsonArrayToList(value)
                org.json.JSONObject.NULL -> null
                else -> value
            })
        }
        return list
    }
}
