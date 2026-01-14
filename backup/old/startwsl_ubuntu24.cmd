
@echo off
REM Get the directory of this script
set SCRIPT_DIR=%~dp0

REM Define the Windows CMD script path
set WIN_CMD_SCRIPT=%SCRIPT_DIR%mount_vhd_wsl.cmd
set WIN_ps1_SCRIPT=%SCRIPT_DIR%mount_vhd_wsl.ps1


REM Run the Windows CMD script with the specified arguments
REM %WIN_CMD_SCRIPT% ubuntu "E:\vms\vmbox\Shared0.vhd" "E:\Hyper-V\vhds\Share1.vhdx"
REM %WIN_CMD_SCRIPT% Ubuntu-24.04 "E:\VHDs\Shared_v0.vhdx" 
%WIN_CMD_SCRIPT% Ubuntu-24.04 "E:\VHDs\Shared_v0.vhdx" 


REM %cmd_script_self% "ubuntu" "E:\vms\vmbox\Shared0.vhd" "E:\Hyper-V\vhds\Share1.vhdx"
pause