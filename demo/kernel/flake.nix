{
  description = "Build env for the UNO Q kernel (matches qcom-deb-images' build-linux-deb.py deps)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      cross = pkgs.pkgsCross.aarch64-multiplatform;
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        # build-linux-deb.py hardcodes CROSS_COMPILE=aarch64-linux-gnu- but
        # nixpkgs' cross stdenv prefixes binaries aarch64-unknown-linux-gnu-;
        # symlink so the expected prefix resolves.
        shellHook = ''
          export CROSS_BIN_DIR=$(mktemp -d)
          for f in ${cross.stdenv.cc}/bin/aarch64-unknown-linux-gnu-*; do
            ln -sf "$f" "$CROSS_BIN_DIR/aarch64-linux-gnu-''${f##*aarch64-unknown-linux-gnu-}"
          done
          export PATH=$CROSS_BIN_DIR:$PATH
        '';
        buildInputs = [
          cross.stdenv.cc
          pkgs.git
          pkgs.gnumake
          pkgs.flex
          pkgs.bison
          pkgs.bc
          pkgs.elfutils
          pkgs.openssl
          pkgs.kmod
          pkgs.dpkg
          pkgs.python3
          pkgs.dtc
          pkgs.rsync
          pkgs.coreutils
          pkgs.cpio
        ];
      };
    };
}
