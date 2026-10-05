# Nix project

Enter `nix develop`, then run `just` to list the commands.

- `just fmt` formats Nix files.
- `just check` runs flake checks, including formatting.
- `just up` updates all inputs; `just upp <input>` updates one.
- `just sync-nixpkgs` aligns nixpkgs with the sibling `../nix-config` checkout.
  Pass another source with `just sync-nixpkgs <path-or-flake-reference>`.
- `just syncup` updates inputs and then aligns nixpkgs; `just syncupp <input>`
  aligns nixpkgs before updating one input.

Set the description in `flake.nix`, extend the development shell, and define
packages or modules as the project grows. Keep `flake.lock` under version control.
