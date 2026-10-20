# 内置字体（不随仓库分发）

界面设置可切换的两款字体体积较大（霞鹜文楷全字库约 26 MB），不进 git；
本地与 CI 构建时放入本目录即可（文件名必须一致）：

- LXGWWenKai-Regular.ttf — 霞鹜文楷 v1.530（SIL OFL 1.1 开源）
  https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf
- ZCOOLKuaiLe-Regular.ttf — 站酷快乐体（免费商用，经 Google Fonts 分发）
  https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf

GitHub Actions 的 build-apk 工作流有「下载内置字体」步骤自动完成；
本地打包前手动下载这两个文件到本目录。
