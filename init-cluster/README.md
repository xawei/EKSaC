# EKSaC Control Plane Cluster

This directory helps you bootstrap a **control plane cluster** for EKSaC (EKS as Code). The control plane cluster runs ArgoCD and Crossplane to manage your target AWS EKS clusters declaratively.

## Architecture Overview

```
┌─────────────────────────┐    ┌─────────────────────────┐
│   Control Plane         │    │   Target EKS Clusters   │
│   (Kind/EKS/GKE)       │───▶│   (AWS)                 │
│                         │    │                         │
│ • ArgoCD               │    │ • Application Workloads │
│ • Crossplane           │    │ • Managed by Crossplane │
│ • EKSaC XRDs           │    │                         │
│ • EKSaC Compositions   │    │                         │
└─────────────────────────┘    └─────────────────────────┘
```

The control plane cluster contains:
- **ArgoCD**: GitOps controller for application delivery
- **Crossplane**: Infrastructure orchestration platform  
- **AWS Providers**: EC2, EKS, IAM resource management
- **EKSaC XRDs**: Custom resource definitions for network and cluster
- **EKSaC Compositions**: Implementation logic for XRDs

## Prerequisites

- Docker Desktop
- kubectl
- Helm 3.x
- Kind (for local development)

```bash
brew install kubectl helm kind
```

## Quick Start

### 1. Create Control Plane Cluster

#### Local Kind Cluster (Recommended for Development)

```bash
cd init-cluster/local-kind && kind create cluster --config kind-config.yaml
```

#### Use Existing Cluster
You can also use an existing Kubernetes cluster (EKS, GKE, etc.) as your control plane.

### 2. Install ArgoCD

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd
helm install argocd argo/argo-cd --namespace argocd \
  --set server.extraArgs[0]="--insecure"
```

**If you encounter network connectivity issues**, try these alternatives:

1. **Use OCI registry** (recommended alternative):
   ```bash
   helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
   --namespace argocd \
   --create-namespace \
   --set "server.extraArgs[0]=--insecure"
   ```

2. **Use kubectl directly** (fallback method):
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   
   # Configure for local access
   kubectl patch deployment argocd-server -n argocd -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}'
   ```

For Kind clusters, you may also want to set the service type:
```bash
# Alternative for Kind with LoadBalancer simulation
helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set "server.extraArgs[0]=--insecure"
  --set "server.service.type=LoadBalancer"
```

### 3. Access ArgoCD

```bash
# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# Port forward to access UI (for Kind clusters)
kubectl port-forward svc/argocd-server -n argocd 8080:80

# Open http://localhost:8080
# Username: admin
# Password: (from command above)
```

### 4. Create ArgoCD Application for Crossplane

Instead of installing Crossplane directly, we'll use ArgoCD to manage it:

```bash
# Create ArgoCD application for Crossplane
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
    targetRevision: 1.20.0  # Use latest stable version
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
```

Wait for Crossplane to be ready:
```bash
# Check Crossplane application status
kubectl get application crossplane -n argocd

# Wait for Crossplane deployment to be ready
kubectl wait --for=condition=Available deployment/crossplane -n crossplane-system --timeout=300s
```

### 5. Deploy EKSaC Components via ArgoCD

Create ArgoCD applications to manage the EKSaC components:

```bash
# Create eksac namespace
kubectl create namespace eksac

# Create ArgoCD application for Crossplane Providers (with local Kind configuration)
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: crossplane-providers
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/xawei/EKSaC.git
    path: crossplane-providers-chart
    targetRevision: main
    helm:
      valueFiles:
        - values-local-kind.yaml  # Use local Kind configuration
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: crossplane-system  # Changed to crossplane-system for providers
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
    repoURL: https://github.com/xawei/EKSaC.git
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
    repoURL: https://github.com/xawei/EKSaC.git
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
```

For local development without Git, you can install directly:
```bash
# Direct installation (for local development only)
kubectl create namespace eksac
# Install providers with local Kind configuration  
helm install crossplane-providers ../crossplane-providers-chart \
  --namespace crossplane-system \
  --values ../crossplane-providers-chart/values-local-kind.yaml
kubectl apply -f ../xnetwork/ -n eksac
kubectl apply -f ../xekscluster/ -n eksac
```

### 6. Configure AWS Credentials (Local Development)

**For local Kind clusters**: Since local clusters cannot use IRSA (IAM Roles for Service Accounts), you need to manually configure AWS credentials. The `values-local-kind.yaml` file configures the providers to use Secret-based authentication with optional role assumption for better security.

