---
title: 显微成像处理管线（Windows + Fiji headless）方案调研
版本: v1（完整版：含单文件并行、Rust 重构评估、GPU 功能矩阵、推荐架构与实施路线）
日期: 2026-10-16
依据: DeepSeek 会话共享 5i7x3qb94js70oofpw（3 轮问答）+ 22 路联网调研（含证据链接）
状态: 未在本机或目标机做任何实测；本文件为文档产出，未改动任何环境
---

# 0. 一页结论

| # | 你的需求 | 调研结论 | 关键依赖 / 落地物 | 风险等级 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | 基于 Win Fiji headless | **可行，但有一条硬红线**：headless 下**不能用** `run("Bio-Formats Importer")`（抛 `VerifyError`）。必须走 Bio-Formats 的 Java/脚本 API：`Ext.openImagePlus(path)` / `BF.openImagePlus(options)` / 命令行 `bftools showinf·bfconvert·bioformats2raw` | Fiji + Bio-Formats 8.5.0；Jaunch 启动器（2025-02 起，入口 `fiji.bat`） | 低 |
| 2 | 自动检测配置并设优化参数 | **可行，且必须自己写**（无现成插件）。Jython 内拿逻辑核/内存/当前堆；物理核、磁盘类型、显卡需 `ProcessBuilder` 调 PowerShell（`wmic` 已被 Windows 移除）。GPU 用 `nvidia-smi` + `CLIJ2.clinfo()` | 一段 `probe.py` + 两阶段启动（先探测，再带 `--mem=` 重启） | 中（堆内存不能运行时改） |
| 3 | Bio-Formats 并行读 CZI/VSI·OIR/ND2/MRC 并保留成像参数 | **部分可行，且四种格式差距很大**。OME 字段只是子集：ND2 只映 52/476 个字段、**缺少全部 Laser/LightSource**；VSI **丢通道伪彩与激光**；OIR 激光最全但**激光功率不映射进 OME**（issue #3748 已 closed as **not planned**）；CZI 的 zoom 等只在 OriginalMetadata。→ **必须双轨：OME 字段 + 全量 `getGlobalMetadata()` 落 JSON/CSV** | Bio-Formats 8.5.0（ND2 必须 ≥8.4.0，见 bug #4431）；自写元数据审计脚本 | 高 |
| 3.1 | 单文件并行 / Rust 重构 | 见 §6 / §7。主线结论：**单文件并行靠「每线程一个独立 reader 实例」**（`bioformats2raw --max-workers` 就是这么做的），官方**没有**线程安全承诺；**不建议为并行而用 Rust 重写厂商容器解析** | bioformats2raw；pylibCZIrw / nd2（补元数据） | 高 |
| 4.1 | 拼接（GPU） | 见 §8 | BigStitcher(headless 最完整) / MIST(CUDA，仅 2D) / ashlar | 中 |
| 4.2 | 阴影矫正 | BaSiC 插件 headless 未见官方说明；GPU 路线走 **BaSiCPy**（Python 侧） | 建议放到 Python 侧车 | 中 |
| 4.3 | 3D 渲染 + 视频导出/播放 | **ImageJ 3D Viewer 明确无 headless 方案**（官方 FAQ 原文：无 workaround）。批处理出视频走 3Dscript(OpenCL) 或 Fiji 外离屏渲染；交互核验另配查看器 | 3Dscript / napari / PyVista / BigDataViewer | 中 |
| 4.4 | 反卷积（CUDA 优先） | Fiji 侧的 GPU 几乎都是 **OpenCL**（CLIJ2/clijx-deconvolution/clFFT）。**要真 CUDA 得离开 Fiji**：`cudadecon/pycudadecon`、Microvolution（商业）、PyTorch/TF 深度学习方案 | Python 侧车 + PyTorch/CuPy | 中 |
| 4.5 | 超分（像素倍增、去锯齿） | 需先区分「插值放大 / 去噪 / 真超分」，三者代价与收益差一个数量级。见 §8 | eSRRF(OpenCL) / CARE(CSBDeep) / N2V / 通用超分模型 | 中高 |

**一句话架构建议**：
> **Fiji headless 当「IO 与 OME 化内核」，Python(NVIDIA/CUDA) 当「重计算与渲染侧车」，两者用 OME-TIFF / OME-Zarr 文件交接。**
> 不要在 Fiji 里硬凑 CUDA，也不要指望 Bio-Formats 的 OME 字段能装下厂商的全部成像参数。

---

# 1. 需求与已确认约束

| 项 | 你的确认 | 对方案的影响 |
| :-- | :-- | :-- |
| 硬件 | NVIDIA 独显，允许装 CUDA；**有管理员权限** | CUDA 路线全开；但仍建议保留 OpenCL 回退（Fiji 插件绝大多数是 OpenCL） |
| 安装权限 | 可装 CUDA Toolkit / 驱动 / 系统级软件 | 可以引入 Python 侧车、注册表 TDR 调参、Defender 排除项 |
| 数据规模 | **全谱**：<2GB 批量小文件 / 2–50GB 大图（文件内多 tile 需拼接）/ >50GB / 4D 多通道 Z 栈时间序列 | 必须做分块 + 金字塔 + 多进程；不能只写「一把梭读进内存」的脚本 |
| 纳析 .mrc | 纳析 SIM 超分辨**原始格式**（非 IMOD MRC），**可提供样例文件与厂商说明** | 样例到手前，纳析一节只能给判定流程，不能给结论（见 §4.4） |
| 3D 需求 | **两者都要**：批处理出视频 + 人工核验时可交互查看 | 需要两条独立通道；交互部分无法在 headless 服务里做 |
| 交付物 | 只要调研报告 | 本轮不改任何环境；所有脚本建议都只作为附录/下一步 |

**沿用上一轮（DeepSeek 会话）已验证的结论**：`Ext.openImagePlus()` 替代 Importer 解决 VerifyError；文件级并行；Grid/Collection Stitching 在 headless 下 `compute_overlap` 会被强行打开（Fiji bug 900，已修但建议显式写参）。本轮把「文件级并行」进一步推进到「单文件并行」与「Rust 重构」的评估。

---

# 2. 自动检测硬件与参数落点

## 2.1 探什么、在哪探

| 目标 | 通道 | 具体 API | 备注 |
| :-- | :-- | :-- | :-- |
| 逻辑核数 | Fiji 内（Jython） | `Runtime.getRuntime().availableProcessors()` | ImageJ 插件普遍用它决定并行度；**在容器/配额环境下可能虚高** |
| 物理核数 / 主频 | PowerShell 子进程 | `Get-CimInstance Win32_Processor` → `NumberOfCores` / `NumberOfLogicalProcessors` / `MaxClockSpeed` | Java 拿不到物理核 |
| 物理内存 / 可用 | Fiji 内 | `ManagementFactory.getOperatingSystemMXBean()` 强转 `com.sun.management.OperatingSystemMXBean` → `getTotalMemorySize()`/`getFreeMemorySize()`（Java 14+），旧 JDK 用已废弃的 `getTotalPhysicalMemorySize()` | 需按 Fiji 自带 JRE 版本分支 |
| 当前堆上限 | Fiji 内 | `Runtime.getRuntime().maxMemory()` | ImageJ 自身 `ij.plugin.Memory` 就是这么取的 |
| 显卡（NVIDIA） | 子进程 | `nvidia-smi -L`；`nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv`（字段先用 `--help-query-gpu` 校验） | 官方声明 **输出不保证向后兼容**，长期工具应走 NVML |
| 显卡（任意） | OpenCL | `clinfo -l`；Fiji 内 `CLIJ2.clinfo()` / `Ext.CLIJ2_clInfo()` | **判断 OpenCL 环境是否装好的第一手段** |
| 显卡（无工具） | PowerShell | `Win32_VideoController` → `Name`/`DriverVersion`/`AdapterRAM` | `AdapterRAM` 是 uint32，**>4GB 显存不可信** |
| 磁盘类型 | PowerShell | `Get-PhysicalDisk` / `MSFT_PhysicalDisk` → `MediaType`(3=HDD,4=SSD,5=SCM)、`BusType`(11=SATA,17=NVMe) | `Win32_DiskDrive` **分不出** SSD/HDD/NVMe |
| 剩余空间 | Fiji 内 | `new File(path).getUsableSpace()` / `Files.getFileStore(path)` | |
| 是否网络盘 | 前缀 / WMI | UNC `\\server\share\...` 前缀，或 `Win32_LogicalDisk.DriveType==4` | **不要用 `FileStore.type()`** 判 SMB（实现相关） |

