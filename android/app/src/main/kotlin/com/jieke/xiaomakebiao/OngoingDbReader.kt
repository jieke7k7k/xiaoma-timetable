package com.jieke.xiaomakebiao

import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.util.Log

/**
 * 原生只读库层（WB_SPEC_229 第 4.1 节）：只负责把 SQLite 行读成纯数据类，
 * 一行计算都不做。
 *
 * 库路径必须走 [Context.getDatabasePath]：sqflite（lib/database/db_helper.dart 的
 * `_dbName = 'simple_timetable.db'`）把库放在 /data/data/<包名>/databases/ 下，
 * 不是 app_flutter/ 之类的目录——凭猜测拼路径会读不到。
 *
 * 三条硬约束：
 * 1. 只读打开（OPEN_READONLY），原生侧永不写库；
 * 2. 读不到 / 库损坏 / 表缺失一律返回空结果并打日志，绝不闪退；
 * 3. 表名与列名以 lib/database/db_helper.dart 的建表语句为准（v7）。
 *
 * 读库层不进 JVM 单测（WB_SPEC_229 第 4.4 节），靠真机验收覆盖；其中可以纯逻辑化的
 * 防御分支（weeksJson 损坏、表缺失异常）已在 [OngoingFocusCalculator.parseWeeks]
 * 与 OngoingReadGuard.kt 的 readOrEmpty 上单独写测试。
 */
object OngoingDbReader {

    private const val TAG = "OngoingDbReader"

    /** 库文件名，与 db_helper 的 _dbName 必须一致 */
    const val DB_NAME = "simple_timetable.db"

    /**
     * 一次读库的结果。
     *
     * [enabled] 为 app_settings.ongoing_enabled（缺失按开）；[semester] 为 null 表示
     * 没有当前学期——此时 Receiver 取消通知、不排链，与 Flutter 侧 refresh() 兜底一致。
     */
    class Snapshot(
        val enabled: Boolean,
        val semester: FocusSemester?,
        val courses: List<FocusCourse>,
        val slots: List<FocusTimeSlot>,
        val overrides: List<FocusOverride>,
    )

    /**
     * 读一次库。返回 null 表示库文件不存在或整体读取失败（Receiver 遇到 null 一律
     * 取消通知并停链，等下次 App 打开重建）。
     */
    fun read(context: Context): Snapshot? = try {
        val file = context.getDatabasePath(DB_NAME)
        if (file == null || !file.exists()) {
            Log.w(TAG, "库文件不存在（App 尚未创建数据库？），本轮跳过常驻通知刷新")
            null
        } else {
            SQLiteDatabase.openDatabase(
                file.absolutePath,
                null,
                SQLiteDatabase.OPEN_READONLY,
            ).use { db ->
                val enabled = readOngoingEnabled(db)
                val current = readCurrentSemester(db)
                if (current == null) {
                    Log.i(TAG, "没有当前学期，本轮不排链")
                    Snapshot(enabled, null, emptyList(), emptyList(), emptyList())
                } else {
                    Snapshot(
                        enabled = enabled,
                        semester = current.semester,
                        courses = readCourses(db, current.id),
                        slots = readSlots(db),
                        overrides = readOverrides(db, current.id),
                    )
                }
            }
        }
    } catch (t: Throwable) {
        // 库损坏 / 被占用 / 权限异常：只记日志，绝不向上抛（Receiver 里抛会闪退）
        Log.w(TAG, "读取数据库失败，本轮跳过常驻通知刷新", t)
        null
    }

    /** 读表失败（表缺失 / 列改名 / 游标异常）统一日志出口 */
    private fun logReadFailure(tag: String, t: Throwable) {
        Log.w(TAG, "读取 $tag 失败，按空结果处理", t)
    }

    /** ongoing_enabled：缺失按开；'1' / 'true' 为开；其余为关（与 Dart getSettingBool 一致） */
    private fun readOngoingEnabled(db: SQLiteDatabase): Boolean {
        val rows = readOrEmpty("app_settings", ::logReadFailure) {
            db.rawQuery(
                "SELECT value FROM app_settings WHERE key = ? LIMIT 1",
                arrayOf("ongoing_enabled"),
            ).use { c -> if (c.moveToFirst()) listOf(c.getStringOrNull(0)) else emptyList() }
        }
        val value = rows.firstOrNull()
        if (value == null) return true
        return value == "1" || value.equals("true", ignoreCase = true)
    }

