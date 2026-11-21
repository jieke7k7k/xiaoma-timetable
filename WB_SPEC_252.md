# WB_SPEC_252 — App 内直接下载新版安装包，不跳浏览器

> 来源：他 2026-11-22 00:44 提「支持软件里直接下载新版本安装包，不要跳转链接」；00:45 补充「不要用云盘链接，不是所有人都有 vpn，要有不用 vpn 就能下载的方式」。
>
> 现状已查实（`lib/pages/about_page.dart` 约 100–133 行 + `lib/services/channel_service.dart`）：更新弹窗「去下载」走 `_launch(latest.downloadUrl)` → `launchUrl(uri, mode: LaunchMode.externalApplication)`，即系统浏览器打开云盘链接；「更新说明」同样外跳到 `releaseUrl`。AndroidManifest 无 `REQUEST_INSTALL_PACKAGES`、无 FileProvider；pubspec 无 dio/open_file。
>
> Neon 审规格（2026-11-22 02:12，云端对话）：指出 7 类缺口，已全部补进本版（见 §2/§3/§5 的「Neon 补」标注）；另核实：下载入口只有一个（见 §2 入口说明），与 Neon 的担心相反——主页横幅只跳到关于页，不直接下载。

## §0 目标

- 点「去下载」，安装包直接在 App 里下载，全程不跳浏览器。
- 下载源必须不用 vpn 就能下：**不用云盘链接**。

## §1 下载源：GitHub Releases，不用云盘

- `channel.json` 的 `downloadUrl` 改指 GitHub Release 的安装包直链（随版本发布时更新），不再指云盘文件。
- 理由：通道本身已从 `raw.githubusercontent.com` 拉取（App 内更新检查就走这条路，不用 vpn 也能通）；Release 安装包与通道同属 GitHub 域名族，同一可达性。云盘文件继续上传（手动分享/备份用），不再挂在更新链路上。
- 副作用（正面的）：2.10.0 云盘文件公开权限卡超时导致「App 内更新打不开」的问题，换源后不再阻塞更新——更新不再依赖云盘权限。
- 发布流程随之改：CI 出包后 `gh release create` 附安装包，再把 `downloadUrl` 指到该 Release 资产；通道其余字段不动。
- **Neon 补（可达性风险，先记下来）**：`github.com/.../releases/download/...` 会 302 到 `objects.githubusercontent.com`（AWS S3 / Fastly CDN），三个域名在移动宽带/校园网下的可达性与限速经常不一致。验收「断开 vpn 能下完」保留，但要先实测（移动数据与家庭宽带各测一次，均关 vpn）；若实测被阻断，代码修不了，后续版本在 channel.json 预留镜像源字段，本版不做。

## §2 下载与安装流程

