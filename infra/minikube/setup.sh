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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    local missing_tools=()

    if ! command_exists docker; then
        missing_tools+=("docker")
    fi

    if ! command_exists kubectl; then
        missing_tools+=("kubectl")
    fi

    if ! command_exists minikube; then
        missing_tools+=("minikube")
    fi

    if ! command_exists helm; then
        missing_tools+=("helm")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_error "Please install the missing tools and try again."
        print_error "Installation instructions:"
        print_error "  - Docker: https://docs.docker.com/get-docker/"
        print_error "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        print_error "  - minikube: https://minikube.sigs.k8s.io/docs/start/"
        print_error "  - helm: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    print_success "All prerequisites are installed"
}

# Function to check Docker
check_docker() {
    print_status "Checking Docker..."

    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        print_error "Please start Docker and try again"
        exit 1
    fi

    print_success "Docker is running"
}

# Function to check minikube
check_minikube() {
    print_status "Checking minikube..."

    if ! command_exists minikube; then
        print_error "minikube is not installed"
        print_error "Please install minikube from: https://minikube.sigs.k8s.io/docs/start/"
        exit 1
    fi

    print_success "minikube is available"

    # Verify minikube version
    minikube version
}

# Function to start minikube cluster
start_minikube() {
    local cluster_name="backstage-gitops"

    print_status "Starting minikube cluster '$cluster_name'..."

    # Check if cluster already exists
    if minikube status >/dev/null 2>&1; then
        print_warning "minikube cluster already exists"
        read -p "Do you want to delete the existing cluster and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deleting existing cluster..."
            minikube delete
        else
            print_status "Using existing cluster"
            return 0
        fi
    fi

    # Start minikube with appropriate configuration
    print_status "Starting minikube with Docker driver..."
    if minikube start \
        --driver=docker \
        --cpus=2 \
        --memory=4096 \
        --disk-size=20g \
        --kubernetes-version=stable \
        --addons=ingress \
        --ports=30080:80,30401:4001,30800:8000; then

        print_success "minikube cluster started successfully"
    else
        print_error "Failed to start minikube cluster"
        exit 1
    fi

    # Enable ingress addon if not already enabled
    print_status "Ensuring ingress addon is enabled..."
    minikube addons enable ingress

    # Wait for cluster to be ready
    print_status "Waiting for cluster to be ready..."
    kubectl wait --for=condition=ready node/minikube --timeout=300s

    print_success "Cluster is ready!"
}

# Function to configure kubectl
configure_kubectl() {
    print_status "Configuring kubectl..."

    # Point kubectl to minikube
    if kubectl config use-context minikube >/dev/null 2>&1; then
        print_success "kubectl configured to use minikube context"
    else
        print_warning "Could not switch to minikube context"
    fi

    # Verify connection
    if kubectl cluster-info >/dev/null 2>&1; then
        print_success "kubectl can connect to cluster"
    else
        print_error "kubectl cannot connect to cluster"
        exit 1
    fi
}

# Function to verify cluster
verify_cluster() {
    print_status "Verifying cluster setup..."

    # Check nodes
    print_status "Cluster nodes:"
    kubectl get nodes

    # Check cluster status
    print_status "Cluster status:"
    kubectl get componentstatuses 2>/dev/null || kubectl get cs 2>/dev/null || echo "Component statuses not available (expected in newer k8s versions)"

    # Check minikube status
    print_status "Minikube status:"
    minikube status

    # Check ingress
    print_status "Ingress status:"
    kubectl get pods -n ingress-nginx

    print_success "Cluster verification completed"
}

# Function to show access information
show_access_info() {
    echo
    print_success "🎉 Minikube cluster setup completed!"
    echo
    print_status "Cluster Information:"
    echo "  - Cluster name: backstage-gitops"
    echo "  - Kubernetes version: $(kubectl version --client | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+')"
    echo "  - Driver: docker"
    echo
    print_status "Port mappings:"
    echo "  - 30080 → 80 (HTTP/Ingress)"
    echo "  - 30401 → 4001 (Backstage Backend)"
    echo "  - 30800 → 8000 (Backstage Frontend)"
    echo
    print_status "Useful commands:"
    echo "  # Get cluster info"
    echo "  kubectl cluster-info"
    echo
    echo "  # Access Kubernetes dashboard"
    echo "  minikube dashboard"
    echo
    echo "  # Stop cluster"
    echo "  minikube stop"
    echo
    echo "  # Delete cluster"
    echo "  minikube delete"
    echo
    print_status "Next steps:"
    echo "  1. Run './bootstrap.sh' to deploy ArgoCD and Backstage"
    echo "  2. Use 'kubectl get nodes' to verify cluster"
}

# Function to show usage information
show_usage() {
    echo
    print_status "Minikube Setup Script"
    print_status "===================="
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --delete        Delete existing cluster if it exists"
    echo "  -s, --stop          Stop the cluster"
    echo "  -v, --verify        Only verify existing cluster"
    echo
    echo "Examples:"
    echo "  $0                    # Start cluster with default settings"
    echo "  $0 --delete          # Delete and recreate cluster"
    echo "  $0 --verify          # Only verify existing cluster"
    echo "  $0 --stop            # Stop the cluster"
}

# Main function
main() {
    local delete_existing=false
    local stop_cluster=false
    local verify_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -d|--delete)
                delete_existing=true
                shift
                ;;
            -s|--stop)
                stop_cluster=true
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
    print_status "🚀 Minikube Cluster Setup Script"
    print_status "==============================="

    # Handle special cases
    if [ "$stop_cluster" = true ]; then
        print_status "Stopping minikube cluster..."
        minikube stop
        print_success "Cluster stopped"
        exit 0
    fi

    if [ "$verify_only" = true ]; then
        check_prerequisites
        check_docker
        check_minikube
        verify_cluster
        exit 0
    fi

    # Normal setup flow
    check_prerequisites
    check_docker
    check_minikube

    if [ "$delete_existing" = true ] && minikube status >/dev/null 2>&1; then
        print_status "Deleting existing cluster..."
        minikube delete
    fi

    start_minikube
    configure_kubectl
    verify_cluster
    show_access_info

    print_success "Minikube setup completed successfully! 🎯"
}

# Run main function
main "$@"