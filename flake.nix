{
  description = "ogmios";

  inputs = {
    ogmios-src = {
      url = "git+https://github.com/CardanoSolutions/ogmios?ref=v6.10.0&submodules=1";
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
              "https://github.com/CardanoSolutions/cardano-ledger"."f051a2ed0db076a869d14643a65ce6e8250b6324" = "1zi91lzms5kyjmc7r0p12hrvyg34dyqcvz3bkvsw9djjj4gngkbf";
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
        builtins.removeAttrs self.flake.${system}.packages [
          "hjsonschema:test:local"
          "hjsonschema:test:remote"
          "hjsonschema:test:spec"
        ]
      );

      devShell = perSystem (system: self.flake.${system}.devShell);

      herculesCI.ciSystems = [ "x86_64-linux" ];
    };
}

