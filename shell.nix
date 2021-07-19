with import <nixpkgs> {};

stdenv.mkDerivation rec {
  name = "nix-pure-shell";
  buildInputs = [
    coreutils
    which
    less
    bashInteractive_5
  ];

  shellHook = ''
    PATH="${builtins.concatStringsSep ":" (map (x: x + "/bin") buildInputs)}"
    exec env -i       \
      PATH="$PATH"    \
      TERM="$TERM"    \
      bash --norc
  '';
}