## 2.2 参数落点（这是「自动优化」的真正难点）

1. **堆内存不能运行时改**。Java 没有 setter；ImageJ 自己的 Memory 对话框也是写配置文件 + 提示重启。
   - Jaunch（Fiji ≥ 2025-02）：`fiji --mem=48g`，或写 `config/jaunch/fiji.cfg` 的 `max-heap = '48g'`；默认值本来就是「可用内存的 75%」。
   - 旧 launcher：`ImageJ.cfg` 的 `maxheap.mb` / `jvmargs`。
   - **因此探测流程是两阶段的**：第一次启动只探测并算出建议值 → 带 `--mem=` 重新拉起真正的批处理。或者干脆固定 `--mem=75%`（放弃按实测调优，换一次启动）。
2. **线程数落点是 ImageJ 偏好项**：`ij.Prefs.setThreads(n)`（落盘键 `threads`，见 `IJ_Prefs.txt`）；并行栈滤镜读的就是它。**Fiji 没有 `--nthread` 这类启动参数**。
3. **GPU 设备不要靠默认**：CLIJ 不做 benchmark，默认取 OpenCL 设备列表**第一项**。多设备（独显 + 核显）必须显式指定，如 `run("CLIJ2 Macro Extensions", "cl_device=[RTX ...]")` 或 `CLIJ2.getInstance("...")`。
4. **经验规则**（有官方出处）：
   - 堆内存不建议超过物理内存 75%，否则 Fiji 变慢且不稳定（Bio-Formats 官方「Managing memory」页）。
   - CLIJ 的 GPU 划算门槛：图像 **> ~10 MB** 才值得上 GPU；选卡看**显存带宽**而非核心数；尽量把操作串成一个块避免反复 push/pull。
   - Windows 上跑大图必须先把 **TDR 超时**调到 60 秒（注册表 `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay=60` + `TdrDdiDelay=60`），否则大图会以 `CL_INVALID_COMMAND_QUEUE` / `CL_MEM_OBJECT_ALLOCATION_FAILURE` 失败。

---

# 3. Windows + Fiji headless 工程化要点

## 3.1 启动与调用

| 场景 | 命令 |
| :-- | :-- |
| 宏 | `fiji.bat --headless -macro path\m.ijm "arg1=..."`（`-macro` **不支持** SciJava 脚本参数） |
| SciJava 脚本（Groovy/Jython） | `fiji.bat --headless --run "path\to.py" "key='value'"` |
| Windows 引号规则 | **与 Linux 相反**：脚本路径用双引号，参数值用单引号 |
| 只打印将执行的命令行（排查参数） | `fiji.bat --dry-run ...` |
| 装/更新插件（纯命令行） | `fiji.bat --update add-update-site <nick> <url>`；`fiji.bat --update update` |
| 并行任务关自动更新检查 | `-Dimagej.updater.disableAutocheck=true` |

- **启动器已换代**：Fiji 自 2025-02 起从 ImageJ Launcher 换成 **Jaunch**，Windows 入口是 `fiji.bat`；旧 `ImageJ-win64.exe` 属 legacy（源码仓库 2024-07-15 后停更）。现场先跑 `fiji.bat --help` 与 `--dry-run` 确认。
- **控制台输出**：Windows 上 GUI 子系统 exe 不继承父控制台，这是「命令立刻返回、日志晚到」的根因。用 `fiji.bat`（或 `start /wait` / `Start-Process -Wait`）拿输出；不要再依赖老的 `--console`。
- 日志：SciJava 默认 INFO 进 stdout、WARN/ERROR 进 stderr；用 `-Dscijava.log.level=debug` 提级。

## 3.2 headless 下会崩的与绕过

| 现象 | 根因 | 对策 |
| :-- | :-- | :-- |
| `java.lang.VerifyError: Bad type on operand stack` | Importer 初始化 `MainDialog`，依赖 `java.awt.Container` | 改用 `Ext.openImagePlus()` / `BF.openImagePlus()`；**2026-02 有用户实测确认可解决** |
| 所有依赖对话框的命令静默走默认值 | ImageJ2 用 Javassist + `HeadlessGenericDialog` 运行时打补丁 | 参数**全部显式写全**，不要依赖默认（例：Grid/Collection Stitching 显式写 `compute_overlap=[false]`） |
| `selectWindow("...")` / 表格重命名 失败 | 纯 GUI 依赖命令 | 改成不弹窗的 SciJava Command / 直接调 API |
| 3D Viewer 打不开 | 依赖 Java 3D + 硬件 3D 加速 | **官方 FAQ 明确「目前无 workaround」**；渲染另找出路（§8.3） |
| 进程跑完不退出 | 2016 年的 headless bug | 宏末尾加 `eval("script","System.exit(0);")`（BigStitcher 官方示例就这么写） |
| **退出码恒为 0**（即使宏报错） | ImageJ1 不返回错误码，imagej2 **issue #61（2014 开，至今 open）** | **成功判据必须自建**：输出文件 + 校验（尺寸/元数据）+ 每次任务的 JSON 状态文件；日志关键字仅作兜底 |

## 3.3 平台级陷阱（Windows 特有）

