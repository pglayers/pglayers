#!/usr/bin/env bash
#
# Integration test: validate pglayers isolated images work with
# CloudNativePG operator using the direct extension definition method.
#
# Requirements:
#   - Docker
#   - k3d (https://k3d.io)
#   - kubectl
#
# Usage:
#   ./tests/test-cnpg.sh [REGISTRY] [PG_MAJOR]
#
# The test:
#   1. Creates a k3d cluster with k3s 1.33+ (ImageVolume)
#   2. Installs CloudNativePG operator
#   3. Imports pglayers extension images into the cluster
#   4. Creates a CNPG Cluster with extensions defined directly
#   5. Waits for the cluster to be ready
#   6. Runs CREATE EXTENSION and functional tests
#   7. Tears down everything

set -euo pipefail

REGISTRY="${1:-local}"
PG="${2:-18}"
PREFIX="pgx"
CLUSTER_NAME="pglayers-cnpg-test"
K3S_IMAGE="rancher/k3s:v1.33.13-k3s1"
CNPG_VERSION="1.30.0"
PG_CLUSTER_NAME="pg-ext-test"
NAMESPACE="default"

# Extensions to test
TEST_EXTENSIONS=(pgvector pg_cron postgis)

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
else
    RED=''; GREEN=''; NC=''
fi

PASS=0
FAIL=0

pass() { ((PASS++)) || true; printf '%b%s%b\n' "${GREEN}PASS " "$1" "${NC}"; }
fail() { ((FAIL++)) || true; printf '%b%s%b\n' "${RED}FAIL " "$1" "${NC}"; }
info() { printf '%s %s\n' "----" "$1"; }

cleanup() {
    info "Cleaning up..."
    k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================
# Preflight checks
# ============================================================
info "Preflight checks..."

command -v k3d >/dev/null 2>&1 || { echo "Error: k3d not found. Install from https://k3d.io"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Error: docker not found."; exit 1; }

if [ "$PG" -lt 18 ] 2>/dev/null; then
    echo "Error: CNPG ImageVolume test requires PG >= 18"
    exit 1
fi

# Check extension images exist
for ext in "${TEST_EXTENSIONS[@]}"; do
    if ! docker image inspect "${REGISTRY}/${PREFIX}-${ext}:${PG}" >/dev/null 2>&1; then
        echo "Error: image ${REGISTRY}/${PREFIX}-${ext}:${PG} not found."
        echo "Build it first: make build EXT=${ext} PG=${PG} REGISTRY=${REGISTRY}"
        exit 1
    fi
done
pass "All extension images available locally"

# ============================================================
# Create k3d cluster
# ============================================================
info "Creating k3d cluster '${CLUSTER_NAME}' (k3s 1.33, ImageVolume)..."

k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true

k3d cluster create "$CLUSTER_NAME" \
    --image "$K3S_IMAGE" \
    --wait \
    --timeout 120s \
    --k3s-arg "--kube-apiserver-arg=feature-gates=ImageVolume=true@server:0" \
    --k3s-arg "--kube-controller-manager-arg=feature-gates=ImageVolume=true@server:0" \
    --k3s-arg "--kubelet-arg=feature-gates=ImageVolume=true@server:0" \
    2>&1 | sed 's/^/       /'

kubectl wait --for=condition=Ready node --all --timeout=60s >/dev/null 2>&1
pass "k3d cluster created ($(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'))"

# ============================================================
# Install CloudNativePG operator
# ============================================================
info "Installing CloudNativePG operator v${CNPG_VERSION}..."

kubectl apply --server-side \
    -f "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v${CNPG_VERSION}/cnpg-${CNPG_VERSION}.yaml" \
    >/dev/null 2>&1

# Wait for operator to be ready
kubectl -n cnpg-system wait --for=condition=Available deployment/cnpg-controller-manager --timeout=120s >/dev/null 2>&1
pass "CNPG operator v${CNPG_VERSION} running"

# ============================================================
# Import images into cluster
# ============================================================
info "Importing images into cluster..."

# Import extension images
for ext in "${TEST_EXTENSIONS[@]}"; do
    k3d image import "${REGISTRY}/${PREFIX}-${ext}:${PG}" -c "$CLUSTER_NAME" 2>/dev/null
done

# CNPG operand image must match our extension build distro (Trixie/glibc 2.38+)
CNPG_PG_IMAGE="ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie"
docker pull "$CNPG_PG_IMAGE" >/dev/null 2>&1 || true
k3d image import "$CNPG_PG_IMAGE" -c "$CLUSTER_NAME" 2>/dev/null

pass "Images imported: CNPG PG 18 + ${TEST_EXTENSIONS[*]}"

# ============================================================
# Create CNPG Cluster with extensions
# ============================================================
info "Creating CNPG Cluster with pglayers extensions..."

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${PG_CLUSTER_NAME}
  namespace: ${NAMESPACE}
spec:
  instances: 1
  imageName: ${CNPG_PG_IMAGE}

  postgresql:
    shared_preload_libraries:
      - pg_cron
    extensions:
      - name: pgvector
        image:
          reference: docker.io/${REGISTRY}/${PREFIX}-pgvector:${PG}
          pullPolicy: Never
      - name: pg-cron
        image:
          reference: docker.io/${REGISTRY}/${PREFIX}-pg_cron:${PG}
          pullPolicy: Never
      - name: postgis
        image:
          reference: docker.io/${REGISTRY}/${PREFIX}-postgis:${PG}
          pullPolicy: Never
        ld_library_path:
          - lib

  storage:
    size: 1Gi

  bootstrap:
    initdb:
      database: app
      owner: app
EOF

# Wait for cluster to be ready
info "Waiting for CNPG cluster to become ready (this may take a few minutes)..."
cluster_ready=false
for _ in $(seq 1 300); do
    phase="$(kubectl get cluster "$PG_CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")"
    if [ "$phase" = "Cluster in healthy state" ]; then
        cluster_ready=true
        break
    fi
    # Also check for errors
    if [ "$phase" = "Setting up primary" ] || [ "$phase" = "Creating primary" ] || \
       [ "$phase" = "First primary" ] || [ -z "$phase" ]; then
        sleep 2
        continue
    fi
    sleep 2
done

if [ "$cluster_ready" = false ]; then
    fail "CNPG cluster did not become healthy within 10 minutes"
    echo "       Phase: $(kubectl get cluster "$PG_CLUSTER_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)"
    echo "       Conditions:"
    kubectl get cluster "$PG_CLUSTER_NAME" -o jsonpath='{.status.conditions}' 2>/dev/null | python3 -m json.tool 2>/dev/null || true
    echo "       Pod status:"
    kubectl get pods -l cnpg.io/cluster="$PG_CLUSTER_NAME" -o wide 2>/dev/null
    echo "       Pod logs (last 20 lines):"
    kubectl logs -l cnpg.io/cluster="$PG_CLUSTER_NAME" --tail=20 2>/dev/null || true
    exit 1
fi
pass "CNPG cluster '${PG_CLUSTER_NAME}' is healthy"

# ============================================================
# Validate extensions are mounted and discoverable
# ============================================================
info "Validating extension configuration..."

# Get the primary pod name
PRIMARY_POD="$(kubectl get pods -l cnpg.io/cluster="$PG_CLUSTER_NAME",role=primary -o jsonpath='{.items[0].metadata.name}')"

# Check extension_control_path
ecp="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc "SHOW extension_control_path;" 2>&1)"
if echo "$ecp" | grep -q '/extensions/pgvector/share'; then
    pass "extension_control_path includes pglayers extensions"
else
    fail "extension_control_path missing pglayers paths: ${ecp}"
fi

# Check dynamic_library_path
dlp="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc "SHOW dynamic_library_path;" 2>&1)"
if echo "$dlp" | grep -q '/extensions/pgvector/lib'; then
    pass "dynamic_library_path includes pglayers extensions"
else
    fail "dynamic_library_path missing pglayers paths: ${dlp}"
fi

# Verify extensions are discoverable
for ext_name in vector pg_cron postgis; do
    result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
        "SELECT name FROM pg_available_extensions WHERE name = '${ext_name}';" 2>&1)"
    if echo "$result" | grep -q "${ext_name}"; then
        pass "Extension '${ext_name}' discoverable"
    else
        fail "Extension '${ext_name}' not found"
    fi
