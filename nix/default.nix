{
  pkgs ? import ./nixpkgs.nix,
  sources ? import ../npins,
}:
let
  # Upstream source, pinned by npins. Update with `npins update`.
  upstreamSrc = sources.capi-janitor-openstack-go;

  # Build the manager binary for a given package set (native or cross).
  buildManager =
    p:
    p.buildGoModule {
      pname = "capi-janitor-openstack-go";
      version = "0.0.0-dev";
      src = upstreamSrc;
      subPackages = [ "cmd" ];
      env.CGO_ENABLED = "0";
      ldflags = [
        "-s"
        "-w"
      ];
      # Run `nix-build nix -A manager` once; it will fail and print the real hash.
      vendorHash = "sha256-QEmjekl3AfSdVLkVVal7CyL7R2lxtN0SNXoUqI1Q+v4=";
      postInstall = ''
        mv $out/bin/cmd $out/bin/manager
      '';
      meta.mainProgram = "manager";
    };

  # Build a layered OCI image for a given package set.
  buildImage =
    p: m:
    p.dockerTools.buildLayeredImage {
      name = "zot.rpcu.io/public/capi-janitor-openstack-go";
      tag = "latest";
      contents = [
        pkgs.cacert
        m
      ];
      config = {
        Entrypoint = [ "/bin/manager" ];
        ExposedPorts."8081/tcp" = { };
        User = "65532:65532";
        Labels = {
          "org.opencontainers.image.source" = "https://github.com/azimuth-cloud/capi-janitor-openstack-go";
          "org.opencontainers.image.licenses" = "Apache-2.0";
        };
      };
    };

  manager = buildManager pkgs;
  image = buildImage pkgs manager;

  # arm64 cross-compiled on an amd64 host.
  crossPkgs = pkgs.pkgsCross.aarch64-multiplatform;
  manager-arm64 = buildManager crossPkgs;
  image-arm64 = buildImage crossPkgs manager-arm64;

  # SBOM — reads Go build-info embedded in the static binary (survives -s -w).
  sbom =
    pkgs.runCommand "sbom.cdx.json"
      {
        nativeBuildInputs = [ pkgs.syft ];
      }
      ''
        export HOME=$TMPDIR
        syft scan ${manager}/bin/manager \
          --output cyclonedx-json=$out \
          --quiet
      '';
in
{
  inherit
    manager
    image
    image-arm64
    sbom
    ;
}
