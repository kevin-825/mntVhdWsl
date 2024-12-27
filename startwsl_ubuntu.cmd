
@echo off
REM Get the directory of this script
set SCRIPT_DIR=%~dp0

REM Define the Windows CMD script path
set WIN_CMD_SCRIPT=%SCRIPT_DIR%mount_vhd_wsl.cmd

REM Run the Windows CMD script with the specified arguments
%WIN_CMD_SCRIPT% ubuntu "E:\vms\vmbox\Shared0.vhd" "E:\Hyper-V\vhds\Share1.vhdx"

REM %cmd_script_self% "ubuntu" "E:\vms\vmbox\Shared0.vhd" "E:\Hyper-V\vhds\Share1.vhdx"
pause