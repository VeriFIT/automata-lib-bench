{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      devShells =
        let
          devShellEnv =
            {
              compiler ? "gcc",
            }:
            pkgs.mkShell.override
              {
                # Override stdenv in order to change compiler.
                stdenv =
                  if compiler == "clang" then
                    pkgs.clangStdenv
                  else if compiler == "gcc" then
                    pkgs.gccStdenv
                  else
                    throw "Invalid compiler value";
              }
              {
                name = "mata-${compiler}-dev";

                # uv-installed wheels (numpy, used by pycobench's compare_profiles)
                # link against libz at runtime.
                LD_LIBRARY_PATH = lib.makeLibraryPath [
                  pkgs.stdenv.cc.cc
                  pkgs.zlib
                ];

                inputsFrom =
                  with inputs.self.packages.${pkgs.stdenv.hostPlatform.system};
                  [
                  ]
                  ++ [
                    inputs.tools-mata.devShells.${pkgs.stdenv.hostPlatform.system}.${compiler}
                  ];

                packages = with inputs.self.packages.${pkgs.stdenv.hostPlatform.system}; [
                ];

                buildInputs =
                  with pkgs;
                  [
                    btop
                    just
                    uv
                    # uv cannot run its own downloaded CPython on NixOS, so the
                    # per-revision venvs are created from the interpreters here.
                    # pycobench needs >= 3.14; the mata bindings build on python3.
                    python3
                    python314
                    yazi
                    helix

                    # git
                    # coreutils
                    # gnumake
                    # pkgs.gcc

                    # pkgs.clang

                    # Formatting and linting.
                    # clang-tools
                    # cppcheck
                    nixd
                    nixfmt
                    yamlfmt
                    taplo
                    prettier
                    prettierd
                  ]
                  ++ (
                    if pkgs.stdenv.hostPlatform.system != inputs.flake-utils.lib.system.aarch64-darwin then
                      [
                        gdb
                      ]
                    else
                      [ ]
                  );
              };
          clang = devShellEnv { compiler = "clang"; };
          gcc = devShellEnv { compiler = "gcc"; };
        in
        {
          inherit gcc clang;
          default = gcc;
        };
    };
}
