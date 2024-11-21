{
  description = "ogmios";

  inputs = {
    ogmios-src = {
      url = "git+https://github.com/CardanoSolutions/ogmios?tag=v6.8.0&submodules=1";
      flake = false;
    };

    haskell-nix = {
      url = "github:input-output-hk/haskell.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.follows = "haskell-nix/nixpkgs-unstable";

    CHaP = {
      url = "github:intersectmbo/cardano-haskell-packages?ref=repo";
      flake = false;
    };

    iohk-nix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, ogmios-src, nixpkgs, haskell-nix, iohk-nix, CHaP, ... }:
    let
      defaultSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = nixpkgs.lib.genAttrs defaultSystems;

      nixpkgsFor = system: import nixpkgs {
        overlays = [
          iohk-nix.overlays.crypto
          haskell-nix.overlay
          iohk-nix.overlays.haskell-nix-crypto

        ];
        inherit (haskell-nix) config;
        inherit system;
      };

      projectFor = { system }:
        let
          pkgs = nixpkgsFor system;

          cleanSource =
            nixpkgs.lib.cleanSourceWith {
              name = "ogmios-src-clean";
              src = "${ogmios-src}/server";
              filter = path: type: builtins.all (x: x) [ (baseNameOf path != "package.yaml") ];
            };

        in
        pkgs.haskell-nix.cabalProject {
          src = cleanSource;
          inputMap = {
            "https://input-output-hk.github.io/cardano-haskell-packages" = CHaP;
          };
          name = "ogmios";
          compiler-nix-name = "ghc966";

          shell = {
            inputsFrom = [ pkgs.libsodium-vrf ];
            exactDeps = true;
            nativeBuildInputs = [ pkgs.libsodium-vrf pkgs.secp256k1 ];
          };

          sha256map =
            {
              "https://github.com/CardanoSolutions/cardano-ledger"."8112c9872f52e5147e28fbdd76a034cdb6eb7fea" = "0lzz5fcl73xz2cq5727q4a7q1855ihrx5wapadlm8izhjvxv4dxb";
            };

          modules = [{
            packages = {
              cardano-crypto-praos.components.library.pkgconfig =
                pkgs.lib.mkForce [ [ pkgs.libsodium-vrf ] ];

              cardano-crypto-class.components.library.pkgconfig =
                pkgs.lib.mkForce [ [ pkgs.libsodium-vrf pkgs.secp256k1 pkgs.libblst ] ];
            };
          }];

        };
    in
    {
      flake = perSystem (system: (projectFor { inherit system; }).flake { });

      defaultPackage = perSystem (system:
        self.flake.${system}.packages."ogmios:exe:ogmios"
      );

      packages = perSystem (system:
        self.flake.${system}.packages
      );

      devShell = perSystem (system: self.flake.${system}.devShell);

      # Build all of the project's packages and run the `checks`
      check = perSystem (system:
        (nixpkgsFor system).runCommand "combined-check"
          {
            nativeBuildInputs =
              builtins.attrValues self.checks.${system}
              ++ builtins.attrValues self.flake.${system}.packages;
          } "touch $out"
      );

      # # HACK
      # # Only include `ogmios:test:unit` and just build/run that
      # # We could configure this via haskell.nix, but this is
      # # more convenient
      # checks = perSystem (system: {
      #   inherit (self.flake.${system}.checks) "ogmios:test:unit";
      # });

      herculesCI.ciSystems = [ "x86_64-linux" "x86_64-darwin" ];
    };
}
