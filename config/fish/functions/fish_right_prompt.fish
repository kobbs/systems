function fish_right_prompt --description 'Git + duration context'
    set -l parts
    set -l accent_s (string replace '#' '' $__accent_secondary)

    # -- Git info -----------------------------------------------------------
    if command -q git
        set -l branch (git symbolic-ref --short HEAD 2>/dev/null)
        or set branch (git describe --tags --exact-match 2>/dev/null)
        or set branch (git rev-parse --short HEAD 2>/dev/null)

        if test -n "$branch"
            set -l git_parts (set_color $accent_s)$branch(set_color normal)

            # Porcelain v2: structured output for reliable parsing
            set -l staged 0
            set -l dirty 0
            set -l untracked 0
            for line in (git status --porcelain=v2 2>/dev/null)
                switch (string sub -l 1 $line)
                    case 1 2
                        set -l xy (string sub -s 3 -l 2 $line)
                        if test (string sub -l 1 $xy) != '.'
                            set staged (math $staged + 1)
                        end
                        if test (string sub -s 2 -l 1 $xy) != '.'
                            set dirty (math $dirty + 1)
                        end
                    case '?'
                        set untracked (math $untracked + 1)
                end
            end

            test $staged -gt 0;    and set git_parts "$git_parts "(set_color 88ff88)"+$staged"(set_color normal)
            test $dirty -gt 0;     and set git_parts "$git_parts "(set_color ff6666)"~$dirty"(set_color normal)
            test $untracked -gt 0; and set git_parts "$git_parts "(set_color 888888)"?$untracked"(set_color normal)

            set -a parts $git_parts
        end
    end

    # -- Command duration (>2s only) ----------------------------------------
    if test "$CMD_DURATION" -gt 2000
        set -l secs (math --scale=1 $CMD_DURATION / 1000)
        set -a parts (set_color 888888)$secs's'(set_color normal)
    end

    string join '  ' $parts
end
