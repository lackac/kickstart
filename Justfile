# https://just.systems

set positional-arguments

default:
  @just --list

fmt:
  nix fmt

check:
  nix flake check

build:
  nix build

run *args:
  nix run . -- "$@"

up:
  nix flake update

upp input:
  nix flake update {{input}}

syncup:
  just up
  just sync-nixpkgs

syncupp input:
  just sync-nixpkgs
  just upp {{input}}

sync-nixpkgs:
  nix flake lock \
    --override-input nixpkgs github:nixos/nixpkgs/$(nix flake metadata ../nix-config --json | jq -r '.locks.nodes[.locks.nodes[.locks.root].inputs.nixpkgs].locked.rev')
