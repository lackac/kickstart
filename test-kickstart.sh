#!/usr/bin/env bash
# Exercise orchestration and checkpoints; never create real commits or services.
set -euo pipefail
source_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kickstart.sh"
root="$(mktemp -d "${TMPDIR:-/tmp}/kickstart-test.XXXXXX")"
trap 'rm -rf -- "$root"' EXIT
mkdir "$root/bin"
export CALL_LOG="$root/calls.jsonl"
export XDG_CACHE_HOME="$root/cache"
export REAL_JQ
REAL_JQ="$(command -v jq)"
export PATH="$root/bin:$PATH"
export MIX_HOME=/user/mix MIX_ENV=prod MIX_DEPS_PATH=/other/project/deps
unset KICKSTART_FLAKE
text="$(<"$source_file")"
text="${text//@templateFlake@/test:flake}"
text="${text//@nixpkgsRev@/build-revision}"
text="${text//@elixirInstaller@/\/read-only installer}"
printf '%s\n' "$text" >"$root/kickstart"

cat >"$root/bin/nix" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
tool="${0##*/}"
"$REAL_JQ" -cn --arg tool "$tool" --arg mix_env "${MIX_ENV:-}" \
  --arg deps_path "${MIX_DEPS_PATH:-}" --arg mix_home "${MIX_HOME:-}" \
  --args '{tool:$tool, mix_env:$mix_env, deps_path:$deps_path, mix_home:$mix_home, args:$ARGS.positional}' -- "$@" >> "$CALL_LOG"
if [[ -n "${FAIL_COMMAND:-}" && "$*" == *"$FAIL_COMMAND"* ]]; then exit 23; fi
if [[ "$tool" == nix ]]; then
  case "$*" in
    'flake metadata '*) printf '%s\n' '{"locks":{"root":"root","nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"rev":"test-revision"}}}}}' ;;
    'flake init '*) printf '{}\n' > flake.nix ;;
    'flake lock '*) printf '{}\n' > flake.lock ;;
  esac
fi
SH
chmod +x "$root/bin/nix"
ln -s nix "$root/bin/jj"

run_case() {
  local name="$1" expected="$2" status=0
  shift 2
  mkdir "$root/$name"
  : >"$CALL_LOG"
  (cd "$root/$name" && bash "$root/kickstart" "$@") >"$root/output" 2>&1 || status=$?
  if ((status != expected)); then
    cat "$root/output"
    printf 'Expected exit %s, got %s\n' "$expected" "$status"
    exit 1
  fi
}

run_case minimal 0 nix app
jq -se 'any(.[]; .args == ["flake","init","-t","test:flake#nix"])' "$CALL_LOG" >/dev/null
jq -se 'all(.[]; .args[0] != "develop")' "$CALL_LOG" >/dev/null
jq -se 'any(.[]; .args == ["flake","lock","--override-input","nixpkgs","github:nixos/nixpkgs/build-revision"]) and all(.[]; .args[:2] != ["flake","metadata"])' "$CALL_LOG" >/dev/null

export KICKSTART_FLAKE=test:override
run_case overridden-templates 0 elixir app
jq -se 'any(.[]; .args == ["flake","init","-t","test:override#elixir"]) and any(.[]; .args == ["flake","lock","--override-input","nixpkgs","github:nixos/nixpkgs/test-revision"])' "$CALL_LOG" >/dev/null
unset KICKSTART_FLAKE
# This argument must remain literal throughout command logging and execution.
# shellcheck disable=SC2016
literal='$(touch injected); a b "quoted"'
run_case passthrough 0 elixir 'project with spaces' -- --module "$literal"
jq -se --arg literal "$literal" 'any(.[]; .args == ["develop","--command","mix","new",".","--module",$literal] and .mix_home == "/user/mix")' "$CALL_LOG" >/dev/null
test ! -e "$root/passthrough/project with spaces/injected"

