alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias c='clear'


alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias md='mkdir -p'

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
#alias f='find . -name'
alias h='history'
alias j='jobs -l'

alias please='sudo $(fc -ln -1)'
alias update='sudo apt update && sudo apt upgrade'
alias untar='tar -xvf'
alias tarc='tar -cvf'
alias serve='python3 -m http.server 8000'


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



if [ -f ~/vhd1/bashconfig.sh ]; then
    . ~/vhd1/bashconfig.sh
fi


export PATH="/mnt/wsl/vhd0/local_bins/riscv/riscv64-glibc-ubuntu-24.04-gcc/bin:/mnt/wsl/vhd0/local_bins/riscv/riscv64-elf-ubuntu-24.04-gcc/bin:$PATH"

export PATH="$PATH:/home/$USER/docker_manage_script"


if [ -f ~/.bash_aliases_1 ]; then
    sed -i 's/\r$//' ~/.bash_aliases_1
    . ~/.bash_aliases_1
fi




