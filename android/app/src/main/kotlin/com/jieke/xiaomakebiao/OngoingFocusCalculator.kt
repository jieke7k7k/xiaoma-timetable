package com.jieke.xiaomakebiao

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.temporal.ChronoUnit

/**
 * 今日课程常驻通知的焦点计算（纯 Kotlin，不 import 任何 Android 框架类）
 *
 * 逐字等价移植自 Dart 侧（WB_SPEC_229 第 4 节）：
 * - lib/utils/week_calc.dart        → [currentWeek] / [alignToMonday]
 * - lib/models/course.dart          → [isActiveInWeek]
 * - lib/utils/override_effect.dart  → [effectiveCoursesForWeek]
 * - lib/utils/next_class.dart       → [sessionsOnDay] / [computeClassFocus] / [dayLabel]
 * - lib/utils/ongoing_notice.dart   → [buildNotice]（文案逐字照搬，含全角冒号与「 · 」后缀）
 *
 * 为什么不直接复用 Dart：App 被系统杀掉后 Flutter Engine 不在，闹钟唤醒的
 * BroadcastReceiver 只能自己算。为了「用户可见行为一字不改」，两边的规则与文案
 * 必须逐字一致——改动任何一条都要两边同时改，并跑共享夹具
 * （test/fixtures/ongoing_focus_cases.json，Dart 侧 test/ongoing_focus_fixture_test.dart，
 * Kotlin 侧 android/app/src/test/.../OngoingFocusCalculatorTest.kt）。
 *
 * 时区口径：一律 Asia/Shanghai（与提醒闹钟固定东八区一致），调用方传入的 [LocalDateTime]
 * 即东八区墙上时间。
 */
object OngoingFocusCalculator {

    /** 向前看的天数：今天起算 9 天（覆盖周末→下周一与短假期），与 Dart 的 0..8 一致 */
    const val LOOKAHEAD_DAYS = 9

    /** 未来 9 天都没课时，次日 00:05 的一天一 tick 闲时闹钟（只为不断链，不为刷新文案） */
    private const val IDLE_TICK_HOUR = 0
    private const val IDLE_TICK_MINUTE = 5

    /**
     * 决策：开关关 / 无当前学期 / 正常出文案三档。
     *
     * 读库失败（[OngoingDbReader.read] 返回 null）在调用方等价于 [NoSemester]：
     * 取消通知、不排链，等下次 App 打开重建——与 Flutter 侧 refresh() 的兜底一致。
     */
    sealed class Decision {
        /** 开关关闭：两个通道都停 */
        object Disabled : Decision()

        /** 无当前学期（或读库失败）：取消通知、不排链 */
        object NoSemester : Decision()

        /** 正常：给出文案与下一个边界点 */
        class Show(val notice: Notice) : Decision()
    }

    /** 一条常驻通知的内容 + 下一个边界点（纯数据） */
    class Notice(
        val title: String,
        val lines: List<String>,
        /** 下一个边界点（东八区墙上时间）：该刷新通知 / 交接链的时刻 */
        val boundary: LocalDateTime,
    )

    /**
     * 统一决策入口。
     *
     * @param enabled app_settings 的 ongoing_enabled（缺失按开，与 Dart 的 getSettingBool 一致）
     * @param semester 当前学期；null 表示没有当前学期
     * @param now 东八区当前时刻
     */
    fun decide(
        enabled: Boolean,
        semester: FocusSemester?,
        now: LocalDateTime,
        courses: List<FocusCourse>,
        timeSlots: List<FocusTimeSlot>,
        overrides: List<FocusOverride>,
    ): Decision {
        if (!enabled) return Decision.Disabled
        if (semester == null) return Decision.NoSemester
        return Decision.Show(computeNotice(now, semester, courses, timeSlots, overrides))
    }

