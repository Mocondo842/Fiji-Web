---
title: 基于 web 浏览的 Fiji 与快捷插件添加工程 技术文档
版本: v1.5（v1.4 基础上回写 V13 <1G 层实测：TIFF 族可用、ND2/CZI/MRC/IMS 不支持；新增异常 #14 open+run 组合限制。修订记录见文末 §15）
日期: 2026-10-25
依据: imjoy-team/imagej.js 官方 README（一手）+ **master 源码核查（2026-10-25，GitHub API 通道：src/index.js、src/index.html、src/service-worker.js、src/zarrUtils.js、webpack.config.js、package.json；master 最后 push 2025-08-21，应用版本 0.6.0）** + imagej.net 官方页 + image.sc 发布帖 + aicell.io 升级博客（2023-11-05）+ CheerpJ 官方文档/博客 + 本目录《方案调研-显微成像Fiji管线-v1》
状态: 文档产出，未在任何机器实测部署；凡标「待确认 / 待实测」的条目不得当结论引用。凡标「（源码）」的为源码级结论，仍以 V 清单冒烟为准
---

# 0. 一页结论

| # | 需求 | 结论 | 关键依赖 / 落地物 | 风险 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | 一台电脑部署，多设备浏览器访问 Fiji | **可行，且是最省服务器资源的一类方案**：imagej.js（ImJoy 团队，MIT 许可）把 ImageJ 1.53 编译进浏览器（CheerpJ），构建产物是纯静态文件，计算 100% 发生在各客户端。官方发布帖原文：*「不必担心访客数量，它们只是托管在 CDN/GitHub 上的静态文件」*；现网 ij.imjoy.io 规模约 1000–1500 独立用户/日 | 仓库 `imjoy-team/imagej.js`；`npm run build` → `dist/`；Nginx / IIS / 临时用 `python -m http.server` | 低–中（前提条件已澄清实测（2026-10-25）：静态文件全走局域网，但**浏览器端首载需经网关出网**拉 CheerpJ 运行时（cjrtnc，实测 0.68s 可达）与 CodeMirror（cdnjs，可达，香港边缘节点）——网段有正常出网即按原样部署；仅完全隔离网段需本地化（V14 复核）） |
| 2 | web 端导入 100G 大文件并多线程加速 | **明确不做（工程边界，非技术攻关项）**：CheerpJ 2.x 时代官方博客明示 >4GB 文件无法加载；升级 CheerpJ 3 后官方仍写明剩余限制是「文件不得超过可用内存」。浏览器标签页内存为 GB 量级，100G 级在本工程任何版本下都不进 web 端。大文件走《方案调研 v1》的 L1 headless 管线，两端用 OME-Zarr/OME-TIFF 文件契约交接 | 方案调研 v1 §9 架构；`bioformats2raw` 产出 OME-Zarr；web 端用 vizarr / ImageJ.JS viewZarr 裁剪查看 | 低（前提：接受边界） |
| 3 | 常用宏/插件快捷化（按钮栏） | **两条线并行，共用一份宏库**：桌面 Fiji 用官方 Action Bar 插件 + Shortcuts；web 端用 URL `?run=` 一键宏链接（门户页）、`addMenuItem` 菜单注入、或构建期把插件打进 dist（现役仅支持 ImageJ-1 插件，不能运行时装本地 jar；CheerpJ 3 动态加载 jar 的路线待实机验证） | `/macros/*.ijm` 宏库（单一事实来源）；Action Bar 配置文件；门户页 | 低（v1.1（源码）：`?run=` 的校验是 `startsWith("http")`，内网 http 宏 URL 代码层放行；另有零开发的 `?install-macro=` 装菜单参数；冒烟确认见 V3） |
| 4 | 线程与内存的真实能力 | **版本敏感，不要拍脑袋**：CheerpJ 2.x（现役 ImageJ.JS 基线）= 无 Java 多线程、4GB 文件上限；CheerpJ 3.0（2024-01-30 GA）= WASM JIT 免预编译、完整 Java 多线程（依赖 SharedArrayBuffer → 服务端需 HTTPS + COOP/COEP 跨源隔离头）、插件 jar 免编译动态加载（MorpholibJ 已实证）。（源码：主线锁定 CheerpJ 2.x——index.html 引 `cjrtnc.leaningtech.com/20201217_2/loader.js` 且全码处理 `.jar.js` 产物；Leaning Tech 展台「已升级 CJ3」应指其演示）→ 部署当日运行时确认（V2） | V 清单 §9；CheerpJ 官方文档 | 中 |
| 5 | 性能预期 | web 端宏约比原生慢 **3×**（官方基准：15s vs 5s），插件可慢 **6×+**（14.2s vs 2.4s）。因此 web 端定位：**查看、标注、轻量宏**；批处理与重计算一律回桌面/headless | 本文档 §5.4 分流规则 | 低 |

**一句话架构建议**：
> **imagej.js 静态站点当「多设备轻交互前端」，桌面 Fiji + Action Bar 当「日常工作台」，方案调研 v1 的 headless 管线当「大文件重计算后端」，三者用同一份宏库与 OME-Zarr 文件契约衔接。**
> 不要在浏览器里硬扛大文件，也不要把重插件（CLIJ/Java3D 类）塞进 web 端。

---

# 1. 问题与目标

**问题（事实开头）**：课题组内多设备（笔记本、平板、无 Fiji 环境的电脑）要用 Fiji，目前需要逐机安装 Java + Fiji 并各自维护版本；常用宏靠文件拷贝和口头传递，没有统一入口；100G 级大文件的处理能力已由《方案调研-显微成像Fiji管线-v1》承接，但缺一个「在任何设备上快速看一眼、快速跑个宏」的轻量入口。

**目标（可量化；标注「基线未测」的数值在阶段 2 实测后于 v2 修订）**：

| # | 目标 | 判定口径 |
| :-- | :-- | :-- |
| G1 | 局域网内任意设备免安装访问 Fiji | 千兆局域网内，首次打开页面到出现可操作 ImageJ 界面 ≤ 5 分钟（基线未测，V4 定标）；二次打开 ≤ 30 秒（浏览器缓存 + 应用自带 service worker 同源缓存（源码）生效） |
| G2 | ≥ 3 个常用宏实现一键调用，且双端复用 | 同一份 `.ijm` 在 web 端（一键链接）与桌面端（Action Bar 按钮）均执行成功，输出图像尺寸/位深一致 |
| G3 | 明确 web 端单文件内存门槛 | 实测 web 端崩溃点（V5），把门槛值写进部署 README；v1 默认值：解压后像素数据 > 2GB 不走 web 端 |
| G4 | 服务器零维护负担 | 部署后服务器侧无会话/状态/计算；重启部署机后静态服务自动恢复 |

