{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      treefmt = {
        # '.git/config' is not there in a git worktree or a jj workspace, where
        # treefmt would then format the enclosing repository instead.
        projectRootFile = ".treefmt.toml";
        settings.allow-missing-formatter = true;
        programs = {
          nixfmt.enable = true;
          yamlfmt.enable = true;
          taplo.enable = true;
          prettier = {
            enable = true;
            # YAML is yamlfmt's.
            includes = [ "*.md" ];
          };
          just.enable = true;
          # Indentation and the like from .editorconfig.
          shfmt = {
            enable = true;
            useEditorConfig = true;
          };
          ruff-format = {
            enable = true;
            lineLength = 120;
          };
          clang-format.enable = true;
          cmake-format.enable = true;
        };
      };

      # treefmt without Nix reads .treefmt.toml: the configuration above, with the
      # formatters looked up on PATH.
      apps.write-treefmt-toml = {
        type = "app";
        program = toString (
          pkgs.writeShellScript "write-treefmt-toml" ''
            set -euo pipefail
            root="$(${lib.getExe pkgs.git} rev-parse --show-toplevel)"
            {
              echo "# GENERATED FILE. DO NOT EDIT."
              echo "# Source of truth is the \`treefmt\` option in nix/treefmt.nix. Regenerate with: nix run .#write-treefmt-toml"
              echo
              ${lib.getExe pkgs.gnused} -E 's|/nix/store/[^/"[:space:]]+/bin/||g' ${config.treefmt.build.configFile}
            } > "$root/.treefmt.toml"
            ${lib.getExe config.treefmt.build.wrapper} --working-dir "$root" "$root/.treefmt.toml"
            echo "Wrote $root/.treefmt.toml"
          ''
        );
      };
    };
}
