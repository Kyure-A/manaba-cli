{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  packages = with pkgs.ocamlPackages; [
    ocaml
    dune_3
    findlib
    cmdliner
    cohttp-lwt-unix
    lambdasoup
    yojson
    alcotest
    ocamlformat
  ];
}
