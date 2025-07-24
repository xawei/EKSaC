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
 **Use kubectl directly**:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   
   # Configure for local access
   kubectl patch deployment argocd-server -n argocd -p='{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}'
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

### 5. Create ArgoCD Application for External Secrets Operator

The External Secrets Operator helps manage secrets from external secret stores (like AWS Secrets Manager, HashiCorp Vault, etc.) and sync them to Kubernetes secrets:

```bash
# Create ArgoCD application for External Secrets Operator
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
    targetRevision: 0.18.2  # Use latest stable version
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
```

### 6. Deploy EKSaC Components via ArgoCD

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

### 7. Configure AWS Credentials in Local KIND Cluster
- put your aws secrets in local-dev/01-aws-credentials.txt
```
kubectl create secret \
generic aws-secret \
-n crossplane-system \
--from-file=creds=local-dev/01-aws-credentials.txt
```

## Add Local Images to KIND
```
#!/bin/bash

# Set your KIND cluster name
KIND_CLUSTER_NAME="kind"

# List all local images (repo:tag format)
IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>')

for IMAGE in $IMAGES; do
  echo "Loading image: $IMAGE into KIND cluster: $KIND_CLUSTER_NAME"
  kind load docker-image "$IMAGE" --name "$KIND_CLUSTER_NAME"
done

echo "✅ All images loaded into KIND cluster: $KIND_CLUSTER_NAME"
```