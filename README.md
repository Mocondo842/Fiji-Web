# Fiji-Web — 基于 web 浏览的 Fiji/ImageJ 与快捷插件工程

一台部署机 + 局域网多设备浏览器访问的 ImageJ 方案，配套双端（web/桌面）共用宏库与快捷化体系。
**当前轨道（2026-10-26）：分支 B「本地 Fiji 先行」已四轮收口并通过用户验收**；主线 web 侧完成至 R4' 终裁（留守 CJ2），R5–R8 后移保留。

## 仓库结构

| 路径 | 内容 |
| :-- | :-- |
| `技术文档-基于web浏览的Fiji和快捷插件添加工程-v1.md` | 主线技术文档（**v1.8**，V1–V15、规则 R1–R10、验收 S1–S5、§15 修订记录 8 版） |
| `PM-分支-本地Fiji先行-v1.md` | **分支 B PM 文件**（BG1–BG4 / BR1–BR8 / BS1–BS5 / §9 action-bar+常用宏功能 / 轮次 B1–B4）——已验收 |
| `轮次路线图-v1.md` | 主线+分支统一轮次状态表（每轮更新） |
| `核查报告-技术文档v1-2026-10-25.md` | 事实/逻辑核查（v2.1，三轮含源码级） |
| `复核记录-阶段0冒烟/阶段1快捷化骨架/图像格式测试V13/桌面端对照/R4决策轮V15/R4prime自建终裁/B1受阻/B1解阻AB/B2B3B4/人工复核3条处置/验收2条处置/验收2条二次处置`（均 -2026-10-25.md） | 全部执行轮的复核记录链（12 份） |
| `README-部署-v0.md` | web 侧部署 README（构建链/回归清单，待 V4–V7 数据回填） |
| `PM.md` / `方案调研-显微成像Fiji管线-v1.md` | 方法论 / 大文件管线调研（含落地应用登记） |
| `复核证据-B1-按钮栏现场.png` | 按钮栏 GUI 取证截屏 |
| `桌面端-交付/` | 桌面交付物：6 键 Action Bar（my_tools.ijm）、安装说明（收口版）、`转OME-Zarr.bat`、`查看Zarr.bat`（两个桌面拖拽器） |
| `部署-overlay/macros/` | 宏库单一来源镜像（common 01–06 / web / desktop） |
| `部署-overlay/headless/` | 全部工程脚本（批处理引擎 batch_run.py+batch_gui.py、诊断/探针、winctl.ps1 窗口取证工具等，17 个） |
| `部署-overlay/fiji-deploy/` | Fiji 机部署件正本（load_actionbar.ijm 启动装载器、启动Fiji-带工具栏.bat） |
| `部署-overlay/evidence/` | 关键证据日志（批处理 CSV/状态、格式矩阵、N5 命令表、探针等） |
| `部署-overlay/portal.html` + `build-imagejjs.bat` | web 侧门户页与 CJ2 构建链（主线资产，随时可恢复 R5） |

## 关键结论速览

- **桌面侧（现行）**：Fiji 2.18.0/1.54p99 + Bio-Formats 8.5.0；6 键按钮栏开机自启（`-macro` 装载器）；批处理双形态（按钮后台引擎 BS3 级 / headless 脚本）；大文件 → OME-Zarr（bioformats2raw，1.66G≈2min）→ 查看走拖拽回转 OME-TIFF（进程内 N5 栈已证死路）。
- **web 侧（主线，暂停于 R4'）**：CJ2 基线可用（V13：仅 TIFF 族）；aicell/CJ4.2 迁移被否决（BF 实测不工作 + 性能 50× 劣化 + 宏引擎回归）；CheerpJ 许可为非商业非公开（已确认合规）。
- **环境铁律（防复发）**：Action Bar 参数只认 `/plugins/ActionBar/<名>`；本版 Fiji 无 bsh 插件、无 StartupMacros 钩子、不注册手动 jar；宏内 `getDateAndTime()` 不可字符串拼接、宏无 try/catch；fiji.bat 无 stdout（一切落盘）。

## 部署基线（R7 登记，2026-10-25）

- web：imjoy-team/imagej.js master@c25ef77 · v0.6.0 · ImageJ 1.53m99 + CheerpJ 2.x（cjrtnc 20201217_2）· Node 13.14.0 · dist 58.1MB
- 桌面：Fiji 2.18.0/1.54p99 + BF 8.5.0 @ `C:\Users\sr123\APP\Fiji` · action_bar.jar 2023-09（Mutterer 官方站点经更新器安装）· bioformats2raw 0.13.0 / raw2ometiff 0.10.1 @ `ijweb\`
- 偏差登记：vue-js-modal 改 tarball URL；ij153 并入 1.53m+1.53m3；prepare.sh python3→python + CRLF 修正

## 同步约定

- 文档持续在本仓库更新（溯源）；上游代码未修改（覆盖层部署）。
- 每轮「执行→复核」以 `复核记录-*.md` 归档，人工意见**原文照录**（`Q… <- 结论`）；路线图状态表每轮同步。