| 主题 | 结论 | 依据 |
| :-- | :-- | :-- |
| 长路径 | `MAX_PATH=260`；`LongPathsEnabled=1` 只对声明 `longPathAware` 的程序生效。JDK 对 >247 的**文件路径**会自动加 `\\?\` 前缀，但 **`CreateProcessW` 无解**（`JDK-8315405`，状态 External，不修）：**exe 路径与工作目录必须 ≤260**。→ 把 Fiji 装在短英文路径，工作目录也短 | JDK-8315405 / MS Learn |
| 中文/空格路径 | JDK 18+（JEP 400）默认 UTF-8；17 及以前 Windows 用 ANSI 代码页，需显式 `-Dfile.encoding=UTF-8` | JEP 400 |
| 网络盘（SMB/NAS） | 1Gbps≈110MB/s、10Gbps≈1.1GB/s 上限；SMB 签名/加密进一步拖慢（Win11 24H2 起签名默认强制）。Bio-Formats 家族会在**源文件同目录**写 `.<文件名>.bfmemo`，只读共享会导致缓存失效（日志 `directory not writeable`）→ 用 `Memoizer(reader, 本地目录)` 把缓存指到本地盘 | MS Learn / bioformats2raw README |
| Defender | 三类排除语义不同：`ExclusionPath`（文件/文件夹，覆盖实时+计划+按需扫描）、`ExclusionProcess`（只排该进程打开的文件，**仅实时保护**）、上下文排除。**不要排除映射盘符，要写 UNC 真实路径**；`*` 在文件夹路径中只匹配单层 | MS Learn |
| 并发模型 | **优先多进程**（按文件切分，每进程独立 `-Xmx`）；`N × Xmx` 会超配。单文件内并行需每线程独占 reader | 见 §6 |
| >50GB 大文件 | `FileChannel.map` 单次映射受 `Integer.MAX_VALUE` 限制，必须分片映射；虚拟栈不缓冲整栈；直接内存/映射**不计入 `-Xmx`**，但占物理内存与页缓存 | OpenJDK 源码 |
| 无人值守 | 计划任务选「不管用户是否登录都运行」会进**非交互会话**；默认 **`ExecutionTimeLimit=PT72H`（超 3 天即停）**，长任务必须改 `PT0S`；重试用 `-RestartCount/-RestartInterval`；断点续跑靠自己写 sentinel 状态文件 | MS Learn TaskSettings |

---

# 4. 四类格式：元数据覆盖矩阵与读取路线

> 权威版本：**Bio-Formats 8.5.0**（稳定）。ND2 有近两年的尺寸/维度回归 bug，生产必须锁 **≥8.4.0** 并逐文件断言 T/Z/series。

## 4.1 覆盖度矩阵（✅有 / ⚠️仅 OriginalMetadata / ❌缺）

| 字段 | CZI | ND2 | VSI | OIR |
| :-- | :-- | :-- | :-- | :-- |
| 物镜（NA/放大/浸没） | ✅ Immersion/LensNA/NominalMagnification | ⚠️ 仅 CalibratedMagnification/LensNA/Immersion；**缺 NominalMagnification、WorkingDistance** | ✅ + WorkingDistance | 部分 |
| 通道伪彩（LUT/Color） | ✅ 通道色 hex | ✅（但有 LUT 反色 #3761、8bit #3964 的 open issue） | ❌ **CellSensReader 不映射 Channel Color** | ✅ |
| XYZ 坐标 | ✅ PlanePositionX/Y/Z（⚠️ 取值依赖 subblock 目录，无 stage 元数据时会**回退成像素索引**） | ✅ | ✅ | ⚠️ **只有 Z，无 XY** |
| **zoom（缩放）** | ⚠️ `ZoomX`/`Zoom` 在 global metadata，**不写 OME** | ❌ **三个 reader 全文搜不到 zoom**，只能读原图或 description 文本 | ❌ | ❌ |
| 激光 / 光源 | ⚠️ 强度→Attenuation | ❌ **全部 Laser/LightSource 字段缺失** | ❌ | ✅ Laser ID/Model/Wavelength ✅ |
| **激光功率** | ⚠️ | ❌ | ❌ | ❌ **`getLaserPower()` 恒空；issue #3748 已 closed as not planned**（功率只能从 OriginalMetadata 的 power/transmissivity 取） |
| 探测器 / 增益 | ✅ | ✅ Binning/Gain/ReadOutRate；缺 Manufacturer | ✅ 含 SerialNumber | 缺 Model/Type |
| 时间戳 | ✅ DeltaT/TimeIncrement | ✅ DeltaT | ⚠️ DeltaT 直到 8.4.0（PR #4387）才解析，之前只在 OriginalMetadata | — |

**结论（这一条决定架构）**：
> **只存 OME-XML 一定会丢参数。**必须同时导出 `getGlobalMetadata()` / `getSeriesMetadata()` 的**全量键值对**，落到 JSON/CSV 作为「成像参数审计表」，再谈拼接与可视化。
> 官方自己给的数据：ND2 的 reader 只映射了 476 个 OME 字段中的 **52 个**（格式本身约 10% 可映射）。

## 4.2 蔡司 CZI

- **Bio-Formats**：物镜、通道色、Ex/Em、Pinhole、Detector、PlanePosition XYZ、DeltaT 基本都有；**zoom 等 ZEN 专有字段只在 OriginalMetadata**（整棵 CZI Metadata XML 以 `A|B|C` 键塞进 global metadata）。
- **已知 bug**：多 scene 维度 `S` 不转 OME（#4194 开放）；`zeissczi.autostitch` 在真实文件上会失败并散成几十个 series（#4102）→ **不要赌 autostitch**；另有 Z1 光片 DeltaT、Lightsheet、PixelShift 等问题。⚠️ 上一轮会话提到的「多 series 坐标被误读为时间位置」**本次未找到对应 issue，不要当事实引用**。
- **官方/第三方库**：
  - `libCZI`（ZEISS，**LGPL-3.0-or-later**，C++/VS+vcpkg）：`CziReader::ReadMetadataSegment` 拿完整 XML、`GetDisplaySettings` 拿通道 tint、`EnumerateSubBlocks/ReadSubBlock` **随机访问子块**、SingleChannel Tile/PyramidLayer accessor 可直接出拼接图。
  - `pylibCZIrw 6.1.0`（LGPL-3.0，**PyPI 有 win_amd64 轮子**，Python 3.9–3.14）：`czi.open_czi(path)`，可读 raw metadata、`scenes_bounding_rectangle`（拼图边界是**显式 API**）。⚠️ Windows 下 JPEG-XR 默认走 **WIC**，多线程易崩 → 显式切到内置解码器规避 COM 问题。
  - `czifile`（BSD-3，纯 Python + imagecodecs）：支持 memmap 并行子块读；元数据以 xarray 坐标给出。
- **单文件并行可行性**：**在子块粒度可以**——CZI 子块各自独立压缩（0/无、1/JPEG、2/LZW、4/JPEG-XR、5·6/ZSTD）。Bio-Formats 侧无并发保证，要并行就用 pylibCZIrw / czifile / libCZI。
- **建议**：**元数据双轨（OME + 全量 XML）**；拼接用 `scenes_bounding_rectangle` + tile 坐标自己算，或先转 OME-Zarr 再拼。

## 4.3 尼康 ND2 与奥林巴斯 VSI / OIR

- **ND2**：reader 只映 52 字段，**激光与光源全缺、物镜 NominalMagnification 缺、zoom 三处都读不到**。近两年 bug 密集（8.1.1 #4276；8.4.0 修 #4370/#4381/#4392），**但 #4431（2026-05 报，仍 open）显示 8.5.0 会把 11T×7Z 读成 7 series×11Z** → 必须锁版本 + **逐文件断言维度**。好消息：`LegacyND2Reader` 已于 7.0.0 移除，**不再需要 Nikon DLL 与 32 位 Windows**。
  - **补元数据**：`nd2`（Python，纯 Python 无 DLL，自称与官方 SDK 对齐，`imread(dask=True)`）能拿 `zoomMagnification`；或解析 NIS-Elements 的 description 文本（内含 `Zoom: 1.00x`、NA、折射率、Z step、相机型号、滤块）。
  - **ND2 SDK**：Nikon 官方 SDK 经 `nisoftware.net` 分发，本次**该站不可达，许可与 Windows 支持未证实**，需走商务确认。
- **VSI**：格式页自评 Pixels 仅 **2-Fair**；映射 49 字段。**丢通道伪彩、Ex 波长、Pinhole、物镜 Correction/Immersion、全部 Laser**。
  - **三个硬坑**：① 必须存在同级的 `_<name>_/` 目录且内含 `.ets`，否则报 `missing expected .ets`；② `CellSensReader` 自建分组，**Fiji 的「Group files by name」对 VSI 无效**，官方建议脚本合成为 OME-TIFF；③ DeltaT 与像素校准直到 8.4.0/8.5.0 才修。
  - **Evident/Olympus 无公开读 VSI/OIR 的 SDK**（OME 持有 VSI 规范但不许转授）→ **Bio-Formats 是唯一实用通路**。
- **OIR**：**激光覆盖最好**（Laser ID/Model/Wavelength、Channel LightSourceSettings、Excitation、Pinhole），但缺 PlanePositionX/Y、Detector Model、Binning，且**激光功率不映射**（#3748 not planned）。
- **单文件并行**：`bioformats2raw --max-workers=N`（默认=CPU 数）会起 **N 个各自包 Memoizer 的 reader 实例**，用一个容量为 N 的队列按 tile 并行读同一文件；README 只点名 Imaris HDF 等少数 reader 需设 1，**ND2/VSI/OIR 不在其列**——但这只是反推，**真实加速比必须实测**。

## 4.4 纳析科技 `.mrc`（本轮最大的未知）

- **现状**：纳析（北京纳析光电，产品 Multi-SIM / NanoSlice / SpinX / DeepInsight）**没有公开的数据格式文档**；未找到其提供 OME-TIFF/CZI 导出或 SDK 的公开证据。
- **倾向性判断（待样本证实）**：其技术源头（李栋组 rDL-SIM / caGAN-SIM 等开源代码）把 SIM 原始数据与 OTF 都存成 **`.mrc`，属标准 MRC 容器而非私有变体**（如 `MT.mrc`、`..._OTF2d.mrc`）。若成立，Bio-Formats 的 MRCReader 可直接读。
- **三行自检（拿到样例当天就能定案）**：
  1. `xxd -l 16 x.mrc` —— 前 3 个 int32 应为 `nx, ny, nz`；
  2. `mrcfile.validate()`（Python `mrcfile`，返回 True 即兼容）；
  3. `bftools showinf -nopix -omexml x.mrc` —— 看 Bio-Formats 8.5.0 能否识别并给出什么元数据。
- **即使兼容，也有硬限制**：
  - MRCReader 靠**魔数**识别（后缀无关）；支持 `.mrc/.mrcs`、大小端、mode 0/1/2/6/16；**nz 被当作 Z 栈，sizeT=1、sizeC=1**（只有 RGB 才是 3）；
  - 不支持 mode 12 与 IMOD 复数 mode 3/4；**扩展头整段跳过**（日志 `Skipping extended header`）；
  - **单位陷阱**：仅当扩展头 `extType=AGAR` 时才按 µm，否则按 **Å** 解释 → 可能差 **1e4 倍**；
  - **头里没有物镜/NA/波长/伪彩/Laser** —— 这些只能来自采集端 sidecar 或厂商说明。
  - **许可**：MRCReader 在 `formats-gpl`（官方格式页 BSD=No），**产品内嵌需评估 GPL 合规**；`formats-bsd` 不含 MRC。
- **因此需要你向纳析索取**：① 数据格式说明（是否 MRC2000/2014、扩展头定义、单位）；② 元数据 sidecar（物镜/激光/通道伪彩）；③ 批量导出接口（OME-TIFF/Zarr 优先）。拿不到就按「mrcfile 读 + 自建元数据表 + 转 OME-Zarr」自研，成本可控。

---

# 5. 待你在实机上验证的清单（按优先级）

| # | 待验证项 | 验证方法 | 为什么必须先验 |
| :-- | :-- | :-- | :-- |
| V1 | Fiji 版本与启动器类型 | `fiji.bat --help`、`fiji.bat --dry-run --headless --run x.py` | 决定写 `fiji.cfg` 还是 `ImageJ.cfg`、`--mem` 是否可用 |
| V2 | **headless 下用 `loci.formats` API 读 CZI/VSI/OIR/ND2 是否完全不报错** | 用 `showinf -nopix -omexml` + 一份真实文件跑通 | 官方只说「Importer 插件不能 headless」，**没有**承诺「库也不能」，也没承诺「一定能」 |
| V3 | 各格式 T/Z/series 与 PhysicalSize 断言 | 每格式取 1–2 个真实文件，比对厂商软件显示值 | ND2 #4431 级别 bug 会静默改变维度 |
| V4 | 纳析 `.mrc` 三行自检（§4.4） | `xxd` + `mrcfile.validate` + `showinf` | 决定纳析支线是「直接读」还是「自研解析」 |
| V5 | `bioformats2raw --max-workers` 的真实加速比 | 同文件 `--max-workers=1/4/8` 三次计时 + 峰值内存 | 决定要不要上单文件并行、要不要上 Rust |
| V6 | OpenCL 环境是否存在且设备名是什么 | `clinfo -l`；`Ext.CLIJ2_clInfo()` | CLIJ2 默认取第一项，多设备会选错 |
| V7 | TDR 注册表是否已调 | 查 `TdrDelay` | 不调，大图 GPU 必炸 |
| V8 | .ets 目录结构是否完整（VSI） | 抽样检查 `_<name>_/` 与 `.ets` | VSI 最常见的失败点 |
| V9 | 计划任务是否会在 3 天后被杀 | 查 `ExecutionTimeLimit` | 长批处理静默中断 |

# 6. 单文件并行：能否做、怎么做、代价是什么

## 6.1 官方立场（此前会话的说法需要修正）

- **官方定论**：Bio-Formats 的格式 reader **不是线程安全**的；并行时必须「**每个并行会话各自完整初始化一个新的 reader**」，禁止多线程共享同一个 `IFormatReader` 实例（官方 *File reader* 开发文档）。
- **官方给的单文件并行范式**：每个 worker 一个 **`Memoizer` 包装的新 reader** 读**同一个文件**的不同部分——MATLAB 文档 *Improving reading performance* 里就是 `Memoizer` + `parfor` 的示例，Bio-Formats 还为此补了多线程测试（PR #1693）。
- 所以此前会话里「Bio-Formats 本身不支持多线程，只能文件级并行」这句话**过于绝对**：准确表述是「**reader 实例不能共享；单文件并行是可行的，但必须多实例**」。

## 6.2 已经有人把它工程化了：bioformats2raw

我直接读了 bioformats2raw 的 README 与 v0.12.1 源码（一手证据）：

| 事实 | 内容 |
| :-- | :-- |
| 线程模型 | 启动时创建 `maxWorkers` 个**各自独立**的 reader 放进 `ArrayBlockingQueue` 池，配一个同尺寸线程池；每个 reader = 原生 reader → `Memoizer` → `ChannelSeparator` → `setId`。tile 任务各取一个 reader，实例不共享 |
| `--max-workers` | **默认 = 检测到的 CPU 数**（README 与源码对默认值口径不完全一致，源码里还有 4 的上限截断，须实机核对） |
| 何时必须设为 1 | README 原文：「**如果输入数据需要一个非线程安全的 Bio-Formats reader，worker 数应设为 1**。这不是常见情况，但 Imaris HDF 是已知个例。」**CZI/VSI/OIR/ND2 不在其列** |
| 性能警告 | README 原文：在高带宽存储（SATA/NVMe）上，**worker 数越高收益急剧递减**（sharp diminishing returns），应改用更大的 `--tile-width/--tile-height`（默认 1024） |
| memo 缓存 | `--memo-directory` 可把 `.*.bfmemo` 指到本地盘（0.5.0 起转换结束默认删除）；`Memoizer` 仅在 `setId` 耗时 > 100ms 时才写 memo |
| 元数据提速 | `ImageReader` 有 `setMetadataOptions()` / `setMetadataFiltered()` / `setOriginalMetadataPopulated()`；bioformats2raw 硬编码 `setMetadataFiltered(true)`。**`MetadataLevel.MINIMUM` 的实际收益未证实**（官方 javadoc 页 404） |
| `bfconvert` | **没有任何并行/线程数选项**（只有 `-cache`、`-tilex/-tiley`、`-crop`、`-no-sequential` 等）→ 要并行就用 bioformats2raw，或自己写 reader 池 |

## 6.3 代价与坑（必须知道的坏消息）

1. **CZI 的 JPEG-XR 并发解码不稳定**。社区实测（MATLAB `parfor`，每 worker 一个 Memoizer 读同一 CZI）：worker 越多失败越多——6–8 → 1 次失败、12 → 1–2 次、24 → 3–5 次，报 `UnsatisfiedLinkError: ome.jxrlib.JXRJNI.new_DecodeContext`（CZI 的 JPEG-XR **原生**解码库）。更小的块、更多内存能撑更多 worker，但**这是压测才能定的数**。
2. **没有公开的加速比基准**。本次检索未找到任何受控的单文件并行加速比数据（各 `--max-workers` 的耗时曲线、CPU 解压 vs 磁盘 IO 的占比）。**结论：必须自己在目标机上量**（V5）。
3. **GPU 完全不参与**。Bio-Formats 只有 CPU 解码通路，没有任何 GPU/CUDA 解码。

## 6.4 推荐做法（按稳定性排序）

1. **多文件 → 多进程**（最稳、最快见效）：按文件切分，每进程独立 `-Xmx`；`N × Xmx` 不要超过物理内存的 ~75%。
2. **单文件 → `bioformats2raw --max-workers=N`**：先用 `--max-workers=1` 记基线，再试 4/8/16，配 `--tile-width/--tile-height` 与 `--memo-directory`，**用实测决定最终值**。产出 OME-Zarr，正好是下游 GPU 计算层的天然输入。
3. **若瓶颈锁定在 CZI**：改用 `pylibCZIrw` / `czifile` 在**子块粒度**并行（避开 Bio-Formats 的 JXR 原生库），或对 CZI 直接调 libCZI 的 `ReadSubBlock`。
4. **不要自己从零写 reader 池**——除非你要做的正是 bioformats2raw 已做的事。

---

# 7. 用 Rust 重构单文件并行读取：评估结论

> 直接回答你的问题 3.1：**技术上做得到，但不建议为此重构读取层。**

## 7.1 现有 Rust 生态的真实状态

| 路线 | 具体项目 | 状态 | 许可 |
| :-- | :-- | :-- | :-- |
| **最成熟现成路线** | `henriksson-lab/bioformats-rs`（Bio-Formats 8.5.0 的 LLM 翻译；crates.io `bioformats` 0.1.8，131 commits，2026-10 仍活跃） | CZI/ND2/VSI/OIR/MRC/OME-TIFF/OME-Zarr **均标 ✅**，API 为 `ImageReader::open / open_bytes_region` | **按格式分许可：CZI/ND2/LIF/MRC 属 GPL，TIFF/OME-TIFF 属 BSD** |
| **最短 FFI 路径** | `libczirw-sys` 0.5.1（Rust 封装 ZEISS 官方 `libCZIAPI`，含 `CziReader`/`CziWriter` 安全 wrapper，累计 ~2000 下载） | 可用，静态/动态链接均可 | Rust 侧 MIT/Apache；**libCZI 本体 LGPLv3 + 商业双许可** |
| 纯 Rust 单格式 | `czi` 1.0.0（**不支持 JPEG-XR**）、`nd2-rs` 0.2.0（累计 294 下载）、`openreadout-czi/vsi/oir`（42–195 下载，2026-10 新发布） | **全部过年轻，无生产证据** | 多为 MIT/Apache |
| 唯一有基准的纯 Rust | `openslide-pure-rs`：Aperio 1.44×、Hamamatsu NDPI 2.3–2.8×、MIRAX 最高 35×、DICOM 18–19×，RSS 降到 0.19–0.61× | **但像素校验和与参考实现不一致**（纯 Rust JPEG/JPEG2000 舍入差异），作者声明「不要轻信」；且把 **Zeiss CZI 标为 Experimental (reference blocked)** | — |

## 7.2 为什么不建议

- **格式复杂度不在「并行」上，而在「正确性」上**：CZI 的 JPEG-XR + 金字塔瓦片 + M 维 mosaic、VSI 的 `.ets` 分片、ND2 的变长 chunk，都是深坑。Bio-Formats 有 ~20 年的兼容性积累（164+ 格式）。
- **并行本身用 Rust 也快不了多少**：瓶颈是解码与 IO，不是调度。换语言解决不了 JPEG-XR 解码器的问题（Rust 目前没有成熟 JPEG-XR 实现，openslide-pure-rs 只能实验性开启）。
- **许可风险**：CZI/ND2/MRC 的可用实现是 **GPL**（bioformats-rs）或 **LGPL/商业双许可**（libCZI）。若这是要交付给平台/客户的闭源产品，这一条可能直接否掉方案。

## 7.3 Rust 真正值得的落点（如果你的目标是性能）

| 落点 | 建议 | 依据 |
| :-- | :-- | :-- |
| 并行调度 / 流水线 | `rayon`、`tokio`（成熟） | 生态成熟 |
| **GPU 反卷积 / 超分后段** | `cudarc` 0.19.10（**累计 1001 万次下载**，CUDA **11.4–13.4**，含 cuFFT/cuDNN/cuBLAS） | 生态最成熟的 CUDA Rust 绑定 |
| OME-Zarr / OME-TIFF 读写 | `zarrs`（月下载 3.4 万，MIT/Apache） | 成熟 |
| 3D 渲染 | `wgpu` | 可选 |

**触发门槛（满足其一才考虑 Rust 化）**：读取耗时占比 < 30% 且算力占比 > 70%；或必须单进程低 RSS（内存受限场景）。

**下决定前必须先确认两件事**：① 这套东西是否**闭源商用**（决定能否碰 GPL 格式 reader）；② 你是否**已经持有 ZEN / NIS-Elements 授权**（厂商 SDK 可能已随授权提供，比自研划算）。

---

# 8. GPU 功能矩阵（你要的 4.1–4.5）

> 总原则：**Fiji 生态的「GPU」≈ OpenCL**（CLIJ2 / clijx-deconvolution / eSRRF / 3Dscript / MSSR 全是 OpenCL）。**CUDA 只在离开 Fiji 之后才存在**——这恰好是你这台机器（NVIDIA + 管理员权限）能吃到红利的地方。

## 8.1 拼接 stitch

| 工具 | 定位 | GPU | headless | 判断 |
| :-- | :-- | :-- | :-- | :-- |
| **Grid/Collection Stitching** | 规则网格 2D/3D | ❌ 纯 CPU | ⚠️ **源码 `Stitching_Grid.java` 无条件 `new GenericDialogPlus()`，无 headless 分支** → 必须实测；官方只保证 macro-recordable | 小规模可用，headless 存疑 |
| **BigStitcher** | 大规模 / 多视角 / 多通道 | ⚠️ **仅「多点反卷积」走 JNA+CUDA（需自编译 native 库）**；拼接/融合/平场全 CPU | ✅ **官方 headless 文档最完整**（Batch Processing 宏录制 + `System.exit(0)`）；超大数据走 **BigStitcher-Spark** CLI | **首选主干** |
| **MIST 2.1** | 仅 **2D** 网格 | ✅ CUDA（**GUI 里勾选**，官方建议显存 ≥1GB）；论文称比同类快 15–100× | ⚠️ 有 CLI（`java -jar MIST_...jar`），但**命令行是否支持 CUDA 未证实** | 2D 大网格的加速备选 |
| ashlar 1.20.0 | 2D 网格 + 平/暗场 | ❌ CPU | ✅ `pip install ashlar` CLI，`--ffp/--dfp` | Python 侧稳定备选 |
| m2stitch 0.7.2 | 2D 网格 | ❌ CPU | ✅ pip，API `m2stitch.stitch_images` | 轻量备选 |
| multiview-stitcher 0.1.62 | 多视角 + Zarr 流式 | ✅ `pip install "multiview-stitcher[gpu-cuda12]"`（cupy） | ⚠️ 无 CLI | 唯一现成 GPU 融合路线 |
| ZarrStitcher | — | — | — | **未找到**（GitHub/PyPI 均无） |
| diSPIMFusion | 双视角 SPIM | ✅ CUDA **10.0**，单卷 <4GB | ⚠️ 控制台程序 | **2021-12 停更**，不进产线 |

## 8.2 阴影矫正

| 工具 | GPU | headless | 判断 |
| :-- | :-- | :-- | :-- |
| BaSiC（Fiji 插件） | ❌ | ⚠️ jar 停留在 **2017-01**，纯 Java、只有 `GenericDialog` | **不建议** |
| **BaSiCPy 2.0.0** | ✅ 主实现已改 **PyTorch**（装上 torch 即 GPU） | ✅ CLI/ Python | **推荐**（放 Python 侧车） |
| 朴素平/暗场 `(I−D)/(F−D)` | — | ✅ | 要求：同物镜/曝光/增益、无饱和、线性响应；ashlar `--ffp/--dfp` 已内置 |
| CIDRE | ❌ | — | **2021-08 停更**（MATLAB/ImageJ） |
| BigStitcher Flatfield Correction | ❌ | ✅（需自备 dark/bright TIFF） | 实验性 |

## 8.3 反卷积

| 路线 | 后端 | Windows 可行性 | CUDA 依赖 | 判断 |
| :-- | :-- | :-- | :-- | :-- |
| **cudadecon 0.7.0 / pycudadecon 0.5.1** | **真 CUDA** | ✅ **conda-forge 有 `win-64` 构建**（我已实测确认，另有 linux-64）；`conda install -c conda-forge pycudadecon cuda-version=12`，**CUDA 运行库随包自带，无需装 Toolkit** | 自带，`CMAKE_CUDA_ARCHITECTURES=all-major`（不限算力） | **CUDA 首选** |
| CLIJ2-FFT | OpenCL（clFFT） | Fiji 内：需 clij/clij2/clijx-deconvolution 三个站点 | — | ⚠️ **headless 有实测坑**：`ImageJ-linux64 -macro` 调 CLIJ2 直接抛 RuntimeException（论坛 77654），提问者改用 pyclesperanto → **headless 批处理别走 Fiji 宏** |
| deconwolf 0.4.6 | OpenCL | ✅ **有 Windows 安装包/二进制，纯 CLI `dw`** | — | **CLI headless 最契合**，注意 `DW_TEMPDIR` |
| RedLionfish 0.10 | OpenCL（PyOpenCL+Reikna） | ✅ pip | — | **仅 3D**，GPU 失败自动回落 CPU |
| DeconvolutionLab2 | ❌ 纯 CPU | ✅ | — | 算法最全但无 GPU |
| Multiview deconvolution | **CUDA** | ⚠️ **需自编译 `FourierConvolutionCUDALib`**（CUDA+cuFFT+boost），旧算力会 `nvcc fatal compute_30` | 需 | 仅多视角场景 |
| Microvolution（商业） | CUDA | — | — | ⚠️ **官网已解析不到站点（TLS 失败/404）**，论坛称已停售停维护 → **待你或采购确认，暂不纳入** |
| 深度学习：ZS-DeconvNet | TF-gpu 2.5.0 + **CUDA 11.4**（论文实测 RTX 3090） | ⚠️ Fiji 插件需装 TF jar | 强绑定 | 可试零样本 2D/3D |
| 深度学习：CARE / CSBDeep | TF1/TF2，**CUDA/cuDNN 严格配对** | ⚠️ 版本地狱 | 强绑定 | 长期迁 **CAREamics（PyTorch）**；`n2v` 只兼容 TF 2.7/2.10/2.13，**不兼容 ≥2.16** |

## 8.4 超分（**先分清你要的是哪一类**）

你说的是「**像素倍增，减少图像颗粒锯齿感**」——按字面，这**不是真超分**，而是「上采样 + 去噪 + 去卷积」的组合。三者代价差一个数量级，建议按下面分层落地：

| 层 | 你要的效果 | 手段 | GPU | 备注 |
| :-- | :-- | :-- | :-- | :-- |
| **① 像素倍增** | 像素数 ×2/×4 | Lanczos/bicubic 插值（ImageJ `Scale`、CuPy、scipy） | CPU 足够 / CuPy 可选 | **单独做这件事几乎不改善「颗粒感」**，只会把颗粒放大 |
| **② 去噪**（这才是「颗粒感」的解药） | 颗粒变细、背景干净 | Noise2Void / CAREamics（PyTorch CUDA）、CLIJ2 去噪、BaSiCPy 先修照明 | ✅ | 先做阴影矫正 + 去噪，再谈放大 |
| **③ 真超分** | 分辨率真的提高 | **eSRRF / NanoJ**（纯 OpenCL，**需时序涨落数据**）；**MSSR**（单帧，Nat Commun 13:7452，插件有「GPU Computing」开关但**未写明后端**）；**CARE**（TF 版本坑）；ZS-DeconvNet | OpenCL / TF-CUDA | ⚠️ 荧光涨落类方法**要求同一视野多帧**，「一张图变大」做不到 |
| ⚠️ 不建议 | — | Real-ESRGAN（BSD-3，ncnn-vulkan 版可免 CUDA）、SwinIR（Apache-2.0） | — | 属**自然图像** SR，**显微图像的适用性无同行评审证据**，容易生成假结构 |

## 8.5 3D 渲染与视频导出/播放

| 方案 | GPU | headless | 判断 |
| :-- | :-- | :-- | :-- |
| **3Dscript**（Fiji 内） | ✅ OpenCL，但**硬约束**：只接受 `CL_DEVICE_TYPE_GPU` 且必须 `CL_DEVICE_IMAGE_SUPPORT=TRUE`；**无 CUDA 实现** | ⚠️ 绕开菜单，直接调静态方法 **`BatchRaycaster.render(ImagePlus, scriptPath, w, h, false)`**（`Animator` 不 import AWT） | **首选但要 PoC**；⚠️ **最后提交 2025-06-06、v0.2.4、无 Releases，维护近乎停更** |
| 3Dscript + POV-Ray 后端 | ❌ CPU 光追 | ⚠️ 硬编码 `C:\Program Files\POV-Ray\v3.7-beta\bin\pvengine64.exe` | 无 GPU 时的退路 |
| **ImageJ 3D Viewer** | Java 3D | ❌ **不可能**：`takeSnapshot()` 需 `getDefaultScreenDevice()`；官方 FAQ 明说**无 workaround** | **放弃** |
| BigDataViewer 录制 | — | ❌ Windows 无 Xvfb | **放弃** |
| **napari + napari-animation** | ✅（OpenGL） | ✅ `napari.Viewer(show=False)` / `ViewerModel()` + `QT_QPA_PLATFORM=offscreen`；`Animation.animate('a.mp4', fps=20, quality=5)` 直出 mp4 | **Python 侧首选** |
| **PyVista / VTK** | ✅（EGL/OSMesa） | ✅ `Plotter.open_movie()` + `write_frame()`；VTK ≥9.5 提供 OSMesa 离屏轮子（无 X 时会警告并可能 segfault） | 大体积渲染备选 |
| Blender | ✅ CUDA/OptiX | ✅ `blender -b f.blend -x 1 -o //render -a`（`-f/-a` 放最后；Windows 注意 TDR） | 只做「美化输出」 |
| ParaView | ✅ | ⚠️ **Windows 版没有 `pvbatch`**（官方原文），用 `pvpython`；mp4 仅 Windows 可存，官方建议 PNG 帧 + ffmpeg | 不推荐当管线 |
| OME-Zarr → mp4 专用工具 | — | — | **未找到**；可行组合 = `napari + napari-ome-zarr 0.11.0 + napari-animation`，或 `zarr/dask → PyVista` |
| **交互核验**（人工查看） | — | — | 推荐顺序：**vizarr（纯浏览器 GPU，零安装）→ napari-ome-zarr → Fiji BigDataViewer**；Imaris/arivis 是否原生读 OME-Zarr **未找到官方证据**，需向厂商确认 |