**Steps for local Kind deployment:**
1. Create AWS credentials secret (as detailed in [`local-kind/README.md`](local-kind/README.md#configure-aws-credentials-local-kind-specific))
2. The providers will automatically use the secret-based configuration from `values-local-kind.yaml`
3. Optional: Configure role assumption for better security practices

**For production EKS clusters**: Use the standard `values.yaml` file which configures providers to use IRSA authentication.

**Deployment Mode Configuration:**
- **Local Kind**: Use `values-local-kind.yaml` (sets `deploymentMode: "local"`)
- **Production EKS**: Use `values.yaml` (sets `deploymentMode: "eks"`)

The Helm chart automatically creates the appropriate ProviderConfigs based on the deployment mode.

## Verify Installation

```bash
# Check Crossplane (in crossplane-system namespace)
kubectl get pods -n crossplane-system

# Check Crossplane providers and EKSaC components (in eksac namespace)
kubectl get providers -n eksac

# Check XRDs (cluster-wide resources)
kubectl get xrd

# Check Compositions (in eksac namespace)
kubectl get compositions -n eksac

# Check ArgoCD applications
kubectl get applications -n argocd

# Check ArgoCD
kubectl get pods -n argocd
```

Expected output:
```bash
$ kubectl get providers -n eksac
NAME                   INSTALLED   HEALTHY   PACKAGE
provider-aws-ec2       True        True      crossplane-contrib/provider-aws-ec2:v1
provider-aws-eks       True        True      crossplane-contrib/provider-aws-eks:v1  
provider-aws-iam       True        True      crossplane-contrib/provider-aws-iam:v1
provider-helm          True        True      crossplane-contrib/provider-helm:v0
provider-kubernetes    True        True      crossplane-contrib/provider-kubernetes:v0

$ kubectl get xrd
NAME                                    ESTABLISHED   OFFERED
xeksclusters.consumable.trustbank.sg    True          True
xnetworks.consumable.trustbank.sg       True          True

$ kubectl get applications -n argocd
NAME                   SYNC STATUS   HEALTH STATUS
crossplane             Synced        Healthy
crossplane-providers   Synced        Healthy
xnetwork              Synced        Healthy
xekscluster           Synced        Healthy
```

## Using the Control Plane

Once set up, you can:

1. **Deploy target EKS clusters** using the XRDs:
   ```bash
   kubectl apply -f ../eks-cluster/00-eksac-public-network.yaml
   kubectl apply -f ../eks-cluster/01-eksac-cluster01.yaml
   ```

2. **Manage applications via ArgoCD** pointing to your Git repositories

3. **Monitor infrastructure** through Crossplane resources:
   ```bash
   kubectl get managed  # View all managed AWS resources
   kubectl get networks # View network resources
   kubectl get eksclusters # View EKS cluster resources
   ```

## Environment Options

### Local Kind (Development)
- **Location**: `local-kind/`
- **Use case**: Development, testing, learning
- **Target clusters**: Can manage real AWS EKS clusters from local Kind control plane

### AWS EKS (Production)
- **Location**: `aws-eks/` (coming soon)
- **Use case**: Production control plane
- **Target clusters**: Manage multiple AWS EKS clusters

### GCP GKE (Multi-cloud)
- **Location**: `gcp-gke/` (coming soon)  
- **Use case**: Multi-cloud or GCP-based control plane
- **Target clusters**: Manage EKS clusters from GCP

## Cleanup

⚠️ **IMPORTANT**: Clean up managed resources BEFORE destroying the control plane cluster to avoid orphaned AWS resources.

### 1. Clean Up Managed AWS Resources First

```bash
# Delete all EKS clusters (this will take 10-15 minutes per cluster)
kubectl delete eksclusters --all

# Delete all networks
kubectl delete networks --all

# Wait for all managed resources to be cleaned up
kubectl get managed
# Wait until this returns "No resources found"
```

### 2. Clean Up ArgoCD Applications

```bash
# Delete ArgoCD applications
kubectl delete applications -n argocd --all

# Or delete specific applications
kubectl delete application crossplane-providers -n argocd
kubectl delete application xnetwork -n argocd  
kubectl delete application xekscluster -n argocd
```

### 3. Clean Up Control Plane Components

```bash
# Uninstall EKSaC applications (this will also clean providers in eksac namespace)
kubectl delete application crossplane-providers -n argocd
kubectl delete application xnetwork -n argocd  
kubectl delete application xekscluster -n argocd

# Uninstall Crossplane (this will clean up crossplane in crossplane-system)
kubectl delete application crossplane -n argocd

# Wait for all applications to be removed
kubectl wait --for=delete application/crossplane-providers -n argocd --timeout=300s
kubectl wait --for=delete application/crossplane -n argocd --timeout=300s

# Uninstall ArgoCD
helm uninstall argocd -n argocd

# Delete namespaces (this ensures all resources are cleaned up)
kubectl delete namespace argocd crossplane-system eksac
```

### 4. Finally, Delete Control Plane Cluster

```bash
# Only after all managed resources are cleaned up
kind delete cluster --name eksac-dev
```

## Next Steps

1. **Configure AWS credentials** for Crossplane providers
2. **Set up Git repositories** for ArgoCD applications  
3. **Deploy your first EKS cluster** using the provided examples
4. **Customize XRDs and Compositions** for your organization's needs

## Directory Structure

```
init-cluster/
├── README.md                    # This file
├── local-kind/                  # Local Kind cluster setup
│   └── kind-config.yaml         # Kind cluster configuration
├── aws-eks/                     # AWS EKS control plane (coming soon)
└── gcp-gke/                     # GCP GKE control plane (coming soon)
```
