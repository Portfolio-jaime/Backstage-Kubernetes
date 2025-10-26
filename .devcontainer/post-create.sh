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

# Function to check if Docker is accessible
check_docker() {
    print_status "Checking Docker access..."

    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker is not accessible from within the container"
        print_warning "You may need to run 'docker-in-docker' or mount the Docker socket"
        print_warning "Some features may not work properly"
    else
        print_success "Docker is accessible"
    fi
}

# Function to check tools
check_tools() {
    print_status "Checking installed tools..."

    local tools=("node" "yarn" "kubectl" "kind" "helm" "docker")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_success "$tool is available"
        else
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_warning "Missing tools: ${missing_tools[*]}"
    fi
}

# Function to setup Git (if needed)
setup_git() {
    print_status "Setting up Git configuration..."

    if [ -z "$(git config --global user.name)" ]; then
        git config --global user.name "Dev Container User"
        print_success "Set default Git user name"
    fi

    if [ -z "$(git config --global user.email)" ]; then
        git config --global user.email "devcontainer@example.com"
        print_success "Set default Git user email"
    fi

    git config --global init.defaultBranch main
    print_success "Git configuration completed"
}

# Function to install Backstage dependencies (if backstage directory exists)
setup_backstage() {
    if [ -d "backstage" ]; then
        print_status "Setting up Backstage dependencies..."

        cd backstage

        # Check if node_modules exists
        if [ ! -d "node_modules" ]; then
            print_status "Installing Backstage dependencies..."
            if yarn install; then
                print_success "Backstage dependencies installed"
            else
                print_warning "Failed to install Backstage dependencies"
            fi
        else
            print_success "Backstage dependencies already installed"
        fi

        cd ..
    else
        print_warning "Backstage directory not found, skipping dependency installation"
    fi
}

# Function to create helpful scripts
create_helper_scripts() {
    print_status "Creating helper scripts..."

    # Create a script to start local development
    cat > start-dev.sh << 'EOF'
#!/bin/bash
set -e

echo "🚀 Starting Backstage development environment..."

# Check if we're in the right directory
if [ ! -d "backstage" ]; then
    echo "❌ Backstage directory not found. Please run this from the project root."
    exit 1
fi

cd backstage

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    yarn install
fi

# Start development server
echo "🏃 Starting Backstage development server..."
echo "📱 Frontend will be available at: http://localhost:3000"
echo "🔧 Backend will be available at: http://localhost:7007"
echo ""
echo "Press Ctrl+C to stop the development server"
echo ""

yarn start
EOF

    chmod +x start-dev.sh
    print_success "Created start-dev.sh script"

    # Create a script to check cluster status
    cat > check-cluster.sh << 'EOF'
#!/bin/bash

echo "🔍 Checking cluster status..."

# Check if kind cluster exists
if kind get clusters | grep -q "backstage-gitops"; then
    echo "✅ Kind cluster 'backstage-gitops' exists"

    # Switch to cluster context
    kubectl config use-context kind-backstage-gitops >/dev/null 2>&1

    # Check cluster info
    echo ""
    echo "📊 Cluster Information:"
    kubectl cluster-info 2>/dev/null || echo "Unable to get cluster info"

    # Check nodes
    echo ""
    echo "🖥️  Nodes:"
    kubectl get nodes

    # Check namespaces
    echo ""
    echo "📁 Namespaces:"
    kubectl get namespaces

    # Check ArgoCD applications
    if kubectl get namespace argocd >/dev/null 2>&1; then
        echo ""
        echo "🎯 ArgoCD Applications:"
        kubectl get applications -n argocd 2>/dev/null || echo "No applications found"
    fi

    # Check Backstage pods
    if kubectl get namespace backstage-system >/dev/null 2>&1; then
        echo ""
        echo "🎭 Backstage Pods:"
        kubectl get pods -n backstage-system 2>/dev/null || echo "No pods found"
    fi

else
    echo "❌ Kind cluster 'backstage-gitops' does not exist"
    echo "💡 Run './kind-setup.sh' to create the cluster"
fi
EOF

    chmod +x check-cluster.sh
    print_success "Created check-cluster.sh script"
}

# Function to show welcome message
show_welcome() {
    echo ""
    print_success "🎉 Dev Container setup completed!"
    echo ""
    print_status "Available commands:"
    echo "  ./start-dev.sh     - Start Backstage development server"
    echo "  ./check-cluster.sh - Check cluster and deployment status"
    echo "  ./bootstrap.sh     - Deploy ArgoCD and Backstage to cluster"
    echo "  ./kind-setup.sh    - Setup kind cluster"
    echo ""
    print_status "Useful kubectl commands:"
    echo "  kubectl get pods -n backstage-system    # Check Backstage pods"
    echo "  kubectl get applications -n argocd      # Check ArgoCD apps"
    echo "  kubectl port-forward svc/backstage...   # Access services"
    echo ""
    print_status "Happy coding! 🚀"
}

# Main setup function
main() {
    print_status "🚀 Dev Container Post-Create Setup"
    print_status "=================================="

    check_docker
    check_tools
    setup_git
    setup_backstage
    create_helper_scripts
    show_welcome
}

# Run main function
main "$@"