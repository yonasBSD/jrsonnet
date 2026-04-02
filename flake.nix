{
  description = "Jrsonnet";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    hercules-ci-effects = {
      url = "github:hercules-ci/hercules-ci-effects";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";
    shelly.url = "github:CertainLach/shelly";
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.shelly.flakeModule
        inputs.hercules-ci-effects.flakeModule
      ];
      systems = inputs.nixpkgs.lib.systems.flakeExposed;
      perSystem =
        {
          config,
          system,
          ...
        }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.fenix.overlays.default ];
            config.allowUnsupportedSystem = true;
          };
          toolchain = pkgs.fenix.combine [
            (pkgs.fenix.stable.withComponents [
              "cargo"
              "clippy"
              "rustc"
              "rust-src"
            ])
            pkgs.fenix.complete.rustfmt
          ];
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain toolchain;
          treefmt =
            (inputs.treefmt-nix.lib.evalModule pkgs (
              import ./treefmt.nix { rustfmt = pkgs.fenix.complete.rustfmt; }
            )).config.build;
        in
        {
          legacyPackages = {
            jsonnetImpls = {
              go-jsonnet = pkgs.callPackage ./nix/go-jsonnet.nix { };
              sjsonnet = pkgs.callPackage ./nix/sjsonnet.nix { };
              cpp-jsonnet = pkgs.callPackage ./nix/cpp-jsonnet.nix { };
              # I didn't managed to build it, and nixpkgs version is marked as broken
              # haskell-jsonnet = pkgs.callPackage ./nix/haskell-jsonnet.nix { };
              rsjsonnet = pkgs.callPackage ./nix/rsjsonnet.nix { };
            };
          };
          packages =
            let
              jrsonnet = pkgs.callPackage ./nix/jrsonnet.nix {
                inherit craneLib;
              };
              jrsonnet-experimental = pkgs.callPackage ./nix/jrsonnet.nix {
                inherit craneLib;
                withExperimentalFeatures = true;
              };
              jrsonnet-release = pkgs.callPackage ./nix/jrsonnet-release.nix {
                rustPlatform = pkgs.makeRustPlatform {
                  rustc = toolchain;
                  cargo = toolchain;
                };
              };
            in
            {
              default = jrsonnet;
              inherit jrsonnet jrsonnet-experimental jrsonnet-release;
            }
            // pkgs.lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-linux") {
              benchmarks = pkgs.callPackage ./nix/benchmarks.nix {
                inherit (config.legacyPackages.jsonnetImpls)
                  go-jsonnet
                  sjsonnet
                  cpp-jsonnet
                  rsjsonnet
                  ;
                jrsonnetVariants = [
                  {
                    drv = jrsonnet.override { forBenchmarks = true; };
                    name = "";
                  }
                ];
              };
              benchmarks-quick = pkgs.callPackage ./nix/benchmarks.nix {
                inherit (config.legacyPackages.jsonnetImpls)
                  go-jsonnet
                  sjsonnet
                  cpp-jsonnet
                  rsjsonnet
                  ;
                quick = true;
                jrsonnetVariants = [
                  {
                    drv = jrsonnet.override { forBenchmarks = true; };
                    name = "";
                  }
                ];
              };
              benchmarks-against-release = pkgs.callPackage ./nix/benchmarks.nix {
                inherit (config.legacyPackages.jsonnetImpls)
                  go-jsonnet
                  sjsonnet
                  cpp-jsonnet
                  rsjsonnet
                  ;
                jrsonnetVariants = [
                  {
                    drv = jrsonnet.override { forBenchmarks = true; };
                    name = "current";
                  }
                  {
                    drv = jrsonnet-experimental.override { forBenchmarks = true; };
                    name = "current-experimental";
                  }
                  {
                    drv = jrsonnet-release.override { forBenchmarks = true; };
                    name = "release";
                  }
                ];
              };
              benchmarks-quick-against-release = pkgs.callPackage ./nix/benchmarks.nix {
                inherit (config.legacyPackages.jsonnetImpls)
                  go-jsonnet
                  sjsonnet
                  cpp-jsonnet
                  rsjsonnet
                  ;
                quick = true;
                jrsonnetVariants = [
                  {
                    drv = jrsonnet.override { forBenchmarks = true; };
                    name = "current";
                  }
                  {
                    drv = jrsonnet-experimental.override { forBenchmarks = true; };
                    name = "current-experimental";
                  }
                  {
                    drv = jrsonnet-release.override { forBenchmarks = true; };
                    name = "release";
                  }
                ];
              };
            };
          checks.formatting = treefmt.check inputs.self;
          formatter = treefmt.wrapper;
          shelly.shells.default = {
            factory = craneLib.devShell;
            packages =
              with pkgs;
              [
                cargo-edit
                cargo-outdated
                cargo-watch
                cargo-insta
                cargo-hack
                lld
                hyperfine
                graphviz
              ]
              ++ lib.optionals (!stdenv.isDarwin) [
                valgrind
                kdePackages.kcachegrind
              ];
          };
        };
      herculesCI =
        { lib, ... }:
        {
          ciSystems = [
            "x86_64-linux"
            "i686-linux"
            # TODO: add workers for these platforms
            # "aarch64-linux"
            # "aarch64-darwin"
            # "armv7l-linux"
          ];
          onPush.default.outputs.devShells = lib.mkForce { };
        };
    };
}
