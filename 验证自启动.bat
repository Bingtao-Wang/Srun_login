@echo off
title 校园网自启动验证
echo.
echo 正在检查自启动配置...
echo.

if exist "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\srun_login.vbs" (
    echo [成功] 自启动已配置
    echo.
    echo VBS 文件路径:
    echo   %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\srun_login.vbs
) else (
    echo [失败] 未检测到自启动配置，请重新运行"一键部署_Windows.bat"
)

echo.
pause