done

# ============================================================
# CREATE EXTENSION tests
# ============================================================
info "Testing CREATE EXTENSION..."

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "CREATE EXTENSION vector; SELECT extname FROM pg_extension WHERE extname='vector';" 2>&1)"
if echo "$result" | grep -q "vector"; then
    pass "CREATE EXTENSION vector"
else
    fail "CREATE EXTENSION vector: ${result}"
fi

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "CREATE EXTENSION pg_cron; SELECT extname FROM pg_extension WHERE extname='pg_cron';" 2>&1)"
if echo "$result" | grep -q "pg_cron"; then
    pass "CREATE EXTENSION pg_cron"
else
    fail "CREATE EXTENSION pg_cron: ${result}"
fi

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "CREATE EXTENSION postgis; SELECT extname FROM pg_extension WHERE extname='postgis';" 2>&1)"
if echo "$result" | grep -q "postgis"; then
    pass "CREATE EXTENSION postgis"
else
    fail "CREATE EXTENSION postgis: ${result}"
fi

# ============================================================
# Functional smoke tests
# ============================================================
info "Running functional smoke tests..."

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector;" 2>&1)"
if [ -n "$result" ] && echo "$result" | grep -qE '^[0-9]'; then
    pass "pgvector: vector distance = ${result}"
else
    fail "pgvector similarity: ${result}"
fi

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "SELECT ST_AsText(ST_Point(1, 2));" 2>&1)"
if echo "$result" | grep -q "POINT"; then
    pass "PostGIS: ST_Point = ${result}"
else
    fail "PostGIS geometry: ${result}"
fi

result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "SELECT cron.schedule('test', '* * * * *', 'SELECT 1');" 2>&1)"
if [ -n "$result" ]; then
    pass "pg_cron: job scheduled (id=${result})"
else
    fail "pg_cron schedule: ${result}"
fi

# Contrib still works
result="$(kubectl exec "$PRIMARY_POD" -- psql -U postgres -tAc \
    "CREATE EXTENSION hstore; SELECT 'a=>1'::hstore -> 'a';" 2>&1)"
if echo "$result" | grep -q "1"; then
    pass "contrib (hstore): \$system fallback works"
else
    fail "contrib hstore: ${result}"
fi

# ============================================================
# Results
# ============================================================
echo
echo "========================================"
printf 'Results: %b%d passed%b, %b%d failed%b\n' "${GREEN}" "$PASS" "${NC}" "${RED}" "$FAIL" "${NC}"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
