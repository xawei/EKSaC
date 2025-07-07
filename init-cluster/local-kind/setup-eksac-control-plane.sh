#!/bin/bash

# EKSaC Control Plane Setup Script for KIND
# This script automates the complete setup of EKSaC control plane using ArgoCD and Crossplane

set -e  # Exit on any error

# Configuration
KIND_CLUSTER_NAME="eksac-dev"  # Must match the name in kind-config.yaml
REPO_URL="https://github.com/xawei/EKSaC.git"
CREDENTIALS_FILE="../../local-dev/01-aws-credentials.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    commands=("kubectl" "helm" "kind" "docker")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "All prerequisites are available"
}

# Check if KIND cluster exists and create if needed
ensure_kind_cluster() {
    log_info "Checking if KIND cluster exists..."
    
    if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
        log_success "KIND cluster '${KIND_CLUSTER_NAME}' already exists"
        
        # Set kubectl context to the KIND cluster
        kubectl cluster-info --context kind-${KIND_CLUSTER_NAME} &>/dev/null
        if [ $? -ne 0 ]; then
            log_info "Setting kubectl context to kind-${KIND_CLUSTER_NAME}"
            kubectl config use-context kind-${KIND_CLUSTER_NAME}
        fi
    else
        log_info "KIND cluster '${KIND_CLUSTER_NAME}' does not exist. Creating..."
        
        # Check if kind-config.yaml exists
        if [ ! -f "kind-config.yaml" ]; then
            log_error "kind-config.yaml not found in current directory"
            log_error "Please run this script from the init-cluster/local-kind directory"
            exit 1
        fi
        
        # Create KIND cluster with config
        kind create cluster --name ${KIND_CLUSTER_NAME} --config kind-config.yaml
        
        if [ $? -eq 0 ]; then
            log_success "KIND cluster '${KIND_CLUSTER_NAME}' created successfully"
        else
            log_error "Failed to create KIND cluster"
            exit 1
        fi
    fi
    
    # Verify cluster is accessible
    kubectl cluster-info --context kind-${KIND_CLUSTER_NAME} &>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Cannot access KIND cluster. Please check your setup."
        exit 1
    fi
    
    log_success "KIND cluster is ready and accessible"
}

# Wait for deployment to be ready
wait_for_deployment() {
    local namespace=$1
    local deployment=$2
    local timeout=${3:-300}
    
    log_info "Waiting for deployment $deployment in namespace $namespace to be ready..."
    kubectl wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n $namespace
}

# Wait for ArgoCD to be ready
wait_for_argocd() {
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-dex-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-redis -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd
}

# Install ArgoCD
install_argocd() {
    log_info "Installing ArgoCD..."
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Install ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    # Wait for ArgoCD to be ready
    wait_for_argocd
    
    # Configure for local access (insecure mode)
    kubectl patch deployment argocd-server -n argocd -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}'
    
    # Wait for patched deployment
    wait_for_deployment argocd argocd-server
    
    log_success "ArgoCD installed successfully"
}

# Create ArgoCD Application for Crossplane
create_crossplane_app() {
    log_info "Creating ArgoCD Application for Crossplane..."
    
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crossplane
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.crossplane.io/stable
    chart: crossplane
    targetRevision: 1.20.0
    helm:
      valueFiles: []
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    
    log_success "Crossplane ArgoCD Application created"
}

# Create ArgoCD Application for External Secrets Operator
create_external_secrets_app() {
    log_info "Creating ArgoCD Application for External Secrets Operator..."
    
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets-operator
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.external-secrets.io
    chart: external-secrets
    targetRevision: 0.18.2
    helm:
      values: |
        installCRDs: true
        webhook:
          port: 9443
        certController:
          requeueInterval: 20s
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: external-secrets
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    
    log_success "External Secrets Operator ArgoCD Application created"
}

