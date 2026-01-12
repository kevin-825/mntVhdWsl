alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias c='clear'


alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias md='mkdir -p'
alias rd='rmdir'
alias cpv='rsync -ah --info=progress2'

alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

alias dfh='df -h'
alias duh='du -sh *'
alias mem='free -h'
alias ports='netstat -tulanp'

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'
alias gco='git checkout'
alias gb='git branch'

alias grep='grep --color=auto'
alias f='find . -name'
alias h='history'
alias j='jobs -l'

alias please='sudo $(fc -ln -1)'
alias update='sudo apt update && sudo apt upgrade'
alias untar='tar -xvf'
alias tarc='tar -cvf'
alias serve='python3 -m http.server 8000'


alias cd2d1='cd /mnt/wsl/disk1_32g_p1'
alias cd2d2='cd /mnt/wsl/disk2_110g_p1'
cd2d1p() {
    local n="${1#cd2d1p}"
    cd "/mnt/wsl/disk1_32g_p$n"
}
alias cd2d1p=cd2d1p

cd2d2p() {
    local n="${1#cd2d1p}"
    cd "/mnt/wsl/disk2_110g_p$n"
}
alias cd2d1p=cd2d2p

#alias cd2d5='cd /mnt/disk5_ramdisk'
alias cd2rd0='cd /mnt/ramdisk0'
alias cd2vhd0='cd /mnt/wsl/vhd0'
alias cd2vhd1='cd /mnt/wsl/vhd1'

mkramdisk() {
    size="$1"
    sudo mkdir -p /mnt/ramdisk0
    sudo mount -t tmpfs -o size="$size" tmpfs /mnt/ramdisk0
    echo "RAM disk mounted at /mnt/ramdisk0 with size $size"
}

rmramdisk() {
    if mountpoint -q /mnt/ramdisk0; then
        echo "Before unmount:"
        df -h /mnt/ramdisk0 2>/dev/null

        # If current directory is inside the ramdisk, move out
        case "$PWD" in
            /mnt/ramdisk0* )
                cd ~
                ;;
        esac

        sudo umount -l /mnt/ramdisk0
        sudo rmdir /mnt/ramdisk0 2>/dev/null

        echo "RAM disk unmounted and directory removed"

        echo "After unmount:"
        df -h /mnt/ramdisk0 2>/dev/null || echo "No filesystem at /mnt/ramdisk0"
    else
        echo "No RAM disk mounted at /mnt/ramdisk0"
    fi
}

# if ! mount | grep -q "/mnt/disk1_32g"; then
#     echo mounting disk1_32g as /mnt/disk1_32g
#     sudo mkdir -p /mnt/disk1_32g
#     sudo mount -L disk1_32g /mnt/disk1_32g
# fi
# if ! mount | grep -q "/mnt/disk2_110g"; then
#     echo mounting disk2_110g as /mnt/disk2_110g
#     sudo mkdir -p /mnt/disk2_110g
#     sudo mount -L disk2_110g /mnt/disk2_110g
# fi
#sudo mount -t tmpfs -o size=40G tmpfs /mnt/ramdisk0
#if ! mount | grep -q "/mnt/ramdisk0"; then
#    echo mounting ramdisk0 as /mnt/ramdisk0
#    sudo mkdir -p /mnt/ramdisk0
#    sudo mount -t tmpfs -o size=40G tmpfs /mnt/ramdisk0
#fi

if [ -f ~/vhd1/bashconfig.sh ]; then
    . ~/vhd1/bashconfig.sh
fi

export PATH="$PATH:/home/$USER/docker_manage_script"

