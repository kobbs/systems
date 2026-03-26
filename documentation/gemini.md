# Gemini Code Assist CLI — practical cheatsheet

Full reference: `gemini --help` or `/help` inside an interactive session. This covers the combos worth memorizing.

## Installation

```bash
# Install the CLI globally via npm
npm install -g @google/gemini-cli
```

### Adding plugins (Superpowers)

The Gemini CLI supports plugins to extend its capabilities. The "superpowers" plugin is a common addition:

```bash
gemini plugin add superpowers
```

## Model selection

```bash
gemini --model gemini-3.1-pro       # use 3.1 Pro (flagship, best for coding/planning)
gemini --model gemini-3.1-flash     # use 3.1 Flash (fast, default for most tasks)
gemini --model gemini-3-deepthink   # use Deep Think (extreme reasoning for hard problems)
```

Inside an interactive session, you can also switch models dynamically using the slash command:
- `/model gemini-3.1-pro`

## Plan Mode

Plan mode analyzes requirements, explores the codebase, and drafts an implementation plan for your approval before making any source code edits.

```bash
gemini --plan                # start a session directly in Plan Mode
```

*(Note: Inside a standard session, the CLI automatically enters plan mode when it detects complex tasks requiring approval.)*

## Slash commands (inside a session)

These are typed at the Gemini prompt, not on the command line:

- `/help` — usage reference
- `/bug` — report a bug or provide feedback

