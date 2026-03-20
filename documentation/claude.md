# Claude Code CLI — practical cheatsheet

Full reference: `claude --help`. This covers the combos worth memorizing.

## Model selection

```bash
claude --model opus       # use Opus (most capable, slower)
claude --model sonnet     # use Sonnet (default, fast)
claude --model haiku      # use Haiku (cheapest, fastest)
```

## Permission modes

By default Claude asks before every tool call (file edits, shell commands, etc.).

```bash
claude --permission-mode plan        # read-only: can explore code but won't edit anything
claude --permission-mode auto        # auto-approve safe operations (reads, ls, git status…)
claude --permission-mode dontAsk     # approve everything without prompting
claude --permission-mode acceptEdits # auto-approve file edits, still ask for shell commands
```

`--dangerously-skip-permissions` is the nuclear option — no prompts at all. Only use in throwaway sandboxes with no network.

### Fine-grained tool allowlists

Instead of a blanket mode, allow specific tools:

```bash
claude --allowedTools "Bash(git:*) Read Glob Grep"   # allow git commands + read-only tools
claude --allowedTools "Edit Write Bash(npm:*)"        # allow edits + npm commands
```

## Non-interactive / scripting (`--print`)

```bash
echo "explain this error" | claude -p                          # pipe in, get answer, exit
claude -p "list all TODO comments in src/"                     # one-shot question
claude -p --model opus --output-format json "summarize main.go"  # structured output
```

Useful flags with `-p`:
- `--output-format json` — machine-readable single JSON result
- `--output-format stream-json` — streaming JSON chunks
- `--max-budget-usd 0.50` — hard spending cap
- `--fallback-model sonnet` — auto-fallback if primary model is overloaded

## Session management

```bash
claude -c                   # continue last conversation in this directory
claude -r                   # interactive picker to resume any past session
claude -r "bootstrap"       # fuzzy-search sessions by name/content
claude -n "refactor auth"   # name the session for easier resume later
```

## Common combos

```bash
# Explore a codebase without risk of changes
claude --model opus --permission-mode plan

# Autonomous coding session (reads context from CLAUDE.md)
claude --model opus --permission-mode auto

# Quick one-shot from a script or Makefile
claude -p --model sonnet "what does scripts/bootstrap.sh do?"

# Resume yesterday's work with full permissions
claude -c --permission-mode auto

# Work in an isolated git worktree (changes on a temp branch)
claude -w "experiment-name" --model opus
```

## Effort levels

```bash
claude --effort low     # quick answers, less thinking
claude --effort high    # default-ish depth
claude --effort max     # deep reasoning, slower
```

## Slash commands (inside a session)

These are typed at the Claude prompt, not on the command line:

- `/help` — usage reference
- `/compact` — compress conversation context (useful in long sessions)
- `/resume` — pick a past session to continue
- `/commit` — stage + commit with a generated message
- `/review-pr` — review a pull request
- `/fast` — toggle fast mode (same model, faster output)
