@echo off
REM build-imagejjs.bat — 实测构建链（2026-10-25 阶段0 复核通过版本）
REM 前置：Node 13.14.0 解压于 %IJWEB%\node-v13.14.0-win-x64；本机 git 不可用时全部走 api.github.com 通道
REM 用法： set IJWEB=C:\Users\sr123\ijweb ^&^& build-imagejjs.bat

setlocal
if "%IJWEB%"=="" set IJWEB=C:\Users\sr123\ijweb
set PATH=%IJWEB%\node-v13.14.0-win-x64;%PATH%

cd /d %IJWEB%

if not exist repo.tar.gz curl -L -o repo.tar.gz https://api.github.com/repos/imjoy-team/imagej.js/tarball/master
if not exist ij153m.tgz  curl -L -o ij153m.tgz  https://github.com/imjoy-team/ImageJA.JS/releases/download/1.53m/imagej-js-dist.tgz
if not exist ij153m3.tgz curl -L -o ij153m3.tgz https://github.com/imjoy-team/ImageJA.JS/releases/download/1.53m3/imagej-js-dist.tgz

if not exist imjoy-team-imagej.js-c25ef77 tar -xzf repo.tar.gz

cd imjoy-team-imagej.js-c25ef77
REM R7 偏差①：vue-js-modal 的 github: 依赖改为等价 tarball URL（无 git 环境必需；内容同 tag）
powershell -Command "(Get-Content package.json -Raw) -replace '\"vue-js-modal\": \"github:imjoy-team/vue-js-modal#2.0.0-rc.3g\"', '\"vue-js-modal\": \"https://api.github.com/repos/imjoy-team/vue-js-modal/tarball/2.0.0-rc.3g\"' | Set-Content package.json -Encoding UTF8"

call npm install --no-audit --no-fund --loglevel=error || goto :err
call npm run build || goto :err

cd /d %IJWEB%
tar -xzf ij153m.tgz
tar -xzf ij153m3.tgz
xcopy /E /I /Y imagej-js-dist imjoy-team-imagej.js-c25ef77\dist\ || goto :err
REM 覆盖层：宏库 + 门户页（本 overlay 的 macros/ 与 portal.html）
xcopy /E /I /Y "%~dp0macros" imjoy-team-imagej.js-c25ef77\dist\macros\ || goto :err
copy /Y "%~dp0portal.html" imjoy-team-imagej.js-c25ef77\dist\portal.html || goto :err

echo ==== BUILD OK ==== dist = %IJWEB%\imjoy-team-imagej.js-c25ef77\dist
echo 冒烟： cd imjoy-team-imagej.js-c25ef77 ^&^& npm run serve  [http://127.0.0.1:9090/portal.html]
exit /b 0
:err
echo ==== BUILD FAILED ====
exit /b 1