- **入口（唯一）**：下载入口只有一个——`lib/pages/about_page.dart` `_showUpdateDialog`（91 行起）里的「去下载」按钮。主页周视图的更新横幅（`week_view_page.dart` 约 924–937 行）点「去看看」只是 `Navigator.pushNamed(context, '/about')`，不直接下载；20 小时静默检查（`ChannelService.shouldSilentCheck`，`channel_service.dart:172`）只拉取通道数据、不弹更新弹窗。本次只改 `_showUpdateDialog` 的「去下载」动作，别处不用动。
- 点「去下载」后，弹窗内（或独立下载行）显示下载进度条 + 百分比 + 已下/总量；下载走 `HttpClient`（`channel_service.dart` 已有同款用法），跟随重定向（GitHub Release 直链会 302 到对象存储域名）。
- **Neon 补（实现路线定死）**：零新增 pub 依赖——`HttpClient` + `path_provider` + 手写 `MethodChannel` 调原生安装器，不引入 dio/open_file 等第三方插件。
- 下载完成自动调起系统安装确认；用户点安装即走系统安装流程（首次会弹系统「允许安装未知应用」授权，按系统流程走，App 内只做引导文案，不绕过）。
- **Neon 补（授权回流）**：Android 8.0+ 首次调用 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` 跳去系统设置，用户开启后按返回回到 App，系统不会自动继续安装——在 App `onResume`（`WidgetsBindingObserver.didChangeAppLifecycleState`）里自动复检 `canRequestPackageInstalls()` 并继续调起安装；若复检仍未授权，弹窗里明确保留「立即安装」按钮。
- 失败（无网、超时、下载中断）时不跳浏览器、不静默失败：显示失败原因 + 「重试」按钮；取消下载则停在原弹窗，可再点「去下载」。
- **Neon 补（切后台不断开）**：下载只在前台跑（本版不做 Foreground Service / 不做后台下载），但切后台回来进度不断：用 `.part` 文件 + `Range` 断点续传，`AppLifecycleState.resumed` 时自动静默续下。Android 14+（尤其 HyperOS / MIUI 的后台网络冻结）切后台几秒就可能挂起或重置前台 HttpClient 的 TCP socket，仅靠普通 HttpClient 会抛 SocketException，所以续传是必选项，不是可选项。
- **Neon 补（断点续传边界）**：续传时给初始 URL（github.com）带 `Range` 头，HttpClient 自动跟随 302 到对象存储时可能保留该头；若对象存储返回 **416 Range Not Satisfiable**（本地 .part 损坏或比新包还大），必须删掉 .part 从头重下，不能只认 200/206 否则永久报错卡死。
- **Neon 补（Content-Length 缺失）**：`contentLength == -1` 时进度条不能除以 -1（负数/NaN），降级为不确定进度条 + 只显示已下载大小。
- **Neon 补（磁盘满）**：下载中 `IOSink` 写满抛 `FileSystemException`，捕获后提示「存储空间不足」，同时清理残余 .part。
- **Neon 补（误触）**：下载中弹窗设 `barrierDismissible: false` 并拦截 `PopScope`，防止点弹窗外或按物理返回键把下载变成孤儿任务；连续点「去下载」不得重复开两个下载任务。
- **Neon 补（同版本重复下载）**：上次下载完但用户取消了系统安装，再次点「去下载」时先检查缓存里是否已有完整同版本 APK，有则直接调起安装，不重复耗流量。
- **Neon 补（完整性校验）**：落盘前校验 `receivedBytes == totalBytes`（当 totalBytes > 0）以及 APK ZIP 魔数（前两字节 `0x50 0x4B`，即 PK）；校验失败按下载失败处理（提示 + 重试），不要直接调安装器让用户看到「解析软件包时出现问题」。channel.json 本版不加 sha256 字段。

## §3 需要补的东西

- AndroidManifest：加 `REQUEST_INSTALL_PACKAGES` 权限；加 FileProvider（`android:authorities` + `file_paths.xml`，安装包放缓存目录经 FileProvider 分享给安装器）。
- **Neon 补（FileProvider 细节）**：authorities 必须用 `${applicationId}.fileprovider`（对应 `com.jieke.xiaomakebiao.fileprovider`）；若工程里已有其他库（如 share_plus、image_picker）注册了 `androidx.core.content.FileProvider`，Manifest 合并会报错，需自定义子类或 `tools:replace`，先跑一次 `assembleDebug` 验证 Manifest 合并。`file_paths.xml` 必须配 `<cache-path>`（Flutter 的 `getTemporaryDirectory()` 在 Android 对应 `context.cacheDir`）；误配成 `<files-path>` 或 `<external-cache-path>` 时 `FileProvider.getUriForFile()` 直接抛 `IllegalArgumentException: Failed to find configured root`。
- **Neon 补（安装 Intent 细节）**：Action 用 `Intent.ACTION_VIEW`（比已废弃的 `ACTION_INSTALL_PACKAGE` 兼容性更稳）；MIME Type 必须是 `application/vnd.android.package-archive`；Flags 必须同时加 `FLAG_ACTIVITY_NEW_TASK` 和 `FLAG_GRANT_READ_URI_PERMISSION`（漏了后者在 Android 7.0+ 会报 SecurityException 或安装器闪退）；禁止在 Intent 中直接传 `file://` URI（Android 7.0+ 抛 `FileUriExposedException`）。
- 下载文件落盘：App 缓存目录（`apk_updates/` 子目录），文件名带版本号避免与旧包混淆。
- **Neon 补（缓存清理时机）**：下次 App 启动且当前版本号 >= 缓存 APK 版本号时，或发起新版本下载前，清理 `apk_updates/` 下的旧 .apk / .part。系统安装器是异步外部进程，App 无法直接得知用户最终点了「安装」还是「取消」，所以不在安装后立即清。
- 「更新说明」按钮不动：仍外跳 GitHub Release 页看文字说明（只是看文字，他只要求下载不跳链接）。

## §4 不动项

- 通道检查逻辑（`ChannelService.fetch`、20 小时静默检查、已读/已关状态）不动。
- `releaseUrl` 字段保留（更新说明用）。
- 云盘上传流程不动（仍传安装包做手动分享/备份，只是不再是更新下载源）。

## §5 验收

1. 点「去下载」，不打开任何浏览器，App 内出现下载进度，完成后弹出系统安装确认。
2. 下载源是 GitHub Release 直链（`channel.json` 里 `downloadUrl` 不再是云盘链接）；断开 vpn 的环境下能正常下完（与通道拉取同款可达性）。**实测要求**：移动数据与家庭宽带各测一次，均关 vpn（Neon 提醒 objects.githubusercontent.com 可达性可能与 raw.githubusercontent.com 不一致）。
3. 下载失败有明确提示 + 重试；取消后可重新下载。
4. 首次安装弹系统「允许安装未知应用」授权时有引导文案；授权后能继续安装（回 App 自动复检继续，或点「立即安装」）。
5. 测试：下载进度回调测试（mock HttpClient）；`parseChannel` 对新 `downloadUrl` 的解析回归；安装 intent 构造测试（FileProvider URI 格式）。
6. **Neon 补（测试缺口）**：302 重定向跟随测试（mock 一次 302 跳转再返回字节流）；失败与取消路径测试（断网/非 200 状态码报错、取消后状态复位且可重新下载）；断点续传 / 416 恢复测试（已有 .part 文件时带 Range 请求，416 后删 .part 重下）；权限未授予时的 UI 引导态 widget 测试（mock `canRequestPackageInstalls` 返回 false 时显示引导文案而非直接报错）。

## §6 版本

- **2.11.0（+47）**，与 249 / 247 / 253 同版发（版本号只升一次，发版时统一改）。