    /** 算焦点 → 出文案 → 定边界点 */
    fun computeNotice(
        now: LocalDateTime,
        semester: FocusSemester,
        courses: List<FocusCourse>,
        timeSlots: List<FocusTimeSlot>,
        overrides: List<FocusOverride>,
    ): Notice {
        val today = now.toLocalDate()
        // 开学日期只解析一次（解析失败回退到 today 所在周一），9 天复用——
        // 与 Dart 的 Semester.startDateParsed 一致（一次求值、DateTime.now() 为基准）。
        // 绝不能在 sessionsOnDay 里按被评估日逐日回退：那样 offset>0 的日期恒算第 1 周。
        val semesterStart = startDate(semester, today)
        val sessions = ArrayList<FocusSession>()
        for (offset in 0 until LOOKAHEAD_DAYS) {
            sessions.addAll(
                sessionsOnDay(
                    today.plusDays(offset.toLong()),
                    semester,
                    courses,
                    timeSlots,
                    overrides,
                    semesterStart,
                )
            )
        }
        sessions.sortBy { it.start }

        // 正在上的课：第一个满足 start <= now < end 的
        var current: FocusSession? = null
        for (s in sessions) {
            if (!s.start.isAfter(now) && s.end.isAfter(now)) {
                current = s
                break
            }
        }
        // 下一节：第一个 start > now 的
        var next: FocusSession? = null
        for (s in sessions) {
            if (s.start.isAfter(now)) {
                next = s
                break
            }
        }
        // 今天在下一节之后还有几节：只在下一节就是今天时才算
        var laterTodayCount = 0
        if (next != null && next.date == today) {
            laterTodayCount = sessions.count { it.date == today && it.start.isAfter(next.start) }
        }

        val title: String
        val lines: MutableList<String> = ArrayList(2)
        if (current != null) {
            title = "正在上课：${current.course.name}"
            lines.add(current.timeRange() + roomSuffix(current.course))
            if (next != null) {
                lines.add(
                    "下一节：${next.course.name} · ${dayLabel(next.date, today)} " +
                        "${fmtHhmm(next.start)}${roomSuffix(next.course)}"
                )
            } else {
                lines.add("今天没有其他课了")
            }
        } else if (next != null) {
            title = "下一节：${next.course.name}"
            val isToday = dayLabel(next.date, today) == "今天"
            val prefix = if (isToday) "" else "${dayLabel(next.date, today)} "
            lines.add(prefix + next.timeRange() + roomSuffix(next.course))
            if (laterTodayCount > 0) {
                lines.add("今天后面还有 $laterTodayCount 节课")
            }
        } else {
            title = "暂无课程安排"
            lines.add("近期没有要上的课，好好休息")
        }

        return Notice(title = title, lines = lines, boundary = nextBoundary(now, current, next))
    }

    /**
     * 下一个边界点 = min(正在上的课的下课时刻, 下一节课的上课时刻)（WB_SPEC_229 第 3.2 节）；
     * 两者都没有（未来 9 天无课：假期 / 学期外 / 课表为空）→ 次日 00:05 的一天一 tick。
     *
     * 若算出的时刻不晚于 now（时钟跳变 / 脏数据），同样退回次日 00:05，
     * 避免闹钟立刻触发后自我接力形成死循环。
     */
    fun nextBoundary(
        now: LocalDateTime,
        current: FocusSession?,
        next: FocusSession?,
    ): LocalDateTime {
        val candidates = listOfNotNull(current?.end, next?.start)
        val earliest = candidates.minOrNull()
        if (earliest != null && earliest.isAfter(now)) return earliest
        return now.toLocalDate().plusDays(1).atTime(IDLE_TICK_HOUR, IDLE_TICK_MINUTE)
    }

