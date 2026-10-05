{
  pkgs,
  templateFlake,
  nixpkgsRev,
}:
let
  templateNames = builtins.filter (name: name != "default") (
    builtins.attrNames templateFlake.templates
  );
  installerSource = pkgs.lib.cleanSourceWith {
    src = ./elixir;
    filter =
      path: _:
      !(builtins.elem (baseNameOf path) [
        "_build"
        "deps"
        ".git"
      ]);
  };
  script = pkgs.writeShellApplication {
    name = "kickstart";
    runtimeInputs = [
      pkgs.jq
      pkgs.jujutsu
    ];
    text =
      builtins.replaceStrings
        [ "@templateFlake@" "@elixirInstaller@" "@nixpkgsRev@" ]
        [ "path:${templateFlake}" (toString installerSource) nixpkgsRev ]
        (builtins.readFile ./kickstart.sh);
  };
  completionText =
    builtins.replaceStrings
      [ "@mix@" "@templateWords@" ]
      [ "${pkgs.beam29Packages.elixir_1_20}/bin/mix" (builtins.concatStringsSep " " templateNames) ]
      (builtins.readFile ./_kickstart);
  completions = pkgs.runCommand "kickstart-completions" { } ''
    mkdir -p $out/share/zsh/site-functions
    cp ${pkgs.writeText "_kickstart" completionText} $out/share/zsh/site-functions/_kickstart
  '';
in
pkgs.symlinkJoin {
  name = "kickstart";
  paths = [
    script
    completions
  ];
  meta.mainProgram = "kickstart";
}
