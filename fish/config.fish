if test -d "$HOME/go/bin"
    fish_add_path --path "$HOME/go/bin"
end

function c --description 'Change directory or select a child directory with fzf'
    if test (count $argv) -gt 0
        cd -- $argv
        return $status
    end

    if not command -sq fzf
        echo 'c requires fzf' >&2
        return 1
    end

    set -l target (find . -mindepth 1 -maxdepth 1 -type d -print | fzf)
    if test -n "$target"
        cd -- "$target"
    end
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