    /** 某一天的具体课次：已应用单次调课与单双周 / 周次过滤，按开始时间排序
     *
     * @param semesterStart 已解析好的开学日期，由调用方（[computeNotice]）按计算时刻
     * （today）一次解析后传入，9 天复用；不要在这里按被评估日逐日解析回退，
     * 否则开学日期脏数据时 offset>0 的日期恒算第 1 周（Kimi 复审 Bug 2）。
     */
    fun sessionsOnDay(
        date: LocalDate,
        semester: FocusSemester,
        courses: List<FocusCourse>,
        timeSlots: List<FocusTimeSlot>,
        overrides: List<FocusOverride>,
        semesterStart: LocalDate,
    ): List<FocusSession> {
        val week = currentWeek(semesterStart, date)
        if (week < 1 || week > semester.totalWeeks) return emptyList()
        val slotMap = HashMap<Int, FocusTimeSlot>(timeSlots.size)
        for (slot in timeSlots) slotMap[slot.section] = slot
        val out = ArrayList<FocusSession>()
        for (c in effectiveCoursesForWeek(courses, overrides, week)) {
            // effectiveCoursesForWeek 按约定不做周次过滤，这里统一补上（与 Dart 一致）
            if (!isActiveInWeek(c, week)) continue
            if (c.dayOfWeek != date.dayOfWeek.value) continue
            val startSlot = slotMap[c.startSection] ?: continue
            val endSlot = slotMap[c.endSection] ?: continue
            val start = combineDateAndTime(date, startSlot.startTime) ?: continue
            val end = combineDateAndTime(date, endSlot.endTime) ?: continue
            out.add(FocusSession(course = c, date = date, start = start, end = end))
        }
        out.sortBy { it.start }
        return out
    }

    /**
     * 开学日期解析；失败回退到「参考日所在周一」。
     *
     * 注意：回退基准必须由调用方按计算时刻（[computeNotice] 的 today）一次解析、
     * 9 天复用——与 Dart 的 Semester.startDateParsed（一次求值、DateTime.now() 为基准）
     * 同口径。不要对 sessionsOnDay 的每一天各传各的 reference，否则开学日期脏数据时
     * offset>0 的日期恒算第 1 周（Kimi 复审 Bug 2）。
     */
    fun startDate(semester: FocusSemester, reference: LocalDate): LocalDate {
        val raw = semester.startDate.trim()
        try {
            return LocalDate.parse(raw)
        } catch (_: Throwable) {
            // 落到下面继续尝试带时间的 ISO 串
        }
        try {
            return LocalDateTime.parse(raw).toLocalDate()
        } catch (_: Throwable) {
            return alignToMonday(reference)
        }
    }

    /** 把日期对齐到所在周的周一 */
    fun alignToMonday(date: LocalDate): LocalDate =
        date.minusDays((date.dayOfWeek.value - 1).toLong())

    /** 周次：开学前返回 0，开学当天所在周返回 1（与 WeekCalc.currentWeek 一致） */
    fun currentWeek(semesterStart: LocalDate, target: LocalDate): Int {
        val startMonday = alignToMonday(semesterStart)
        val diffDays = ChronoUnit.DAYS.between(startMonday, target).toInt()
        if (diffDays < 0) return 0
        return diffDays / 7 + 1
    }

    /** 该周是否上这门课（周次列表 + 单双周） */
    fun isActiveInWeek(course: FocusCourse, week: Int): Boolean {
        if (!course.weeks.contains(week)) return false
        return when (course.weekType) {
            1 -> week % 2 != 0
            2 -> week % 2 == 0
            else -> true
        }
    }

    /** 应用单次调课后 [week] 周的有效上课实例（停课移除、调课替换副本） */
    fun effectiveCoursesForWeek(
        courses: List<FocusCourse>,
        overrides: List<FocusOverride>,
        week: Int,
    ): List<FocusCourse> {
        val byCourse = HashMap<Int, FocusOverride>()
        for (o in overrides) {
            // 同一 (courseId, originalWeek) 至多一条；真有重复时后者覆盖前者
            if (o.originalWeek == week) byCourse[o.courseId] = o
        }
        val result = ArrayList<FocusCourse>(courses.size)
        for (c in courses) {
            val o = c.id?.let { byCourse[it] }
            // 课程该周本就不上课：override 无效，忽略
            if (o == null || !isActiveInWeek(c, week)) {
                result.add(c)
                continue
            }
            if (o.isCancellation) continue
            result.add(
                c.copy(
                    dayOfWeek = o.targetDayOfWeek ?: c.dayOfWeek,
                    startSection = o.targetStartSection ?: c.startSection,
                    endSection = o.targetEndSection ?: c.endSection,
                    // 教室为 null 表示沿用原教室
                    classroom = o.targetClassroom ?: c.classroom,
                )
            )
        }
        return result
    }

