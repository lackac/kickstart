# Agent Guidance

Kickstart packages Nix, Elixir, and Phoenix project scaffolding as a standalone Nix flake.

- Prefer small changes and native Nix/Mix tools.
- Keep shell helpers in separate files and generated assets with the Elixir installer.
- Run `just fmt` and `just check` for relevant changes. Use `just test-agentic`
  when changing generated project behavior; it downloads and builds dependencies.
- Kickstart creates Jujutsu commits when invoked. Use the orchestration mocks
  or installer smoke tests when testing without permission to create commits.
- Keep generated `AGENTS.md` focused on daily development.
- Follow Conventional Commits; do not commit or push without an explicit request.
