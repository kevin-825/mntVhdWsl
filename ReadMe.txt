when a xxx.vhdx virtual hard disk file created first time, the virtual hard disk left uninitialized! 



wsl --mount --vhd \\?\Z:\ramDisk2.vhdx --bare

then in  Linux,

lsblk

find the sdx device under /dev/

then do:
sudo fdisk /dev/sdx

then create partition table and new partition