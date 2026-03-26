# Custom key bindings
# Uses fish_vi_key_bindings as base, with insert-mode enhancements.

status is-interactive; or return

# Vi mode as base (prompt char changes handled in fish_mode_prompt)
fish_vi_key_bindings

# -- Insert-mode keybinds --------------------------------------------------

# Ctrl+Z: suspend foreground process (vi mode doesn't bind this by default)
bind -M insert \cz 'fg 2>/dev/null; commandline -f repaint'

# Ctrl+E: open command in $EDITOR (like bash Ctrl+X Ctrl+E)
bind -M insert \ce edit_command_buffer

# Ctrl+F: accept autosuggestion (right arrow alternative — closer to home row)
bind -M insert \cf accept-autosuggestion

# Alt+.: insert last argument from previous command (bash-like)
bind -M insert \e. history-token-search-backward

# -- Normal-mode extras ----------------------------------------------------

# Y in normal mode: yank entire line (vi default Y yanks to end)
bind -M default Y 'commandline -b | fish_clipboard_copy; commandline -f repaint'
