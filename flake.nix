{
  description = "Build a cargo project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    crane.url = "github:ipetkov/crane";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, rust-overlay, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        version = "kani-0.56.0";

        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit overlays system; };

        inherit (pkgs) lib;

        rustToolchainFor = p: p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchainFor;
        rustToolchain = rustToolchainFor pkgs;

        src = craneLib.cleanCargoSource ./.;
        tgz = pkgs.fetchurl {
          url = "https://github.com/model-checking/kani/releases/download/${version}/${version}-x86_64-unknown-linux-gnu.tar.gz";
          sha256 = "0n4z3d8lzkpgf6qpq2y5n5aqihla9q2k2fmfgdfhmvr2w6if4pwk";
        };

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;

          buildInputs = with pkgs; [
            cbmc
            kissat
            rustToolchain
          ];

          strictDeps = true;

          # Additional environment variables can be set directly
          RUSTUP_HOME = "${rustToolchain}";
          RUSTUP_TOOLCHAIN = "..";
        };

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        kani = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;

          nativeBuildInputs = with pkgs; [
            autoPatchelfHook
            makeWrapper
            gnutar
            gzip
          ];

          postInstall = ''
            mkdir -p $out/lib
            tar -C $out/lib -xzf ${tgz}
            rm -f $out/lib/${version}/bin/{kani-compiler,kani-driver}
            ln -s $out/bin/{kani-compiler,kani-driver} $out/lib/${version}/bin/
            ln -s ${rustToolchain} $out/lib/${version}/toolchain
          '';

          postFixup = ''
            wrapProgram $out/bin/cargo-kani --set KANI_HOME $out/lib
            wrapProgram $out/bin/kani --set KANI_HOME $out/lib
          '';
        });
      in
      {
        packages.default = kani;

        apps.default = flake-utils.lib.mkApp {
          drv = kani;
        };

        devShells.default = craneLib.devShell {
          packages = [
            rustToolchain
          ];
        };
      });
}
