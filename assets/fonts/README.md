# 内置字体（不随仓库分发）

界面设置可切换的四款字体体积较大（霞鹜文楷全字库约 26 MB），不进 git；
本地与 CI 构建时放入本目录即可（文件名必须一致）：

- LXGWWenKai-Regular.ttf — 霞鹜文楷 v1.530（SIL OFL 1.1 开源）
  https://github.com/lxgw/LxgwWenKai/releases/download/v1.530/LXGWWenKai-Regular.ttf
- ZCOOLKuaiLe-Regular.ttf — 站酷快乐体（免费商用，经 Google Fonts 分发）
  https://raw.githubusercontent.com/google/fonts/main/ofl/zcoolkuaile/ZCOOLKuaiLe-Regular.ttf

- SmileySans.ttf — 得意黑 Smiley Sans v2.0.1（免费商用），取发行 zip 内的 SmileySans-Oblique.ttf 改名
  https://github.com/atelier-anchor/smiley-sans/releases/download/v2.0.1/smiley-sans-v2.0.1.zip
- NotoSansSC.ttf — 思源黑体 Noto Sans SC 可变字体（SIL OFL 1.1 开源）
  https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf

GitHub Actions 的 build-apk 工作流有「下载内置字体」步骤自动完成；
本地打包前手动下载这四个文件到本目录。
