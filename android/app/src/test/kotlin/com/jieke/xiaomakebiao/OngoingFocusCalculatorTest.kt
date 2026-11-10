package com.jieke.xiaomakebiao

import java.io.File
import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 今日课程常驻通知焦点计算的纯 JVM 单测（WB_SPEC_229 第 4.4 节）
 *
 * 只测 [OngoingFocusCalculator] 这块纯逻辑，不碰任何 Android 框架类（不引 Robolectric）。
 * 夹具与 Dart 侧共用同一份文件 test/fixtures/ongoing_focus_cases.json：
 * Dart 侧 test/ongoing_focus_fixture_test.dart 断言的 expected 与本文件逐字相同，
 * 两边跑绿才算「App 被杀后原生算出来的通知与 App 内说法完全一致」。
 *
 * 覆盖：上课中 / 课间 / 午休 / 晚上 / 周末 / 假期 / 停课当天 / 调课当天 /
 * 单周 / 双周 / 学期外（开学前 + 学期结束）/ 课表为空 / 当天最后一节；
 * 另加三条防御分支（weeksJson 损坏、读表抛异常、开关关 / 无学期）。
 */
class OngoingFocusCalculatorTest {

    private val fixture = Fixture.load()

    // ---------- 共享夹具：文案 + 边界点 ----------

    @Test
    fun `夹具覆盖了规格要求的全部场景`() {
        val names = fixture.cases.map { it.name }
        // 场景名里的关键词就是验收清单，少一个都别打包
        val mustContain = listOf("上课中", "课间", "午休", "晚上", "周末", "假期",
            "停课当天", "调课当天", "单周", "双周", "学期外", "课表为空")
        for (key in mustContain) {
            assertTrue("夹具缺少场景：$key", names.any { it.contains(key) })
        }
    }

    @Test
    fun `逐字等价 Dart 的文案与边界点`() {
        for (case in fixture.cases) {
            val notice = OngoingFocusCalculator.computeNotice(
                now = case.now,
                semester = fixture.semester,
                courses = case.courses ?: fixture.courses,
                timeSlots = fixture.timeSlots,
                overrides = fixture.overrides,
            )
            assertEquals("[${case.name}] 标题不一致", case.expectedTitle, notice.title)
            assertEquals("[${case.name}] 行文案不一致", case.expectedLines, notice.lines)
            assertEquals(
                "[${case.name}] 边界点不一致",
                case.expectedBoundary,
                Fixture.format(notice.boundary),
            )
        }
    }

    // ---------- 防御分支 ----------

    @Test
    fun `开关关闭时不起通知也不排链`() {
        val decision = OngoingFocusCalculator.decide(
            enabled = false,
            semester = fixture.semester,
            now = LocalDateTime.parse("2026-09-07T08:20"),
            courses = fixture.courses,
            timeSlots = fixture.timeSlots,
            overrides = fixture.overrides,
        )
        assertTrue(decision is OngoingFocusCalculator.Decision.Disabled)
    }

    @Test
    fun `无当前学期（读库失败同样落到这里）时取消通知不排链`() {
        val decision = OngoingFocusCalculator.decide(
            enabled = true,
            semester = null,
            now = LocalDateTime.parse("2026-09-07T08:20"),
            courses = emptyList(),
            timeSlots = emptyList(),
            overrides = emptyList(),
        )
        assertTrue(decision is OngoingFocusCalculator.Decision.NoSemester)
    }