---

# 2. 范围与非范围

**Must（本期必须）**

- M1 imagej.js 在一台 Windows 机器上的构建与静态托管（含防火墙/端口/自启动；源码约束：须挂站点根路径或独立端口/子域，**不可子目录**——资源用根绝对路径引用 + service worker 作用域）。
- M2 宏脚本库 + web 端一键入口（门户页 + `?run=` 链接）+ 桌面端 Action Bar 工具栏。
- M3 与《方案调研 v1》管线的交接约定：OME-Zarr / OME-TIFF 文件契约 + web 端 OME-Zarr 裁剪查看路径；部署件：zarr 输出目录经同一 Nginx 提供 http 静态服务，vizarr **同源自托管**（vizarr 只能读 http(s)/s3 URL，开不了本地/共享盘路径，且官方 https demo 打不了内网 http 源——混合内容拦截）。
- M4 可判定业务规则（§6）、验收标准（§7）、异常与边界清单（§8）。

**Not now（本期明确不做）**

- N1 web 端 100G/大文件导入与多线程解码 —— **永久性边界**（除非底座变化并重开调研）；重计算归方案调研 v1 的 L1/L2。
- N2 自研 ImageJ 插件开发 —— 本期只做「已有宏/已有插件的快捷化与分发」。
- N3 用户账号体系、权限、多人协同编辑 —— 内网信任模型。
- N4 Python 侧车（L2）、GPU 层 —— 归方案调研 v1，不重复。
- N5 纳析 .mrc 等厂商格式的 web 端支持 —— 归方案调研 v1（web 端格式支持现状本身也是待实测项，见 V13）。

---

# 3. 用户故事

- **US1**：作为课题组成员，我希望在平板/笔记本的浏览器里直接打开课题组服务器上的 ImageJ，进行查看、标注和跑宏，以便不在工作站前也能完成轻量图像任务。
- **US2**：作为宏/工具的管理者，我希望把常用宏做成一键链接和按钮栏，让组内成员点一下就执行，以便降低培训成本、保证大家用的是同一份脚本。
- **US3**：作为有 100G 数据需求的用户，我希望浏览器端只负责轻量查看与裁剪核验，重活按既有管线在服务器端跑，以便两端各司其职、互不拖累。

---

# 4. 总体架构

```
┌─ 部署机（1 台 Windows；可与方案调研 v1 的 Fiji 工作站同一台）──────────────┐
│  A. 静态站点：imagej.js 构建产物 dist/（Nginx 或 IIS 托管；冒烟可用          │
│     python -m http.server）。无会话、无计算、无状态。                       │
│  B. 宏脚本库 /macros/*.ijm：单一事实来源，web 与桌面共用（分 common/desktop/web）│
│  C. 门户页（可选）：常用宏的一键链接清单（?run=<URL>）+ 使用说明 + 大文件分流指引 │
│  D. 大文件管线：方案调研 v1 的 L1 headless + bioformats2raw → *.ome.zarr；    │
│     输出目录由 A 的同一 Nginx 下发（vizarr 同源自托管）                        │
└──────────────────────────────────────────────────────────────────────────┘
        │ 静态文件（每设备一次性下载，之后走缓存）     │ OME-Zarr / OME-TIFF（文件契约）
        ▼                                          ▼
┌─ 多设备浏览器（N 台，彼此完全独立）───────────┐  ┌─ 大文件轻量查看 ─────────────────┐
│  每个标签页一个 ImageJ.JS 实例：              │  │  vizarr（浏览器零安装，首选）      │
│  · 打开本机/共享盘中小文件                    │  │  ImageJ.JS ?open=<...zarr>       │
│  · 查看、标注、跑 common 宏                   │  │  （实验性 NGFF，offset/size 裁剪，│
│  · 结果显式保存 → 本机下载目录 / 共享盘       │  │   单平面 < 50000px）              │
└─────────────────────────────────────────────┘  └──────────────────────────────────┘
        桌面 Fiji（交互工作台）＝ Action Bar 按钮栏 + Shortcuts，读同一份 /macros
        headless Fiji（大文件）＝ 方案调研 v1，见其 §9/§10
```

---

# 5. 技术方案

## 5.1 imagej.js：获取、构建与静态托管

**它是什么**：`imjoy-team/imagej.js`（GitHub，MIT 许可）——用 CheerpJ 把 ImageJ 1.53（ImageJA）编译进浏览器运行，与 ImJoy 生态双向集成。现网实例 https://ij.imjoy.io；官方页注明「只在 Chrome/Firefox 上测试过」「也支持移动设备」。README 自述 *under development, expect frequent changes* → **一切以部署当日仓库为准**（v1.1 注：master 最后 push 2025-08-21，已一年余未更新，「频繁变更」警示已过时，但仍按 R7 钉死 commit；当前应用版本 0.6.0）。

**构建前置（v1.1 补，README 原文）**：Node.js 版本应为 **13**（README 明文 `The version should be 13`；依赖树为 webpack 4 / babel beta 时代，新 Node 有已知不兼容风险）→ 部署机用 nvm-windows 安装并切换。

**构建步骤（当前 README 原文流程；v1 版多写的 submodule 行已删——当前仓库无 `.gitmodules`，GitHub API 404）**：

```bash
git clone https://github.com/imjoy-team/imagej.js.git
cd imagej.js
npm install
npm run build          # 产物在 ./dist
sh get-imagej.sh       # Windows: get-imagej.bat，拉取预编译的 ImageJ
npm run serve          # 开发态冒烟：webpack-dev-server，0.0.0.0:9090（webpack.config.js）
```

**托管方式**：

