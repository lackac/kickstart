set -euo pipefail

usage() {
  printf 'usage: kickstart <template> [project] [--agentic] [-- generator-args...]\n' >&2
  printf '       kickstart sync-nixpkgs\n' >&2
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

template_flake="${KICKSTART_FLAKE:-@templateFlake@}"
installer_source="@elixirInstaller@"

root_nixpkgs_rev() {
  if [[ -z ${KICKSTART_FLAKE:-} ]]; then
    printf '%s\n' '@nixpkgsRev@'
    return
  fi

  nix flake metadata "$template_flake" --json |
    jq -r '.locks.nodes[.locks.nodes[.locks.root].inputs.nixpkgs].locked.rev'
}

sync_nixpkgs() {
  local rev

  if [[ ! -e flake.nix ]]; then
    printf 'kickstart: flake.nix does not exist\n' >&2
    exit 1
  fi

  rev="$(root_nixpkgs_rev)"
  if [[ -z $rev || $rev == "null" ]]; then
    printf 'kickstart: could not determine the template flake nixpkgs revision\n' >&2
    exit 1
  fi

  nix flake lock --override-input nixpkgs "github:nixos/nixpkgs/${rev}"
}

shell_quote() {
  local value="$1"

  if [[ $value =~ ^[A-Za-z0-9_./:=+-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi

  value="${value//\'/\'\\\'\'}"
  printf "'%s'" "$value"
}

build_generator_command() {
  case "$template" in
  elixir)
    generator_command=(mix new .)
    ;;
  phoenix)
    generator_command=(mix phx.new .)
    if [[ $agentic == true ]]; then
      local install_option=false arg
      for arg in "${generator_args[@]}"; do
        case "$arg" in --install | --no-install | --install=*) install_option=true ;; esac
      done
      if [[ $install_option == false ]]; then generator_command+=(--no-install); fi
    fi
    ;;
  *)
    printf 'kickstart: no generator configured for template: %s\n' "$template" >&2
    exit 1
    ;;
  esac

  generator_command+=("${generator_args[@]}")
}

checkpoint() {
  printf '\nKickstart checkpoint: %s\n' "$PWD"
  printf '  Tooling: %s; quality: %s; security: %s.\n' "$setup_status" "$quality_status" "$security_status"
  printf '  Forgejo execution has not been verified. Review the findings above.\n'
  if [[ $template == phoenix ]]; then
    printf '  Phoenix may need lint fixes, database setup, and a CSP decision.\n'
  fi
  printf '\nOptional follow-up prompt:\n'
  printf '  "Read AGENTS.md and review the bootstrap diff. Run mix ci and\n'
  printf '  mix security; resolve findings without weakening the gates.\n'
  if [[ $template == phoenix ]]; then
    printf '  For local Ecto development, use the existing PostgreSQL service: role\n'
    printf '  postgres, socket /tmp, with separate dev/test databases in Repo config.\n'
    printf '  Serve https://<app-name>.test through existing Caddy using a persistent\n'
    printf '  /etc/caddy/local.d/<host>.caddy snippet and a free hostname-derived port.\n'
    printf '  Bind Phoenix and restrict proxy clients to loopback; configure the public\n'
    printf '  URL, forwarded HTTPS, and certificate trust. Ask before host-service changes.\n'
    printf '  Optionally enable dev-only Tidewave and connect OpenCode to its MCP endpoint.\n'
    printf '  Review CSP, verify browser/LiveView flows, and rerun the checks.\n'
  fi
  printf '  Report what passed and what remains; do not commit."\n'
}

