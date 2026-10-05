{ pkgs, ... }:
{
  projectRootFile = "flake.nix";
  programs.nixfmt.enable = true;
  programs.shfmt = {
    enable = true;
    indent_size = 2;
  };
  programs.mix-format = {
    enable = true;
    package = pkgs.beam29Packages.elixir_1_20;
  };
  settings.global.excludes = [
    "elixir/deps/**"
    "elixir/_build/**"
  ];
}
