#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Docker
check_docker() {
    print_status "Checking Docker..."

    if ! command_exists docker; then
        print_error "Docker is not installed"
        print_error "Please install Docker from: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        print_error "Please start Docker and try again"
        exit 1
    fi

    print_success "Docker is running"
}

# Function to check kind
check_kind() {
    print_status "Checking kind..."

    if ! command_exists kind; then
        print_status "kind is not installed. Installing kind..."

        # Detect OS and architecture
        local os
        local arch
        os=$(uname -s | tr '[:upper:]' '[:lower:]')
        arch=$(uname -m)

        case $arch in
            x86_64)
                arch="amd64"
                ;;
            aarch64)
                arch="arm64"
                ;;
            *)
                print_error "Unsupported architecture: $arch"
                exit 1
                ;;
        esac

        # Download and install kind
        local kind_version="v0.20.0"
        local kind_url="https://kind.sigs.k8s.io/dl/${kind_version}/kind-${os}-${arch}"

        print_status "Downloading kind from: $kind_url"
        if command -v curl >/dev/null 2>&1; then
            curl -Lo ./kind "$kind_url"
        elif command -v wget >/dev/null 2>&1; then
            wget -O ./kind "$kind_url"
        else
            print_error "Neither curl nor wget is available"
            exit 1
        fi

        chmod +x ./kind
        sudo mv ./kind /usr/local/bin/kind

        print_success "kind installed successfully"
    else
        print_success "kind is already installed"
    fi

    # Verify kind version
    kind --version
}

# Function to check kubectl
check_kubectl() {
    print_status "Checking kubectl..."

    if ! command_exists kubectl; then
        print_status "kubectl is not installed. Installing kubectl..."

        # Detect OS and architecture
        local os
        local arch
        os=$(uname -s | tr '[:upper:]' '[:lower:]')
        arch=$(uname -m)

        case $arch in
            x86_64)
                arch="amd64"
                ;;
            aarch64)
                arch="arm64"
                ;;
            *)
                print_error "Unsupported architecture: $arch"
                exit 1
                ;;
        esac

        # Download kubectl
        local kubectl_version
        kubectl_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        local kubectl_url="https://dl.k8s.io/release/${kubectl_version}/bin/${os}/${arch}/kubectl"

        print_status "Downloading kubectl from: $kubectl_url"
        if command -v curl >/dev/null 2>&1; then
            curl -LO "$kubectl_url"
        elif command -v wget >/dev/null 2>&1; then
            wget "$kubectl_url"
        else
            print_error "Neither curl nor wget is available"
            exit 1
        fi

        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/kubectl

        print_success "kubectl installed successfully"
    else
        print_success "kubectl is already installed"
    fi

    # Verify kubectl version
    kubectl version --client --short
}

# Function to create kind cluster
create_cluster() {
    local cluster_name="backstage-gitops"
    local config_file="infra/kind/kind-config.yaml"

    print_status "Creating kind cluster '$cluster_name'..."

    # Check if cluster already exists
    if kind get clusters | grep -q "^${cluster_name}$"; then
        print_warning "Cluster '$cluster_name' already exists"
        read -p "Do you want to delete the existing cluster and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting existing cluster..."
            kind delete cluster --name "$cluster_name"
        else
            print_status "Using existing cluster"
            return 0
        fi
    fi

    # Check if config file exists
    if [ ! -f "$config_file" ]; then
        print_error "Config file '$config_file' not found"
        print_error "Please ensure you're in the project root directory"
        exit 1
    fi

    # Create cluster
    if kind create cluster --config "$config_file" --name "$cluster_name"; then
        print_success "Cluster '$cluster_name' created successfully"
    else
        print_error "Failed to create cluster '$cluster_name'"
        exit 1
    fi

    # Verify cluster
    print_status "Verifying cluster..."
    kubectl cluster-info --context "kind-$cluster_name"

    # Wait for nodes to be ready
    print_status "Waiting for nodes to be ready..."
    kubectl wait --for=condition=ready node --all --timeout=300s

    print_success "Cluster is ready!"
}

# Function to verify cluster
verify_cluster() {
    local cluster_name="backstage-gitops"

    print_status "Verifying cluster '$cluster_name'..."

    # Check cluster exists
    if ! kind get clusters | grep -q "^${cluster_name}$"; then
        print_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    # Check kubectl context
    local current_context
    current_context=$(kubectl config current-context)
    if [ "$current_context" != "kind-$cluster_name" ]; then
        print_warning "Current kubectl context is '$current_context'"
        print_status "Switching to 'kind-$cluster_name' context..."
        kubectl config use-context "kind-$cluster_name"
    fi

    # Check nodes
    print_status "Cluster nodes:"
    kubectl get nodes

    # Check cluster status
    print_status "Cluster status:"
    kubectl get componentstatuses 2>/dev/null || kubectl get cs 2>/dev/null || echo "Component statuses not available (expected in newer k8s versions)"

    print_success "Cluster verification completed"
}

# Function to show usage information
show_usage() {
    echo
    print_status "Kind Cluster Setup Script"
    print_status "========================"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -n, --name NAME     Cluster name (default: backstage-gitops)"
    echo "  -c, --config FILE   Config file path (default: infra/kind/kind-config.yaml)"
    echo "  -d, --delete        Delete existing cluster if it exists"
    echo "  -v, --verify        Only verify existing cluster"
    echo
    echo "Examples:"
    echo "  $0                    # Create default cluster"
    echo "  $0 --delete          # Delete and recreate cluster"
    echo "  $0 --verify          # Only verify existing cluster"
    echo "  $0 --name my-cluster # Create cluster with custom name"
}

# Main function
main() {
    local cluster_name="backstage-gitops"
    local config_file="infra/kind/kind-config.yaml"
    local delete_existing=false
    local verify_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -n|--name)
                cluster_name="$2"
                shift 2
                ;;
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -d|--delete)
                delete_existing=true
                shift
                ;;
            -v|--verify)
                verify_only=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    echo
    print_status "🚀 Kind Cluster Setup Script"
    print_status "==========================="
    echo

    # Check prerequisites
    check_docker
    check_kind
    check_kubectl

    if [ "$verify_only" = true ]; then
        verify_cluster
        exit 0
    fi

    # Handle existing cluster
    if [ "$delete_existing" = true ] && kind get clusters | grep -q "^${cluster_name}$"; then
        print_status "Deleting existing cluster '$cluster_name'..."
        kind delete cluster --name "$cluster_name"
    fi

    # Create cluster
    create_cluster

    # Verify cluster
    verify_cluster

    echo
    print_success "🎉 Kind cluster setup completed successfully!"
    echo
    print_status "Next steps:"
    echo "  1. Run './bootstrap.sh' to deploy ArgoCD and Backstage"
    echo "  2. Access Kubernetes dashboard: kubectl proxy"
    echo "  3. Use 'kubectl get nodes' to see cluster nodes"
    echo
    print_status "Useful commands:"
    echo "  # Switch to cluster context"
    echo "  kubectl config use-context kind-$cluster_name"
    echo
    echo "  # Get cluster info"
    echo "  kubectl cluster-info"
    echo
    echo "  # Delete cluster when done"
    echo "  kind delete cluster --name $cluster_name"
}

# Run main function
main "$@"