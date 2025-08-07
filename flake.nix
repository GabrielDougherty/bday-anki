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
          ] ++ pkgs.lib.optionals isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Foundation
            pkgs.darwin.apple_sdk.frameworks.Cocoa
            pkgs.darwin.apple_sdk.frameworks.AppKit
          ];

          # Set environment variables to help Zig find system libraries
          shellHook = pkgs.lib.optionalString isDarwin ''
            export MACOSX_DEPLOYMENT_TARGET=11.0
            export CPATH="${pkgs.darwin.apple_sdk.frameworks.Foundation}/Library/Frameworks/Foundation.framework/Headers:${pkgs.darwin.apple_sdk.frameworks.Cocoa}/Library/Frameworks/Cocoa.framework/Headers:$CPATH"
            export LIBRARY_PATH="${pkgs.darwin.apple_sdk.frameworks.Foundation}/Library/Frameworks:${pkgs.darwin.apple_sdk.frameworks.Cocoa}/Library/Frameworks:$LIBRARY_PATH"
          '' + ''
            echo "Zig development environment loaded"
            echo "Zig version: $(zig version)"
            echo "macOS frameworks available for GUI development"
          '';
        };
      });
}
