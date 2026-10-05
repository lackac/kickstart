# Kickstart

`kickstart` creates a project with a Nix development shell and a colocated
Jujutsu/Git repository. It pins the project's nixpkgs input to the revision used
to build Kickstart.

## Usage

Run directly from this checkout:

```sh
nix run . -- phoenix ../my_app --agentic --
```

Or install the package and use `kickstart`:

```sh
kickstart nix my-project
kickstart elixir my_app
kickstart elixir my_app -- --sup --module MyApp
kickstart phoenix my_app -- --no-ecto
kickstart phoenix my_app --agentic --
```

Without `--`, Kickstart creates the project flake. Include `--` to also run the
upstream Mix or Phoenix generator; arguments after the separator go directly to it.
Omit the project path to use the current directory. Zsh completion includes
template names and generator options.

Run `kickstart sync-nixpkgs` inside a project to align its nixpkgs lock with
Kickstart's build. Set `KICKSTART_FLAKE` to choose another template flake and use
its locked nixpkgs revision instead.

## Nix projects

`kickstart nix my-project` creates a flake with a development shell, treefmt,
formatting checks, a `Justfile`, `.envrc`, `.gitignore`, and a short README.
Use `just fmt`, `just check`, `just up`, and `just upp <input>` in the new project.
Its `just sync-nixpkgs` recipe defaults to the sibling `../nix-config` checkout;
pass a path or flake reference to use another source.

## Development tooling

For fresh, single-application Elixir and Phoenix projects, put `--agentic` before
the separator:

```sh
kickstart elixir my_app --agentic -- --sup
kickstart phoenix my_app --agentic -- --no-ecto --module MyApp
```

The profile installs:

- Igniter as a development dependency for future installers and generators.
- Credo and ExSlop for code checks, plus Sobelow for Phoenix security analysis.
- `check`, `ci`, and `security` Mix aliases.
- A Forgejo workflow with quality and security jobs.
- A short development-workflow section appended to `AGENTS.md`.

Use a current Hex installation and, for Phoenix, the `phx_new` archive. To install
or upgrade them from an Elixir development shell:

```sh
mix local.hex --force
mix archive.install hex phx_new --force
```

Kickstart uses the normal Mix and Hex locations. Its one-time installer uses the
standard `Mix.install` cache; project dependencies and builds use `deps/` and
`_build/`. Phoenix generation defaults to `--no-install`, followed by dependency
installation after tooling setup. An explicit generator `--install` is honored.

## Checks and checkpoint

Run these commands in the project's development environment:

| Command | Checks |
| --- | --- |
| `mix check` | Formatting, compilation with warnings as errors, strict Credo/ExSlop, tests |
| `mix ci` | `check`, then unused lock entries |
| `mix security` | Hex advisories and retirements; Phoenix also runs Sobelow |

All three aliases select the test environment. Sobelow fails on medium- and
high-confidence findings. The Forgejo workflow runs `ci` and `security` as
separate jobs on a Nix-capable `x86_64-linux` runner. Ecto projects need database
provisioning and connection settings for local tests and CI.

Security checks use the tools' native exit statuses. Hex can report success when
advisory retrieval fails with an empty cache, and Sobelow can exit successfully
after encountering unreadable source. Review their output for these limitations.

Kickstart runs both gates and prints their results with an optional follow-up
prompt. Fresh Phoenix projects may need lint fixes, database configuration, and
a Content-Security-Policy. A failed gate returns a nonzero exit status and leaves
the generated project available for review.

Kickstart records the flake and generator checkpoints in Jujutsu. After successful
validation it records the tooling setup and creates the `main` bookmark. On
failure, inspect the reported error and working-tree diff before retrying.

## Developing Kickstart

Enter `nix develop`, then run `just` to list the commands:

- `just fmt` formats Nix, Bash, and Elixir sources.
- `just check` runs the flake's formatting and CLI checks.
- `just build` builds the package; `just run --help` runs it.
- `just up` updates all inputs; `just upp <input>` updates one.
- `just sync-nixpkgs` aligns the lock with the sibling `../nix-config` checkout.
- `just test-agentic` runs the networked generated-project smoke suite.

The flake exports `packages.<system>.default` (also named `kickstart`), a default
development shell, and the `nix`, `elixir`, `phoenix`, and default Elixir templates.
