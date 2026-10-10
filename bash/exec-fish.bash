# dotfiles: begin exec-fish
function c() {
    if (($#)); then
        builtin cd -- "$@"
        return
    fi

    if ! command -v fzf >/dev/null 2>&1; then
        echo 'c requires fzf' >&2
        return 1
    fi

    local target
    target=$(find . -mindepth 1 -maxdepth 1 -type d -print | fzf) || return
    [[ -n $target ]] && builtin cd -- "$target"
}

if [[ $- == *i* && -z ${BASH_EXECUTION_STRING:-} ]] && command -v fish >/dev/null 2>&1; then
    exec fish
fi
# dotfiles: end exec-fish