## 8.6 「Fiji + Python 侧车」还是「全 Python」？——**混合，不要替代**

| 层 | 该用什么 | 理由 |
| :-- | :-- | :-- |
| **格式读取** | **必须留 Bio-Formats / Fiji** | **VSI/OIR 没有原生 Python 读取器**，Bio-Formats 是唯一通路 |
| 元数据 | Bio-Formats（OME + 全量 OriginalMetadata） | 见 §4 |
| 读取层 Python 补充 | `bioio 3.6.0` + `bioio-czi/nd2/ome-tiff/ome-tiled-tiff/ome-zarr`（`dask_data` 分块、`mosaic_dask_data` 拼接、`physical_pixel_sizes`） | ⚠️ **`aicsimageio` 已进维护模式，不要再用**；bioio **无 VSI/OIR 插件** |
| GPU 计算 | **原生 Windows 只有 `CuPy 14.2.0`（`cupy-cuda12x` 有 win_amd64 轮子）与 `pyclesperanto[cuda] 0.25.1`** | |
| **cuCIM** | ⚠️ **只能读 SVS / Philips TIFF / 分块 RGB TIFF——没有 CZI/VSI/ND2/OIR**；**只发 manylinux 轮子，Windows 装不上**（RAPIDS 官方 Windows 路径只有 Win11 + WSL2） | **不要把 cuCIM 当读取层规划** |
| cuCIM 的算法 | 若走 WSL2，`cucim.skimage.restoration.richardson_lucy()/wiener()` 与 `registration.phase_cross_correlation()`（GPU 版）可直接用 | 与 Windows 侧用 OME-Zarr 交换 |
| Fiji ↔ Python | `pyimagej 1.8.0`（JPype）驱动同一 JVM | |