| 场景 | 方案 | 要点 |
| :-- | :-- | :-- |
| 冒烟/临时 | `python -m http.server 8080`（在 dist 目录） | 一条命令验证可用性；勿做长期服务 |
| 生产（内网长期） | Nginx 或 Windows IIS | 开机自启、缓存头、gzip；Windows 防火墙放行端口 |
| 关键坑 | MIME、外部 CDN、托管路径 | ① `.wasm` MIME 仅 CJ3 路线相关（主线 CJ2（源码）为 JS 产物，无 wasm）；② 若未来切 CJ3 且要多线程，必须 HTTPS + COOP/COEP（SharedArrayBuffer 硬前提），纯 http 降级——降级后是否完全可用**官方文档无表述**（V12 实测）；③ **（源码 + 2026-10-25 实测）首载外部依赖与可达性**：**必需**——CheerpJ 运行时 `cjrtnc.leaningtech.com/20201217_2/loader.js`（不可达 = 整站无法启动；本机实测 0.68s / 108KB，可达）、CodeMirror 全家（cdnjs.cloudflare.com，实测可达，经 Cloudflare 香港节点）；**非必需**——pwacompat（cdn.jsdelivr.net；本网络被重置，但它是异步 PWA 兼容增强，失败不影响运行）、Google Analytics（遥测，尊重 DNT）、viewZarr 的 zarr 库（cdn.skypack.dev，按需动态加载，实测 GET 可达——HEAD 探测会误报 404）。**判定规则（v1.2）**：部署机与访问设备同处局域网（如 192.168.1.0/24）不改变「每台设备的浏览器首载需经网关出网拉取上述必需 CDN」的事实；网段有正常出网（NAT）→ 原样部署，无需本地化；网段被完全隔离 → 才做本地化（把外链与 cjrtnc `20201217_2` 运行时目录镜像进 dist，MIT 允许；注意官方中国镜像 cnij.imjoy.io 的页面引用的是**同一批外部 CDN**，它只是静态站镜像，不是离线方案）；V14 从真实内网客户机复核；④ 应用资源用根绝对路径（`/style.css` 等）+ service worker 作用域 → **须挂站点根/独立端口，不可子目录**；⑤ 官方为中国用户自动提示镜像站 `cnij.imjoy.io`（Asia/Shanghai 时区显示） |

**URL 参数（web 端快捷化的地基；v1.1 已按源码 `processUrlParameters()` 修正行为口径）**：

| 参数 | 作用 | 备注 |
| :-- | :-- | :-- |
| `?open=<url>` | 打开远程图片或宏文件 | （源码）`.zarr` 后缀走 JS 侧 viewZarr（http 源可用）；带扩展名的普通图片 URL ——**阶段 0 实测（2026-10-25）：内网 http 图片 URL 打开成功**（请求按 http 发出、200；源码 `getBytesFromUrl` 的 https 改写未在此路径触发，v1.2 的「预期失败」预判作废）；无扩展名 URL 走 JS fetch 按 Content-Type 判断（http 可用）；外链需 CORS；GitHub 链接会被转成 raw.githubusercontent.com（该域名在实验网络被重置，外链源仅作备选） |
| `?run=<url 或压缩串>` | 打开页面即运行宏 | （源码）URL 校验是 `startsWith("http")`，**http 前缀放行**，宏经 JS fetch 拉取后 `runMacroAsync` 执行 → 内网 http 同源宏 URL 代码层可行（V3 冒烟确认）；也接受 lz-string 压缩串直执行（内嵌宏，绕开一切 fetch；压缩后 >8092 字符会警告 URL 过长） |
| `?install-macro=<url 或压缩串>` / `?install-tool=` | 把宏/工具**装入** ImageJ 宏系统（`IJ.installMacro` / `installTool`） | （源码，README 未记载；阶段 0 实测通过）装入后落位 **Plugins > Macros** 菜单；**要求宏为 `macro "命名"` 块格式**（顶层命令式宏装入后无可见落位——阶段 0 实测结论） |
| `?plugin=<url>` | 加载 ImJoy 插件 | — |
| `spec` / `engine` | 接 Python 插件（MyBinder / 本地 Jupyter 引擎） | 本期不用，留 v2 |
| lz-string | 短宏可直接编码进 URL | 脚本编辑器「Share via URL」；`open` 换 `run` 即直接执行（源码证实） |

## 5.2 多设备并发模型

- 计算发生在每个浏览器标签页内，服务器只做静态分发：**并发台数不受「Fiji 实例数」限制**，唯一被共享的是首载时的带宽。
- 官方证据两处：image.sc 发布帖原文（静态文件，无需担心访客数）；ij.imjoy.io 现网约 1000–1500 独立用户/日的运行规模。
- 语义上的「同时使用」= N 个互不可见的独立实例（无共享状态、无互踩风险）；同理，**一人开多个标签页也是多实例**。
- （源码）二次打开的缓存三件套：应用自带 service worker（DOMContentLoaded 即注册；同源静态资源 cache-first、HTML network-first、跨源请求不接管）+ 浏览器 HTTP 缓存 + `cheepjPreload`（localStorage 记录的 CheerpJ 运行时资源预载清单）；CheerpJ 运行时（cjrtnc CDN，跨源）不在 SW 缓存内，依赖其 HTTP 缓存头（V4 观察）。
- 待实测：dist 实际体积、千兆局域网首载时间基线、5 台设备并发首载的带宽饱和情况（V4/V6）。

## 5.3 快捷插件体系（本工程的核心增量）

### 5.3.1 宏脚本库（单一事实来源）

```
/macros/
  common/    # 双端可跑：纯 ImageJ-1 宏 API，不依赖 AWT 窗口类
  desktop/   # 仅桌面：依赖窗口/GUI 的宏（selectWindow 等）
  web/       # 仅 web 端：含自动 saveAs 到下载目录等 web 特有收尾
```

- 命名规范：`<序号>_<动作>_<对象>.ijm`（如 `01_stack2images.ijm`），门户页与 Action Bar 配置都指向它。
- 新宏准入规则：先在 web 端与桌面端各跑一遍样例（对应方案调研 v1 的 headless 纪律——依赖对话框的命令在非 GUI 环境不可靠，web 同理）。

### 5.3.2 web 端三条快捷化路径（按优先级）

