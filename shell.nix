with import <nixpkgs> {};

stdenv.mkDerivation rec {
  name = "nix-pure-shell";
  buildInputs = [
    # provides core commands, such as: ls, rm, dir, cp, mkdir, etc.
    coreutils
    # You can choose to have a specific version of Bash shell, or any other
    # shell from nixpkgs here.
    bashInteractive_5
    # You can pick any other packages you need, below.
    which
    less
  ];

  # The environment created by nix-shell has *many* extraneous (and some even
  # undocumented) variables, functions, etc. Many of these are populated by
  # files such as invoking user's ~/.bashrc, or /etc/bashrc, and some are
  # populated/overridden by nix-shell. This behaviour makes the resulting shell
  # "impure" by depending on the environment it is invoked in. Even the --pure
  # option of nix-shell does not fully remedy this.
  #
  # Using the `exec env -i bash --norc` command, we ensure that we get a clean
  # environment. Then we pick the minimal number of environment variables to
  # get a functioning environment. For example, if you need tools like Vim or
  # Less to work in the new shell, you need to tell them what kind of terminal
  # they are dealing with, so we populate the TERM variable with the same value
  # that we inherited. But if you don't intend to use
  #
  # We discard the value of PATH, and repopulate it with the `bin/` directories of
  # just the packages that we list as input in buildInputs, and use that new
  # list as the PATH environment variable in our pure shell.
  #
  # This forces us to use only those binaries that we requested from Nix
  # package manager.
  #
  # Note that our use of `exec` causes this shell.nix to be unusable for batch
  # use-cases such as `nix-shell --run some-command`.
  shellHook = ''
    PATH="${builtins.concatStringsSep ":" (map (x: x + "/bin") buildInputs)}"
    exec env -i       \
      PATH="$PATH"    \
      TERM="$TERM"    \
      bash --norc
  '';
}

