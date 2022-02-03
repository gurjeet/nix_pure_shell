
# The parameters we accept, follow.
{
  # The system we're building for; defaults to the host system
  system ? builtins.currentSystem,

  /* The Bash shell we want; defaults to Bash 5 */
  bashVersion ? "5",

  /* Where do you want us to install the results */
  installationPath ? "./inst",

  # The compiler we will use; defaults to GCC
  ccName ? "gcc",

  # How many parallel jobs should we run
  jobs ? 2, # By default use at least 2 jobs

  # Should we use the ccache?
  useCcache ? true,
}:
with import <nixpkgs> {inherit system;};
/*

# For stability of your package, You can pick a specific version of NixPkgs, like below.
import (builtins.fetchTarball {
  name = "2020-12-22";
  url = "https://github.com/NixOS/nixpkgs/archive/2a058487cb7a50e7650f1657ee0151a19c59ec3b.tar.gz";
  sha256 = "1h8c0mk6jlxdmjqch6ckj30pax3hqh6kwjlvp2021x3z4pdzrn9p";
}) {;

*/
let
  _cc = (if ccName == "gcc"
          then gcc
          else
            if ccName == "clang"
            then clang
            else {});
  bash = (if bashVersion == "5"
          then bashInteractive_5
          else
            if bashVersion == "4"
            then bashInteractive_4
            else {});

  _if = cond: _then: _else: if cond then _then else _else;

in
stdenv.mkDerivation rec {
  name = "nix-pure-shell";

  # List those packages here that provide binaries/executables, and are
  # necessary for the build environment.
  binPackages = [
    # provides basic commands, such as: ls, rm, dir, cp, mkdir, head, etc.
    coreutils
    # You can choose to have a specific version of Bash shell, or any other
    # shell from nixpkgs here.
    bashInteractive_5
    # You can pick any other packages you need, below.
    which
    less
    _cc
    ccache
    gnugrep
    gnused
    git
    gawk
    gnumake
    perl
    bison
    flex
    pkg-config
    libxml2
    libxslt
  ] ++ (if !stdenv.hostPlatform.isDarwin then [binutils.bintools] else []);

  /*
   * List those packages here that provide libraries, and/or include files,
   * and are necessary for the build environment.
   */
  libPackages = [
    zlib
    zlib.dev
    readline81
    readline81.dev
    openssl
    openssl.dev
    libxml2
  ];

  # List those packages here that you need just for manual editing, etc.
  personalBinPackages = [
    findutils
    less
    which
    vim
    file
    watch
  ];

  personalLibPackages = [
  ];


  # TODO: Add personalBinPackages and personalLibPackages to buildInputs, iff
  # in nix-shell; do not add them if we're in nix-build.
  allBinPackages = binPackages ++ personalBinPackages;
  allLibPackages = libPackages ++ personalLibPackages;

  # TODO: Remove duplicates, if any, from the result of list concatenations,
  # before assigning to buildInputs. This should be a low priority, becuse
  # having duplicates in these lists is not that big a concern.
  buildInputs = allBinPackages ++ allLibPackages;

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
  # that we inherited.
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
    PATH="${builtins.concatStringsSep ":" (map (x: x + "/bin") allBinPackages)}"

    # Get the last element's value from BASH_SOURCE[] array; this is the path
    # of rcfile passed by nix-shell.
    rc_file="''${BASH_SOURCE[''${#BASH_SOURCE[*]}-1]}"

    # Extract the first line from the rcfile.
    rc_file_line_1=$(head -1 "$rc_file")
    rc_file_line_2=$(head -2 "$rc_file" | tail -1)

    # Check if the --run or --command option was used; if yes, the second
    # wildcard pattern will represent the value of the --run/--command option
    # to nix-shell.
    [[ "$rc_file_line_1" =~ .*shopt\ -s\ execfail\;(.*) ]]  \
    && run_args="''${BASH_REMATCH[1]}"

    # When an empty string is passed to the --run option, nix-shell exits
    # cleanly, whereas in our case the interactive shell is invoked. Replace
    # the empty string with a blank (spaces only) string, so that our behaviour
    # matches that of nix-shell.
    if [[ -z "$run_args" && "$rc_file_line_2" == "exit" ]]; then
      run_args=' '
    fi

    # TODO: Support multi-line value of --run option; capture all lines between
    # 'shopt -s execfail' and 'exit', and pass them to the new shell.
    #
    # Note that we don't support nix-shell's --command option, yet, because
    # that option promises to run the command(s) in an interactive shell. We
    # currently don't have a way to do that. Moreover, by looking at the
    # contents of the rcfile, we currently cannot determine if the --run option
    # was used or --command option was used.
    #
    # TODO: Support the --command option; if the last line of the rcfile does
    # *not* contain the word 'exit' all by itself, it's very likely a --command
    # invocation, rather than the --run invocation.

    # If nix-shell was invoked with --run option, pass that value to our shell,
    # else just start the shell in interactive mode. We use Bash's string
    # operator ''${x:+} to achieve this.
    echo exec env -i                                                                 \
      PATH="$PATH${_if stdenv.isDarwin '':''${PWD}/nix_impure_files/macos'' ""}"\
      TERM="''${TERM}"                                                          \
      CC="${_if useCcache "ccache" "" } ${ccName}"                              \
      JOBS=${toString jobs}                                                     \
      PKG_CONFIG_PATH="$PKG_CONFIG_PATH_FOR_TARGET"                             \
      LDFLAGS="$( pkg-config --libs-only-L   readline zlib libcrypto libxml-2.0)"\
      CPPFLAGS="$(pkg-config --cflags-only-I readline zlib libcrypto libxml-2.0)"\
      bash --norc ''${run_args:+-c} ''${run_args:+"$run_args"}

      #${if stdenv.hostPlatform.isDarwin then "AR=/usr/bin/ar" else ""}                \

      #pkg-config --cflags-only-I  $(pkg-config --list-all | cut -d ' ' -f 1)
      #LDFLAGS="${         builtins.concatStringsSep ""  (map (x: " -L" + x + "/lib"     ) libPackages)}" \
      #CPPFLAGS="${        builtins.concatStringsSep ""  (map (x: " -I" + x + "/include" ) libPackages)}" \
      #LD_LIBRARY_PATH="${ builtins.concatStringsSep ":" (map (x:         x + "/lib"     ) libPackages)}" \

      out="$out"                                                                      \
      #${if stdenv.hostPlatform.isDarwin then "AS=/usr/bin/as" else ""}  \
      #${if stdenv.hostPlatform.isDarwin then "RANLIB=/usr/bin/ranlib" else ""}             \
      #PKG_CONFIG_PATH_FOR_TARGET="$PKG_CONFIG_PATH_FOR_TARGET"\
      #PKG_CONFIG_PATH_x86_64_apple_darwin="$PKG_CONFIG_PATH_x86_64_apple_darwin"\
      #NIX_PKG_CONFIG_WRAPPER_TARGET_TARGET_x86_64_apple_darwin="$NIX_PKG_CONFIG_WRAPPER_TARGET_TARGET_x86_64_apple_darwin"\
      #PKG_CONFIG_FOR_TARGET="$PKG_CONFIG_FOR_TARGET"\
      #NIX_PKG_CONFIG_WRAPPER_FLAGS_SET_x86_64_apple_darwin="$NIX_PKG_CONFIG_WRAPPER_FLAGS_SET_x86_64_apple_darwin"\
  '';
}

