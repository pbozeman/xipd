{
  description = "Python Dev Env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        # Python package with required dependencies
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
        ]);

        buildInputs = with pkgs; [
          pythonEnv
        ];
      in
      {
        devShell = pkgs.mkShell {
          inherit buildInputs;
        };
      }
    );
}
