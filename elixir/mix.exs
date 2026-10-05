defmodule KickstartElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :kickstart_elixir,
      version: "0.1.0",
      elixir: "~> 1.20",
      deps: [{:igniter, "== 0.8.4"}, {:sourceror, "== 1.12.3"}]
    ]
  end
end
