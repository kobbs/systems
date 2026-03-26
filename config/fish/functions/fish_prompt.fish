function fish_prompt --description 'Contextual left prompt'
    set -l last_status $status

    # Accent colors (from 02-colors.fish, sed-swappable via apply_accent)
    set -l accent (string replace '#' '' $__accent_primary)
    set -l dim    (string replace '#' '' $__accent_dim)

    # Path: full directory names, ~ replaces $HOME (--dir-length=0 disables truncation)
    set -l cwd (prompt_pwd --dir-length=0)

    set -l parts

    # SSH indicator: show hostname only when remote
    if set -q SSH_CONNECTION
        set -a parts (set_color $dim --bold)$hostname(set_color normal)' '
    end

    # Working directory
    set -a parts (set_color brwhite)$cwd(set_color normal)

    # Exit status (only on failure)
    if test $last_status -ne 0
        set -a parts ' '(set_color ff6666)'['$last_status']'(set_color normal)
    end

    # Prompt character: accent-colored, red on error
    if test $last_status -ne 0
        set -a parts ' '(set_color ff6666 --bold)'>'(set_color normal)' '
    else
        set -a parts ' '(set_color $accent --bold)'>'(set_color normal)' '
    end

    string join '' $parts
end
