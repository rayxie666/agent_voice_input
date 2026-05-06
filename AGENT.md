# Agent rules for this repository

These rules apply to **any AI coding assistant** working in this repo
(Claude Code, Cursor, Copilot agents, etc.).

## Git hygiene

- **Do NOT add `Co-Authored-By:` trailers crediting AI assistants**
  (no `Co-Authored-By: Claude …`, no `Co-Authored-By: Cursor …`, etc.)
  in any commit message.
- **Do NOT add "🤖 Generated with …" / "Built with …" footers** in
  pull request descriptions, issue templates, or commit bodies.
- The author of every commit is **the human running the assistant**,
  not the assistant. Don't surface the tooling in the git log.

## When in doubt

If a commit-message template you'd normally produce contains *any*
mention of an AI tool — strip it. Plain commit messages only.
