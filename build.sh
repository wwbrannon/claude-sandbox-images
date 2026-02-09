#!/bin/bash
# Build script for Claude Code Sandbox images
# Builds base image first, then all variants with proper tagging

set -euo pipefail

# Configuration
VERSION="${1:-v1.0}"
REGISTRY="${REGISTRY:-}"  # Set REGISTRY env var to push to a registry
PARALLEL_BUILDS="${PARALLEL_BUILDS:-4}"  # Number of parallel builds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Function to build a single image
build_image() {
    local variant="$1"
    local dockerfile="Dockerfile.${variant}"
    local image_name="claude-sandbox-${variant}"

    log_info "Building ${image_name}:${VERSION}..."

    if docker build -f "${dockerfile}" -t "${image_name}:${VERSION}" -t "${image_name}:latest" .; then
        log_success "Built ${image_name}:${VERSION}"

        # Get image size
        local size
        size=$(docker images "${image_name}:${VERSION}" --format "{{.Size}}")
        log_info "Image size: ${size}"

        # Tag for registry if specified
        if [ -n "${REGISTRY}" ]; then
            docker tag "${image_name}:${VERSION}" "${REGISTRY}/${image_name}:${VERSION}"
            docker tag "${image_name}:latest" "${REGISTRY}/${image_name}:latest"
            log_info "Tagged for registry: ${REGISTRY}/${image_name}"
        fi

        return 0
    else
        log_error "Failed to build ${image_name}"
        return 1
    fi
}

# Print banner
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Claude Code Sandbox Image Builder                 ║"
echo "║         Version: ${VERSION}                                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Build base image first (all others depend on it)
log_info "Step 1: Building base image..."
if ! build_image "base"; then
    log_error "Base image build failed. Cannot continue."
    exit 1
fi
echo ""

# Build variants
log_info "Step 2: Building specialized variants..."
variants=(
    "minimal"
    "python"
    "r"
    "python-aws"
    "python-gcp"
    "python-azure"
    "r-aws"
    "full"
)

failed_builds=()

# Build in parallel if possible
if command -v parallel &> /dev/null; then
    log_info "Building ${#variants[@]} variants in parallel (max ${PARALLEL_BUILDS} concurrent)..."

    export -f build_image log_info log_success log_error
    export VERSION REGISTRY RED GREEN YELLOW BLUE NC

    if ! printf "%s\n" "${variants[@]}" | parallel -j "${PARALLEL_BUILDS}" build_image; then
        log_warning "Some builds failed when running in parallel"
    fi
else
    log_warning "GNU parallel not found. Building sequentially..."
    for variant in "${variants[@]}"; do
        if ! build_image "${variant}"; then
            failed_builds+=("${variant}")
        fi
        echo ""
    done
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Build Summary                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

log_info "Listing all built images:"
docker images | grep "claude-sandbox" | grep -E "(${VERSION}|latest)"

echo ""

if [ ${#failed_builds[@]} -eq 0 ]; then
    log_success "All images built successfully!"
else
    log_error "Failed builds: ${failed_builds[*]}"
    exit 1
fi

# Push to registry if specified
if [ -n "${REGISTRY}" ]; then
    echo ""
    log_info "Push to registry with: docker push ${REGISTRY}/claude-sandbox-<variant>:${VERSION}"
    log_info "Or push all with: docker images | grep '${REGISTRY}/claude-sandbox' | awk '{print \$1\":\"\$2}' | xargs -n1 docker push"
fi

echo ""
log_success "Build complete!"
