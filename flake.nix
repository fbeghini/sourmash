{

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "utils";
      };
    };
  };

  outputs = { self, nixpkgs, rust-overlay, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        rustVersion = pkgs.rust-bin.stable.latest.default.override {
          #extensions = [ "rust-src" ];
          #targets = [ "x86_64-unknown-linux-musl" ];
          targets = [ "wasm32-wasi" "wasm32-unknown-unknown" "wasm32-unknown-emscripten" ];
        };
        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustVersion;
          rustc = rustVersion;
        };

        python = pkgs.python310Packages;

      in

      with pkgs;
      {
        packages = {

          lib = rustPlatform.buildRustPackage {
            name = "libsourmash";
            pname = "libsourmash";
            src = lib.cleanSource ./.;
            copyLibs = true;
            cargoLock.lockFile = ./Cargo.lock;
            nativeBuildInputs = with rustPlatform; [ bindgenHook ];
          };

          sourmash = python.buildPythonPackage rec {
            pname = "sourmash";
            version = "4.8.2";
            format = "pyproject";

            src = ./.;

            cargoDeps = rustPlatform.importCargoLock {
              lockFile = ./Cargo.lock;
            };

            nativeBuildInputs = with rustPlatform; [ cargoSetupHook maturinBuildHook bindgenHook ];

            buildInputs = lib.optionals stdenv.isDarwin [ libiconv ];
            propagatedBuildInputs = with python; [ cffi deprecation cachetools bitstring numpy scipy matplotlib screed ];

            DYLD_LIBRARY_PATH = "${self.packages.${system}.lib}/lib";
          };

          docker =
            let
              bin = self.defaultPackage.${system};
            in
            pkgs.dockerTools.buildLayeredImage {
              name = bin.pname;
              tag = bin.version;
              contents = [ bin ];

              config = {
                Cmd = [ "/bin/sourmash" ];
                WorkingDir = "/";
              };
            };
        };

        defaultPackage = self.packages.${system}.sourmash;

        devShell = mkShell {
          nativeBuildInputs = [ rustPlatform.bindgenHook ];

          buildInputs = [
            rustPlatform.rust.cargo
            openssl
            pkgconfig

            git
            stdenv.cc.cc.lib
            (python310.withPackages (ps: with ps; [ virtualenv tox cffi ]))
            (python311.withPackages (ps: with ps; [ virtualenv ]))
            (python39.withPackages (ps: with ps; [ virtualenv ]))
            (python38.withPackages (ps: with ps; [ virtualenv ]))

            rust-cbindgen
            maturin

            wasmtime
            wasm-pack
            nodejs-18_x

            #py-spy
            heaptrack
            cargo-watch
            cargo-limit
            cargo-outdated
            cargo-udeps
            nixpkgs-fmt
            cargo-deny
          ];

          # Needed for matplotlib
          LD_LIBRARY_PATH = "${stdenv.cc.cc.lib}/lib64:$LD_LIBRARY_PATH";

          # workaround for https://github.com/NixOS/nixpkgs/blob/48dfc9fa97d762bce28cc8372a2dd3805d14c633/doc/languages-frameworks/python.section.md#python-setuppy-bdist_wheel-cannot-create-whl
          SOURCE_DATE_EPOCH = 315532800; # 1980
        };
      });
}