---

# 9. 推荐架构（三层 + 文件契约）

```
┌─ L1 采集入库层（Windows，Fiji headless + Bio-Formats 8.5.0）────────────────┐
│  输入：CZI / VSI+ETS / OIR / ND2 / MRC(待证)                               │
│  动作：① 只读打开 → ② 抽 OME 字段 + 全量 OriginalMetadata → ③ 转 OME-Zarr  │
│  并行：多文件=多进程；单文件=bioformats2raw --max-workers（实测调参）       │
│  产出：*.ome.zarr  +  *.meta.json（成像参数审计表）  +  *.status.json      │
│  红线：不用 Importer 插件；不靠退出码判成败；memo 指本地盘                  │
└────────────────────────────────────────────────────────────────────────────┘
                        │  文件契约（唯一交接方式）
                        ▼
┌─ L2 计算层（Python + CUDA，不碰厂商格式）──────────────────────────────────┐
│  阴影矫正 BaSiCPy(PyTorch) / ashlar --ffp --dfp                            │
│  拼接      2D: MIST CLI 或 ashlar；3D/多视角: BigStitcher(CPU) 或           │
│            multiview-stitcher[cupy]                                        │
│  反卷积    cudadecon / pycudadecon（CUDA，conda-forge win-64）              │
│  去噪/超分 Noise2Void / CAREamics（PyTorch CUDA）；真超分走 eSRRF/MSSR      │
│  通用 GPU  CuPy / pyclesperanto                                            │
└────────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─ L3 渲染与核验层 ──────────────────────────────────────────────────────────┐
│  批处理出片：3Dscript BatchRaycaster(OpenCL) 或 napari-animation / PyVista  │
│  人工核验：vizarr（浏览器零安装）→ napari-ome-zarr → BigDataViewer          │
└────────────────────────────────────────────────────────────────────────────┘
```

