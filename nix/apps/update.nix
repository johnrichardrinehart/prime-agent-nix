{ pkgs }:
pkgs.writeShellApplication {
  name = "prime-agent-update";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
    git
    gnugrep
    gnused
    jq
    nix
    nodejs
    npm-lockfile-fix
  ];
  runtimeEnv.PRIME_AGENT_NIXPKGS = pkgs.path;
  text = builtins.readFile ../../scripts/update.sh;
}
