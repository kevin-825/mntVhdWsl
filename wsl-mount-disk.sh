#!/bin/bash
set -e

name="$1"   # already Name_pPartition
type="$2"

src="/mnt/wsl/$name"
mnt="/mnt/$name"
link_target="/home/${USER}/$name"

#dock="/var/lib/docker-volumes/$name"

mkdir -p "$mnt"
#mkdir -p "$dock"

if [ ! -d "$src" ]; then
    echo "ERROR: WSL mountpoint $src not found"
    exit 1
fi

mount --bind "$src" "$mnt"
##mount --bind "$src" "$dock"
ln -s $src $link_target

