package com.jieke.xiaomakebiao

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * 今日课程桌面小部件 Provider（Android only）
 *
 * 继承 home_widget 的 [HomeWidgetProvider]：Dart 端 [HomeWidget.saveWidgetData]
 * 写入的 SharedPreferences 作为第 4 个参数 data 注入，本类只做「哑渲染」。
 *
 * 1.2.2 列表式改版：数据契约改为整包 JSON（键 widget_payload，结构由
 * Flutter 端 utils/widget_data.dart 定义）：顶栏（学期名 + 日期/第X周/周X）、
 * 最多 4 行课程（色条色值 + 课名 + 教室教师 + 起止时间）、尾注、空文案。
 * 内容决策（今天剩余课 / 今天没课换明天 / 颜色映射）全部在 Flutter 端完成。
 *
 * 任一环节解析失败都回退默认文案，绝不崩溃；单实例渲染异常不拖垮其他实例。
 */
class CourseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
        data: SharedPreferences,
    ) {
        val payload = parsePayload(data.getString(KEY_PAYLOAD, null))
        ids.forEach { id ->
            runCatching {
                val views = RemoteViews(context.packageName, R.layout.course_widget)
                render(views, payload)
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, id))
                manager.updateAppWidget(id, views)
            }
        }
    }

    private data class Row(
        val name: String,
        val sub: String,
        val start: String,
        val end: String,
        val color: Int,
    )

    private data class Payload(
        val headerLeft: String,
        val headerRight: String,
        val rows: List<Row>,
        val footer: String,
        val emptyText: String,
    )

    /** 解析整包 JSON；缺失/损坏时返回 null（render 用默认文案兜底） */
    private fun parsePayload(json: String?): Payload? {
        if (json.isNullOrBlank()) return null
        return try {
            val o = JSONObject(json)
            val arr = o.optJSONArray("rows")
            val rows = mutableListOf<Row>()
            if (arr != null) {
                for (i in 0 until minOf(arr.length(), MAX_ROWS)) {
                    val r = arr.optJSONObject(i) ?: continue
                    rows.add(
                        Row(
                            name = r.optString("name"),
                            sub = r.optString("sub"),
                            start = r.optString("start"),
                            end = r.optString("end"),
                            // JSON 数字按 double/long 读，统一转 Int（ARGB 位模式不变）
                            color = r.optLong("color", 0).toInt(),
                        )
                    )
                }
            }
            Payload(
                headerLeft = o.optString("headerLeft", DEFAULT_TITLE),
                headerRight = o.optString("headerRight"),
                rows = rows,
                footer = o.optString("footer"),
                emptyText = o.optString("emptyText", DEFAULT_EMPTY),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun render(views: RemoteViews, payload: Payload?) {
        views.setTextViewText(R.id.widget_header_left, payload?.headerLeft ?: DEFAULT_TITLE)
        views.setTextViewText(R.id.widget_header_right, payload?.headerRight ?: "")

        val rows = payload?.rows ?: emptyList()
        // 空状态文案：无行时显示
        if (rows.isEmpty()) {
            views.setTextViewText(R.id.widget_empty, payload?.emptyText ?: DEFAULT_EMPTY)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_empty, View.GONE)
        }
        for (i in 0 until MAX_ROWS) {
            val rowId = ROW_IDS[i]
            if (i >= rows.size) {
                views.setViewVisibility(rowId, View.GONE)
                continue
            }
            val row = rows[i]
            views.setTextViewText(NAME_IDS[i], row.name)
            views.setTextViewText(SUB_IDS[i], row.sub)
            views.setTextViewText(START_IDS[i], row.start)
            views.setTextViewText(END_IDS[i], row.end)
            views.setInt(BAR_IDS[i], "setBackgroundColor", row.color)
            views.setViewVisibility(rowId, View.VISIBLE)
        }
        val footer = payload?.footer ?: ""
        if (footer.isNotEmpty()) {
            views.setTextViewText(R.id.widget_footer, footer)
            views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_footer, View.GONE)
        }
    }

    /** 点击小部件任意处唤起 App 主界面（回首页） */
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
        private const val KEY_PAYLOAD = "widget_payload"
        private const val DEFAULT_TITLE = "小马课表"
        private const val DEFAULT_EMPTY = "暂无课程"
        private const val MAX_ROWS = 4
        private const val ACTION_OPEN_APP =
            "com.jieke.xiaomakebiao.action.OPEN_WIDGET"

        private val ROW_IDS = intArrayOf(
            R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3, R.id.widget_row_4,
        )
        private val BAR_IDS = intArrayOf(
            R.id.widget_bar_1, R.id.widget_bar_2, R.id.widget_bar_3, R.id.widget_bar_4,
        )
        private val NAME_IDS = intArrayOf(
            R.id.widget_name_1, R.id.widget_name_2, R.id.widget_name_3, R.id.widget_name_4,
        )
        private val SUB_IDS = intArrayOf(
            R.id.widget_sub_1, R.id.widget_sub_2, R.id.widget_sub_3, R.id.widget_sub_4,
        )
        private val START_IDS = intArrayOf(
            R.id.widget_start_1, R.id.widget_start_2, R.id.widget_start_3, R.id.widget_start_4,
        )
        private val END_IDS = intArrayOf(
            R.id.widget_end_1, R.id.widget_end_2, R.id.widget_end_3, R.id.widget_end_4,
        )
    }
}
