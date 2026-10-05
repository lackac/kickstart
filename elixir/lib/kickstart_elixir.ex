defmodule KickstartElixir do
  @moduledoc "A one-time development-tooling overlay for upstream Mix projects."

  @deps [
    {:igniter, "~> 0.8.4", only: :dev, runtime: false},
    {:credo, "== 1.7.19", only: [:dev, :test], runtime: false},
    {:ex_slop, "== 0.4.5", only: [:dev, :test], runtime: false}
  ]
  @check [
    "format --check-formatted",
    "compile --warnings-as-errors",
    "credo --strict",
    "test --warnings-as-errors"
  ]

  def main(args, assets) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [target: :string, template: :string])
    if rest != [] or invalid != [], do: fail!("invalid installer arguments")
    install!(Keyword.fetch!(opts, :target), opts, assets)
  rescue
    error ->
      IO.puts(:stderr, "kickstart: #{Exception.message(error)}")
      IO.puts(:stderr, "Inspect the working tree before retrying; no changes were rolled back.")
      System.halt(1)
  end

  def install!(target, opts, assets) do
    template = Keyword.fetch!(opts, :template)
    unless template in ["elixir", "phoenix"], do: fail!("unsupported template")

    File.cd!(target, fn ->
      if File.dir?("apps"), do: fail!("umbrella projects are not supported")
      regular_destination!(".kickstart-profile")
      if File.exists?(".kickstart-profile"), do: fail!("tooling is already installed")

      if File.exists?(".igniter.exs"),
        do: fail!("existing Igniter configuration needs manual review")

      regular_destination!("mix.exs")
      regular_destination!("AGENTS.md")

      source = File.read!("mix.exs")
      {mix, app, phoenix?} = prepare_mix!(source, template)
      bindings = [app: Atom.to_string(app), phoenix?: phoenix?]
      files = render_assets!(assets, bindings)
      guidance = EEx.eval_file(Path.join(assets, "agents.md.eex"), bindings)

      for {path, _} <- files do
        regular_destination!(path)
        if File.exists?(path), do: fail!("tooling file already exists: #{path}")
      end

      # All rendering, conflict checks, and syntax validation precede writes.
      # I/O failures leave ordinary working-tree changes for inspection.
      File.write!("mix.exs", mix <> "\n")

      for {path, content} <- files do
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content, [:exclusive])
      end

      File.write!("AGENTS.md", "\n" <> guidance, [:append])
      File.write!(".kickstart-profile", "tooling-v1\n", [:exclusive])
      %{app: app, phoenix?: phoenix?}
    end)
  end

  defp prepare_mix!(source, template) do
    # Edit an in-memory source from the installer's directory. Sourceror looks
    # up formatter options in the cwd; Phoenix's formatter would compile the app.
    # No project files are copied or temporarily replaced.
    File.cd!(Path.expand("..", __DIR__), fn ->
      igniter = %Igniter{
        rewrite:
          Rewrite.new(dot_formatter: Rewrite.DotFormatter.default())
          |> Rewrite.put!(Rewrite.Source.Ex.from_string(source, path: "mix.exs"))
      }

      app = Igniter.Project.Application.app_name(igniter)
      phoenix? = dependency?(igniter, :phoenix)
      if phoenix? != (template == "phoenix"), do: fail!("template does not match project")

      deps =
        @deps ++
          if(phoenix?,
            do: [{:sobelow, "== 0.16.0", only: [:dev, :test], runtime: false}],
            else: []
          )

      for dep <- deps do
        if dependency?(igniter, elem(dep, 0)),
          do: fail!("dependency already exists: #{elem(dep, 0)}")
      end

      igniter =
        Enum.reduce(
          deps,
          igniter,
          &Igniter.Project.Deps.add_dep(&2, &1, error?: true, yes?: true)
        )
        |> Igniter.Project.TaskAliases.add_alias(:check, @check, if_exists: :warn)
        |> Igniter.Project.TaskAliases.add_alias(:ci, ["check", "deps.unlock --check-unused"],
          if_exists: :warn
        )
        |> Igniter.Project.TaskAliases.add_alias(
          :security,
          ["hex.audit"] ++
            if(phoenix?, do: ["sobelow --private --strict --exit medium --summary"], else: []),
          if_exists: :warn
        )

      igniter =
        Enum.reduce([:check, :ci, :security], igniter, fn task, acc ->
          Igniter.Project.MixProject.update(acc, :cli, [:preferred_envs, task], fn _ ->
            {:ok, {:code, :test}}
          end)
        end)

      if igniter.issues != [] or igniter.warnings != [],
        do: fail!("cannot safely edit mix.exs: #{inspect(igniter.issues ++ igniter.warnings)}")

      source = Rewrite.source!(igniter.rewrite, "mix.exs")
      if Rewrite.Source.has_issues?(source), do: fail!("cannot safely rewrite mix.exs")

      mix =
        source
        |> Rewrite.Source.get(:content)
        |> Code.format_string!()
        |> IO.iodata_to_binary()

      {mix, app, phoenix?}
    end)
  end

  defp dependency?(igniter, name) do
    case Igniter.Project.Deps.get_dep(igniter, name) do
      {:ok, nil} -> false
      {:ok, _} -> true
      {:error, message} -> fail!(message)
    end
  end

  defp render_assets!(assets, bindings) do
    groups = if bindings[:phoenix?], do: ["common", "phoenix"], else: ["common"]

    for group <- groups,
        source <- Path.wildcard(Path.join([assets, group, "**/*.eex"]), match_dot: true) do
      path =
        source |> Path.relative_to(Path.join(assets, group)) |> String.replace_suffix(".eex", "")

      {path, EEx.eval_file(source, bindings)}
    end
  end

  defp regular_destination!(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} -> :ok
      {:error, :enoent} -> :ok
      _ -> fail!("expected a regular file: #{path}")
    end

    for parent <- path |> Path.dirname() |> Path.split() |> Enum.scan(&Path.join(&2, &1)),
        parent != "." do
      case File.lstat(parent) do
        {:ok, %{type: :directory}} -> :ok
        {:error, :enoent} -> :ok
        _ -> fail!("expected a directory: #{parent}")
      end
    end
  end

  defp fail!(message), do: raise(ArgumentError, message)
end