    private class SemesterRow(val id: Int, val semester: FocusSemester)

    private fun readCurrentSemester(db: SQLiteDatabase): SemesterRow? {
        val rows = readOrEmpty("semesters", ::logReadFailure) {
            db.rawQuery(
                "SELECT id, name, startDate, totalWeeks FROM semesters " +
                    "WHERE isCurrent = 1 LIMIT 1",
                null,
            ).use { c ->
                if (!c.moveToFirst()) {
                    emptyList()
                } else {
                    listOf(
                        SemesterRow(
                            id = c.getInt(0),
                            semester = FocusSemester(
                                name = c.getStringOrNull(1) ?: "",
                                startDate = c.getStringOrNull(2) ?: "",
                                // 与 Dart 的 (totalWeeks ?? 20).clamp(1, 30) 同口径
                                totalWeeks = (c.getIntOrNull(3) ?: 20).coerceIn(1, 30),
                            ),
                        )
                    )
                }
            }
        }
        return rows.firstOrNull()
    }

    private fun readCourses(db: SQLiteDatabase, semesterId: Int): List<FocusCourse> =
        readOrEmpty("courses", ::logReadFailure) {
            db.rawQuery(
                "SELECT id, name, classroom, dayOfWeek, startSection, endSection, " +
                    "weeksJson, weekType FROM courses WHERE semesterId = ?",
                arrayOf(semesterId.toString()),
            ).use { c ->
                buildList {
                    while (c.moveToNext()) {
                        add(
                            FocusCourse(
                                id = c.getIntOrNull(0),
                                name = c.getStringOrNull(1) ?: "",
                                classroom = c.getStringOrNull(2),
                                dayOfWeek = c.getIntOrNull(3) ?: 0,
                                startSection = c.getIntOrNull(4) ?: 0,
                                endSection = c.getIntOrNull(5) ?: 0,
                                // weeksJson 损坏按空列表处理（与 Dart 的 _parseWeeks 容错一致）
                                weeks = OngoingFocusCalculator.parseWeeks(c.getStringOrNull(6)),
                                weekType = c.getIntOrNull(7) ?: 0,
                            )
                        )
                    }
                }
            }
        }

    private fun readSlots(db: SQLiteDatabase): List<FocusTimeSlot> =
        readOrEmpty("time_slots", ::logReadFailure) {
            db.rawQuery(
                "SELECT section, startTime, endTime FROM time_slots",
                null,
            ).use { c ->
                buildList {
                    while (c.moveToNext()) {
                        add(
                            FocusTimeSlot(
                                section = c.getIntOrNull(0) ?: 0,
                                startTime = c.getStringOrNull(1) ?: "",
                                endTime = c.getStringOrNull(2) ?: "",
                            )
                        )
                    }
                }
            }
        }

    /** 只取当前学期的调课记录：按课程反查学期，与 Dao.getOverridesBySemester 的联表口径一致 */
    private fun readOverrides(db: SQLiteDatabase, semesterId: Int): List<FocusOverride> =
        readOrEmpty("course_overrides", ::logReadFailure) {
            db.rawQuery(
                "SELECT o.courseId, o.originalWeek, o.targetWeek, o.targetDayOfWeek, " +
                    "o.targetStartSection, o.targetEndSection, o.targetClassroom " +
                    "FROM course_overrides o INNER JOIN courses c ON o.courseId = c.id " +
                    "WHERE c.semesterId = ?",
                arrayOf(semesterId.toString()),
            ).use { c ->
                buildList {
                    while (c.moveToNext()) {
                        add(
                            FocusOverride(
                                courseId = c.getIntOrNull(0) ?: 0,
                                originalWeek = c.getIntOrNull(1) ?: 0,
                                targetWeek = c.getIntOrNull(2) ?: FocusOverride.CANCEL_FLAG,
                                targetDayOfWeek = c.getIntOrNull(3),
                                targetStartSection = c.getIntOrNull(4),
                                targetEndSection = c.getIntOrNull(5),
                                targetClassroom = c.getStringOrNull(6),
                            )
                        )
                    }
                }
            }
        }
}

/** 列可能为 NULL 时安全读取（getString 遇 NULL 会返回 null 但 getInt 会返回 0，无法区分） */
internal fun Cursor.getStringOrNull(index: Int): String? =
    if (isNull(index)) null else getString(index)

internal fun Cursor.getIntOrNull(index: Int): Int? =
    if (isNull(index)) null else getInt(index)
