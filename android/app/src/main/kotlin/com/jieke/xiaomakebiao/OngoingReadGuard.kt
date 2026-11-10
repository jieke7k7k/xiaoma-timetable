package com.jieke.xiaomakebiao

/**
 * 单表读取的防御包装（WB_SPEC_229 第 4.1 节「读不到不闪退」）
 *
 * 表缺失（旧版本库还没建这张表）、列改名、游标异常，一律降级成空结果，
 * 不让一张表拖垮整条常驻通知链——通知最多停在上一版文案，绝不闪退、绝不写库。
 *
 * 单独成文件、日志由调用方以 [onError] 注入，而不是在这里直接打 android.util.Log：
 * 这样「读表抛异常 → 空结果」这条防御分支可以在纯 JVM 单测里跑
 * （Android 的 Log 在单测里是抛异常的空桩）。
 */
internal inline fun <T> readOrEmpty(
    tag: String,
    onError: (String, Throwable) -> Unit,
    block: () -> List<T>,
): List<T> = try {
    block()
} catch (t: Throwable) {
    onError(tag, t)
    emptyList()
}
