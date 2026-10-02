{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Thin wrapper: runs a `just` recipe inside this flake's own devShell, so
      # `nix run .#<recipe>` gets exactly the toolchain `nix develop` would give you,
      # without duplicating any build/setup logic here (the justfile stays canonical).
      justApp =
        recipe:
        let
          script = pkgs.writeShellApplication {
            name = recipe;
            runtimeInputs = [ pkgs.nix ];
            text = ''
              exec nix develop --command just ${recipe} "$@"
            '';
          };
        in
        {
          type = "app";
          program = "${script}/bin/${recipe}";
        };
    in
    {
      apps = {
        build = justApp "build";
        setup-python = justApp "setup-python";
        smoke-test = justApp "smoke-test";
        clean = justApp "clean";
        default = justApp "build";

        # Generic escape hatch: `nix run .#just -- <recipe> [args...]`.
        just = {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "just";
              runtimeInputs = [ pkgs.nix ];
              text = ''
                exec nix develop --command just "$@"
              '';
            }
          }/bin/just";
        };
      };
    };
}
