defmodule KickstartElixirTest do
  use ExUnit.Case, async: false

  @assets Path.expand("../priv", __DIR__)

  setup do
    root = System.fetch_env!("KICKSTART_TEST_ROOT")
    work = Path.join(root, Integer.to_string(System.unique_integer([:positive])))
    File.mkdir_p!(work)
    on_exit(fn -> File.rm_rf!(work) end)
    {:ok, work: work}
  end

  test "plain custom-module project receives only tooling and preserves guidance", %{work: work} do
    target = generate!(work, "elixir")
    original = "Existing guidance\r\nπ\nNo final newline"
    File.write!(Path.join(target, "AGENTS.md"), original)
    upstream = snapshot(target)
    inode = File.stat!(target).inode

    File.cd!(target, fn ->
      assert %{app: :custom_app, phoenix?: false} = install!(target, "elixir")
      assert File.stat!(".").inode == inode
      assert File.read!("mix.exs") =~ "credo"
    end)

    assert_untouched(target, upstream)
    assert read(target, "AGENTS.md") |> String.starts_with?(original <> "\n")
    refute File.exists?(Path.join(target, "AGENTIC.md"))
    refute File.exists?(Path.join(target, "opencode.jsonc"))
    refute File.exists?(Path.join(target, ".opencode"))
    assert length(String.split(read(target, "AGENTS.md"), "\n")) < 30
    mix = read(target, "mix.exs")
    assert mix =~ ~s({:igniter, "~> 0.8.4", only: :dev, runtime: false})
    refute mix =~ "{:sourceror,"
    assert mix =~ "preferred_envs: [check: :test, ci: :test, security: :test]"
    assert mix =~ ~s(ci: ["check", "deps.unlock --check-unused"])
    assert mix =~ ~s(security: ["hex.audit"])
    {credo, _} = Code.eval_string(read(target, ".credo.exs"))
    assert hd(credo.configs).plugins == [{ExSlop, []}]
    refute read(target, ".credo.exs") =~ "excluded"
    refute File.exists?(Path.join(target, "scripts/check-security"))
    assert Path.wildcard(target <> ".kickstart-*") == []
  end

  test "Phoenix variants keep all application files, formatter, and generator guidance intact", %{
    work: work
  } do
    for flags <- [[], ["--no-ecto"], ["--no-ecto", "--no-html", "--no-assets"]] do
      target = generate!(work, "phoenix", flags)
      layout = Path.join(target, "lib/custom_app_web/components/layouts/root.html.heex")

      if File.exists?(layout),
        do: File.write!(layout, File.read!(layout) <> "<!-- newer generator -->\n")

      upstream = snapshot(target)
      install!(target, "phoenix")
      assert_untouched(target, upstream)
      assert String.starts_with?(read(target, "AGENTS.md"), upstream["AGENTS.md"])
      assert read(target, "mix.exs") =~ "{:sobelow,"

      assert read(target, "mix.exs") =~
               ~s(security: ["hex.audit", "sobelow --private --strict --exit medium --summary"])

      refute read(target, "mix.exs") =~ "{:tidewave,"
      refute File.exists?(Path.join(target, "scripts/dev-proxy"))

      assert Regex.run(~r/precommit: \[.*?\]/s, read(target, "mix.exs")) ==
               Regex.run(~r/precommit: \[.*?\]/s, upstream["mix.exs"])
    end
  end

  test "a project whose generator fetched dependencies is supported", %{work: work} do
    target = generate!(work, "elixir", ["--sup"])
    File.mkdir!(Path.join(target, "deps"))
    File.mkdir!(Path.join(target, "_build"))
    File.write!(Path.join(target, "mix.lock"), "%{}\n")
    install!(target, "elixir")
    assert read(target, "mix.lock") == "%{}\n"
  end

  test "file, dependency, and alias conflicts fail before writes", %{work: work} do
    for conflict <- [:file, :dependency, :alias] do
      target = generate!(work, "elixir")

      case conflict do
        :file ->
          File.write!(Path.join(target, ".credo.exs"), "existing config")

        :dependency ->
          File.write!(
            Path.join(target, "mix.exs"),
            String.replace(
              read(target, "mix.exs"),
              "defp deps do\n    [",
              "defp deps do\n    [{:credo, \"~> 1.7\"},"
            )
          )

        :alias ->
          File.write!(
            Path.join(target, "mix.exs"),
            String.replace(
              read(target, "mix.exs"),
              "app: :custom_app,",
              "app: :custom_app, aliases: [check: [\"test\"]],"
            )
          )
      end

      before = snapshot(target)
      assert_raise ArgumentError, fn -> install!(target, "elixir") end
      assert snapshot(target) == before
    end
  end

  test "reinstallation and symlink destinations are refused without writes", %{work: work} do
    target = generate!(work, "elixir")
    install!(target, "elixir")
    before = snapshot(target)
    assert_raise ArgumentError, ~r/already installed/, fn -> install!(target, "elixir") end
    assert snapshot(target) == before

    other = generate!(work, "elixir")
    File.mkdir!(Path.join(work, "external"))
    File.mkdir!(Path.join(work, "external/workflows"))
    File.ln_s!(Path.join(work, "external"), Path.join(other, ".forgejo"))
    original = read(other, "mix.exs")
    assert_raise ArgumentError, ~r/expected a directory/, fn -> install!(other, "elixir") end
    assert read(other, "mix.exs") == original
    assert File.ls!(Path.join(work, "external/workflows")) == []
  end

  test "unsafe compact dependency edits cannot write invalid Elixir", %{work: work} do
    target = generate!(work, "elixir")

    mix =
      Regex.replace(
        ~r/defp deps do\s*\[.*?\]\s*end/s,
        read(target, "mix.exs"),
        "defp deps, do: []"
      )

    File.write!(Path.join(target, "mix.exs"), mix)
    before = snapshot(target)

    try do
      install!(target, "elixir")
      assert {:ok, _} = Code.string_to_quoted(read(target, "mix.exs"))
    rescue
      _error in [SyntaxError, TokenMissingError, ArgumentError] ->
        assert snapshot(target) == before
    end
  end

  defp generate!(work, template, flags \\ []) do
    target = Path.join(work, "project-#{System.unique_integer([:positive])}")
    args = if template == "elixir", do: ["new", target], else: ["phx.new", target, "--no-install"]

    {output, code} =
      System.cmd("mix", args ++ ["--app", "custom_app", "--module", "Custom.Name"] ++ flags,
        cd: work,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "dev"}]
      )

    assert code == 0, output
    target
  end

  defp install!(target, template),
    do: KickstartElixir.install!(target, [template: template], @assets)

  defp read(target, path), do: File.read!(Path.join(target, path))

  defp snapshot(target) do
    for path <- Path.wildcard(Path.join(target, "**/*"), match_dot: true),
        File.regular?(path),
        into: %{},
        do: {Path.relative_to(path, target), File.read!(path)}
  end

  defp assert_untouched(target, upstream) do
    for {path, content} <- upstream,
        path not in ["mix.exs", "AGENTS.md"],
        do: assert(read(target, path) == content, "installer changed #{path}")
  end
end
