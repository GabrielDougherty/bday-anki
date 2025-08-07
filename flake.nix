{
  description = "Development environment with Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        isDarwin = pkgs.stdenv.isDarwin;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            zls
          ];

          # Set environment variables for macOS development with impure system frameworks
          shellHook = pkgs.lib.optionalString isDarwin ''
            export MACOSX_DEPLOYMENT_TARGET=11.0
            export IN_NIX_SHELL=1
            
            # Allow access to system frameworks (impure)
            export NIX_ENFORCE_PURITY=0
            
            # Ensure system paths are available
            export LIBRARY_PATH="/usr/lib:/System/Library/Frameworks:$LIBRARY_PATH"
            export FRAMEWORK_PATH="/System/Library/Frameworks:/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks:$FRAMEWORK_PATH"
          '' + ''
            echo "Zig development environment loaded"
            echo "Zig version: $(zig version)"
            echo "Using host system macOS frameworks (impure build)"
          '';
        };
      });
}