# Deploy EKSaC Components via ArgoCD
deploy_eksac_components() {
    log_info "Deploying EKSaC Components via ArgoCD..."
    
    # Create eksac namespace
    kubectl create namespace eksac --dry-run=client -o yaml | kubectl apply -f -
    
    # Create ArgoCD application for Crossplane Providers
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crossplane-providers
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    path: crossplane-providers-chart
    targetRevision: main
    helm:
      valueFiles:
        - values-local-kind.yaml
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    
    # Create ArgoCD application for xNetwork XRDs and Compositions
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: xnetwork
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    path: xnetwork
    targetRevision: main
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: eksac
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    
    # Create ArgoCD application for xEKSCluster XRDs and Compositions
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: xekscluster
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    path: xekscluster
    targetRevision: main
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: eksac
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
    
    log_success "EKSaC Components ArgoCD Applications created"
}

# Configure AWS Credentials in Local KIND Cluster
configure_aws_credentials() {
    log_info "Configuring AWS Credentials in Local KIND Cluster..."
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "AWS credentials file not found at $CREDENTIALS_FILE"
        log_error "Please create the file with your AWS credentials before running this script"
        exit 1
    fi
    
    # Ensure crossplane-system namespace exists
    log_info "Ensuring crossplane-system namespace exists..."
    kubectl create namespace crossplane-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Ensure external-secrets namespace exists
    log_info "Ensuring external-secrets namespace exists..."
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    
    # Wait a moment for namespaces to be fully created
    sleep 2
    
    # Create AWS secret in crossplane-system namespace (file-based for Crossplane)
    log_info "Creating AWS secret for Crossplane..."
    kubectl create secret generic aws-secret \
        -n crossplane-system \
        --from-file=creds="$CREDENTIALS_FILE" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create AWS secret in external-secrets namespace (key-value for ESO)
    log_info "Creating AWS secret for External Secrets Operator..."
    kubectl create secret generic eso-aws-creds \
        -n external-secrets \
        --from-literal=aws_access_key_id=$(grep aws_access_key_id "$CREDENTIALS_FILE" | awk -F' = ' '{print $2}') \
        --from-literal=aws_secret_access_key=$(grep aws_secret_access_key "$CREDENTIALS_FILE" | awk -F' = ' '{print $2}') \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "AWS credentials configured successfully for both Crossplane and External Secrets Operator"
}

