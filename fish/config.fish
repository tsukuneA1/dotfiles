if test -d "$HOME/go/bin"
    fish_add_path --path "$HOME/go/bin"
end

function cdr --description 'Select a ghq repository with fzf and change directory'
    if not command -sq ghq; or not command -sq fzf
        echo 'cdr requires ghq and fzf' >&2
        return 1
    end

    set -l target (ghq list --full-path | fzf)
    if test -n "$target"
        cd -- "$target"
    end
end
