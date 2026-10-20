package com.jieke.xiaomakebiao

import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：注册「今日课程常驻通知」MethodChannel，
 * 把 Flutter 端 OngoingNoticeService 的 update/stop 转发给前台 Service。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        val title = call.argument<String>("title")
                            ?: OngoingCourseService.DEFAULT_TITLE
                        val lines = call.argument<List<String>>("lines") ?: emptyList()
                        startOngoingService(title, lines)
                        result.success(null)
                    }
                    "stop" -> {
                        stopOngoingService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** 启动前台 Service 渲染常驻通知 */
    private fun startOngoingService(title: String, lines: List<String>) {
        val intent = Intent(this, OngoingCourseService::class.java).apply {
            action = OngoingCourseService.ACTION_UPDATE
            putExtra(OngoingCourseService.EXTRA_TITLE, title)
            putStringArrayListExtra(OngoingCourseService.EXTRA_LINES, ArrayList(lines))
        }
        ContextCompat.startForegroundService(this, intent)
    }

    /** 停止前台 Service 并移除常驻通知 */
    private fun stopOngoingService() {
        val intent = Intent(this, OngoingCourseService::class.java).apply {
            action = OngoingCourseService.ACTION_STOP
        }
        // stop 无需前台启动，直接 startService 触发 onStartCommand 的 STOP 分支
        startService(intent)
    }

    companion object {
        private const val CHANNEL = "com.jieke.xiaomakebiao/ongoing_course"
    }
}
