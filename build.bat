@echo off
rem WeKan-Lite build script - Windows (cmd.exe).
rem Cross-compiles src\wlhttp.lpr with FreePascal (fpc). See README.md / docs.
rem
rem Cross targets need the matching FPC cross build installed; missing toolchains make that
rem target fail (expected). Some targets are experimental in FPC (Linux s390x, AROS arm64).
rem
rem Env overrides:  set FPC=...   set FPCFLAGS=...   (e.g. set FPCFLAGS=-dWLDB_CLI)
setlocal enabledelayedexpansion
cd /d "%~dp0"

if "%FPC%"=="" set "FPC=fpc"
set "SRC=src\wlhttp.lpr"
set "OUTDIR=build"
set "BASEFLAGS=-O3 -Xs -Fusrc"

rem parallel arrays: CPUn / OSn / FLAGSn / OUTn / LBLn
set "N=20"
set "CPU1=x86_64"    & set "OS1=linux"   & set "FLAGS1="                            & set "OUT1=welite-linux-amd64"     & set "LBL1=Linux amd64"
set "CPU2=aarch64"   & set "OS2=linux"   & set "FLAGS2="                            & set "OUT2=welite-linux-arm64"     & set "LBL2=Linux arm64"
set "CPU3=arm"       & set "OS3=linux"   & set "FLAGS3=-CaEABIHF -CfVFPV3"          & set "OUT3=welite-linux-armhf"     & set "LBL3=Linux armhf"
set "CPU4=arm"       & set "OS4=linux"   & set "FLAGS4=-Cparmv7a -CfVFPV3 -CaEABIHF"& set "OUT4=welite-linux-armv7"     & set "LBL4=Linux armv7"
set "CPU5=s390x"     & set "OS5=linux"   & set "FLAGS5="                            & set "OUT5=welite-linux-s390x"     & set "LBL5=Linux s390x"
set "CPU6=powerpc"   & set "OS6=linux"   & set "FLAGS6="                            & set "OUT6=welite-linux-ppc"       & set "LBL6=Linux ppc"
set "CPU7=powerpc64" & set "OS7=linux"   & set "FLAGS7=-Caelfv2"                    & set "OUT7=welite-linux-ppc64le"   & set "LBL7=Linux ppc64le"
set "CPU8=aarch64"   & set "OS8=darwin"  & set "FLAGS8="                            & set "OUT8=welite-macos-arm64"     & set "LBL8=macOS arm64"
set "CPU9=i386"      & set "OS9=win32"   & set "FLAGS9="                            & set "OUT9=welite-windows-x86.exe" & set "LBL9=Windows x86"
set "CPU10=x86_64"   & set "OS10=win64"  & set "FLAGS10="                           & set "OUT10=welite-windows-amd64.exe" & set "LBL10=Windows amd64"
set "CPU11=i386"     & set "OS11=go32v2" & set "FLAGS11="                           & set "OUT11=welite-dos.exe"        & set "LBL11=DOS"
set "CPU12=x86_64"   & set "OS12=haiku"  & set "FLAGS12="                           & set "OUT12=welite-haiku"          & set "LBL12=Haiku"
set "CPU13=m68k"     & set "OS13=amiga"  & set "FLAGS13="                           & set "OUT13=welite-amiga-m68k"     & set "LBL13=Amiga m68k"
set "CPU14=powerpc"  & set "OS14=amiga"  & set "FLAGS14="                           & set "OUT14=welite-amigaos4-ppc"   & set "LBL14=AmigaOS 4.1 PPC"
set "CPU15=powerpc"  & set "OS15=morphos"& set "FLAGS15="                           & set "OUT15=welite-morphos"        & set "LBL15=MorphOS"
set "CPU16=i386"     & set "OS16=aros"   & set "FLAGS16="                           & set "OUT16=welite-aros-x86"       & set "LBL16=AROS x86"
set "CPU17=x86_64"   & set "OS17=aros"   & set "FLAGS17="                           & set "OUT17=welite-aros-amd64"     & set "LBL17=AROS amd64"
set "CPU18=aarch64"  & set "OS18=aros"   & set "FLAGS18="                           & set "OUT18=welite-aros-arm64"     & set "LBL18=AROS arm64"
set "CPU19=m68k"     & set "OS19=aros"   & set "FLAGS19="                           & set "OUT19=welite-aros-m68k"      & set "LBL19=AROS m68k"
set "CPU20=powerpc"  & set "OS20=aros"   & set "FLAGS20="                           & set "OUT20=welite-aros-ppc"       & set "LBL20=AROS ppc"

:menu
echo.
echo   WeKan-Lite build  (fpc: %FPC%)
echo   1) Build for current platform
echo   2) Build for all platforms
echo   3) Select platform and build for it
echo   4) Quit
set "C="
set /p "C=  Choice: "
if "%C%"=="1" goto current
if "%C%"=="2" goto all
if "%C%"=="3" goto select
if "%C%"=="4" goto end
echo   Pick 1-4.
goto menu

:current
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
echo ^>^> Building for current platform
"%FPC%" %BASEFLAGS% %FPCFLAGS% -o"%OUTDIR%\welite.exe" "%SRC%"
goto menu

:all
for /L %%i in (1,1,%N%) do call :build %%i
echo == done ==
goto menu

:select
echo.
for /L %%i in (1,1,%N%) do echo   %%i) !LBL%%i!
set "S="
set /p "S=  Platform number (or 0 to cancel): "
if "%S%"=="0" goto menu
if "%S%"=="" goto menu
call :build %S%
goto menu

:build
rem %1 = platform index
set "i=%~1"
if "!CPU%i!"=="" ( echo   No such platform: %i & exit /b )
if not exist "%OUTDIR%" mkdir "%OUTDIR%"
echo ^>^> Building !LBL%i!  (-P!CPU%i! -T!OS%i! !FLAGS%i!)
"%FPC%" %BASEFLAGS% %FPCFLAGS% -P!CPU%i! -T!OS%i! !FLAGS%i! -o"%OUTDIR%\!OUT%i!" "%SRC%"
exit /b

:end
endlocal
