{
  description = "Elixir development shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.beam29Packages.elixir_1_20
              pkgs.beam29Packages.rebar3
              pkgs.git
            ];
            MIX_REBAR3 = "${pkgs.beam29Packages.rebar3}/bin/rebar3";
            HEX_CACERTS_PATH = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        }
      );
    };
}
