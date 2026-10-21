package com.jieke.xiaomakebiao

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * 今日课程桌面小组件 Provider（阶段四·第 2 项，Android only）
 *
 * 继承 home_widget 的 [HomeWidgetProvider]：其内部会把 Dart 端 [HomeWidget.saveWidgetData]
 * 写入的 SharedPreferences 作为第 4 个参数 data 注入，本类从 data 读取标题与行文案后渲染。
 *
 * 「哑渲染」：本类不做任何计算，只负责把 Flutter 端（WidgetService）下发的
 * widget_title / widget_lines 渲染成 RemoteViews；今日/明日切换的 B 决策全部在
 * Flutter 端 buildOngoingNotice 完成。
 *
 * 布局为 4×2（250dp × 110dp）：标题 + 最多 3 行「时间 课程名 教室」，
 * 超出 3 行时最后一行显示「…等 X 节」。
 */
class CourseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        data: SharedPreferences,
    ) {
        // 读标题与行文案；读不到（首次添加、数据尚未下发）用兜底文案，绝不崩溃
        val title = data.getString(KEY_TITLE, null) ?: DEFAULT_TITLE
        val lines = parseLines(data.getString(KEY_LINES, null))

        ids.forEach { id ->
            // 单个实例渲染异常不能拖垮其余实例（1.2.1 加固）
            runCatching {
                val views = RemoteViews(context.packageName, R.layout.course_widget)
                views.setTextViewText(R.id.widget_title, title)
                renderLines(views, lines)
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, id))
                manager.updateAppWidget(id, views)
            }
        }
    }

    /** 解析行文案 JSON 数组；解析失败返回空列表（由 renderLines 兜底） */
    private fun parseLines(json: String?): List<String> {
        if (json.isNullOrBlank()) return emptyList()
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).map { arr.optString(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 把行文案渲染进布局：最多 [MAX_LINES] 行，超出时最后一行显示「…等 X 节」 */
    private fun renderLines(views: RemoteViews, lines: List<String>) {
        val viewIds = intArrayOf(
            R.id.widget_line_1,
            R.id.widget_line_2,
            R.id.widget_line_3,
        )

        // 空数据兜底：第一行显示「暂无课程」，其余隐藏
        if (lines.isEmpty()) {
            views.setTextViewText(viewIds[0], DEFAULT_LINE)
            views.setViewVisibility(viewIds[0], View.VISIBLE)
            for (i in 1 until MAX_LINES) {
                views.setViewVisibility(viewIds[i], View.GONE)
            }
            return
        }

        val overflow = lines.size > MAX_LINES
        for (i in 0 until MAX_LINES) {
            if (i >= lines.size) {
                // 行数不足：多余行隐藏
                views.setViewVisibility(viewIds[i], View.GONE)
                continue
            }
            val text = if (overflow && i == MAX_LINES - 1) {
                // 超出上限：最后一行显示汇总，X = 总节数
                "…等 ${lines.size} 节"
            } else {
                lines[i]
            }
            views.setTextViewText(viewIds[i], text)
            views.setViewVisibility(viewIds[i], View.VISIBLE)
        }
    }

    /** 点击小组件任意处唤起 App 主界面（回首页） */
    private fun openAppIntent(context: Context, widgetId: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            widgetId,
            Intent(context, MainActivity::class.java).apply {
                action = ACTION_OPEN_APP
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    companion object {
        private const val KEY_TITLE = "widget_title"
        private const val KEY_LINES = "widget_lines"
        private const val DEFAULT_TITLE = "今日课程"
        private const val DEFAULT_LINE = "暂无课程"
        private const val MAX_LINES = 3
        private const val ACTION_OPEN_APP =
            "com.jieke.xiaomakebiao.action.OPEN_WIDGET"
    }
}
