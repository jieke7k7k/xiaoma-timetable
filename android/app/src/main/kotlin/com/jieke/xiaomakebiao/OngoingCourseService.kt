package com.jieke.xiaomakebiao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 今日课程常驻通知栏前台 Service（阶段四·第 3 项，Android only）
 *
 * 「哑渲染」：本 Service 不做任何计算，只负责把 Flutter 端（OngoingNoticeService）
 * 通过 MethodChannel 下发的标题 + 行文案，渲染成一条可折叠的 InboxStyle 常驻通知，
 * 并 startForeground 保活。
 *
 * 通知渠道 ongoing_course_channel：中文名「今日课程」，IMPORTANCE_LOW（静默、不打扰）。
 */
class OngoingCourseService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 关闭开关 / 清通知：移除前台通知并停服务
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val lines = intent?.getStringArrayListExtra(EXTRA_LINES) ?: arrayListOf()
        val notification = buildNotification(title, lines)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+：specialUse 前台服务类型必须显式传入
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        // 保险：服务销毁时移除常驻通知，避免残留
        stopForeground(STOP_FOREGROUND_REMOVE)
        getSystemService(Context.NOTIFICATION_SERVICE)
            ?.let { it as NotificationManager }
            ?.cancel(NOTIFICATION_ID)
    }

    /** 构建可折叠 InboxStyle 常驻通知 */
    private fun buildNotification(title: String, lines: List<String>): Notification {
        ensureChannel()

        // 点按通知回到 App 主界面
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val inbox = NotificationCompat.InboxStyle()
        if (lines.isEmpty()) {
            inbox.addLine("暂无课程")
        } else {
            for (line in lines) {
                inbox.addLine(line)
            }
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            // 纯白日历剪影：应用彩色图标在通知栏会变白块/模糊，深浅色通知栏下剪影都清晰
            .setSmallIcon(R.drawable.ic_stat_course)
            .setContentTitle(title)
            .setContentText(if (lines.isNotEmpty()) lines.first() else "暂无课程")
            .setStyle(inbox)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
    }

    /** 创建「今日课程」低重要性通知渠道（Android 8+） */
    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = CHANNEL_DESC
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val CHANNEL_ID = "ongoing_course_channel"
        const val CHANNEL_NAME = "今日课程"
        const val CHANNEL_DESC = "今日剩余 / 明日课程常驻通知"
        const val NOTIFICATION_ID = 1001

        const val ACTION_UPDATE = "com.jieke.xiaomakebiao.action.ONGOING_UPDATE"
        const val ACTION_STOP = "com.jieke.xiaomakebiao.action.ONGOING_STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_LINES = "lines"
        const val DEFAULT_TITLE = "今日课程"
    }
}
