@echo off
rem Branch B / B3: drag a microscopy file (czi/ims/nd2/tif...) onto THIS bat -> OME-Zarr beside the source
if "%~1"=="" (
  echo Drag a microscopy file onto this bat icon to convert it to OME-Zarr.
  pause
  exit /b 1
)
set "JAVA_HOME=C:\Users\sr123\APP\Fiji\java\win64\zulu21.42.19-ca-jdk21.0.7-win_x64"
set "JAVA_OPTS=-Xmx12g"
set "SRC=%~1"
set "OUT=%~dpn1.ome.zarr"
echo Converting:
echo   %SRC%
echo to:
echo   %OUT%
"C:\Users\sr123\ijweb\b2r\bioformats2raw-0.13.0\bin\bioformats2raw.bat" --max-workers 4 "%SRC%" "%OUT%"
if errorlevel 1 (echo FAILED - see messages above) else (echo DONE.)
pause
