function fish_mode_prompt --description 'Vi mode indicator'
    # Only show indicator outside insert mode (insert is the default state)
    set -l accent    (string replace '#' '' $__accent_primary)
    set -l secondary (string replace '#' '' $__accent_secondary)

    switch $fish_bind_mode
        case default
            set_color --background $accent 000000
            echo -n ' N '
            set_color normal
            echo -n ' '
        case visual
            set_color --background $secondary 000000
            echo -n ' V '
            set_color normal
            echo -n ' '
        case replace replace_one
            set_color --background ff6666 000000
            echo -n ' R '
            set_color normal
            echo -n ' '
        case insert
            # No indicator in insert mode — clean prompt
    end
end
