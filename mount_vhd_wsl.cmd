@echo off
setlocal

REM Check if at least two arguments are provided
if "%1"=="" (
    echo No WSL distro name provided.
    exit /b 1
)
if "%2"=="" (
    echo No VHD/VHDX path provided.
    exit /b 1
)

REM Set the WSL distro name
set "distro=%1"
shift

REM Mount each VHD/VHDX file and create symbolic links in WSL
set "count=0"
set "vhdlist="
:loop
if "%1"=="" goto endloop

    REM Get the VHD/VHDX file path
    set "vhdpath=%1"
    shift

    REM Get the drive name
    set "drivename=vhd%count%"

    REM Mount the VHD/VHDX file using wsl --mount
    wsl --mount --vhd %vhdpath% --name %drivename%

    REM Keep track of mounted VHDs
    set "vhdlist=%vhdlist% \\?\\%vhdpath%"

    REM Create the symbolic link in WSL
    wsl -d %distro% -- sh -c "[ ! -e /home/$(whoami)/%drivename% ] && ln -s /mnt/wsl/%drivename% /home/$(whoami)/%drivename%"

    REM Increment the count
    set /a count+=1

goto loop
:endloop

REM Start the WSL distro and change to the home directory
wsl -d %distro% -- sh -c "cd ~ && exec \$SHELL"

REM Terminate the WSL distro before unmounting
wsl -t %distro%

REM Unmount all VHD/VHDX files after exiting the WSL session
for %%v in (%vhdlist%) do (
    wsl --unmount %%v
)

endlocal
echo All VHD/VHDX files unmounted.

pause
