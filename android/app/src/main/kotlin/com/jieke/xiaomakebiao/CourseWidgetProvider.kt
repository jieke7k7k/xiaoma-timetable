package com.jieke.xiaomakebiao

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
 * 1.3.4：另有一份逐日表 widget_payload_days（键 yyyy-MM-dd → 该日 payload JSON），
 * 由 [resolvePayload] 按本地今天日期优先取用，取不到才回退 widget_payload。
 *
 * v3（备注）：payload 可选字段 notes（字符串数组，最多 3 条当日备注）。
 * 有就渲染在列表下方的 widget_footer 里（复用现有 footer，最多 2 行），
 * 没有这个字段的老 payload 走 [parsePayload] 的默认空列表，渲染行为完全不变。
 *
 * 1.3.7（尺寸自适应）：渲染前读 [AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT]，
 * 按 [WidgetMetrics] 里与 course_widget.xml 逐条对齐的尺寸常量算出「能完整放下几行」，
 * 只渲染整行，放不下的行 GONE 并把节数并进 footer（「还有 X 节课」）；
 * [onAppWidgetOptionsChanged] 在拉大/缩小后走同一条渲染链。
 * 取不到 options（老系统/异常）时回退「全显」，全程 runCatching，绝不因算尺寸变黑框。
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
        val payload = resolvePayload(data)
        var firstError: String? = null
        ids.forEach { id ->
            runCatching {
                val views = RemoteViews(context.packageName, R.layout.course_widget)
                render(views, payload, maxHeightDp(manager, id))
                views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, id))
                manager.updateAppWidget(id, views)
            }.onFailure {
                if (firstError == null) firstError = it.toString()
            }
        }
        // 自检记录（1.2.7）：写回同一份偏好，设置页「部件状态」可读——
        // 宿主侧渲染失败时不再盲猜，能看到更新时间/实例数/首个异常
        runCatching {
            data.edit().apply {
                putLong(KEY_DBG_TS, System.currentTimeMillis())
                putInt(KEY_DBG_IDS, ids.size)
                if (firstError != null) {
                    putString(KEY_DBG_ERROR, firstError)
                } else {
                    remove(KEY_DBG_ERROR)
                }
                apply()
            }
        }
    }

    /**
     * 尺寸变化（手动拖拽 / 系统换网格）重新排版（1.3.7）
     *
     * 这里拿不到 HomeWidgetProvider 注入的 SharedPreferences，故不直接渲染：
     * 发一条显式的 APPWIDGET_UPDATE 广播回自己，走与系统刷新完全相同的
     * onReceive → onUpdate 链路取数据（避免硬编码 home_widget 的偏好文件名）。
     * 广播在 options 落库之后才发出，onUpdate 里读到的就是新尺寸。
     * 广播失败只吞掉：下次系统刷新/App 推送会再渲染一次，不阻断。
     */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        runCatching {
            context.sendBroadcast(
                Intent(context, CourseWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(appWidgetId))
                }
            )
        }
    }

    /**
     * 当前实例的最大可用高度（dp）；取不到返回 null → 渲染层回退「全显」。
     * 老系统/宿主没写这个 option、id 已失效都会抛或给 0，一律由 runCatching 吞掉。
     */
    private fun maxHeightDp(manager: AppWidgetManager, appWidgetId: Int): Int? =
        runCatching {
            val h = manager.getAppWidgetOptions(appWidgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
            if (h > 0) h else null
        }.getOrNull()

    /** 色条位图缓存：按颜色生成一张小纯色图（替代反射 setBackgroundColor） */
    private val barBitmapCache = HashMap<Int, Bitmap>()

    private fun barBitmap(color: Int): Bitmap =
        barBitmapCache.getOrPut(color) {
            Bitmap.createBitmap(6, 54, Bitmap.Config.ARGB_8888).apply {
                eraseColor(color)
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
        val notes: List<String> = emptyList(),
    )

    /** 一屏排版结果：可见课程行数 + footer 是否还有位置显示 */
    private data class RowPlan(val visibleRows: Int, val showFooter: Boolean)

    /**
     * 与 course_widget.xml 逐条对齐的尺寸度量（dp）。
     *
     * 改布局（根 padding / 顶栏字号 / 色条高度 / 行间距 / footer 字号）时必须同步这里，
     * 否则又会回到「最后一行被底边切一半」。数值取整并略偏保守（宁可少放一行也不切边）。
     */
    private object WidgetMetrics {
        /** 根布局 padding=14dp，上下各一份 */
        const val verticalPadding = 28

        /** 顶栏：15sp 单行（CJK 行距 + 字体上下留白）≈ 22dp */
        const val header = 22

        /** 单行课程：色条固定 36dp，比「15sp 课名 + 12sp 副文」两行文字更高，取大者 */
        const val rowHeight = 36

        /** 行间距：每个课程行 layout_marginTop=12dp（第一行也有） */
        const val rowMargin = 12

        /** 一行课程实际占高（行高 + 行间距） */
        val rowBlock = rowHeight + rowMargin

        /** footer 的 marginTop=8dp */
        const val footerGap = 8

        /** footer 一行 11sp ≈ 16dp */
        const val footerLine = 16
    }

    /**
     * 取「今天」该渲染的 payload（1.3.4 跨天自动切换）
     *
     * 优先读逐日表 widget_payload_days：按设备本地今天日期（yyyy-MM-dd）取对应那份，
     * 用户长假不开 App 时也能跟着日期走；取不到（无此键 / 日期不在范围内 / 解析失败）
     * 一律回退 widget_payload（旧逻辑，行为不变）。
     * 全程 runCatching：任何异常都不能让小部件变回黑框错误态。
     */
    private fun resolvePayload(data: SharedPreferences): Payload? {
        val daysJson = data.getString(KEY_PAYLOAD_DAYS, null)
        if (!daysJson.isNullOrBlank()) {
            val fromDays = runCatching {
                val o = JSONObject(daysJson)
                val key = DAY_KEY_FORMAT.format(Date())
                if (o.has(key)) parsePayload(o.optString(key, null)) else null
            }.getOrNull()
            if (fromDays != null) return fromDays
        }
        return runCatching { parsePayload(data.getString(KEY_PAYLOAD, null)) }.getOrNull()
    }

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
                // 备注是 v3 才加的可选字段：老 payload 没有 notes 键时为空列表，
                // 下面的 notesText 直接跳过，渲染与升级前完全一致
                notes = parseNotes(o),
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * 解析备注数组；字段缺失/不是数组/元素非字符串时返回空列表。
     * JSON 里取出的元素一律用 optString(i) 读，拿不到就跳过该条，不抛异常。
     */
    private fun parseNotes(o: JSONObject): List<String> {
        val arr = o.optJSONArray("notes") ?: return emptyList()
        val out = mutableListOf<String>()
        for (i in 0 until minOf(arr.length(), MAX_NOTES)) {
            val s = arr.optString(i, "").trim()
            if (s.isNotEmpty()) out.add(s)
        }
        return out
    }

    /** 备注要显示的前缀：第一条挂「备注：」，后续行对齐留两个空格 */
    private fun notesText(notes: List<String>): String =
        notes.take(MAX_NOTE_LINES).mapIndexed { i, s ->
            if (i == 0) "备注：$s" else "  $s"
        }.joinToString("\n")

    /**
     * 渲染一份 payload
     *
     * @param maxHeightDp 宿主给的最大可用高度（dp）。null/<=0（老系统取不到 options）
     *   时按老行为全显，不做任何裁剪。
     */
    private fun render(views: RemoteViews, payload: Payload?, maxHeightDp: Int?) {
        views.setTextViewText(R.id.widget_header_left, payload?.headerLeft ?: DEFAULT_TITLE)
        views.setTextViewText(R.id.widget_header_right, payload?.headerRight ?: "")

        val rows = payload?.rows ?: emptyList()
        val footerText = payload?.footer ?: ""
        val notes = notesText(payload?.notes ?: emptyList())
        val noteLines = if (notes.isEmpty()) 0 else notes.count { it == '\n' } + 1
        val footerLines = (if (footerText.isEmpty()) 0 else 1) + noteLines

        // 尺寸自适应（1.3.7）：只渲染能完整放下的整行，footer/备注先占位
        //（备注优先保留，空间不够先砍课程行；极端缩小时才让位，见 planRows）
        val plan = planRows(rows.size, footerLines, maxHeightDp)
        val visible = minOf(plan.visibleRows, rows.size)
        val overflow = maxOf(0, rows.size - visible)

        // 空状态文案：无行时显示
        if (rows.isEmpty()) {
            views.setTextViewText(R.id.widget_empty, payload?.emptyText ?: DEFAULT_EMPTY)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_empty, View.GONE)
        }
        for (i in 0 until MAX_ROWS) {
            val rowId = ROW_IDS[i]
            if (i >= visible) {
                views.setViewVisibility(rowId, View.GONE)
                continue
            }
            val row = rows[i]
            views.setTextViewText(NAME_IDS[i], row.name)
            views.setTextViewText(SUB_IDS[i], row.sub)
            views.setTextViewText(START_IDS[i], row.start)
            views.setTextViewText(END_IDS[i], row.end)
            // 1.2.7：色条改位图填充——setInt 反射调用在个别厂商宿主上会让
            // 整份 RemoteViews 应用失败（桌面报「载入窗口小部件时出现问题」），
            // 位图是一级动作，兼容性最稳
            views.setImageViewBitmap(BAR_IDS[i], barBitmap(row.color))
            views.setViewVisibility(rowId, View.VISIBLE)
        }
        // 底部区域（复用现有 footer）：尾注 + 溢出提示 + 当日备注拼在一起。
        // 不新增布局/不改结构——溢出文案接在已有尾注后面（同一行），
        // 备注最多 2 行，接在后面各占一行。
        val lines = mutableListOf<String>()
        val footerWithOverflow = mergeFooter(footerText, overflow)
        if (footerWithOverflow.isNotEmpty()) lines.add(footerWithOverflow)
        if (notes.isNotEmpty()) lines.add(notes)
        val bottom = lines.joinToString("\n")
        if (plan.showFooter && bottom.isNotEmpty()) {
            views.setTextViewText(R.id.widget_footer, bottom)
            views.setViewVisibility(R.id.widget_footer, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_footer, View.GONE)
        }
    }

    /**
     * 把「被裁掉的行数」并进 footer
     *
     * Dart 端 footer 的既有文案恰好也是「还有 N 节课」（payload 只带 4 行，超出的
     * 已在 Dart 算过）。若直接再追加一句就成了「还有 2 节课 还有 1 节课」，
     * 所以能认出自家格式时把两个数量相加（2+1=还有 3 节课），
     * 其它任意 footer 文案按需求原样在其后追加。
     */
    private fun mergeFooter(footer: String, overflow: Int): String {
        if (overflow <= 0) return footer
        val prefix = "还有 "
        val suffix = " 节课"
        val existing = if (footer.startsWith(prefix) && footer.endsWith(suffix)) {
            footer.substring(prefix.length, footer.length - suffix.length).toIntOrNull()
        } else {
            null
        }
        return when {
            existing != null -> "还有 ${existing + overflow} 节课"
            footer.isEmpty() -> "还有 $overflow 节课"
            else -> "$footer 还有 $overflow 节课"
        }
    }

    /**
     * 根据高度预算算出「放得下几行 + footer 是否还显示」
     *
     * 高度从 [WidgetMetrics]（与布局逐条对齐）扣：上下 padding → 顶栏 →
     * footer（尾注/备注行，裁行时至少预留 1 行放「还有 N 节课」）→ 剩下的除以行块高。
     * 一行都放不下时（约 110dp 的极限缩档）优先保 1 行课程、砍掉 footer，
     * 避免出现「只剩标题和还有 N 节课」的空壳。
     */
    private fun planRows(rowCount: Int, footerLines: Int, maxHeightDp: Int?): RowPlan {
        if (maxHeightDp == null || maxHeightDp <= 0) return RowPlan(rowCount, true)
        if (rowCount <= 0) return RowPlan(0, true)

        val content = maxHeightDp - WidgetMetrics.verticalPadding - WidgetMetrics.header
        // 全部行 + 不需要 footer 时直接全显，别白扣一行
        if (footerLines <= 0 && content >= rowCount * WidgetMetrics.rowBlock) {
            return RowPlan(rowCount, true)
        }

        val footerBlock = WidgetMetrics.footerGap +
            maxOf(footerLines, 1) * WidgetMetrics.footerLine
        val fit = (content - footerBlock) / WidgetMetrics.rowBlock
        if (fit >= 1) return RowPlan(minOf(fit, rowCount), true)

        val oneRow = if (content >= WidgetMetrics.rowBlock) 1 else 0
        return RowPlan(minOf(oneRow, rowCount), showFooter = oneRow == 0)
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
        private const val KEY_PAYLOAD_DAYS = "widget_payload_days"
        private const val DEFAULT_TITLE = "小马课表"
        private const val DEFAULT_EMPTY = "暂无课程"
        private const val MAX_ROWS = 4
        /** payload 里最多带几条备注（与 Dart 端 kWidgetMaxNotes 对齐） */
        private const val MAX_NOTES = 3
        /** 备注在部件里最多渲染几行（4×2 空间有限，再多行会挤掉课程） */
        private const val MAX_NOTE_LINES = 2
        private const val ACTION_OPEN_APP =
            "com.jieke.xiaomakebiao.action.OPEN_WIDGET"
        private const val KEY_DBG_TS = "dbg_widget_ts"
        private const val KEY_DBG_IDS = "dbg_widget_ids"
        private const val KEY_DBG_ERROR = "dbg_widget_error"

        /**
         * 逐日表的日期键格式，与 Dart 端 widgetDayKey 必须一致。
         * 用 Locale.US 固定公历（避免部分地区的佛历/和历导致年份对不上），
         * 时区取设备本地，与 Dart 的本地日期口径相同。
         */
        private val DAY_KEY_FORMAT = SimpleDateFormat("yyyy-MM-dd", Locale.US)

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