if [[ $1 == "sync-nixpkgs" ]]; then
  if [[ $# -ne 1 ]]; then
    usage
    exit 64
  fi

  sync_nixpkgs
  exit 0
fi

generator_args=()
template_args=()
generator_requested=false
agentic=false

while (($# > 0)); do
  case "$1" in
  --agentic)
    agentic=true
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    generator_requested=true
    shift
    generator_args=("$@")
    break
    ;;
  -*)
    printf 'kickstart: unknown option: %s (generator options belong after --)\n' "$1" >&2
    exit 64
    ;;
  *)
    template_args+=("$1")
    shift
    ;;
  esac
done

if [[ ${#template_args[@]} -lt 1 || ${#template_args[@]} -gt 2 ]]; then
  usage
  exit 64
fi

template="${template_args[0]}"
project="${template_args[1]:-}"

if [[ $agentic == true ]]; then
  if [[ $generator_requested != true || ($template != elixir && $template != phoenix) ]]; then
    printf 'kickstart: --agentic requires the elixir or phoenix template and -- to run its generator\n' >&2
    exit 64
  fi
  for arg in "${generator_args[@]}"; do
    case "$arg" in
    --umbrella | --umbrella=*)
      printf 'kickstart: agentic generation does not support %s yet\n' "$arg" >&2
      exit 64
      ;;
    esac
  done
fi

if [[ -n $project ]]; then
  mkdir "$project"
  cd "$project"
fi

if [[ -e flake.nix ]]; then
  printf 'kickstart: flake.nix already exists\n' >&2
  exit 1
fi

if [[ $agentic == true && -e mix.exs ]]; then
  printf 'kickstart: --agentic supports fresh generation; mix.exs already exists\n' >&2
  exit 1
fi

if [[ $agentic == true ]]; then
  for entry in .[^.]* ..?* *; do
    [[ -e $entry || -L $entry ]] || continue
    case "$entry" in
    .git | .jj) ;;
    *)
      printf 'kickstart: --agentic requires a fresh directory (found %s)\n' "$entry" >&2
      exit 1
      ;;
    esac
  done
fi

if [[ ! -d .jj ]]; then
  if [[ -d .git ]]; then
    jj git init --git-repo=.
  else
    jj git init --colocate
  fi
fi

nix flake init -t "${template_flake}#${template}"
sync_nixpkgs
jj commit -m "chore(env): bootstrap nix flake"

if [[ $generator_requested == "true" ]]; then
  build_generator_command
  if [[ $agentic == true ]]; then
    setup_status="not completed"
    quality_status="not run"
    security_status="not run"
    trap checkpoint EXIT
    export MIX_ENV=dev
    unset MIX_BUILD_PATH MIX_BUILD_ROOT MIX_DEPS_PATH
    if ! nix develop --command mix help hex.audit >/dev/null 2>&1; then
      printf 'kickstart: install a current Hex archive with: nix develop --command mix local.hex --force\n' >&2
      exit 1
    fi
    if [[ $template == phoenix ]] && ! nix develop --command mix help phx.new >/dev/null 2>&1; then
      printf 'kickstart: install the Phoenix generator with: nix develop --command mix archive.install hex phx_new --force\n' >&2
      exit 1
    fi
  fi
  generator_command_text="$(for arg in "${generator_command[@]}"; do
    shell_quote "$arg"
    printf ' '
  done)"
  nix develop --command "${generator_command[@]}"
  jj commit \
    -m "chore: run project generator" \
    -m "$(printf 'Generator command:\n\n    %s' "$generator_command_text")"

  if [[ $agentic == true ]]; then
    nix develop --command elixir "$installer_source/install.exs" --target "$PWD" --template "$template"
    nix develop --command mix deps.get
    nix develop --command mix format mix.exs .credo.exs
    setup_status="installed"
    validation_status=0
    if nix develop --command env MIX_ENV=test mix ci; then
      quality_status="passed"
    else
      quality_status="failed (exit $?)"
      validation_status=1
    fi
    if nix develop --command env MIX_ENV=test mix security; then
      security_status="passed"
    else
      security_status="failed (exit $?)"
      validation_status=1
    fi
    if ((validation_status != 0)); then
      printf '\nGenerated project retained with uncommitted tooling changes; checks need attention.\n' >&2
      exit "$validation_status"
    fi
    jj commit -m "chore: configure development tooling"
  fi
fi

jj bookmark set main -r @-
