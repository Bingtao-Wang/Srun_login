@echo off
title У԰���Զ���¼ - һ������
echo ========================================
echo    У԰���Զ���¼ һ�����𹤾�
echo    (������ PowerShell ��)
echo ========================================
echo.

:: �����˺�����
echo [1/4] ������У԰���˺���Ϣ:
set /p SRUN_USER=  ѧ��:
echo   ����(����ʱ����ʾ�����갴�س�):
for /f "delims=" %%p in ('powershell -Command "$p=Read-Host -AsSecureString;[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "SRUN_PASS=%%p"
echo.
echo   Ĭ�Ϸ�����: http://192.168.75.252
echo   ������У����ͬ����������ȷ�ķ�������ַ
set /p SRUN_SERVER=  ��������ַ(ֱ�ӻس�ʹ��Ĭ��):
if "%SRUN_SERVER%"=="" set "SRUN_SERVER=http://192.168.75.252"

:: ���������ļ�
echo.
echo [2/4] ���������ļ�...
(
echo [srun]
echo username = %SRUN_USER%
echo password = %SRUN_PASS%
echo server = %SRUN_SERVER%
echo ac_id = 1
) > "%~dp0config.ini"
echo       config.ini ������

:: ���ÿ���������VBS ���� PowerShell��
echo.
echo [3/4] ���ÿ�������...
set "VBS_PATH=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\srun_login.vbs"
set "PS1_PATH=%~dp0srun_login.ps1"
powershell -Command "$ps1=$env:PS1_PATH; $vbs=$env:VBS_PATH; $c='CreateObject(\"WScript.Shell\").Run \"powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File \"\"' + $ps1 + '\"\" -keepalive\", 0, False'; [IO.File]::WriteAllText($vbs, $c + \"`r`n\", [Text.Encoding]::Default)"
if exist "%VBS_PATH%" (
    echo       [�ɹ�] ��������������
) else (
    echo       [ʧ��] ��������ʧ�ܣ����Ȩ��
)

:: ���Ե�¼
echo.
echo ----------------------------------------
echo [4/4] ���Ե�¼...
echo ----------------------------------------
powershell -ExecutionPolicy Bypass -File "%~dp0srun_login.ps1"

:: ��֤��������HTTP��⣬У԰����������ping��
echo.
echo ��֤������ͨ�ԣ��ȴ����������...
timeout /t 3 /nobreak >nul
powershell -ExecutionPolicy Bypass -Command "try { $r = Invoke-WebRequest -Uri 'https://www.baidu.com' -UseBasicParsing -TimeoutSec 10; if ($r.StatusCode -eq 200) { Write-Host '      [�ɹ�] ��������ͨ��������������' } else { Write-Host '      [ʧ��] �޷����������������˺������Ƿ���ȷ' } } catch { Write-Host '      [ʧ��] �޷����������������˺������Ƿ���ȷ' }"

echo.
echo ========================================
echo   ������ɣ��´ο������Զ���¼У԰��
echo ========================================
echo.
echo   �ֶ���¼:  ˫��"�ֶ���¼.bat"
echo   ж������:  ˫��"ж������.bat"
echo.
pause
