# shellcheck shell=bash
#
# Shared helper for the k3d integration tests (test-k8s.sh, test-cnpg.sh).
# Source it; do not execute it.
#
# k3d_import <cluster> <image>
#
# Imports a local Docker image into every node of a k3d cluster and verifies
# that the kubelet can actually see it.
#
# Why not plain `k3d image import <image>`:
#   With Docker's containerd image store (default since Docker 29, and on the
#   GitHub ubuntu-24.04 runners since image 20261028), `docker save` of a
#   pulled multi-arch image writes the WHOLE OCI index (amd64 + arm64 +
#   attestation manifests), but only the host platform's blobs exist locally.
#   `ctr image import` inside the k3s node then fails with
#   "content digest sha256:...: not found". k3d logs that as ERRO yet still
#   prints "Successfully imported" and exits 0, so pods using
#   `pullPolicy: Never` die with ErrImageNeverPull.
#
#   Saving only the host platform (`docker save --platform`) gives a
#   self-consistent tarball. On older Docker without `--platform` on save (or
#   the classic store, where images are single-platform anyway) we fall back to
#   a plain save.
k3d_import() {
    local cluster="$1" image="$2"
    local platform tmpdir tar import_output inspect_output cri_image registry

    # Docker's OCI export records canonical registry names. CRI inspecti does
    # not reliably expand shorthand names, even though pod image pulls do.
    cri_image="$image"
    registry="${image%%/*}"
    if [[ "$image" != */* ]]; then
        cri_image="docker.io/library/$image"
    elif [[ "$registry" != *.* && "$registry" != *:* && "$registry" != localhost ]]; then
        cri_image="docker.io/$image"
    fi

    platform="$(docker version -f '{{.Server.Os}}/{{.Server.Arch}}')"
    tmpdir="$(mktemp -d)"
    tar="${tmpdir}/image.tar"

    if ! docker save --platform "$platform" -o "$tar" "$image" 2>/dev/null; then
        docker save -o "$tar" "$image"
    fi

    if ! import_output="$(k3d image import "$tar" -c "$cluster" 2>&1)"; then
        printf '%s\n' "$import_output" >&2
        rm -rf "$tmpdir"
        return 1
    fi
    rm -rf "$tmpdir"

    # k3d exits 0 even when the in-node `ctr import` fails, so verify on every
    # node through the CRI, using the same canonical reference the kubelet uses.
    local node role ok=true
    while read -r node role; do
        case "$role" in server|agent) ;; *) continue ;; esac
        if ! inspect_output="$(docker exec "$node" crictl inspecti "$cri_image" 2>&1)"; then
            echo "Error: image ${image} is not present in node ${node} after k3d import" >&2
            printf '%s\n' "$inspect_output" "$import_output" >&2
            ok=false
        fi
    done < <(docker ps --filter "label=k3d.cluster=${cluster}" \
        --format '{{.Names}} {{.Label "k3d.role"}}')
    [ "$ok" = true ]
}
