(lang dune 3.12)
(name manaba_cli)
(generate_opam_files true)
(source (github Kyure-A/manaba-cli))
(license GPL-3.0-only)
(authors Kyure_A)
(maintainers "Kyure_A <49436968+Kyure-A@users.noreply.github.com>")

(package
 (name manaba_cli)
 (synopsis "CLI client for University of Tsukuba manaba")
 (description "Operate University of Tsukuba manaba from a terminal.")
 (depends
  (ocaml (>= 5.1))
  cmdliner
  conduit-lwt-unix
  cohttp-lwt-unix
  lambdasoup
  lwt
  uri
  yojson
  (alcotest :with-test)))
