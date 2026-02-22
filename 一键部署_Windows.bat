@echo off
title 校园网自动登录 - 一键部署
echo ========================================
echo    校园网自动登录 一键部署工具
echo    (零依赖 PowerShell 版)
echo ========================================
echo.

:: 输入账号密码
echo [1/4] 请输入校园网账号信息:
set /p SRUN_USER=  学号:
echo   密码(输入时不显示，输完按回车):
for /f "delims=" %%p in ('powershell -Command "$p=Read-Host -AsSecureString;[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "SRUN_PASS=%%p"
echo.
echo   默认服务器: http://192.168.75.252
echo   如果你的校区不同，请输入正确的服务器地址
set /p SRUN_SERVER=  服务器地址(直接回车使用默认):
if "%SRUN_SERVER%"=="" set "SRUN_SERVER=http://192.168.75.252"

:: 生成配置文件
echo.
echo [2/4] 生成配置文件...
(
echo [srun]
echo username = %SRUN_USER%
echo password = %SRUN_PASS%
echo server = %SRUN_SERVER%
echo ac_id = 1
) > "%~dp0config.ini"
echo       config.ini 已生成

:: 设置开机自启（VBS 调用 PowerShell）
echo.
echo [3/4] 设置开机自启...
set "VBS_PATH=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\srun_login.vbs"
set "PS1_PATH=%~dp0srun_login.ps1"
>"%VBS_PATH%" (
echo CreateObject^("WScript.Shell"^).Run "powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%PS1_PATH%"" -keepalive", 0, False
)
if exist "%VBS_PATH%" (
    echo       [成功] 开机自启已配置
) else (
    echo       [失败] 自启配置失败，检查权限
)

:: 测试登录
echo.
echo ----------------------------------------
echo [4/4] 测试登录...
echo ----------------------------------------
powershell -ExecutionPolicy Bypass -File "%~dp0srun_login.ps1"

:: 验证联网（用HTTP检测，校园网可能屏蔽ping）
echo.
echo 验证网络连通性（等待网络就绪）...
timeout /t 3 /nobreak >nul
powershell -ExecutionPolicy Bypass -Command "try { $r = Invoke-WebRequest -Uri 'https://www.baidu.com' -UseBasicParsing -TimeoutSec 10; if ($r.StatusCode -eq 200) { Write-Host '      [成功] 网络已连通，可正常上网！' } else { Write-Host '      [失败] 无法访问外网，请检查账号密码是否正确' } } catch { Write-Host '      [失败] 无法访问外网，请检查账号密码是否正确' }"

echo.
echo ========================================
echo   部署完成！下次开机将自动登录校园网
echo ========================================
echo.
echo   手动登录:  双击"手动登录.bat"
echo   卸载自启:  双击"卸载自启.bat"
echo.
pause
