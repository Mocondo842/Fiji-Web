@echo off
rem Branch B / B3 viewer v2: drag an .ome.zarr FOLDER onto this bat
rem -> converts to OME-TIFF (raw2ometiff) -> opens it in Fiji automatically.
rem (In-process N5 zarr viewing is broken in this Fiji build: reader & importer both hang - documented.)
if "%~1"=="" (
  echo Drag an .ome.zarr folder onto this bat icon to view it in Fiji.
  pause
  exit /b 1
)
set "JAVA_HOME=C:\Users\sr123\APP\Fiji\java\win64\zulu21.42.19-ca-jdk21.0.7-win_x64"
set "JAVA_OPTS=-Xmx12g"
set "SRC=%~1"
set "TIF=%~dpn1_view.ome.tif"
echo Converting to OME-TIFF for viewing ^(about 1-2 min per GB^)...
echo   %SRC%  --^>  %TIF%
"C:\Users\sr123\ijweb\r2t\raw2ometiff-0.10.1\bin\raw2ometiff.bat" --max_workers 4 "%SRC%" "%TIF%"
if errorlevel 1 (
  echo FAILED - see messages above.
  pause
  exit /b 1
)
start "" "C:\Users\sr123\APP\Fiji\fiji-windows-x64.exe" "%TIF%"