**三条架构红线**：
1. **厂商原始格式只解析一次**（在 L1），下游一律读 OME-Zarr/OME-TIFF。否则每加一个功能都要重踩一遍 §4 的元数据坑。
2. **headless 与交互分离**：交互查看器永不出现在批处理服务里（Windows 上 3D Viewer / BDV 录制这条路已被官方判死）。
3. **GPU 只在 L2/L3 用**：Fiji 里最可靠的 GPU 只有 CLIJ2(OpenCL) 与 3Dscript(OpenCL)；要 CUDA 就出 Fiji。

---

# 10. 实施路线（建议）

| 阶段 | 时长 | 做什么 | 验收判据 |
| :-- | :-- | :-- | :-- |
| **0 只读核查** | 0.5 天 | 跑完 §5 的 V1–V9；拿 4 种格式各 1 个真实文件（**含 1 个纳析 .mrc**） | 一页实测结果：Fiji 版本、headless 能否 `showinf`、.mrc 是否 MRC2004/2014、维度断言是否通过 |
| **1 headless 骨架** | 2–3 天 | 硬件探测脚本（§2）+ 元数据双轨导出（OME + 全量 JSON）+ 状态文件机制 | 同一台机器上跑完一批小文件，产出 meta.json 且字段与厂商软件一致 |
| **2 并行与拼接 PoC** | 1 周 | `bioformats2raw --max-workers=1/4/8/16` 实测（含 CZI JPEG-XR 稳定性）；2×2 → 5×5 tile 拼接对比 BigStitcher / MIST / ashlar | 有加速比曲线与失败率；拼接接缝无错位（人工抽检 3 处） |
| **3 GPU 计算层** | 1–2 周 | 装 conda 环境（pycudadecon/cupy）；BaSiCPy 阴影矫正；一轮反卷积 + 去噪的参数标定 | 一张图在 CUDA 与 CPU 上的耗时/质量对比 |
| **4 渲染与交付** | 1 周 | 3Dscript PoC（若失败即切 napari-animation）；vizarr 核验流程；README + 一份「怎么加新格式」的 SOP | 一条从原始文件到 mp4 的完整可复跑链路 |

