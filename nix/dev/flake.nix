{
  description = "Private inputs for development purposes.
    These are used by the top level flake in the `dev` partition, but do not appear in consumers' lock files.";

  inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
    tools-mata = {
      url = "path:./subjects/mata";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # This flake is only used for its inputs.
  outputs = { ... }: { };
}
