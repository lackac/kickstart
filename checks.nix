{ pkgs }:
pkgs.runCommand "kickstart-checks"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.jq
      pkgs.shellcheck
      pkgs.zsh
    ];
  }
  ''
    cp ${./kickstart.sh} kickstart.sh
    cp ${./test-kickstart.sh} test-kickstart.sh
    cp ${./_kickstart} _kickstart
    bash -n kickstart.sh
    bash -n ${./test-agentic.sh}
    zsh -n _kickstart
    shellcheck --shell bash kickstart.sh
    shellcheck --shell bash ${./test-agentic.sh}
    shellcheck --shell bash test-kickstart.sh
    bash test-kickstart.sh
    touch "$out"
  ''
