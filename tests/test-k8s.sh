#!/usr/bin/env bash
#
# Integration test: validate pglayers isolated images work as Kubernetes
# ImageVolumes with the official postgres:18 image (no CNPG operator).
#
# Requirements:
#   - Docker
#   - k3d (https://k3d.io)
#   - kubectl
#
# Usage:
#   ./tests/test-k8s.sh [REGISTRY] [PG_MAJOR]
#
# The test:
#   1. Creates a k3d cluster with k3s 1.33+ (ImageVolume GA)
#   2. Imports pglayers extension images into the cluster
#   3. Deploys a Pod with postgres:18 + extensions as ImageVolumes
#   4. Configures extension_control_path via postgres args
#   5. Runs CREATE EXTENSION and functional tests
#   6. Tears down the cluster

set -euo pipefail

REGISTRY="${1:-local}"
PG="${2:-18}"
PREFIX="pgx"
CLUSTER_NAME="pglayers-test"
K3S_IMAGE="rancher/k3s:v1.33.13-k3s1"
NAMESPACE="default"
POD_NAME="pg-ext-test"

# Extensions to test (representative sample)
TEST_EXTENSIONS=(pgvector pg_cron postgis)

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
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
    echo "Error: ImageVolume test requires PG >= 18 (isolated layout)"
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
info "Creating k3d cluster '${CLUSTER_NAME}' (k3s 1.33, ImageVolume GA)..."

# Delete existing cluster if any
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true

k3d cluster create "$CLUSTER_NAME" \
    --image "$K3S_IMAGE" \
    --wait \
    --timeout 120s \
    --k3s-arg "--kube-apiserver-arg=feature-gates=ImageVolume=true@server:0" \
    --k3s-arg "--kube-controller-manager-arg=feature-gates=ImageVolume=true@server:0" \
    --k3s-arg "--kubelet-arg=feature-gates=ImageVolume=true@server:0" \
    2>&1 | sed 's/^/       /'

# Wait for cluster to be ready
kubectl wait --for=condition=Ready node --all --timeout=60s >/dev/null 2>&1
pass "k3d cluster created ($(kubectl version --short 2>/dev/null | grep Server | sed 's/.*: //' || kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}'))"

# ============================================================
# Import images into k3d cluster
# ============================================================
info "Importing images into cluster..."

# Import postgres base image
docker pull "postgres:${PG}" >/dev/null 2>&1 || true
k3d image import "postgres:${PG}" -c "$CLUSTER_NAME" 2>/dev/null

# Import extension images
for ext in "${TEST_EXTENSIONS[@]}"; do
    k3d image import "${REGISTRY}/${PREFIX}-${ext}:${PG}" -c "$CLUSTER_NAME" 2>/dev/null
done
pass "Images imported: postgres:${PG} + ${TEST_EXTENSIONS[*]}"

# ============================================================
# Deploy PostgreSQL pod with ImageVolume extensions
# ============================================================
info "Deploying PostgreSQL pod with ImageVolume extensions..."

# Build extension_control_path and dynamic_library_path
EXT_PATHS=""
LIB_PATHS=""
for ext in "${TEST_EXTENSIONS[@]}"; do
    EXT_PATHS="${EXT_PATHS}/extensions/${ext}/share:"
    LIB_PATHS="${LIB_PATHS}/extensions/${ext}/lib:"
done

# Build the LD_LIBRARY_PATH (for bundled runtime deps like PostGIS)
LD_LIB_PATH="${LIB_PATHS%:}"

# Generate Pod manifest
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
spec:
  volumes:
