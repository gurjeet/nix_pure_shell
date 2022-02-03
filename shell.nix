
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
  jobs ? 1, # By default disable parallel builds

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
  :<<EOF
    #set -x
    local func_names=$(declare -F | cut -d ' ' -f 1)
    local var_names=$( (set -o posix; set) | cut -d '=' -f 1 | grep -vE 'stdenv')
    for c in $func_names; do unset -f $c; done
    for c in $var_names; do unset -v $c; done
    export HOME="$(mktemp -d)"
    echo $stdenv
    echo $HOME
    #set -x
    #source "$stdenv"/setup
EOF

    PS1='nix> '
    echo exec env -i "stdenv=$stdenv" "out=$out" bash --norc --noprofile
  '';
}