    /** 相对今天的日期标签：今天 / 明天 / 周X（M月D日），周一=1 … 周日=7 */
    fun dayLabel(date: LocalDate, today: LocalDate): String {
        val diff = ChronoUnit.DAYS.between(today, date)
        if (diff == 0L) return "今天"
        if (diff == 1L) return "明天"
        val names = arrayOf("一", "二", "三", "四", "五", "六", "日")
        return "周${names[date.dayOfWeek.value - 1]}（${date.monthValue}月${date.dayOfMonth}日）"
    }

    /** HH:mm 格式化 */
    fun fmtHhmm(t: LocalDateTime): String =
        "${t.hour.toString().padStart(2, '0')}:${t.minute.toString().padStart(2, '0')}"

    /**
     * "HH:mm" 文本解析；解析失败返回 null。
     * 越界值（如 "24:00"）按 Dart DateTime 的进位语义累加，保证两边结果一致。
     */
    fun combineDateAndTime(date: LocalDate, hhmm: String): LocalDateTime? {
        val parts = hhmm.split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        return date.atStartOfDay().plusHours(hour.toLong()).plusMinutes(minute.toLong())
    }

    /**
     * weeksJson 解析（防御）：非 JSON 数组 / 元素不是整数 / 空串一律按空列表处理，
     * 与 Dart 的 Course._parseWeeks 容错口径一致（解析失败不闪退、当没课）。
     */
    fun parseWeeks(json: String?): List<Int> {
        if (json.isNullOrEmpty()) return emptyList()
        val trimmed = json.trim()
        if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) return emptyList()
        val body = trimmed.substring(1, trimmed.length - 1).trim()
        if (body.isEmpty()) return emptyList()
        return try {
            body.split(",").map { it.trim().toInt() }
        } catch (_: Throwable) {
            // 含小数、引号、null 等非整数元素：整条按损坏处理（Dart 的 `e as int` 同样抛）
            emptyList()
        }
    }

    /** 「 · 教室」后缀；无教室返回空串 */
    private fun roomSuffix(course: FocusCourse): String {
        val room = course.classroom?.trim()
        return if (room != null && room.isNotEmpty()) " · $room" else ""
    }
}

/** 一次具体的课：某天的某门课，带确切起止时刻 */
class FocusSession(
    val course: FocusCourse,
    val date: LocalDate,
    val start: LocalDateTime,
    val end: LocalDateTime,
) {
    /** 「08:00–08:40」式时间段文本（与 Dart 一致用半角 en dash） */
    fun timeRange(): String =
        "${OngoingFocusCalculator.fmtHhmm(start)}–${OngoingFocusCalculator.fmtHhmm(end)}"
}

/** 学期（纯数据）：只保留算焦点用得到的字段 */
data class FocusSemester(
    val name: String,
    val startDate: String,
    val totalWeeks: Int,
)

/** 课程（纯数据）：对应 courses 表里算焦点用得到的列 */
data class FocusCourse(
    val id: Int?,
    val name: String,
    val classroom: String?,
    val dayOfWeek: Int,
    val startSection: Int,
    val endSection: Int,
    val weeks: List<Int>,
    val weekType: Int,
)

/** 节次时间（纯数据）：对应 time_slots 表 */
data class FocusTimeSlot(
    val section: Int,
    val startTime: String,
    val endTime: String,
)

/** 单次调课（纯数据）：对应 course_overrides 表 */
data class FocusOverride(
    val courseId: Int,
    val originalWeek: Int,
    val targetWeek: Int,
    val targetDayOfWeek: Int? = null,
    val targetStartSection: Int? = null,
    val targetEndSection: Int? = null,
    val targetClassroom: String? = null,
) {
    /** targetWeek == -1 表示停课 */
    val isCancellation: Boolean get() = targetWeek == CANCEL_FLAG

    companion object {
        const val CANCEL_FLAG: Int = -1
    }
}
