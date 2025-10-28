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

# Function to detect cluster type
detect_cluster_type() {
    if kubectl config current-context 2>/dev/null | grep -q "kind"; then
        echo "kind"
    elif kubectl config current-context 2>/dev/null | grep -q "minikube"; then
        echo "minikube"
    else
        echo "unknown"
    fi
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=${3:-300}

    print_status "Waiting for pods in namespace $namespace with label $label..."
    if kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        print_success "Pods are ready in namespace $namespace"
    else
        print_error "Timeout waiting for pods in namespace $namespace"
        return 1
    fi
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

    if ! command_exists kind; then
        missing_tools+=("kind")
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
        print_error "  - kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
        print_error "  - helm: https://helm.sh/docs/intro/install/"
        exit 1
    fi

    print_success "All prerequisites are installed"
}

# Function to check cluster availability
check_cluster() {
    print_status "Checking cluster availability..."

    local cluster_type
    cluster_type=$(detect_cluster_type)

    case $cluster_type in
        kind)
            print_status "Detected kind cluster"
            if ! kind get clusters | grep -q "^backstage-gitops$"; then
                print_error "Kind cluster 'backstage-gitops' not found"
                print_error "Please run './kind-setup.sh' first"
                return 1
            fi
            ;;
        minikube)
            print_status "Detected minikube cluster"
            if ! minikube status >/dev/null 2>&1; then
                print_error "Minikube cluster not running"
                print_error "Please run './infra/minikube/setup.sh' first"
                return 1
            fi
            ;;
        *)
            print_error "No supported cluster detected (kind or minikube)"
            print_error "Please ensure you have a running cluster"
            return 1
            ;;
    esac

    # Verify kubectl connection
    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to cluster with kubectl"
        return 1
    fi

    # Verify kubectl version (without --short flag for compatibility)
    kubectl version --client >/dev/null 2>&1 || print_warning "Could not verify kubectl version"

    print_success "Cluster is available and accessible"
}

# Function to install ArgoCD
install_argocd() {
    print_status "Installing ArgoCD..."

    # Create namespace if it doesn't exist
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Apply ArgoCD manifests from official repository with retry logic
    local retry_count=0
    local max_retries=3
    local success=false

    while [ $retry_count -lt $max_retries ] && [ "$success" = false ]; do
        if kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml; then
            print_success "ArgoCD manifests applied"
            success=true
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "Failed to apply ArgoCD manifests, retrying in 10 seconds... ($retry_count/$max_retries)"
                sleep 10
            else
                print_error "Failed to apply ArgoCD manifests after $max_retries attempts"
                return 1
            fi
        fi
    done

    # Wait for ArgoCD to be ready
    if wait_for_pods "argocd" "app.kubernetes.io/name=argocd-server"; then
        print_success "ArgoCD is ready"
    else
        print_error "ArgoCD failed to start"
        return 1
    fi

    # Get ArgoCD admin password
    local argocd_password
    argocd_password=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "admin")

    print_success "ArgoCD installed successfully"
    print_status "ArgoCD UI: https://localhost:8080"
    print_status "Username: admin"
    print_status "Password: $argocd_password"
}

# Function to deploy Backstage
deploy_backstage() {
    print_status "Deploying Backstage..."

    # Create namespace if it doesn't exist
    kubectl create namespace backstage-system --dry-run=client -o yaml | kubectl apply -f -

    # Check if secrets exist
    if ! kubectl get secret backstage-secrets -n backstage-system >/dev/null 2>&1; then
        print_warning "Secret 'backstage-secrets' not found in namespace 'backstage-system'"
        print_status "Please create the secret with your credentials:"
        echo
        echo "kubectl create secret generic backstage-secrets \\"
        echo "  --from-literal=github-token=YOUR_GITHUB_TOKEN \\"
        echo "  --from-literal=dockerhub-username=YOUR_DOCKERHUB_USERNAME \\"
        echo "  --from-literal=dockerhub-password=YOUR_DOCKERHUB_PASSWORD \\"
        echo "  -n backstage-system"
        echo
        read -p "Do you want to continue without secrets? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled"
            return 1
        fi
    fi

    # Apply ArgoCD Application
    if kubectl apply -f infra/argocd/backstage-application.yaml; then
        print_success "ArgoCD Application created"
    else
        print_error "Failed to create ArgoCD Application"
        return 1
    fi

    # Wait for Backstage to be ready
    print_status "Waiting for Backstage to be deployed (this may take several minutes)..."
    sleep 10

    local retries=0
    local max_retries=30
    while [ $retries -lt $max_retries ]; do
        if kubectl get pods -n backstage-system -l app.kubernetes.io/name=backstage >/dev/null 2>&1; then
            if wait_for_pods "backstage-system" "app.kubernetes.io/name=backstage" 60; then
                break
            fi
        fi
        retries=$((retries + 1))
        print_status "Waiting for Backstage pods... ($retries/$max_retries)"
        sleep 10
    done

    if [ $retries -eq $max_retries ]; then
        print_error "Timeout waiting for Backstage deployment"
        return 1
    fi

    print_success "Backstage deployed successfully"
}

# Function to show access information
show_access_info() {
    echo
    print_success "🎉 Backstage GitOps environment is ready!"
    echo
    print_status "Access URLs:"
    print_status "  Backstage: http://localhost:8000"
    print_status "  ArgoCD UI: https://localhost:8080"
    echo
    print_status "To access the services, run these commands in separate terminals:"
    echo
    echo "  # Access Backstage"
    echo "  kubectl port-forward svc/backstage -n backstage-system 8000:8000"
    echo
    echo "  # Access ArgoCD"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo
    print_status "Useful commands:"
    echo "  # Check ArgoCD applications"
    echo "  kubectl get applications -n argocd"
    echo
    echo "  # Check Backstage pods"
    echo "  kubectl get pods -n backstage-system"
    echo
    echo "  # View Backstage logs"
    echo "  kubectl logs -n backstage-system deployment/backstage --follow"
    echo
    echo "  # Setup commands:"
    echo "  ./kind-setup.sh                    # Setup kind cluster"
    echo "  ./infra/minikube/setup.sh         # Setup minikube cluster"
}

# Main function
main() {
    echo
    print_status "🚀 Backstage GitOps Bootstrap Script"
    print_status "=================================="
    echo

    # Check prerequisites
    check_prerequisites

    # Check cluster availability
    check_cluster

    # Install ArgoCD
    install_argocd

    # Deploy Backstage
    deploy_backstage

    # Show access information
    show_access_info

    print_success "Bootstrap completed successfully! 🎯"
}

# Run main function
main "$@"