**顺序上的建议**：先做阶段 0 与 1，**不要一开始就碰 GPU 与 Rust**。你这套需求里真正会卡住项目的是**元数据保全**与**格式兼容性**（纳析），而不是算力。

---

# 11. 与前次 DeepSeek 会话结论的差异（哪些被修正）

| 前次结论 | 本次核实 | 处置 |
| :-- | :-- | :-- |
| 「Bio-Formats 的 Reader 不是线程安全的，多线程只能文件级并行」 | **部分修正**：reader 实例确实不能共享，但**官方范式支持「每 worker 一个新 reader 读同一文件」**，bioformats2raw 已把它产品化 | 单文件并行**可行**，走 bioformats2raw |
| 「MIST 完全支持 CUDA，16×22 tile GPU 比 CPU 快 2×」 | **需修正**：CUDA 要在 **GUI** 里勾选，**命令行是否支持 CUDA 未证实**；仅 **2D**；官方/论文口径是「比同类快 15–100×」 | 降级为「2D 大网格的加速备选」，需实测 |
| 「3Dscript 提供 headless 的 BatchRaycaster.render()，200 帧 <1 分钟」 | **部分证实**：静态方法入口确实存在（`render(imp, script, w, h, false)`），但 **2025-06 后停更**、**只认 GPU + `CL_DEVICE_IMAGE_SUPPORT`**、**无 CUDA** | 保留为首选，但**必须 PoC** 并铺 napari 备线 |
| 「eSRRF 完全支持 OpenCL GPU 加速」 | 证实，但 **Windows 10/11 有已知 OpenCL 故障**记录 | 需在目标机验证 |
| 「BaSiCPy 支持 GPU（JAX/CuPy）」 | **修正**：BaSiCPy **2.0.0 主实现已改为 PyTorch**，GPU 靠装 PyTorch | 按 PyTorch 环境规划 |
| 「Multiview Deconvolution 是 Fiji 里性能最高的 CUDA 反卷积」 | 部分证实，但**需自编译 CUDA native 库**、仅多视角 | 不进产线，除非有多视角需求 |
| 「Grid/Collection Stitching headless 有参数解析 bug（已修）」 | **加强**：源码里**无条件 `new GenericDialogPlus()`、无 headless 分支** | 从「显式写参即可」升级为「**必须实测**」 |
| （前次未提） | **新增重大风险**：CZI 的 JPEG-XR 并发解码在高 worker 数下失败率上升 | 写进阶段 2 的压测项 |
| （前次未提） | **新增**：ND2/VSI/OIR 的元数据缺口比前次描述严重得多（激光全缺 / 伪彩丢失 / 功率不映射） | 强制「元数据双轨」 |
| （前次未提） | **新增**：MRCReader 在 `formats-gpl`（**BSD=No**），且非 AGAR 扩展头时像素尺寸单位按 **Å** 解释（可差 1e4 倍） | 写进 GPL 合规与单位核对项 |
| （前次未提） | **新增**：`wmic` 已被 Windows 移除；`bioformats2raw --max-workers` 与 `--memo-directory`；`cudadecon` 有 conda-forge win-64 | 已进 §2/§6/§8 |