    @Test
    fun `weeksJson 损坏时按没课处理而不是抛异常`() {
        // 正常 JSON 数组
        assertEquals(listOf(1, 2, 3), OngoingFocusCalculator.parseWeeks("[1,2,3]"))
        assertEquals(listOf(1, 2, 3), OngoingFocusCalculator.parseWeeks(" [1, 2, 3] "))
        // 空数组 / 空串 / null
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("[]"))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks(""))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks(null))
        // 损坏：不是数组 / 元素不是整数 / 半截括号
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("not json"))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("[1,x,3]"))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("[1,2.5]"))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("[1,2,"))
        assertEquals(emptyList<Int>(), OngoingFocusCalculator.parseWeeks("{\"weeks\":[1]}"))
    }

    @Test
    fun `表缺失导致读表抛异常时降级为空结果`() {
        var reported: String? = null
        val rows = readOrEmpty<String>("course_overrides", { tag, _ -> reported = tag }) {
            throw IllegalStateException("no such table: course_overrides")
        }
        assertEquals(emptyList<String>(), rows)
        assertEquals("course_overrides", reported)
    }

    @Test
    fun `没有 time_slots 对应节次时该课次被跳过`() {
        // 节次表只有第 1 节；课程排在第 5 节 -> 找不到节次时间，当天无课次
        val semester = FocusSemester("默认学期", "2026-09-07", 20)
        val courses = listOf(
            FocusCourse(1, "高等数学", "A101", 1, 5, 5, listOf(1), 0),
        )
        val slots = listOf(FocusTimeSlot(1, "08:00", "08:40"))
        val sessions = OngoingFocusCalculator.sessionsOnDay(
            java.time.LocalDate.parse("2026-09-07"), semester, courses, slots, emptyList(),
            OngoingFocusCalculator.startDate(semester, java.time.LocalDate.parse("2026-09-07")),
        )
        assertEquals(0, sessions.size)
    }

    @Test
    fun `开学日期脏数据时回退到本周一且 9 天复用`() {
        // Kimi 复审 Bug 2 的回归测试：startDate 解析失败时，Dart 回退到「今天所在周一」
        // 一次求值、9 天复用；旧 Kotlin 代码按被评估日逐日回退，offset>0 的日期恒算第 1 周，
        // 第 2 周才有的课永远算不出来（会误判成「暂无课程安排」）。
        val semester = FocusSemester("脏数据学期", "", 20)
        val courses = listOf(
            FocusCourse(1, "高等数学", "A101", 1, 1, 2, listOf(2), 0),
        )
        val notice = OngoingFocusCalculator.computeNotice(
            now = LocalDateTime.parse("2026-09-07T08:20"),
            semester = semester,
            courses = courses,
            timeSlots = fixture.timeSlots,
            overrides = emptyList(),
        )
        // 2026-09-07 是周一：回退到本周一后，本周是第 1 周，下周一（9 月 14 日）是第 2 周
        assertEquals("下一节：高等数学", notice.title)
        assertEquals(listOf("周一（9月14日） 08:00–09:30 · A101"), notice.lines)
        assertEquals("2026-09-14 08:00", Fixture.format(notice.boundary))
    }

    // ---------- 夹具读取 ----------

    private class Case(
        val name: String,
        val now: LocalDateTime,
        val expectedTitle: String,
        val expectedLines: List<String>,
        val expectedBoundary: String,
        val courses: List<FocusCourse>?,
    )

    private class Fixture(
        val semester: FocusSemester,
        val timeSlots: List<FocusTimeSlot>,
        val courses: List<FocusCourse>,
        val overrides: List<FocusOverride>,
        val cases: List<Case>,
    ) {
        companion object {
            fun load(): Fixture {
                val file = fixtureFile()
                val json = Json.parse(file.readText()) as Map<*, *>
                val semesterJson = json["semester"] as Map<*, *>
                val defaultCourses = coursesOf(json["courses"] as List<*>)
                return Fixture(
                    semester = FocusSemester(
                        name = semesterJson["name"] as String,
                        startDate = semesterJson["startDate"] as String,
                        totalWeeks = (semesterJson["totalWeeks"] as Number).toInt(),
                    ),
                    timeSlots = (json["timeSlots"] as List<*>).map { row ->
                        val m = row as Map<*, *>
                        FocusTimeSlot(
                            section = (m["section"] as Number).toInt(),
                            startTime = m["startTime"] as String,
                            endTime = m["endTime"] as String,
                        )
                    },
                    courses = defaultCourses,
                    overrides = (json["overrides"] as List<*>).map { row ->
                        val m = row as Map<*, *>
                        FocusOverride(
                            courseId = (m["courseId"] as Number).toInt(),
                            originalWeek = (m["originalWeek"] as Number).toInt(),
                            targetWeek = (m["targetWeek"] as Number).toInt(),
                            targetDayOfWeek = (m["targetDayOfWeek"] as Number?)?.toInt(),
                            targetStartSection = (m["targetStartSection"] as Number?)?.toInt(),
                            targetEndSection = (m["targetEndSection"] as Number?)?.toInt(),
                            targetClassroom = m["targetClassroom"] as String?,
                        )
                    },
                    cases = (json["cases"] as List<*>).map { row ->
                        val m = row as Map<*, *>
                        val expected = m["expected"] as Map<*, *>
                        val ownCourses = m["courses"] as List<*>?
                        Case(
                            name = m["name"] as String,
                            now = parseTime(m["now"] as String),
                            expectedTitle = expected["title"] as String,
                            expectedLines = (expected["lines"] as List<*>).map { l -> l as String },
                            expectedBoundary = expected["boundary"] as String,
                            courses = ownCourses?.let { c -> coursesOf(c) } ?: defaultCourses,
                        )
                    },
                )
            }

            private fun coursesOf(list: List<*>): List<FocusCourse> = list.map { row ->
                val m = row as Map<*, *>
                FocusCourse(
                    id = (m["id"] as Number?)?.toInt(),
                    name = m["name"] as String,
                    classroom = m["classroom"] as String?,
                    dayOfWeek = (m["dayOfWeek"] as Number).toInt(),
                    startSection = (m["startSection"] as Number).toInt(),
                    endSection = (m["endSection"] as Number).toInt(),
                    weeks = (m["weeks"] as List<*>).map { w -> (w as Number).toInt() },
                    weekType = (m["weekType"] as Number).toInt(),
                )
            }

            /** 'yyyy-MM-dd HH:mm'（东八区墙上时间） */
            fun parseTime(text: String): LocalDateTime =
                LocalDateTime.parse(text.replace(' ', 'T'))

            fun format(t: LocalDateTime): String = buildString {
                append(t.year.toString().padStart(4, '0')).append('-')
                append(t.monthValue.toString().padStart(2, '0')).append('-')
                append(t.dayOfMonth.toString().padStart(2, '0')).append(' ')
                append(t.hour.toString().padStart(2, '0')).append(':')
                append(t.minute.toString().padStart(2, '0'))
            }

            /**
             * 夹具路径：Android 单元测试的工作目录是模块目录（android/app），
             * 从仓库根被外部工具直接跑时是仓库根——两处都试一遍，找不到就让测试红。
             */
            private fun fixtureFile(): File {
                val rel = "test/fixtures/ongoing_focus_cases.json"
                val candidates = listOf(
                    File(rel),
                    File("../../$rel"),
                    File("../$rel"),
                    File(".").absoluteFile.parentFile?.let { File(it, rel) },
                )
                val found = candidates.filterNotNull().firstOrNull { it.exists() }
                assertNotNull(
                    "找不到共享夹具 $rel（试过：${candidates.joinToString()}），" +
                        "请从仓库根或 android/app 目录运行测试",
                    found,
                )
                return found!!
            }
        }
    }
}