$(for ext in "${TEST_EXTENSIONS[@]}"; do
cat <<VOLEOF
    - name: ext-${ext//_/-}
      image:
        reference: docker.io/${REGISTRY}/${PREFIX}-${ext}:${PG}
        pullPolicy: Never
VOLEOF
done)
  containers:
    - name: postgres
      image: docker.io/library/postgres:${PG}
      imagePullPolicy: IfNotPresent
      env:
        - name: POSTGRES_PASSWORD
          value: "test"
        - name: POSTGRES_HOST_AUTH_METHOD
          value: "trust"
        - name: LD_LIBRARY_PATH
          value: "${LD_LIB_PATH}"
      args:
        - "postgres"
        - "-c"
        - "extension_control_path=${EXT_PATHS}\$\$system"
        - "-c"
        - "dynamic_library_path=${LIB_PATHS}\$\$libdir"
        - "-c"
        - "shared_preload_libraries=pg_cron"
      volumeMounts:
$(for ext in "${TEST_EXTENSIONS[@]}"; do
cat <<VMEOF
        - name: ext-${ext//_/-}
          mountPath: /extensions/${ext}
          readOnly: true
VMEOF
done)
      ports:
        - containerPort: 5432
  restartPolicy: Never
EOF

# Wait for pod to be running
info "Waiting for PostgreSQL to start..."
pod_ready=false
for _ in $(seq 1 120); do
    phase="$(kubectl get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")"
    if [ "$phase" = "Running" ]; then
        # Check if postgres is ready
        if kubectl exec "$POD_NAME" -- pg_isready -U postgres -h 127.0.0.1 >/dev/null 2>&1; then
            pod_ready=true
            break
        fi
    elif [ "$phase" = "Failed" ] || [ "$phase" = "Error" ]; then
        break
    fi
    sleep 1
done

if [ "$pod_ready" = false ]; then
    fail "PostgreSQL pod failed to start within 120s"
    echo "       Pod status:"
    kubectl describe pod "$POD_NAME" 2>&1 | tail -20 | sed 's/^/       /'
    echo "       Pod logs:"
    kubectl logs "$POD_NAME" 2>&1 | tail -20 | sed 's/^/       /'
    exit 1
fi
pass "PostgreSQL pod running with ImageVolume extensions"

# ============================================================
# Validate GUC configuration
# ============================================================
info "Validating extension_control_path configuration..."

ecp="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc "SHOW extension_control_path;" 2>&1)"
if echo "$ecp" | grep -q '/extensions/pgvector/share'; then
    pass "extension_control_path configured correctly"
else
    fail "extension_control_path not set: ${ecp}"
fi

dlp="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc "SHOW dynamic_library_path;" 2>&1)"
if echo "$dlp" | grep -q '/extensions/pgvector/lib'; then
    pass "dynamic_library_path configured correctly"
else
    fail "dynamic_library_path not set: ${dlp}"
fi

# ============================================================
# Verify extensions are discoverable
# ============================================================
info "Checking extension discoverability..."

for ext_name in vector pg_cron postgis; do
    result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
        "SELECT name FROM pg_available_extensions WHERE name = '${ext_name}';" 2>&1)"
    if echo "$result" | grep -q "${ext_name}"; then
        pass "Extension '${ext_name}' discoverable via extension_control_path"
    else
        fail "Extension '${ext_name}' not found in pg_available_extensions"
    fi
done

# ============================================================
# CREATE EXTENSION tests
# ============================================================
info "Testing CREATE EXTENSION..."

result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "CREATE EXTENSION vector; SELECT extname FROM pg_extension WHERE extname='vector';" 2>&1)"
if echo "$result" | grep -q "vector"; then
    pass "CREATE EXTENSION vector"
else
    fail "CREATE EXTENSION vector: ${result}"
fi

result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "CREATE EXTENSION pg_cron; SELECT extname FROM pg_extension WHERE extname='pg_cron';" 2>&1)"
if echo "$result" | grep -q "pg_cron"; then
    pass "CREATE EXTENSION pg_cron"
else
    fail "CREATE EXTENSION pg_cron: ${result}"
fi

result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
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

# pgvector: vector similarity search
result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "SELECT '[1,2,3]'::vector <-> '[4,5,6]'::vector;" 2>&1)"
if [ -n "$result" ] && echo "$result" | grep -qE '^[0-9]'; then
    pass "pgvector: vector distance = ${result}"
else
    fail "pgvector similarity: ${result}"
fi

# PostGIS: geometry operations
result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "SELECT ST_AsText(ST_Point(1, 2));" 2>&1)"
if echo "$result" | grep -q "POINT"; then
    pass "PostGIS: ST_Point = ${result}"
else
    fail "PostGIS geometry: ${result}"
fi

# pg_cron: schedule a job
result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "SELECT cron.schedule('test-job', '* * * * *', 'SELECT 1');" 2>&1)"
if [ -n "$result" ]; then
    pass "pg_cron: job scheduled (id=${result})"
else
    fail "pg_cron schedule: ${result}"
fi

# Verify contrib extensions still work ($system fallback)
result="$(kubectl exec "$POD_NAME" -- psql -U postgres -tAc \
    "CREATE EXTENSION hstore; SELECT 'a=>1'::hstore -> 'a';" 2>&1)"
if echo "$result" | grep -q "1"; then
    pass "contrib (hstore): \$system fallback works"
else
    fail "contrib hstore: ${result}"
fi

# ============================================================
# Verify volume mount structure
# ============================================================
info "Verifying ImageVolume mount structure..."

result="$(kubectl exec "$POD_NAME" -- ls /extensions/pgvector/lib/vector.so 2>&1)"
if echo "$result" | grep -q "vector.so"; then
    pass "ImageVolume mount: /extensions/pgvector/lib/vector.so exists"
else
    fail "ImageVolume mount: vector.so not found at expected path"
fi

result="$(kubectl exec "$POD_NAME" -- ls /extensions/pgvector/share/extension/vector.control 2>&1)"
if echo "$result" | grep -q "vector.control"; then
    pass "ImageVolume mount: /extensions/pgvector/share/extension/vector.control exists"
else
    fail "ImageVolume mount: vector.control not found at expected path"
fi

# ============================================================
# Results
# ============================================================
echo
echo "========================================"
printf "Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC}\n" "$PASS" "$FAIL"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
