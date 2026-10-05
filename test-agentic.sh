#!/usr/bin/env bash
# Networked smoke tests; no commits, host changes, or project staging.
set -euo pipefail
tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="${KICKSTART_INSTALLER_SOURCE:-$tools_dir/elixir}"
work="${KICKSTART_TEST_ROOT:-${TMPDIR:-/tmp}/kickstart-acceptance-$(date +%Y-%m-%d-%H%M%S)}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
export MIX_HOME="$work/mix-home" HEX_HOME="$work/hex-home" MIX_INSTALL_DIR="$work/install"
export ELIXIR_MAKE_CACHE_DIR="$work/elixir-make"
unset MIX_ENV MIX_BUILD_PATH MIX_BUILD_ROOT MIX_DEPS_PATH
mix local.hex 2.5.1 --force
mix archive.install hex phx_new 1.8.15 --force

hashes() {
  find . \( -path ./deps -o -path ./_build -o -path ./.git \) -prune -o \
    -type f -exec sha256sum {} + | LC_ALL=C sort
}

verify() {
  local project="$1" template="$2"
  (
    cd "$work/$project"
    elixir "$installer/install.exs" --target "$PWD" --template "$template"
    mix deps.get
    mix format mix.exs .credo.exs
    mix run --no-start -e 'dep = Enum.find(Mix.Project.config()[:deps], &(elem(&1, 0) == :igniter)); true = elem(dep, 2)[:only] == :dev; false = elem(dep, 2)[:runtime]'
    mix help igniter.install >"$work/$project-igniter.log"
    hashes >"$work/$project-before.sha256"
    if [[ $template == elixir ]]; then
      mix ci
      mix security
    else
      # Upstream lint findings remain visible, rather than being auto-excluded.
      if MIX_ENV="test" mix ci >"$work/$project-quality.log" 2>&1; then
        printf 'Upstream lint baseline changed; review this smoke fixture.\n' >&2
        exit 1
      fi
      grep -F 'Checking ' "$work/$project-quality.log"
      grep -F 'code readability issue' "$work/$project-quality.log"
      if [[ $project == web ]]; then
        if mix security >"$work/$project-security.log" 2>&1; then
          printf 'Fresh Phoenix unexpectedly passed the missing-CSP check\n' >&2
          exit 1
        fi
        grep -F 'Config.CSP: Missing Content-Security-Policy' "$work/$project-security.log"
      else
        mix security
        mix test --warnings-as-errors
      fi
    fi
    hashes >"$work/$project-after.sha256"
    cmp "$work/$project-before.sha256" "$work/$project-after.sha256"
  )
}

mix new "$work/plain" --sup --app plain_app --module Custom.Root
verify plain elixir
(
  cd "$work/plain"
  trap 'rm -f lib/kickstart_negative.ex' EXIT
  cat >lib/kickstart_negative.ex <<'ELIXIR'
defmodule KickstartNegative do
  @moduledoc false
  def copy(items), do: Enum.map(items, fn item -> item end)
end
ELIXIR
  mix format lib/kickstart_negative.ex
  if mix check >"$work/exslop-negative.log" 2>&1; then
    printf 'ExSlop negative fixture unexpectedly passed\n' >&2
    exit 1
  fi
  # The diagnostic contains literal Markdown backticks.
  # shellcheck disable=SC2016
  grep -F 'Identity `Enum.map`' "$work/exslop-negative.log"
)
mix phx.new "$work/web" --app web_app --module Custom.Web --no-install
verify web phoenix
mix phx.new "$work/api" --app api_app --module Custom.Api --no-ecto --no-html --no-assets --no-dashboard --no-mailer --no-install
verify api phoenix
printf 'Smoke checks passed, including expected Phoenix lint/CSP findings. Artifacts: %s\n' "$work"
