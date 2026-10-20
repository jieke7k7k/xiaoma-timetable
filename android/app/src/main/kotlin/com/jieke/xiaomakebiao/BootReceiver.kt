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
 * 「今天 + 未来 6 天」的精确闹钟。flutter_local_notifications 插件自带
 * ScheduledNotificationBootReceiver，会在开机后把已排期的通知重新注册到 AlarmManager，
 * 因此重启后滚动窗口内的提醒照常触发，无需额外代码。
 *
 * 本接收器作为第二道保险：仅记录一条日志，便于真机排查「开机后提醒是否被正确恢复」。
 * 真正的「重排全部提醒」发生在 Flutter 端（App 下次打开时由 rescheduleAll() 触发），
 * 或由插件内置接收器恢复已排通知。若后续需要「无感后台重排」，可在此接入
 * 后台 isolate / WorkManager，本阶段先保留为日志占位，避免开机拉起 Activity 打扰用户。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.i(TAG, "设备已开机，课程提醒将由插件内置接收器恢复 / 下次启动时重排")
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
