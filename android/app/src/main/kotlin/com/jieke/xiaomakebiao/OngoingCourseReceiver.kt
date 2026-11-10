package com.jieke.xiaomakebiao

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * 今日课程常驻通知的「单闹钟接力」接收器（WB_SPEC_229 第 5 节）
 *
 * 退役了前台 Service 之后，App 不在前台 / 被杀时由这里接手：
 * 精确闹钟唤醒 → 读库 → 算焦点（[OngoingFocusCalculator]）→ notify() 刷新同一条通知
 * → 按下一个边界点排下一个闹钟 → 结束。全程不启动 Flutter Engine、不拉起 Activity，
 * 因此小米 HyperOS 的耗电统计不会再把这个 App 标成「后台高耗电」。
 *
 * 通知身份与退役前一字不变：渠道 ongoing_course_channel（「今日课程」，IMPORTANCE_LOW）、
 * 通知 id 1001、纯白日历剪影小图标、点按回主页、InboxStyle 可折叠、setOngoing(true)
 * 不能滑掉、setOnlyAlertOnce + setSilent 不打扰。
 */
class OngoingCourseReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        // 闹钟触发：任何一步失败都只记日志——Receiver 里抛异常会直接闪退
        try {
            refreshAndReschedule(context, notify = true)
        } catch (t: Throwable) {
            Log.w(TAG, "常驻通知闹钟处理失败", t)
        }
    }

    companion object {
        private const val TAG = "OngoingCourseReceiver"

        /** 渠道 / 通知身份：与退役前的 Service 完全一致，两个通道（Dart / 原生）互相覆盖 */
        const val CHANNEL_ID = "ongoing_course_channel"
        const val CHANNEL_NAME = "今日课程"
        const val CHANNEL_DESC = "今日剩余 / 明日课程常驻通知"
        const val NOTIFICATION_ID = 1001

        /**
         * 链闹钟的 requestCode：取 1001 与通知 id 对齐（只是好记）。
         * 用途与提醒闹钟完全不同——提醒走 flutter_local_notifications 的 1~360 号 id，
         * 这里排在它之外，不会撞号。
         */
        const val ALARM_REQUEST_CODE = 1001

        /** 固定东八区：与 Dart 侧 tz.setLocalLocation(Asia/Shanghai) 同口径 */
        val SHANGHAI: ZoneId = ZoneId.of("Asia/Shanghai")

        /** 边界点（东八区墙上时间）→ 绝对时间戳，交给 AlarmManager */
        fun toEpochMillis(boundary: LocalDateTime): Long =
            boundary.atZone(SHANGHAI).toInstant().toEpochMilli()

        /**
         * 读库 → 算焦点 →（notify 时）刷新通知 → 接力排下一个闹钟 / 停链。
         *
         * 闹钟触发（onReceive）与开机恢复（scheduleNext）共用同一条逻辑，
         * 只差开机恢复不刷新通知——避免两条链演化出差异（Kimi 复审优化建议 1）。
         * 读库失败 / 开关关 / 无学期时：notify=true 撤通知并停链，notify=false 只停链。
         */
        private fun refreshAndReschedule(context: Context, notify: Boolean) {
            val snapshot = OngoingDbReader.read(context)
            if (snapshot == null) {
                // 读库失败 / 库不存在：取消通知、不排链，等下次 App 打开重建
                if (notify) cancelNotification(context)
                cancelScheduled(context)
                return
            }
            val now = LocalDateTime.now(SHANGHAI)
            when (
                val decision = OngoingFocusCalculator.decide(
                    enabled = snapshot.enabled,
                    semester = snapshot.semester,
                    now = now,
                    courses = snapshot.courses,
                    timeSlots = snapshot.slots,
                    overrides = snapshot.overrides,
                )
            ) {
                OngoingFocusCalculator.Decision.Disabled,
                OngoingFocusCalculator.Decision.NoSemester -> {
                    if (notify) cancelNotification(context)
                    cancelScheduled(context)
                }

                is OngoingFocusCalculator.Decision.Show -> {
                    if (notify) showNotification(context, decision.notice)
                    scheduleAt(context, toEpochMillis(decision.notice.boundary))
                }
            }
        }

        /** 把纯逻辑算出的文案画成常驻通知（样式与退役前的 Service 逐项对齐） */
        private fun showNotification(context: Context, notice: OngoingFocusCalculator.Notice) {
            ensureChannel(context)
            // 点按通知回到 App 主界面
            val contentIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.let { launch ->
                    PendingIntent.getActivity(
                        context,
                        0,
                        launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }

            val inbox = NotificationCompat.InboxStyle()
            if (notice.lines.isEmpty()) {
                inbox.addLine("暂无课程")
            } else {
                for (line in notice.lines) inbox.addLine(line)
            }

            val builder = NotificationCompat.Builder(context, CHANNEL_ID)
                // 纯白日历剪影：应用彩色图标在通知栏会变白块/模糊，深浅色通知栏下剪影都清晰
                .setSmallIcon(R.drawable.ic_stat_course)
                .setContentTitle(notice.title)
                .setContentText(notice.lines.firstOrNull() ?: "暂无课程")
                .setStyle(inbox)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
            if (contentIntent != null) builder.setContentIntent(contentIntent)

            try {
                // Android 13+ 没给 POST_NOTIFICATIONS 时这里会静默失败，不抛异常
                NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, builder.build())
            } catch (t: Throwable) {
                Log.w(TAG, "刷新常驻通知失败", t)
            }
        }

        /**
         * 在 [triggerAtMillis] 排下一个链闹钟（幂等：先撤同 requestCode 的旧闹钟再排）。
         *
         * Android 12+ 没有精确闹钟授权时降级为 setAndAllowWhileIdle 并打日志：
         * 通知仍会翻页，只是可能晚几分钟——文案不带倒计时，用户看不出来（第 5.3 节）。
         */
        fun scheduleAt(context: Context, triggerAtMillis: Long) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            if (alarmManager == null) {
                Log.w(TAG, "取不到 AlarmManager，本轮不排链")
                return
            }
            val pendingIntent = broadcastIntent(context, PendingIntent.FLAG_UPDATE_CURRENT)
            if (pendingIntent == null) {
                Log.w(TAG, "创建链闹钟 PendingIntent 失败，本轮不排链")
                return
            }
            // 先撤旧的同 requestCode 闹钟：改课后不留旧链（排链是幂等的）
            alarmManager.cancel(pendingIntent)

            val exactAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                runCatching { alarmManager.canScheduleExactAlarms() }.getOrDefault(false)
            } else {
                true
            }
            try {
                if (!exactAllowed) {
                    Log.i(TAG, "未获精确闹钟授权，常驻通知链降级为非精确闹钟")
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                    )
                    return
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
                }
            } catch (t: Throwable) {
                // 授权在排链瞬间被撤销会抛 SecurityException：降级而不是丢掉整条链
                Log.w(TAG, "精确闹钟排链失败，降级为非精确闹钟", t)
                runCatching {
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent
                    )
                }.onFailure { Log.w(TAG, "降级排链同样失败", it) }
            }
        }

        /**
         * 自行读库算边界点后排链（开机恢复用；Flutter 侧则通过 MethodChannel 传
         * 精确时刻调 [scheduleAt]）。读库失败 / 开关关 / 无学期时停链。
         * 与闹钟触发共用 [refreshAndReschedule]，只差不刷新通知。
         */
        fun scheduleNext(context: Context) {
            try {
                refreshAndReschedule(context, notify = false)
            } catch (t: Throwable) {
                Log.w(TAG, "开机恢复常驻通知链失败", t)
            }
        }

        /** 停链：开关关闭 / 无学期 / 读库失败时调用 */
        fun cancelScheduled(context: Context) {
            val alarmManager =
                context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val pendingIntent = broadcastIntent(context, PendingIntent.FLAG_NO_CREATE)
            if (pendingIntent == null) return // 本来就没有排过
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
        }

        /** 移除常驻通知 */
        fun cancelNotification(context: Context) {
            try {
                NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
            } catch (t: Throwable) {
                Log.w(TAG, "移除常驻通知失败", t)
            }
        }

        /** 显式 Intent（Manifest 里该 Receiver 不注册任何 intent-filter） */
        private fun broadcastIntent(context: Context, flags: Int): PendingIntent? =
            PendingIntent.getBroadcast(
                context,
                ALARM_REQUEST_CODE,
                Intent(context, OngoingCourseReceiver::class.java),
                flags or PendingIntent.FLAG_IMMUTABLE,
            )

        /** 「今日课程」低重要性渠道（Android 8+）；与 Dart 侧 _ensureOngoingCourseChannel 同名同参 */
        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = CHANNEL_DESC
                setShowBadge(false)
                enableVibration(false)
            }
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }
}