1. **一键宏链接（零开发，首选）**：门户页放链接 `http://<server>/index.html?run=http://<server>/macros/common/01_stack2images.ijm`。成员点链接 = 打开 ImageJ.JS 并自动执行宏。（源码）`?run=` 接受 http 前缀，内网 http 同源可行。**变体（短宏首选）**：宏内容经 lz-string 压缩直接写进 `?run=` 参数（源码支持、脚本编辑器可生成），不依赖宏文件 fetch 与分发；压缩后 >8KB 警告 URL 过长，长宏仍用 URL 形态。链接集中由门户页管理（规则 R6）。
2. **装宏入菜单（v1.1 重写：两个更轻的实现）**：①（源码，零开发）`?install-macro=<宏URL或压缩串>` → `IJ.installMacro` 把宏装入 ImageJ 菜单系统（落位待实测）；②（小改造）构建期在 `fixMenu()`（src/index.js）追加本地 `addMenuItem({...})` 调用——该函数是主线自用的 DOM 级菜单注入（「Load NGFF (Experimental)」菜单项即此实现），**无需 ImJoy RPC**；③ 原「门户页经 ImJoy API 调 addMenuItem」路线降为备选（该 API 需 `api.createWindow`/`getWindow` 的插件上下文，纯静态页调不到）（V8 简化）。
3. **构建期内置插件（仅当确需第三方插件）**：主线已锁定 CheerpJ 2（源码）——只支持 ImageJ-1 插件，且**不能运行时安装本地 jar**；需把插件 jar 放进 `dist/ij153/plugins/` 走编译流程并更新 `plugins/index.list`。若未来迁移 CheerpJ 3（aicell fork 路线），动态 classloader 支持免编译加载 jar（MorpholibJ 已实证），流程大幅简化（V9 按 CJ2 执行）。

### 5.3.3 桌面 Fiji 端：Action Bar + Shortcuts

- **Action Bar**（官方插件，Jerome Mutterer）：配置文件放 `Fiji.app/plugins/ActionBar/`（`.txt`/`.ijm`），按钮定义格式：

  ```
  <line>
  <button>
  label=Stack->Images
  arg=<macro>
  run("Stack to Images");
  </macro>
  </button>
  <button>
  label=Apply LUT
  arg=<macro>
  run("Apply LUT");
  </macro>
  </button>
  </line>
  ```

  开机自动加载：`Edit > Options > Startup`（ImageJ 1.49e+ 推荐）或在 `StartupMacros.txt` 加 AutoRun：`run("Action Bar", "/plugins/ActionBar/my_tools.ijm");`。整条 bar 可打包成 jar 经 update site 分发。高级项：`<sticky>`（跟随图像窗口）、`<beanshell>` 块（按钮间共享变量）。
- **Shortcuts**：`Plugins > Shortcuts > Add Shortcut...` 给宏命令配键；脚本放 `scripts/` 目录自动出现在 Plugins > Scripts 菜单。
- **与宏库的关系**：Action Bar 的 `arg=` 只包一行 `runMacro`/`run`，逻辑本体仍在 `/macros/common/`，避免桌面端复制出第二份脚本。

## 5.4 与大文件管线（方案调研 v1）的边界与桥接

| 事项 | web 端（本工程） | headless 管线（方案调研 v1） |
| :-- | :-- | :-- |
| 单文件量级 | 解压后像素数据 ≤ R1 门槛（v1 默认 2GB，实测后修订） | 全谱：<2GB 批量 / 2–50GB / >50GB / 4D 时序 |
| 厂商格式（CZI/ND2/VSI/OIR） | **不承诺**（ImageJ.JS 基于 ImageJ 1.53，Bio-Formats 全格式 web 版未见官方方案 → V13 实测） | Bio-Formats 8.5.0 全量承接 + 元数据双轨 |
| 100G 类 | 永久性不做（内存墙） | L1/L2 承接 |
| 交接物 | `*.ome.zarr` / OME-TIFF 的**消费方** | `*.ome.zarr` 的**生产方**（bioformats2raw） |
| web 查看大文件产出 | vizarr（纯客户端静态应用，首选；**须自托管并与 zarr 输出目录同源**——vizarr 只能读 http(s)/s3 URL，开不了本地/共享盘路径，官方 https demo 也打不了内网 http 源）或 ImageJ.JS `?open=<...zarr>`（NGFF 实验性、offset/size 裁剪；（源码）不裁剪时要求 sizeX×sizeY ≤ 50000×50000，更大必须显式 offsetX/Y+sizeX/Y；zarr 库运行时从 cdn.skypack.dev 动态加载——可达性归 V14） | — |
| 中量级缓解 | `openVirtualStack`（实验性懒加载）：JS API，需自写供给器（name/dtype/width/height/nSlice/getSlice，源码注释明示），viewZarr 即基于它实现——不是现成「打开大文件」命令，属小开发（V11） | 虚拟栈、多进程并行（方案调研 §6） |

---

# 6. 业务规则（可判定）

| # | 规则 |
| :-- | :-- |
| R1 | 单文件解压后像素数据 > 2GB → 不走 web 端，改走 L1 管线；门槛值以 V5 实测修订并写入部署 README |
| R2 | 服务器不设并发上限（静态分发）；首载带宽饱和属体验问题，用浏览器缓存 + 预热 + 错峰解决，不写限流代码 |
| R3 | 宏调用了 `selectWindow` 等 AWT 窗口依赖命令 → 禁止进入 `common/`（放 `desktop/`） |
| R4 | 依赖 Swing/Java3D/原生库/OpenCL 的插件（CLIJ、3Dscript 等方案调研 §8 全部桌面件）→ 禁止进 web 端构建 |
| R5 | web 端运行结果必须显式保存（浏览器下载或写共享盘）；标签页关闭/崩溃即丢失内存态，收尾 save 逻辑写进 `web/` 宏模板。（源码）**只有经保存对话框（输入文件名）的保存才触发浏览器下载**；宏里写死路径的 saveAs 只会写入浏览器内部文件系统，用户拿不到文件 → web 宏模板统一用无路径 `saveAs("Tiff")` 走对话框（具体写法阶段 1 固化） |
| R6 | 一键宏链接 = `?run=<绝对 URL>`（或压缩串形态），且只允许出现在门户页；禁止在聊天/文档里散播硬编码链接（文件移动即 404）；门户页链接由单一 base-url 配置生成（未来迁 https 只改一处） |
| R7 | 部署基线登记制：记录仓库 commit、应用版本（当前 master = **v0.6.0 @ c25ef77**）、ImageJ 子版本（**运行时实测 1.53m99**；jar 名 1.53m，并入 1.53m3 包）、CheerpJ 大版本（**2.x，cjrtnc `20201217_2` 构建，实测确认**）；master 最后 push 2025-08-21；升级必须回归 §7 全部验收项 |
| R8 | 用户在 web 端尝试打开超过 R1 门槛的文件 → 门户页与文档给出固定分流指引（vizarr 链接模板 + 管线提交方式） |
| R9 | 部署机防火墙放行约定端口、固定内网 IP；端口值待组织 IT 确认（待确认项 #2） |
| R10 | 浏览器支持矩阵：Chrome/Firefox 官方测试过（应用内对其他浏览器弹提示条，源码原文 "only tested with Chrome or Firefox"）；Edge 与平板待 V7 验证；（源码）主线含 iPad 专门适配（mobile-drag-drop 对 iPad 强制启用、iOS 高度修复）→ iPad 实测有正面先验；Safari 仍不承诺 |

