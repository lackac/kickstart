{
  description = "Elixir and Phoenix project bootstrap tooling";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };
      treefmtEval = forAllSystems (system: treefmt-nix.lib.evalModule (pkgsFor system) ./treefmt.nix);
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.beam29Packages.elixir_1_20
              pkgs.beam29Packages.rebar3
              pkgs.bash
              pkgs.coreutils
              pkgs.git
              pkgs.jq
              pkgs.just
            ];
            MIX_REBAR3 = "${pkgs.beam29Packages.rebar3}/bin/rebar3";
            HEX_CACERTS_PATH = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        }
      );

      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (system: {
        formatting = treefmtEval.${system}.config.build.check self;
      });
    };
}
