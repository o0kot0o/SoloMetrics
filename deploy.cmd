@echo off
rem Double-click or run from a terminal. Extra args are passed through, e.g. deploy.cmd -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Deploy-SoloMetrics.ps1" %*
exit /b %ERRORLEVEL%