---

# 7. 验收标准（Given-When-Then）

- **S1 部署可用（US1）**
  - Given 部署机完成构建与托管并放行端口，When 任一支持矩阵内浏览器访问 `http://<server>:<port>`，Then 在 G1 时限内出现 ImageJ 工具栏与菜单，且关于/控制台显示 ImageJ 1.53 系版本。
  - Given 两台设备同时打开同一 URL，When 各自打开各自图像并跑宏，Then 两端互不影响（无窗口抢占、无结果串扰）。
- **S2 一键宏（US2）**：Given 门户页含「Stack→Images」一键链接与内置样例图 URL，When 点击链接，Then ImageJ.JS 打开并自动执行宏，出现结果窗口，无需任何手动输入。
- **S3 桌面按钮栏（US2）**：Given `plugins/ActionBar/my_tools.ijm` 已配置且 Startup 已挂 AutoRun，When 启动桌面 Fiji，Then 按钮栏自动出现且每个按钮执行对应命令成功。
- **S4 大文件分流（US3）**：Given 一个 >R1 门槛的真实大文件且 L1 输出目录已由同一 Nginx 以 http 下发（vizarr 同源自托管），When 用户按门户页指引操作，Then 产出可被 vizarr 打开的 OME-Zarr，且 web 端未尝试直接加载该大文件。
- **S5 双端复用（G2）**：Given `common/` 中任一宏与同一输入样例，When 分别在 web 与桌面执行，Then 输出图像尺寸/位深一致且抽样像素值一致。

---

# 8. 异常与边界清单

| # | 场景 | 系统预期行为 |
| :-- | :-- | :-- |
| 1 | 首载超时 / 中途断网 | 浏览器重试即可；服务器无状态，无恢复问题 |
| 2 | `?run=` 指向的宏 404（文件被移动/改名） | 页面打开但宏不执行；按 R6 由门户页统一修复，不散播链接 |
| 3 | 外链图源 CORS/HTTPS 拒绝 | 改用官方支持的源（GitHub/Gist/Zenodo）或同源自托管文件 |
| 4 | 打开超大文件导致标签页崩溃 | 符合 R1 门槛管理；崩溃无服务端损失；重开页面即恢复，结果按 R5 纪律早保存 |
| 5 | 用户用 Safari/老旧浏览器 | 按提示换 Chrome/Firefox；不做兼容开发 |
| 6 | 插件在 web 端白屏/报错（GUI/原生库依赖） | 按 R4 该插件本就不应进 web 构建；引导回桌面端 |
| 7 | 多台设备同时首载拖慢内网 | 缓存/预热/错峰（R2）；V6 实测后给出台数参考值 |
| 8 | 快捷键冲突（仓库已知 issue） | 自定义宏不占用 ImageJ 默认快捷键；**第一规则：不用 Ctrl 组合**（浏览器会抢占，官方 tip）；冲突清单写进部署 README |
| 9 | 各设备文件入口不同（每台设备只能选自己本机/共享盘的文件） | 约定共享盘为交换目录；门户页写明「web 端处理共享盘文件」的操作路径 |
| 10 | 部署机重启 / 托管服务停止 | 静态服务注册为开机自启（Nginx 服务 / IIS）；无数据丢失风险（无状态） |
| 11 | 结果文件散落各设备 | 命名规范（日期_设备_内容）+ 共享盘统一回收目录 |
| 12 | 内网 http 下 CheerpJ 3 多线程不可用（secure context 限制） | 降级单线程仍可用（此半句官方文档无表述，V12 实测裁决）；是否值得上内网自签 HTTPS 由 V2/V12 结果决定 |
| 13 | 外部 CDN 不可达（cjrtnc / cdnjs 必需项；jsdelivr / GA 非必需项） | （源码 + 实测）**只有 cjrtnc（CheerpJ 运行时）与 cdnjs（CodeMirror）不可达才致命**：cjrtnc 不可达 = 整站无法启动，cdnjs 缺失影响脚本编辑器；pwacompat（jsdelivr）与 GA 失败不致命（异步增强/遥测）。2026-10-25 本机实测：必需项均可达、jsdelivr 被重置但非必需。预案：V14 从内网客户机复核；若网段完全隔离 → 本地化进 dist（镜像 cjrtnc `20201217_2` 目录 + 替换 index.html 外链；cnij 镜像不是离线方案） |
| 14 | `?open=<图像>&run=<宏>` 组合参数（2026-10-25 V13 实测新知） | **run 不执行**（宏未被 fetch——open 的 await 未返回阻塞后续参数处理）。不受影响的路径：一键宏（自带样例兜底，S2 已证）、装菜单后菜单执行；需要「开图即跑宏」的场景用 `?install-macro=` 预装 + 菜单调用的组合替代 |

---

# 9. 实机验证清单（部署前必须跑）

