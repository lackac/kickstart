# Bootstrap using Mix's standard cache. Project commands use their own deps/_build.
Enum.each(["MIX_BUILD_PATH", "MIX_BUILD_ROOT", "MIX_DEPS_PATH"], &System.delete_env/1)

Mix.install(
  [{:igniter, "== 0.8.4"}, {:sourceror, "== 1.12.3"}],
  lockfile: Path.join(__DIR__, "mix.lock")
)

Path.wildcard(Path.join(__DIR__, "lib/**/*.ex")) |> Enum.each(&Code.require_file/1)
KickstartElixir.main(System.argv(), Path.join(__DIR__, "priv"))
