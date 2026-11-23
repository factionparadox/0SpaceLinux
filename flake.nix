{
  description = "0-Space Linux: an Andalite Dome ship, on NixOS";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable&shallow=1";
    flake-parts.url = "git+https://github.com/hercules-ci/flake-parts?shallow=1";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    import-tree.url = "git+https://github.com/vic/import-tree?shallow=1";
  };

  # Dendritic: every file under modules/ is a flake-parts module, picked up
  # automatically. Each feature lives in one file and declares the NixOS
  # module it contributes under flake.modules.nixos.<feature>.
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