| # | 待验证项 | 方法 | 为什么必须先验 |
| :-- | :-- | :-- | :-- |
| V1 | 构建基线可复现 | 按仓库当前 README 全流程构建一次 | README 自述频繁变更，node 版本/submodule 以当日为准 |
| V2 | 产物运行时版本 | 浏览器 DevTools 网络/控制台确认 CheerpJ 大版本与 ImageJ 子版本 | **✅ 阶段 0 已收尾（2026-10-25）**：cjrtnc `20201217_2` 76 资源实测加载 → CheerpJ 2.x 定案；`getFullVersion()` = **1.53m99**（jar 名 1.53m，并入 1.53m3 包后运行时报告 1.53m99，以运行时为准）；SW 注册与 cheepjPreload 均实证。V9 插件路线按 CJ2 执行 |
| V3 | 内网 http 同源 `?run=` 冒烟确认 + 相邻行为 | **✅ 阶段 0 四项全过（2026-10-25）**：① 同源 http 宏 URL 一键执行（SmokeTest 窗口+Log）；② `?open=` http 图片**打开成功（推翻预判）**；③ `?install-macro=` 落位 Plugins>Macros（命名块宏）；④ lz-string 内嵌直执行（182 字符样例） | 「代码级可行」已落成「部署级可行」；详见《复核记录-阶段0冒烟》 |
| V4 | dist 体积与首载时间基线 | 千兆局域网 3 次取中位；核对 service worker 生效、cheepjPreload 与 cjrtnc 运行时的缓存命中 | G1 的数值定标 |
| V5 | web 端内存崩溃点 | 0.5/1/2/4GB 测试图梯度实测 | R1 门槛定标 |
| V6 | 并发首载负载 | 3–5 台设备同时首载+跑宏，观察服务器 CPU/带宽 | 验证「服务器零负载」口径，给出经验台数 |
| V7 | Edge 与平板可用性 | Chromium 内核实测 + 一台 iPad（Safari/Chrome）与一台 Android 平板 | 支持矩阵 R10；（源码）iPad 有专门适配代码，值得实测（iPad 上所有浏览器为 WebKit，等价于测 Safari） |
| V8 | 菜单注入两路线 | ① `?install-macro=` URL 参数直测；② 改 `fixMenu()` 追加本地 `addMenuItem()` 后重构建 | 路径 2 已有两个更轻实现（源码）；ImJoy RPC 嵌入降为备选 |
| V9 | 自定义插件进 web 构建 | 按 V2 结果选：CJ2 编译流程 / CJ3 动态加载 | 决定第三方插件分发方式 |
| V10 | viewZarr 打开 L1 产出的 OME-Zarr | 取方案调研阶段 2 的产物 + crop 参数 | 两工程桥接的可运行证明 |
| V11 | `openVirtualStack` 中量级文件 | 数 GB 级实测（需先写一个小型 getSlice 供给插件——JS API，源码注释明示） | 明确「实验性」的真实可用度 |
| V12 | http 内网下线程/性能降级评估 | 对照 HTTPS + COOP/COEP 环境 | 决定是否上内网证书 |
| V13 | web 端格式支持面 | **✅ <1G 层已测（2026-10-25，真实样本库 7 格式样本）**：TIFF 族（普通/OME-TIFF/RGB 多通道）全部可用；**ND2 / CZI / MRC / IMS 全部不支持**（HTTP 200 取到但无解码，无 Bio-Formats）——N5 边界实测坐实 | 分级测试记录见《复核记录-图像格式测试V13》；1G–10G 层待特殊需要、>10G（79.4G czi）待指定；V15 若成（Bio-Formats 直载）需全部重测 |
| V14 | 出网依赖复核（从真实内网客户机） | 在一台 192.168.1.x 客户机测 cjrtnc / cdnjs 可达性与首载耗时；对照本机先验（2026-10-25：cjrtnc 0.68s 可达、cdnjs 可达经香港节点、jsdelivr 被重置但非必需、skypack GET 可达〔HEAD 会误报 404〕） | （源码 + 实测）静态文件局域网化不改变「浏览器首载需公网拉 CheerpJ 运行时」；网段出网正常即免本地化，完全隔离才需本地化改造 |
| V15 | **基线迁移评估**（aicell 新版线 CheerpJ 4.2 vs 现行 CJ2） | 冒烟新版（ij.aicell.io 或自建）：① ImageJ1 版本（源码 pinned 2025-11-21 commit，1.54 系）；② 任意 Fiji 插件直载验证（MorphoLibJ 已官方实证）；③ **Bio-Formats 直载 + 真实 CZI**（联动 V13，结论可能改写）；④ Chrome/Edge 原生目录挂载与 >4GB；⑤ 快捷化参数差异（新版 URL 参数为 `mount`/`plugins.dir`，`?run=`/`install-macro` 行为需重验）；⑥ 服务器 Range 头要求；⑦ CheerpJ 非商业许可确认 | 2026-10-25 人工复核 Q2/Q4 调研结论：版本同步与「补 Fiji 功能差」的正解大概率是换基线而非在 CJ2 线上追 |

# 10. 待确认事项（留白，未核实不写结论）

1. 主线 CheerpJ 大版本——（源码）已指向 2.x，V2 运行时收尾。**出网依赖已实测定级**（2026-10-25，本机）：必需 CDN（cjrtnc、cdnjs）可达 → 网段有出网即免本地化；待确认的只剩「192.168.1.0/24 网段是否允许出网（V14 从客户机复核）」以及完全隔离情形下的本地化工作量（cjrtnc `20201217_2` 目录镜像 + index.html 外链替换）。
2. 端口号、是否需要内网 HTTPS、证书签发方式 —— 待组织 IT 政策。
3. dist 产物实际体积与缓存策略 —— 待 V4。
4. 是否存在「Fiji 完整版 + Bio-Formats」的成熟 web 构建 —— v1.4 调研结论：完整 Fiji（ImageJ2 发行版）**无现成方案**；但 aicell 新版线（CheerpJ 4.2，ij.aicell.io，活跃维护）宣称任意 ImageJ/Fiji 插件免编译直载 + Chrome/Edge 原生目录挂载（>4GB）——Bio-Formats 能否直载待实测（V15，联动 V13）。CheerpJ 许可为社区版非商业免费/商业收费，内网科研用途属非商业的判断待组织确认。
5. 内网免鉴权模型是否可接受 —— 组织决定（N3 的边界依据）。
6. ImJoy/Hypha 远程引擎（Python 插件、`spec`/`engine` 参数）与 MyBinder 的整合 —— 本期不展开，v2 再议。

---

# 11. 实施路线

| 阶段 | 时长 | 做什么 | 验收 |
| :-- | :-- | :-- | :-- |
| 0 冒烟 | 0.5–1 天 | V1–V3 + V14：构建、托管、同源宏执行、外部 CDN 可达性 | 一台设备浏览器内可操作 ImageJ 并跑通一个最小宏；CDN 可达性有结论（决定是否做本地化） |
| 1 快捷化骨架 | 1–2 天 | 宏库 v0（≥3 个常用宏）+ 门户页 + `?run=` 链接；桌面端 Action Bar 同步配置 | S2、S3 通过 |
| 2 实测定标 | 2–3 天 | V4/V5/V6/V7/V13；修订 R1/R2 数值 | 部署 README 成稿（含门槛、支持矩阵、快捷键冲突清单） |
| 3 增强项（可选） | 1 周 | V8/V9 插件路线 + V10 OME-Zarr 查看桥 + V11/V12 | S4、S5 通过 |
| 并行纪律 | — | 不碰 N1–N5；大文件需求一律指回方案调研 v1 的阶段 0–4 | — |