/**
 * 极简 JSON 解析（仅测试用，~100 行）
 *
 * 为什么不用 org.json / Gson：前者在 JVM 单测里是抛异常的 Android 空桩，后者要新增
 * 测试依赖（WB_SPEC_229 明确不加新依赖）。夹具只用到「对象 / 数组 / 字符串 / 整数 /
 * true / false / null」，一个递归下降解析器足够，且零依赖、行为可预期。
 */
private object Json {
    fun parse(text: String): Any? = Parser(text).parseValue()

    private class Parser(private val s: String) {
        private var i = 0

        fun parseValue(): Any? {
            skipWs()
            return when (val c = peek()) {
                '{' -> parseObject()
                '[' -> parseArray()
                '"' -> parseString()
                't' -> { expect("true"); true }
                'f' -> { expect("false"); false }
                'n' -> { expect("null"); null }
                else -> {
                    require(c == '-' || c.isDigit()) { "非法 JSON 字符：$c（位置 $i）" }
                    parseNumber()
                }
            }
        }

        private fun parseObject(): Map<String, Any?> {
            val map = LinkedHashMap<String, Any?>()
            expect("{")
            skipWs()
            if (peek() == '}') { i++; return map }
            while (true) {
                skipWs()
                val key = parseString()
                skipWs()
                expect(":")
                map[key] = parseValue()
                skipWs()
                when (peek()) {
                    ',' -> i++
                    '}' -> { i++; return map }
                    else -> throw IllegalArgumentException("对象缺少 , 或 }（位置 $i）")
                }
            }
        }

        private fun parseArray(): List<Any?> {
            val list = ArrayList<Any?>()
            expect("[")
            skipWs()
            if (peek() == ']') { i++; return list }
            while (true) {
                list.add(parseValue())
                skipWs()
                when (peek()) {
                    ',' -> i++
                    ']' -> { i++; return list }
                    else -> throw IllegalArgumentException("数组缺少 , 或 ]（位置 $i）")
                }
            }
        }

        private fun parseString(): String {
            expect("\"")
            val sb = StringBuilder()
            while (true) {
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> when (val e = s[i++]) {
                        '"' -> sb.append('"')
                        '\\' -> sb.append('\\')
                        '/' -> sb.append('/')
                        'b' -> sb.append('\b')
                        'f' -> sb.append('\u000C')
                        'n' -> sb.append('\n')
                        'r' -> sb.append('\r')
                        't' -> sb.append('\t')
                        'u' -> {
                            sb.append(s.substring(i, i + 4).toInt(16).toChar())
                            i += 4
                        }
                        else -> throw IllegalArgumentException("非法转义 \\$e")
                    }
                    else -> sb.append(c)
                }
            }
        }

        private fun parseNumber(): Number {
            val start = i
            if (peek() == '-') i++
            while (i < s.length && (s[i].isDigit() || s[i] == '.' || s[i] == 'e' || s[i] == 'E' || s[i] == '+' || s[i] == '-')) i++
            val raw = s.substring(start, i)
            return raw.toLongOrNull() ?: raw.toDouble()
        }

        private fun expect(token: String) {
            require(s.startsWith(token, i)) { "期望 $token（位置 $i）" }
            i += token.length
        }

        private fun peek(): Char {
            require(i < s.length) { "JSON 提前结束（位置 $i）" }
            return s[i]
        }

        private fun skipWs() {
            while (i < s.length && s[i].isWhitespace()) i++
        }
    }
}
