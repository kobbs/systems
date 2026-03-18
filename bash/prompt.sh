#!/bin/bash

# CachyOS-inspired bash prompt
# Managed by dotfiles-deploy.sh — edit here, re-run deploy to apply.

# ── ANSI color helpers (use \001/\002 so bash counts width correctly) ─────────
_pc() { printf '\001\e[%sm\002' "$1"; }

_R="$(_pc 0)"        # reset
_B="$(_pc 1)"        # bold
_CYAN="$(_pc 96)"    # bright cyan   — username
_GREEN="$(_pc 92)"   # bright green  — hostname  (matches waybar accent)
_BLUE="$(_pc 94)"    # bright blue   — path
_YELLOW="$(_pc 93)"  # bright yellow — git branch
_RED="$(_pc 91)"     # bright red    — root / non-zero exit

# ── Git status ────────────────────────────────────────────────────────────────
_prompt_git() {
    local branch dirty=""
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) \
        || branch=$(git describe --tags --exact-match 2>/dev/null) \
        || branch=$(git rev-parse --short HEAD 2>/dev/null) \
        || return 0
    [[ -n $(git status --porcelain 2>/dev/null) ]] && dirty=" ±"
    printf '\001\e[93m\002  %s%s\001\e[0m\002' "$branch" "$dirty"
}

# ── Prompt builder (called via PROMPT_COMMAND) ────────────────────────────────
_build_prompt() {
    local exit_code=$?

    local user_color="$_CYAN"
    local prompt_char="❯"
    (( UID == 0 )) && user_color="$_RED" && prompt_char="#"

    local exit_str=""
    (( exit_code != 0 )) && exit_str=" ${_RED}✗ ${exit_code}${_R}"

    # Line 1: ╭─[user@host] [~/path] [  branch ±]
    PS1="${_B}╭─${_R}[${user_color}${_B}\u${_R}@${_GREEN}${_B}\h${_R}] [${_BLUE}\w${_R}]$(_prompt_git)\n"
    # Line 2: ╰─❯
    PS1+="${_B}╰─${_R}${exit_str}${user_color}${_B}${prompt_char}${_R} "
}

PROMPT_COMMAND="_build_prompt"