---

# 12. 评审演练（三个视角的遗留问题，评审会上确认）

- **后端/运维**：托管服务的资源占用与自启方式选型（Nginx vs IIS）；dist 更新的发布流程与回滚；无状态意味着备份对象只有宏库与门户页，是否足够。
- **前端/终端**：支持矩阵外的设备（Safari、iPad 旧系统）出现时的话术；平板上键盘快捷键不可用的替代入口（按钮/链接已是主要入口，风险低）。
- **测试**：宏输出一致性的比对基线如何生成与保存（样例图入库）；每次升级 R7 的回归范围是否全量；崩溃场景（异常 4）如何构造复现。

---

# 13. 与既有调研材料的差异（哪些被修正）

| 既有说法 | 本次核实 | 处置 |
| :-- | :-- | :-- |
| 「imagej.js 项目」含糊指向 | 明确为 `imjoy-team/imagej.js`（MIT），现网 ij.imjoy.io，基于 ImageJ 1.53（ImageJA）；另存在 aicell-lab fork（CheerpJ 3 先行版） | §5.1 |
| 「CheerpJ 不支持真正多线程，单线程模拟」 | **仅适用于 2.x**；CheerpJ 3.0（2024-01-30 GA）支持完整 Java 多线程（依赖 SharedArrayBuffer）。主线升级状态待 V2 裁决 | §5.1 加版本限定 |
| 「浏览器每标签页约 4GB 内存」 | 量级成立；硬证据落在官方博客「CheerpJ 2 时代 >4GB 文件无法加载」与「CJ3 后剩余限制=不得超过可用内存」；各浏览器精确数值未实测 | R1 以 V5 定标 |
| 「构建后放任意静态服务器即可」 | 方向正确；补充 `.wasm` MIME、（启用 CJ3 多线程时）HTTPS + COOP/COEP 两个部署条件 | §5.1 |
| 「ImageJ.JS 可处理任意数量用户」 | 证实（发布帖原文 + 1000–1500 人/日运行规模），但准确含义是**静态分发无服务器计算负载**，不是「同时协作」 | §5.2 |
| Action Bar 配置片段格式 | 对齐官方文档的多行按钮定义（label/arg 分行、`<macro>` 块包裹） | §5.3.3 |
| v1 正文构建流程含 submodule（旧核验记录） | 当前 README 无此步、仓库无 `.gitmodules`（GitHub API 404）；README 明确 Node 13 | §5.1 已替换；部署机备 nvm-windows |
| README「URL 必须 https」措辞（v1 当开放问题） | （源码）`?run=` 等按 `startsWith("http")` 放行（JS fetch）；**阶段 0 实测：`?open=` 内网 http 图片 URL 亦打开成功**（v1.2 据源码推的「预期失败」被实测推翻，https 改写未在实际路径触发） | §5.1 表、V3、复核记录 |
| 「单平面 < 50000px」 | （源码）不裁剪时要求 sizeX×sizeY ≤ 50000×50000，超过必须显式裁剪参数 | §5.4 |
| 菜单注入只能走 ImJoy API | （源码）另有 `?install-macro=` 参数与本地 `addMenuItem()`（fixMenu 自用，无需 RPC） | §5.3.2 |
| 「纯静态托管即可」的隐含前提 | （源码）index.html 运行时依赖外部 CDN（CheerpJ 运行时 / CodeMirror 等）；官方为此设中国镜像 cnij.imjoy.io | §5.1 关键坑③、V14 |

# 14. 主要证据链接（按主题）

**imagej.js / ImageJ.JS**
- 仓库：https://github.com/imjoy-team/imagej.js ・ 现网（旧版 CJ2）：https://ij.imjoy.io ・ 官方文档页：https://imagej.net/software/imagej-js
- **新版线（CheerpJ 4.2，活跃维护）**：现网 https://ij.aicell.io ・ 仓库 https://github.com/aicell-lab/imagej.js（prepare.sh 从 ImageJ1 源码 pinned commit+补丁构建）
- ImageJ1 官方入口（v1.4 核实迁移）：https://imagej.net/ij ・ 发布说明：https://wsr.imagej.net/notes.html（最新 1.54t，2026-05-16；旧站 imagej.nih.gov/ij 已退役）
- 发布帖（静态托管原话）：https://forum.image.sc/t/announcing-imagej-js-imagej-running-in-the-browser/43733
- CheerpJ 3 升级（aicell fork，2023-11-05）：https://aicell.io/post/improving-imagej.js ・ demo：https://aicell-lab.github.io/imagej.js/ ・ fork 仓库：https://github.com/aicell-lab/imagej.js
- 运行规模与特性：https://aicell.io/project/imagej-js/ ・ https://labs.leaningtech.com/showcase/imagej-js

**CheerpJ**
- 概览（多线程支持）：https://cheerpj.com/docs/overview.html ・ 架构：https://cheerpj.com/docs/explanation/architecture.html
- GA 公告（2024-01-30）：https://cheerpj.com/cheerpj-3-now-generally-available ・ 深度解析：https://labs.leaningtech.com/blog/cheerpj-3-deep-dive
- 服务端配置：https://cheerpj.com/docs/guides/basic-server-setup.html
- SharedArrayBuffer 与 COOP/COEP：https://web.dev/articles/coop-coep

**Action Bar 与桌面 Fiji**
- Action Bar 官方页：https://imagej.net/plugins/action-bar
- Fiji headless 工程化 / Jaunch / 内存红线：见《方案调研-显微成像Fiji管线-v1》§2/§3/§12（不重复引用）

**大文件管线桥接**
- bioformats2raw / OME-Zarr / vizarr：见《方案调研-显微成像Fiji管线-v1》§6/§8.5/§9

---

# 15. 修订记录

**v1.1（2026-10-25，同日源码级核查修订；架构结论与规则框架不变）**

依据：master 源码核查（GitHub API 通道；master 最后 push 2025-08-21，应用版本 v0.6.0）。逐项证据见《核查报告-技术文档v1-2026-10-25》§1.4。

