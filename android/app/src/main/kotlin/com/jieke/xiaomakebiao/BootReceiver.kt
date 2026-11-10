package com.jieke.xiaomakebiao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机自启接收器（阶段四·上课本地通知提醒）
 *
 * 设计说明：
 * 本项目的提醒采用「滚动窗口」模型——NotificationService.rescheduleAll() 一次性排好
 * 「今天 + 未来 29 天」的精确闹钟。flutter_local_notifications 插件自带
 * ScheduledNotificationBootReceiver，会在开机后把已排期的通知重新注册到 AlarmManager，
 * 因此重启后滚动窗口内的提醒照常触发，无需额外代码。
 *
 * 今日课程常驻通知是另一套机制（WB_SPEC_229）：退役前台 Service 后改成「单闹钟接力」，
 * 链在 App 被杀后仍能自己走；但重启手机后 AlarmManager 里的闹钟全被系统清空，链会断。
 * 所以这里补一次 [OngoingCourseReceiver.scheduleNext]：读库算边界点 → 排下一个闹钟，
 * 不需要用户手动打开 App，也不拉起 Activity / Flutter Engine。
 *
 * 失败只记日志：开机广播里抛异常会被系统当成崩溃，绝不能影响开机。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.i(TAG, "设备已开机，课程提醒将由插件内置接收器恢复 / 下次启动时重排")
            // 今日课程常驻通知：重启后闹钟被系统清空，这里把链重新接上
            try {
                OngoingCourseReceiver.scheduleNext(context)
            } catch (t: Throwable) {
                Log.w(TAG, "开机恢复今日课程常驻通知链失败", t)
            }
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
