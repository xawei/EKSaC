# EKSaC Control Plane Setup for KIND

This script automates the complete setup of EKSaC control plane using ArgoCD and Crossplane on a local KIND cluster.

## Prerequisites

Ensure you have the following tools installed:
- Docker Desktop (running)
- kubectl
- helm
- kind

Install on macOS:
```bash
brew install kubectl helm kind
```

## AWS Credentials Setup

Create the AWS credentials file at `../../local-dev/01-aws-credentials.txt`:
```
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
```

## Usage

From the `init-cluster/local-kind` directory, simply run:

```bash
./setup-eksac-control-plane.sh
```

The script will automatically:
1. ✅ Check prerequisites
2. ✅ Create KIND cluster (if it doesn't exist) using `kind-config.yaml`
3. ✅ Load local Docker images into KIND
4. ✅ Install ArgoCD
5. ✅ Create ArgoCD Application for Crossplane
6. ✅ Create ArgoCD Application for External Secrets Operator
7. ✅ Deploy EKSaC Components via ArgoCD
8. ✅ Configure AWS Credentials

## After Setup

### Access ArgoCD UI

1. Port forward:
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:80
   ```

2. Open: http://localhost:8080

3. Login:
   - Username: `admin`
   - Password: (provided by script or get with):
     ```bash
     kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
     ```

### Verify Installation

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check Crossplane status
kubectl get pods -n crossplane-system

# Check EKSaC resources
kubectl get xrd
kubectl get compositions
```

## Cleanup

To delete the KIND cluster:
```bash
kind delete cluster --name eksac-dev
```

## Configuration

The script uses these configurable variables:
- `KIND_CLUSTER_NAME`: "eksac-dev" (matches kind-config.yaml)
- `REPO_URL`: "https://github.com/xawei/EKSaC.git"
- `CREDENTIALS_FILE`: "../../local-dev/01-aws-credentials.txt"

## Features

- **Automated**: No manual steps required
- **Robust**: Includes error handling and validation
- **Informative**: Color-coded progress updates
- **Smart**: Creates KIND cluster only if needed
- **Complete**: Sets up entire EKSaC control plane

## What You Get

After running the script, you'll have:
- KIND cluster with ArgoCD and Crossplane
- EKSaC XRDs and Compositions for AWS EKS
- External Secrets Operator for secret management
- All local Docker images loaded into KIND
- Ready-to-use infrastructure as code platform