---

# 12. 主要证据链接（按主题）

**Fiji headless 与工程化**
- https://imagej.net/learn/headless ・ https://imagej.net/scripting/headless ・ https://imagej.net/learn/launcher ・ https://imagej.net/formats/bio-formats ・ https://imagej.net/develop/logging
- 退出码问题：https://github.com/imagej/imagej2/issues/61
- headless VerifyError 实测：https://forum.image.sc/t/java-lang-verifyerror-with-bio-formats-headless-on-slurm-cluster/119103
- 3D Viewer 无 headless 方案：https://imagej.net/plugins/3d-viewer/
- Grid/Collection Stitching headless bug：https://fiji.sc/bug/900.html
- 大内存管理：https://bio-formats.readthedocs.io/en/v8.0.1/users/imagej/managing-memory.html

**Windows 平台**
- 长路径：https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation ・ https://bugs.openjdk.org/browse/JDK-8315405
- SMB 慢速：https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/slow-smb-file-transfer
- Defender 排除项：https://learn.microsoft.com/en-us/defender-endpoint/microsoft-defender-antivirus-exclusions-overview
- 计划任务超时：https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings-executiontimelimit
- wmic 移除：https://support.microsoft.com/en-us/servicing/os/windows/docs/2025/09/windows-management-instrumentation-command-line-wmic-removal-from-windows
- 磁盘类型：https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-physicaldisk
- JEP 400（UTF-8 默认）：https://openjdk.org/jeps/400

**硬件探测与 GPU**
- nvidia-smi：https://docs.nvidia.com/deploy/nvidia-smi/index.html ・ CUDA 兼容表：https://docs.nvidia.com/deploy/cuda-compatibility/latest/minor-version-compatibility.html
- clinfo：https://github.com/Oblomov/clinfo
- CLIJ2 FAQ（10MB 门槛、TDR）：https://clij.github.io/clij2-docs/faq ・ 安装：https://clij.github.io/clij2-docs/installationInFiji

**格式与元数据**
- ZeissCZIReader 源码：https://raw.githubusercontent.com/ome/bioformats/develop/components/formats-gpl/src/loci/formats/in/ZeissCZIReader.java
- CZI 相关 issue：#4194 / #4102 / #2975
- libCZI：https://github.com/ZEISS/libczi ・ pylibCZIrw 多线程讨论：https://forum.image.sc/t/about-the-multithreading-in-pylibczirw-or-libczi/79013 ・ czifile：https://pypi.org/project/czifile/
- VSI 格式页：https://bio-formats.readthedocs.io/en/v8.5.0/formats/cellsens-vsi.html ・ .ets 缺失：https://forum.image.sc/t/vsi-missing-expected-ets-files/50410
- ND2 维度 bug #4431：https://github.com/ome/bioformats/issues/4431
- OIR 激光功率 #3748：https://forum.image.sc/t/bio-formats-cannot-read-laserpower-from-olympus-oir-file-meta-information/60311
- MRC 格式页：https://bio-formats.readthedocs.io/en/v8.5.0/formats/mrc.html ・ mrcfile：https://mrcfile.readthedocs.io/en/stable/usage_guide.html
- 纳析官网：https://www.naxi-tech.com/ ・ DeepInsight：https://www.naxi-tech.com/deepinsight ・ rDL-SIM（李栋组，.mrc 用法）：https://github.com/qc17-THU/rDL-SIM

**并行与 Rust**
- Bio-Formats File reader 开发文档：https://bio-formats.readthedocs.io/en/stable/developers/file-reader.html
- MATLAB 并行范式（Memoizer+parfor）：https://bio-formats.readthedocs.io/en/stable/_sources/developers/matlab-dev.rst.txt
- 并行读 tile 实测帖（JPEG-XR 失败率）：https://forum.image.sc/t/parallel-read-tiles-using-bioformats-matlab/89242
- bioformats2raw：https://github.com/glencoesoftware/bioformats2raw（线程模型见 `Converter.java`）
- bioformats-rs：https://github.com/henriksson-lab/bioformats-rs ・ https://lib.rs/crates/bioformats
- libczirw-sys：https://crates.io/crates/libczirw-sys ・ openslide-pure-rs：https://github.com/henriksson-lab/openslide-pure-rs
- cudarc：https://crates.io/crates/cudarc

**拼接 / 阴影 / 反卷积 / 超分 / 渲染**
- BigStitcher headless：https://imagej.net/plugins/bigstitcher/headless
- MIST：https://github.com/usnistgov/MIST ・ ashlar：https://github.com/labsyspharm/ashlar ・ multiview-stitcher：https://github.com/multiview-stitcher/multiview-stitcher
- BaSiC：https://github.com/marrlab/BaSiC ・ BaSiCPy：https://github.com/peng-lab/BaSiCPy
- clij2-fft：https://github.com/clij/clij2-fft ・ CLIJ2 headless 报错帖：https://forum.image.sc/t/77654.json
- deconwolf：https://elgw.github.io/deconwolf/history.html ・ cudadecon CMake：https://gcore.jsdelivr.net/gh/scopetools/cudadecon@main/src/CMakeLists.txt
- NanoJ-eSRRF：https://github.com/HenriquesLab/NanoJ-eSRRF/wiki ・ MSSR：https://www.nature.com/articles/s41467-022-34693-9
- ZS-DeconvNet：https://github.com/TristaZeng/ZS-DeconvNet
- 3Dscript：https://github.com/bene51/3Dscript
- napari headless：https://napari.org/stable/howtos/headless.html ・ PyVista：https://github.com/pyvista/pyvista ・ ParaView 批处理：https://docs.paraview.org/en/latest/Tutorials/ClassroomTutorials/pythonAndBatchPvpythonAndPvbatch.html

**替代栈**
- cuCIM：https://github.com/rapidsai/cucim ・ https://docs.nvidia.com/cucim/latest/api/ ・ RAPIDS 安装：https://docs.rapids.ai/install/
- bioio：https://bioio-devs.github.io/bioio/OVERVIEW.html ・ nd2：https://pypi.org/project/nd2/ ・ mrcfile：https://pypi.org/project/mrcfile/
- pyclesperanto CUDA：https://pypi.org/project/pyclesperanto-cuda/

---

## 附录 A：本轮调研的方法与可信度说明

- 本报告基于 **22 个调研子任务**（联网检索 + 源码/官方文档直取）与**一手核验 3 项**（bioformats2raw README 原文、conda-forge `cudadecon` 的 win-64 构建、bioformats2raw `--max-workers` 条款）。
- 调研过程中检索通道多次被限流（部分子任务报 `firecrawl 429`），**因此"未找到"不等于"不存在"**；凡标「未证实/未找到」的条目，请按 §5 实机验证。
- 本报告**未在任何机器上执行过脚本**，所有命令均为「待验证的建议」。

## 附录 B：需要你补充的三样东西

1. **纳析 `.mrc` 样例文件 1–2 个**（原始数据即可）+ 厂商格式说明（有则更佳）；
2. 蔡司/奥林巴斯/尼康各 **1 个真实文件**（含一个多 tile/多 series 的）；
3. 目标机的 `fiji.bat --help` 输出与 `nvidia-smi -L` 输出（各一行即可）。

拿到这三样，阶段 0 就能在半天内出结论。