# Add Local Images to KIND
add_local_images_to_kind() {
    log_info "Adding relevant local images to KIND worker nodes..."
    
    # Define patterns for relevant images (customize as needed)
    RELEVANT_PATTERNS=(
        "crossplane"
        "upbound"
        "xpkg"
        "provider-"
        "function-"
        "eksac"
        "argocd"
        "external-secrets"
        "ghcr.io/dexidp"
        "quay.io/argoproj/argocd"
    )
    
    # Get worker node names
    WORKER_NODES=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name | grep -E "worker|node" | head -10)
    
    if [ -z "$WORKER_NODES" ]; then
        log_warning "No worker nodes found in cluster"
        return 0
    fi
    
    # Get list of relevant local images only
    IMAGES=()
    for pattern in "${RELEVANT_PATTERNS[@]}"; do
        while IFS= read -r image; do
            if [[ ! " ${IMAGES[*]} " =~ " ${image} " ]]; then
                IMAGES+=("$image")
            fi
        done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i "$pattern" | grep -v '<none>')
    done
    
    # Also check for custom images you might have built
    while IFS= read -r image; do
        if [[ $image == *"localhost"* ]] || [[ $image == *"local"* ]]; then
            if [[ ! " ${IMAGES[*]} " =~ " ${image} " ]]; then
                IMAGES+=("$image")
            fi
        fi
    done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')
    
    if [ ${#IMAGES[@]} -eq 0 ]; then
        log_warning "No relevant images found to load"
        log_info "Searched for images matching patterns: ${RELEVANT_PATTERNS[*]}"
        return 0
    fi
    
    # Safety check - don't load too many images
    if [ ${#IMAGES[@]} -gt 50 ]; then
        log_warning "Found ${#IMAGES[@]} images to load, which seems excessive"
        log_info "First 10 images would be:"
        for i in {0..9}; do
            if [ -n "${IMAGES[$i]}" ]; then
                echo "  - ${IMAGES[$i]}"
            fi
        done
        log_warning "Skipping image loading to prevent excessive space usage"
        log_info "If you need specific images, modify the RELEVANT_PATTERNS in the script"
        return 0
    fi
    
    log_info "Found ${#IMAGES[@]} relevant images to load to worker nodes"
    
    # Convert worker nodes to comma-separated list for KIND
    WORKER_NODE_LIST=$(echo "$WORKER_NODES" | tr '\n' ',' | sed 's/,$//')
    
    for IMAGE in "${IMAGES[@]}"; do
        log_info "Loading image: $IMAGE to worker nodes: $WORKER_NODE_LIST"
        kind load docker-image "$IMAGE" --name "$KIND_CLUSTER_NAME" --nodes "$WORKER_NODE_LIST"
        
        if [ $? -ne 0 ]; then
            log_warning "Failed to load image: $IMAGE"
        fi
    done
    
    log_success "Relevant images loaded to worker nodes in KIND cluster: $KIND_CLUSTER_NAME"
}

# Get ArgoCD admin password
get_argocd_password() {
    log_info "Getting ArgoCD admin password..."
    
    # Wait a bit for the secret to be created
    sleep 10
    
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ -z "$password" ]; then
        log_warning "ArgoCD admin password not found. It may take a few minutes to be generated."
        log_info "You can retrieve it later with: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    else
        log_success "ArgoCD admin password: $password"
    fi
}

# Show access instructions
show_access_instructions() {
    log_info "Setup completed! Here's how to access your services:"
    echo
    echo "KIND Cluster:"
    echo "  Cluster name: ${KIND_CLUSTER_NAME}"
    echo "  Context: kind-${KIND_CLUSTER_NAME}"
    echo
    
    # Get ArgoCD credentials
    local argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    echo "ArgoCD UI:"
    echo "  1. Port forward: kubectl port-forward svc/argocd-server -n argocd 8080:80"
    echo "  2. Open: http://localhost:8080"
    echo "  3. Login Credentials:"
    echo "     Username: admin"
    if [ -n "$argocd_password" ]; then
        echo "     Password: $argocd_password"
    else
        echo "     Password: (retrieving... run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
    fi
    echo
    echo "Check ArgoCD Applications:"
    echo "  kubectl get applications -n argocd"
    echo
    echo "Check Crossplane status:"
    echo "  kubectl get pods -n crossplane-system"
    echo
    echo "Check EKSaC resources:"
    echo "  kubectl get xrd"
    echo "  kubectl get compositions"
    echo
    echo "To delete the KIND cluster when done:"
    echo "  kind delete cluster --name ${KIND_CLUSTER_NAME}"
    echo
}

# Main execution
main() {
    log_info "Starting EKSaC Control Plane Setup for KIND..."
    
    check_prerequisites
    
    log_info "Step 1: Ensuring KIND cluster exists..."
    ensure_kind_cluster
    
    log_info "Step 2: Adding Local Images to KIND..."
    add_local_images_to_kind
    
    log_info "Step 3: Installing ArgoCD..."
    install_argocd
    
    log_info "Step 4: Creating ArgoCD Application for Crossplane..."
    create_crossplane_app
    
    log_info "Step 5: Creating ArgoCD Application for External Secrets Operator..."
    create_external_secrets_app
    
    log_info "Step 6: Deploying EKSaC Components via ArgoCD..."
    deploy_eksac_components
    
    log_info "Step 7: Configuring AWS Credentials..."
    configure_aws_credentials
    
    log_info "Step 8: Getting ArgoCD admin password..."
    get_argocd_password
    
    log_success "EKSaC Control Plane Setup completed successfully!"
    show_access_instructions
}

# Handle script interruption
trap 'log_error "Script interrupted. Cleanup may be needed."; exit 1' INT TERM

# Run main function
main "$@" 