1. §5.1 构建块替换为当前 README 流程（删 submodule 行），补 Node 13 前置与 nvm-windows。
2. §5.1 关键坑重写：`.wasm` 条目改注仅 CJ3 相关；新增 ③ 外部 CDN 依赖、④ 根路径托管约束、⑤ 中国镜像。
3. §5.1 URL 参数表按源码行为重写（http 放行口径、`?open=` 图片的强制 https 改写、新增 `?install-macro=`/`?install-tool=`、lz-string 8KB 界限）。
4. §5.2 补缓存三件套（service worker / HTTP 缓存 / cheepjPreload）。
5. §5.3.2 路径 1 增 lz-string 内嵌变体；路径 2 重写为 install-macro + 本地 addMenuItem 两个更轻实现；路径 3 注明主线锁定 CJ2。
6. §5.4 viewZarr 口径改 50000×50000（源码）；openVirtualStack 标明需自写供给器；vizarr 增同源自托管要求。
7. M1 补根路径约束；M3 / 架构图 / S4 补「zarr 输出目录 http 服务」部署件；G1 补 SW 缓存。
8. R5 补对话框保存机制；R6 补 base-url 生成；R7 填基线值（v0.6.0 / ImageJ 1.53m / CheerpJ 2.x / 2025-08-21）；R10 补 iPad 先验。
9. 异常表 #8 补 Ctrl 规则；#12 后半句改待实测；新增 #13 CDN 不可达。
10. V2/V3/V4/V7/V8/V11 更新，新增 V14；§11 阶段 0 纳入 V14。
11. §13 新增 5 行差异记录。

**v1.2（2026-10-25，部署拓扑澄清 + CDN 可达性实测）**

1. 澄清部署形态：部署机与全部访问设备同处局域网（如 192.168.1.0/24）；静态文件全走局域网，**浏览器端首载仍需经网关出网**拉取 CheerpJ 运行时与 CodeMirror——该性质与「都在局域网」不冲突，取决于网段有无出网。
2. 实测结果落档：cjrtnc（必需）0.68s/108KB 可达；cdnjs（必需）可达（Cloudflare 香港边缘）；jsdelivr（pwacompat，非必需）被重置、不影响运行；skypack（viewZarr 按需）GET 可达（HEAD 探测会误报 404）。
3. 修正一个推断：官方中国镜像 cnij.imjoy.io 的页面引用与主站**完全相同的外部 CDN**——它是静态站镜像而非 CDN 本地化方案，不能当离线部署答案用。
4. §0 表 #1 风险降为低–中（前提：网段出网）；关键坑③、异常 13、V14、待确认 #1 按实测口径重写；判定规则：出网正常 → 原样部署；完全隔离 → 本地化（V14 从真实客户机复核后定）。

**v1.3（2026-10-25，阶段 0 实测回写；实施路线首次执行，阶段 0 复核**通过**）**

1. 执行与复核过程见《复核记录-阶段0冒烟-2026-10-25.md》（构建基线、逐项证据、截图存档路径）。
2. 修正：`?open=` 内网 http 图片 URL **实测通过**（v1.2 的「预期失败」静态预判作废；§5.1 表、§13、V3 已改）。
3. 补充：`?install-macro=` 落位 Plugins>Macros，**要求 `macro "命名"` 块格式**（顶层命令式宏无可见落位）——门户页装入宏的格式约束。
4. 定案：运行时 ImageJ 1.53m99 + CheerpJ 2.x（20201217_2）；SW 注册与 cheepjPreload 实证；dist 58.1MB；首载约 35s、二载 domcontentloaded 495ms（单机数据，V4 正式定标留阶段 2）。
5. 构建偏差登记（R7）：① `vue-js-modal` 的 `github:` 引用改为等价 codeload tarball URL（部署机无 git）；② ij153 按 get-imagej 脚本并入 1.53m+1.53m3 两包，运行时报告 1.53m99。
6. V14 本机结论：必需 CDN（cjrtnc/cdnjs）实测全部可达，jsdelivr 在浏览器环境亦可达；免本地化，待真实内网客户机例行复核。

**v1.4（2026-10-25，阶段 1 人工复核 5 项调研回写；详见《复核记录-阶段1》§4）**

1. Q1：ImageJ1 官方入口迁移至 imagej.net/ij（旧站 nih 已退役），§14 证据链接已补。
2. Q2/Q4：版本落后量化（基线 1.53m/2021 vs 最新 1.54t/2026-05）；**aicell 新版线（CheerpJ 4.2，ij.aicell.io，活跃维护，ImageJ1 源码 pinned 2025-11-21 commit 构建）**为版本同步与补 Fiji 功能差的可行路径——新增 **V15 基线迁移评估**（含 Bio-Formats/CZI 直载、原生目录挂载、Range 头、CheerpJ 非商业许可确认）。
3. Q3：实测口径闭环——`java.version=1.8.0-internal`、`java.vm.name=CheerpJ`；CJ2 模拟 32 位 OpenJDK 8，32 位地址空间即 4GB 上限与 R1 门槛的根因；与桌面 Fiji 的 Java 21 无关。
4. Q5：门户页已改版——「体验话术」替换为「如何导入你的图像」指引导块（File>Open/共享盘、拖拽粘贴、?open= 链接），样例图降级为无图兜底。

**v1.5（2026-10-25，V13 <1G 层实测回写；详见《复核记录-图像格式测试V13》）**

1. V13 定论：TIFF 族（普通/OME-TIFF/RGB 多通道）✅；ND2/CZI/MRC/IMS ❌（无 Bio-Formats，与 N5 一致）。R8 分流口径强化：web 端仅 TIFF 族，厂商格式一律指回管线/桌面。
2. 新知（异常 #14）：`?open=&run=` 组合参数中 run 不执行（open 的 await 未返回）；用 `?install-macro=` 预装 + 菜单执行替代。
3. 样本库分级：E:\wx\测试文件\ 33 文件 → <1G×29（已测代表性 7 个）/ 1G–10G×3（待特殊需要）/ >10G×1（79.4G czi，待指定）。
4. V15 优先级上调：若 aicell 新版线 Bio-Formats 直载成立，V13 全部 ❌ 项需重测。

---

## 附录：本工程与《方案调研 v1》的关系

- **不重叠**：本工程只负责「web 轻交互前端 + 快捷化」，方案调研 v1 负责「headless 批处理 + 元数据 + GPU + 渲染」。
- **两个衔接点**：① 文件契约 `*.ome.zarr`（L1 生产、web/vizarr 消费，V10 验证）；② 宏库与部署纪律共享（headless 不兼容的 GUI 依赖命令，在 web 端同样不兼容，准入规则 R3/R4 一并执行）。
- **顺序建议**：方案调研 v1 的阶段 0（只读核查）先行；本工程阶段 0–1 可与之并行，互不阻塞。
