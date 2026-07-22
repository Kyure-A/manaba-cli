{
  description = "CLI client for University of Tsukuba manaba";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      packageFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) ocamlPackages;
        in
        ocamlPackages.buildDunePackage {
          pname = "manaba_cli";
          version = "0.1.0";
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                name = builtins.baseNameOf path;
              in
              pkgs.lib.cleanSourceFilter path type
              && name != "_build"
              && name != ".direnv"
              && name != "result"
              && !(pkgs.lib.hasPrefix "result-" name);
          };
          duneVersion = "3";
          minimalOCamlVersion = "5.1";

          propagatedBuildInputs = with ocamlPackages; [
            cmdliner
            conduit-lwt-unix
            cohttp-lwt-unix
            lambdasoup
            lwt
            uri
            yojson
          ];

          checkInputs = [ ocamlPackages.alcotest ];
          doCheck = true;

          meta = {
            description = "CLI client for University of Tsukuba manaba";
            homepage = "https://github.com/Kyure-A/manaba-cli";
            license = pkgs.lib.licenses.gpl3Only;
            mainProgram = "manaba";
            platforms = systems;
          };
        };
    in
    {
      packages = forAllSystems (system: rec {
        manaba-cli = packageFor system;
        default = manaba-cli;
      });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/manaba";
          meta = self.packages.${system}.default.meta;
        };
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          package = self.packages.${system}.default;
        in
        {
          inherit package;
          cli-smoke = pkgs.runCommand "manaba-cli-smoke" { } ''
            ${pkgs.bash}/bin/bash ${./scripts/ci-smoke.sh} ${package}/bin/manaba
            touch "$out"
          '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];
            packages = with pkgs.ocamlPackages; [
              alcotest
              dune_3
              findlib
              ocaml
              ocamlformat
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