run_case profile 0 phoenix app --agentic -- --no-ecto --module Custom.Web
jq -se 'any(.[]; .args == ["develop","--command","mix","phx.new",".","--no-install","--no-ecto","--module","Custom.Web"] and .mix_env == "dev" and .deps_path == "")' "$CALL_LOG" >/dev/null
jq -se 'any(.[]; .args[2:4] == ["elixir","/read-only installer/install.exs"])' "$CALL_LOG" >/dev/null
jq -se 'any(.[]; .args == ["commit","-m","chore: configure development tooling"])' "$CALL_LOG" >/dev/null
test ! -e "$XDG_CACHE_HOME/kickstart"
jq -se 'all(.[]; .mix_home == "/user/mix")' "$CALL_LOG" >/dev/null
grep -F 'Tooling: installed; quality: passed; security: passed.' "$root/output"
grep -F 'Optional follow-up prompt:' "$root/output"

run_case explicit-install 0 phoenix app --agentic -- --install
jq -se 'any(.[]; .args == ["develop","--command","mix","phx.new",".","--install"])' "$CALL_LOG" >/dev/null

export FAIL_COMMAND='MIX_ENV=test mix ci'
run_case quality-failure 1 elixir app --agentic --
grep -F 'quality: failed (exit 23); security: passed.' "$root/output"
jq -se 'all(.[]; .args[0] != "bookmark" and (.args | index("chore: configure development tooling") | not))' "$CALL_LOG" >/dev/null
test -f "$root/quality-failure/app/flake.nix"
export FAIL_COMMAND='MIX_ENV=test mix security'
run_case security-failure 1 elixir app --agentic --
grep -F 'quality: passed; security: failed (exit 23).' "$root/output"
export FAIL_COMMAND='/read-only installer/install.exs'
run_case installer-failure 23 elixir app --agentic --
grep -F 'Tooling: not completed; quality: not run; security: not run.' "$root/output"
unset FAIL_COMMAND

export FAIL_COMMAND='help hex.audit'
run_case missing-hex 1 elixir app --agentic --
grep -F 'mix local.hex --force' "$root/output"
export FAIL_COMMAND='help phx.new'
run_case missing-phoenix 1 phoenix app --agentic --
grep -F 'mix archive.install hex phx_new --force' "$root/output"
unset FAIL_COMMAND

run_case missing-generator 64 elixir app --agentic
test ! -s "$CALL_LOG"
run_case unsupported-template 64 nix app --agentic --
test ! -s "$CALL_LOG"
run_case umbrella 64 phoenix app --agentic -- --umbrella
test ! -s "$CALL_LOG"
run_case host-option 64 phoenix app --agentic --dev-port 4000 --
test ! -s "$CALL_LOG"

# Exercise the real completion call chain, which rewrites `words` for Mix.
cat >"$root/bin/mix" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$MIX_HOME" > "$COMPLETION_LOG"
printf '%s\n' '## Options' '  * `--no-ecto` - Skip database integration'
SH
chmod +x "$root/bin/mix"
export COMPLETION_LOG="$root/completion.log"
export COMPLETION_SOURCE="${source_file%/*}/_kickstart"
zsh -f <<'ZSH'
_describe() { return 0; }
compadd() { return 0; }
PREFIX=--
words=(kickstart phoenix app --agentic -- --)
CURRENT=6
source "$COMPLETION_SOURCE"
[[ $(< "$COMPLETION_LOG") == /user/mix ]] || exit 1
words=(kickstart phoenix app -- --agentic --)
CURRENT=6
_kickstart
[[ $(< "$COMPLETION_LOG") == /user/mix ]] || exit 1
compadd() { printf '%s\n' "$@" >> "$COMPLETION_LOG"; }
_files() { return 0; }
: > "$COMPLETION_LOG"
PREFIX=''
words=(kickstart nix '')
CURRENT=3
_kickstart
[[ ! -s "$COMPLETION_LOG" ]] || exit 1
ZSH
printf 'Orchestration and checkpoint checks passed.\n'
