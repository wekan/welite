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
set "BINDIR=build\bin"
set "ARCHROOT=build\arch"
set "BASEFLAGS=-O3 -Xs -Fusrc"

rem DOS 8.3 layout (see CLAUDE.md): each platform builds into build\arch\<code>\ (exe +
rem intermediates), then the executable is copied to build\bin\w<code>.exe. <code> is <=7 chars
rem so "w"+<code> stays <=8; every path component is <=8 chars.
rem parallel arrays: CPUn / OSn / FLAGSn / CODEn (<=7 chars) / LBLn
set "N=20"
set "CPU1=x86_64"    & set "OS1=linux"   & set "FLAGS1="                            & set "CODE1=linx64"  & set "LBL1=Linux amd64"
set "CPU2=aarch64"   & set "OS2=linux"   & set "FLAGS2="                            & set "CODE2=lina64"  & set "LBL2=Linux arm64"
set "CPU3=arm"       & set "OS3=linux"   & set "FLAGS3=-CaEABIHF -CfVFPV3"          & set "CODE3=linahf"  & set "LBL3=Linux armhf"
set "CPU4=arm"       & set "OS4=linux"   & set "FLAGS4=-Cparmv7a -CfVFPV3 -CaEABIHF"& set "CODE4=linav7"  & set "LBL4=Linux armv7"
set "CPU5=s390x"     & set "OS5=linux"   & set "FLAGS5="                            & set "CODE5=lins390" & set "LBL5=Linux s390x"
set "CPU6=powerpc"   & set "OS6=linux"   & set "FLAGS6="                            & set "CODE6=linppc"  & set "LBL6=Linux ppc"
set "CPU7=powerpc64" & set "OS7=linux"   & set "FLAGS7=-Caelfv2"                    & set "CODE7=linp64l" & set "LBL7=Linux ppc64le"
set "CPU8=aarch64"   & set "OS8=darwin"  & set "FLAGS8="                            & set "CODE8=maca64"  & set "LBL8=macOS arm64"
set "CPU9=i386"      & set "OS9=win32"   & set "FLAGS9="                            & set "CODE9=winx86"  & set "LBL9=Windows x86"
set "CPU10=x86_64"   & set "OS10=win64"  & set "FLAGS10="                           & set "CODE10=winx64" & set "LBL10=Windows amd64"
set "CPU11=i386"     & set "OS11=go32v2" & set "FLAGS11="                           & set "CODE11=dos"    & set "LBL11=DOS"
set "CPU12=x86_64"   & set "OS12=haiku"  & set "FLAGS12="                           & set "CODE12=haiku"  & set "LBL12=Haiku"
set "CPU13=m68k"     & set "OS13=amiga"  & set "FLAGS13="                           & set "CODE13=ami68k" & set "LBL13=Amiga m68k"
set "CPU14=powerpc"  & set "OS14=amiga"  & set "FLAGS14="                           & set "CODE14=amios4" & set "LBL14=AmigaOS 4.1 PPC"
set "CPU15=powerpc"  & set "OS15=morphos"& set "FLAGS15="                           & set "CODE15=morphos"& set "LBL15=MorphOS"
set "CPU16=i386"     & set "OS16=aros"   & set "FLAGS16="                           & set "CODE16=arosx86"& set "LBL16=AROS x86"
set "CPU17=x86_64"   & set "OS17=aros"   & set "FLAGS17="                           & set "CODE17=arosx64"& set "LBL17=AROS amd64"
set "CPU18=aarch64"  & set "OS18=aros"   & set "FLAGS18="                           & set "CODE18=arosa64"& set "LBL18=AROS arm64"
set "CPU19=m68k"     & set "OS19=aros"   & set "FLAGS19="                           & set "CODE19=aros68k"& set "LBL19=AROS m68k"
set "CPU20=powerpc"  & set "OS20=aros"   & set "FLAGS20="                           & set "CODE20=arosppc"& set "LBL20=AROS ppc"

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
if not exist "%ARCHROOT%\current" mkdir "%ARCHROOT%\current"
if not exist "%BINDIR%" mkdir "%BINDIR%"
echo ^>^> Building for current platform  -^> %ARCHROOT%\current\wcurrent.exe
"%FPC%" %BASEFLAGS% %FPCFLAGS% -FU"%ARCHROOT%\current" -FE"%ARCHROOT%\current" -o"%ARCHROOT%\current\wcurrent.exe" "%SRC%"
if exist "%ARCHROOT%\current\wcurrent.exe" copy /Y "%ARCHROOT%\current\wcurrent.exe" "%BINDIR%\wcurrent.exe" >nul
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
set "ARCH=%ARCHROOT%\!CODE%i!"
set "BIN=w!CODE%i!.exe"
if not exist "!ARCH!" mkdir "!ARCH!"
if not exist "%BINDIR%" mkdir "%BINDIR%"
echo ^>^> Building !LBL%i!  (-P!CPU%i! -T!OS%i! !FLAGS%i!)  -^> !ARCH!\!BIN!
"%FPC%" %BASEFLAGS% %FPCFLAGS% -P!CPU%i! -T!OS%i! !FLAGS%i! -FU"!ARCH!" -FE"!ARCH!" -o"!ARCH!\!BIN!" "%SRC%"
if exist "!ARCH!\!BIN!" copy /Y "!ARCH!\!BIN!" "%BINDIR%\!BIN!" >nul
exit /b

:end
endlocal
