# dotfiles: begin exec-fish
if [[ $- == *i* && -z ${BASH_EXECUTION_STRING:-} ]] && command -v fish >/dev/null 2>&1; then
    exec fish
fi
# dotfiles: end exec-fish
