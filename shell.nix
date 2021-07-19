with import <nixpkgs> {};

stdenv.mkDerivation rec {
  name = "nix-pure-shell";
  buildInputs = [
    # provides core commands, such as: ls, rm, dir, cp, mkdir, head, etc.
    coreutils
    # You can choose to have a specific version of Bash shell, or any other
    # shell from nixpkgs here.
    bashInteractive_5
    # You can pick any other packages you need, below.
    which
    less
  ];

  # Force nix-shell to retain the temporary directory.
  #
  # If passAsFile list is non-empty, then nix-shell chooses to not delete the
  # temporary directory that it creates to store intermediate files.
  #
  # We need the contents of the temporary directory to support --run option of
  # nix-shell.
  passAsFile=["_nix_pure_shell_dummy_"];
  _nix_pure_shell_dummy_="dummy";

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
  # To support batch mode execution, that is, to support the --run option of
  # nix-shell, we extract the value stored in the "rc" file in the temporary
  # directory. This hack to extract --run option's value was developed by
  # reverse-engineering the source code of nix-shell. Since this is not a
  # documented behaviour, expect this to break in future versions of Nix
  # package manager.
  #
  # Note that the 2 single-quotes ('') below are the Nix language's escape
  # sequemce to escape the ${ (DOLLAR_CURLY) in a string.
  shellHook = ''
    PATH="${builtins.concatStringsSep ":" (map (x: x + "/bin") buildInputs)}"

    # Get the last element's value from BASH_SOURCE[] array; this is the path
    # of rcfile passed by nix-shell.
    rc_file="''${BASH_SOURCE[''${#BASH_SOURCE[*]}-1]}"

    # Extract the first line from the rcfile.
    rc_file_line_1=$(head -1 "$rc_file")

    # Check if the --run or --command option was used; if yes, the second
    # wildcard pattern will represent the value of the --run/--command option
    # to nix-shell.
    [[ "$rc_file_line_1" =~ .*shopt\ -s\ execfail\;(.*) ]]  \
    && run_args="''${BASH_REMATCH[1]}"

    # If nix-shell was invoked with --run option, pass that value to our shell,
    # else just start the shell in interactive mode.
    #
    # Note that we don't support the nix-shell's --command option, yet, because
    # that option promises to run the command(s) in an interactive shell. We
    # currently don't have a way to do that. Moreover, by looking at the
    # contents of the rcfile, we currently cannot determine if the --run option
    # was used or --command option was used.
    [[ -n "$run_args" ]]          \
    && exec env -i                \
      PATH="$PATH"                \
      TERM="$TERM"                \
      bash --norc -c "$run_args"  \
    || exec env -i                \
      PATH="$PATH"                \
      TERM="$TERM"                \
      bash --norc
  '';
}

