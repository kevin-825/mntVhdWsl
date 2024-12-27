
wsl -d ubuntu --cd ~ --shell-type standard -e rm ./vhd0
wsl -d ubuntu --cd ~ --shell-type standard -e rm ./vhd1
wsl --mount --vhd E:\vms\vmbox\Shared0.vhd --name vhd0
wsl --mount --vhd E:\Hyper-V\vhds\Share1.vhdx --name vhd1
wsl -d ubuntu --cd ~ --shell-type standard -e ln -s /mnt/wsl/vhd0 ./vhd0
wsl -d ubuntu --cd ~ --shell-type standard -e ln -s /mnt/wsl/vhd1 ./vhd1
wsl -d ubuntu --cd ~ --shell-type standard -e ls -l
wsl -d ubuntu --cd ~ 

wsl --shell-type standard -e rm /home/kevin/vhd0
wsl --shell-type standard -e rm /home/kevin/vhd1
wsl -t ubuntu
wsl -l -v
wsl.exe --unmount \\?\E:\vms\vmbox\Shared0.vhd
wsl.exe --unmount \\?\E:\Hyper-V\vhds\Share1.vhdx
pause
