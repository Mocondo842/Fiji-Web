---
title: 部署 README（v0 骨架 — 阶段 2 数据回填后成稿）
版本: v0（骨架；凡〔待实测〕处回填后删标记）
日期: 2026-10-25
适用基线: master@c25ef77 ・ 应用 v0.6.0 ・ 运行时 ImageJ 1.53m99 + CheerpJ 2.x（20201217_2）・ Node 13.14.0
---

# 1. 支持矩阵与门槛（回填区）

| 项 | 口径 | 数据来源 |
| :-- | :-- | :-- |
| 浏览器 | Chrome / Firefox（官方口径）；Edge〔待实测 V7〕；iPad/Android 平板〔待实测 V7〕；Safari 不承诺 | R10 |
| 单文件门槛 | 解压后像素数据 > **2GB** 不走 web 端〔V5 实测后修订〕 | R1 |
| 首载时间 | 〔待实测 V4：千兆局域网 3 次取中位 = ___ 〕；本机代理数据：首载全程约 35s、二载 domcontentloaded 495ms | G1 |
| 并发台数参考 | 〔待实测 V6〕 | R2 |
| 快捷键冲突清单 | 第一规则：**不用 Ctrl 组合**（浏览器拦截）。其余冲突项部署后收集补充 | 异常 8 |
| web 端格式支持 | **已实测（2026-10-25，V13 <1G 层）**：TIFF 族（普通/OME-TIFF/RGB 多通道）✅；**ND2 / CZI / MRC / IMS ❌ 全部不支持**（无 Bio-Formats）——厂商格式一律走 L1 管线或桌面 Fiji | N5/V13、复核记录-图像格式测试 |

# 2. 构建与更新流程（本机实测链路，2026-10-25）

构建机准备（一次性）：
1. Node 13.14.0 win-x64 zip（npmmirror：`https://registry.npmmirror.com/-/binary/node/v13.14.0/node-v13.14.0-win-x64.zip`）解压到 `C:\Users\sr123\ijweb\node-v13.14.0-win-x64`，PATH 内联使用（免安装）。
2. 本机 git/直连 GitHub 部分域名被重置：**源码与 release 资产走 api.github.com / release-assets.githubusercontent.com 通道**（实测可达）。

构建步骤（实测通过）：
```bat
cd C:\Users\sr123\ijweb
curl -L -o repo.tar.gz https://api.github.com/repos/imjoy-team/imagej.js/tarball/master
tar -xzf repo.tar.gz        && rem → imjoy-team-imagej.js-c25ef77
curl -L -o ij153m.tgz  https://github.com/imjoy-team/ImageJA.JS/releases/download/1.53m/imagej-js-dist.tgz
curl -L -o ij153m3.tgz https://github.com/imjoy-team/ImageJA.JS/releases/download/1.53m3/imagej-js-dist.tgz
cd imjoy-team-imagej.js-c25ef77
set PATH=C:\Users\sr123\ijweb\node-v13.14.0-win-x64;%PATH%
npm install                 && rem 1973 包 / 约 31s
npm run build               && rem webpack 4.46 production → dist
cd ..
tar -xzf ij153m.tgz  && tar -xzf ij153m3.tgz
xcopy /E /I /Y imagej-js-dist imjoy-team-imagej.js-c25ef77\dist\
xcopy /E /I /Y macros imjoy-team-imagej.js-c25ef77\dist\macros
```

**登记偏差（R7，复现构建时必须保留）**：
1. `package.json` 中 `vue-js-modal` 由 `github:imjoy-team/vue-js-modal#2.0.0-rc.3g` 改为等价 URL `https://api.github.com/repos/imjoy-team/vue-js-modal/tarball/2.0.0-rc.3g`（构建机无 git）。
2. ij153 按 get-imagej 脚本并入 1.53m + 1.53m3 两包；运行时报 1.53m99，以运行时为准。

**注意事项**：
- dist 必须挂在站点**根路径或独立端口**（根绝对路径资源 + service worker 作用域），不可子目录。
- 首载需出网拉 CheerpJ 运行时（cjrtnc.leaningtech.com，实测可达）；完全隔离网段才需本地化。
- webpack-dev-server 仅冒烟用；生产换 Nginx/IIS + 开机自启 + 防火墙放行端口〔端口待 IT 确认〕。
- 可选瘦身：dist 内 `ij153/plugins/Thunder_STORM.jar.js`（37MB）不用可删。

# 3. 宏库管理

- 单一事实来源：`C:\Users\sr123\ijweb\macros\{common,web,desktop}`；web 镜像 `dist\macros`；更新宏后无需重启服务。
- 准入规则：新宏先在 web 与桌面各跑一遍样例（R3/R4）；`common/` 禁止窗口依赖命令；保存收尾走对话框式 `saveAs("Tiff")`（R5）。
- 装入菜单的宏必须为 `macro "命名"` 块格式（阶段 0 实测）。
- 桌面端：`桌面端-交付\Fiji.app\plugins\ActionBar\my_tools.ijm` + Startup 行（见其安装说明）。

# 4. 使用入口

- 门户页：`http://<部署机IP>:<端口>/portal.html`（一键宏 / 装宏入菜单 / 保存与分流指引）
- 大文件（>2GB）：走 L1 管线 → OME-Zarr → vizarr 同源查看〔管线入口待阶段 3/V10〕

# 5. 回归清单（每次升级/换基线必跑，R7）

1. 门户页三个一键宏（S2）
2. install-macro 装入菜单（Plugins>Macros 出现条目）
3. `ij.IJ.getFullVersion()` 与 cjrtnc 资源版本（控制台/网络面板）
4. 保存对话框 → 浏览器下载
5. 桌面端按钮栏三键（S3，实机）
