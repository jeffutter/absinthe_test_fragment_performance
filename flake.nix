{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      # self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      with pkgs;
      {
        devShells.default = mkShell {
          buildInputs = [
            beam.packages.erlang_27.elixir_1_17
            # beam.packages.erlang_26.elixir_1_17
          ];
        };

        formatter = nixpkgs-fmt;
      }
    );
}
