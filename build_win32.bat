@echo off
set TEMP=C:\Users\Yiuf\AppData\Local\Temp
set TMP=C:\Users\Yiuf\AppData\Local\Temp
set PATH=C:\msys64\mingw64\bin;C:\msys64\usr\bin;C:\msys64\usr\local\bin;%PATH%
cd /d D:\Code\koreader\base
mingw32-make TARGET=win32 USE_NINJA= -j4 2>&1
