@echo off
chcp 65001 >nul
title MQL5 Deploy
echo.
echo  Iniciando deploy MQL5...
echo.

python "%~dp0deploy_mql5.py"

echo.
if %ERRORLEVEL% EQU 0 (
    echo  Pressione qualquer tecla para fechar...
) else (
    echo  Ocorreu um erro. Pressione qualquer tecla para fechar...
)
pause >nul
