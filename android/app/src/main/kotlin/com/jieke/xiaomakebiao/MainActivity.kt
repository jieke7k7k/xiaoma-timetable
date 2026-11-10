package com.jieke.xiaomakebiao

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：注册两个 MethodChannel——
 * 1. 「今日课程常驻通知排链」（com.jieke.xiaomakebiao/ongoing_course）：WB_SPEC_229 起
 *    它不再负责渲染通知（前台 Service 已退役），只负责两件事——按 Dart 算好的边界点
 *    排下一个精确闹钟、以及取消已排的链闹钟。通知本身由 Dart 侧
 *    flutter_local_notifications 直接发（App 活着）或由 OngoingCourseReceiver 自己画
 *    （App 被杀），两条通道共用一个渠道 + 一个 id，用户只看到一条通知在翻页；
 * 2. 「设备设置」：给权限页/首次引导查三项权限状态并跳对应的系统页面
 *    （通知设置、闹钟和提醒、电池优化、应用详情）。
 *
 * 第 2 个通道只做「查状态 + 跳页面」这两件系统活儿：申请通知与精确闹钟仍由
 * Flutter 侧的 flutter_local_notifications 插件 API 负责，不在这里重复实现。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 排下一个链闹钟：边界点由 Dart 的 computeClassFocus 算好传过来
                    "scheduleNext" -> {
                        val triggerAtMillis = call.argument<Number>("triggerAtMillis")?.toLong()
                        if (triggerAtMillis == null) {
                            result.error("bad_args", "缺少 triggerAtMillis", null)
                        } else {
                            OngoingCourseReceiver.scheduleAt(this, triggerAtMillis)
                            result.success(null)
                        }
                    }
                    // 取消链闹钟（开关关闭 / 无当前学期 / 排链前幂等清理）
                    "cancelScheduled" -> {
                        OngoingCourseReceiver.cancelScheduled(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "notification" to notificationEnabled(),
                            "exactAlarm" to exactAlarmAllowed(),
                            "battery" to ignoringBatteryOptimizations()
                        )
                    )
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "openBatteryOptimizationSettings" -> {
                        openBatteryOptimizationSettings()
                        result.success(null)
                    }
                    "openAppDetails" -> {
                        openAppDetails()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ---------- 权限状态 ----------

    /** 通知是否开启（Android 13+ 的 POST_NOTIFICATIONS） */
    private fun notificationEnabled(): Boolean = runCatching {
        NotificationManagerCompat.from(this).areNotificationsEnabled()
    }.getOrDefault(true)

    /** 是否允许精确闹钟；Android 12 以前没有这项限制，按允许处理 */
    private fun exactAlarmAllowed(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return runCatching {
            val am = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            am?.canScheduleExactAlarms() ?: true
        }.getOrDefault(true)
    }

    /** 是否已加入电池优化白名单（true = 系统不会为了省电限制它） */
    private fun ignoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return runCatching {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            pm?.isIgnoringBatteryOptimizations(packageName) ?: true
        }.getOrDefault(true)
    }

    // ---------- 跳系统页面 ----------

    /** 本 App 的通知设置页（Android 8+）；低版本回退到应用详情页 */
    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            appDetailsIntent()
        }
        startActivitySafely(intent)
    }

    /** 系统「闹钟和提醒」授权页（Android 12+），取不到就回退应用详情页 */
    private fun openExactAlarmSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                .setData(Uri.parse("package:$packageName"))
        } else {
            appDetailsIntent()
        }
        startActivitySafely(intent)
    }

    /**
     * 系统「电池优化」白名单列表页（不需要任何权限，也不替用户做决定）。
     * 部分厂商把这页藏起来了，跳转失败时回退到应用详情页——那里面同样能改电池策略。
     */
    private fun openBatteryOptimizationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        } else {
            appDetailsIntent()
        }
        if (!startActivitySafely(intent)) openAppDetails()
    }

    /** 本 App 的应用详情页（任何 Android 都有，电池优化的兜底入口） */
    private fun openAppDetails() {
        startActivitySafely(appDetailsIntent())
    }

    private fun appDetailsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:$packageName"))

    /** 跳系统页一律容错：没有能接这个 Intent 的页面时返回 false，绝不崩 */
    private fun startActivitySafely(intent: Intent): Boolean = runCatching {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    }.getOrDefault(false)

    companion object {
        private const val CHANNEL = "com.jieke.xiaomakebiao/ongoing_course"
        private const val DEVICE_CHANNEL = "com.jieke.xiaomakebiao/device"
    }
}
