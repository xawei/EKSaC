# Local Kind Cluster Setup for EKSaC

This directory contains the configuration for setting up EKSaC control plane on a local Kind cluster.

## Overview

The local Kind cluster serves as a development environment for the EKSaC control plane. Since this is not running on AWS EKS, special configuration is needed for AWS provider authentication.

## Prerequisites

- Docker Desktop
- kubectl
- Helm 3.x
- Kind
- AWS CLI configured (for credential generation)

```bash
brew install kubectl helm kind awscli
```

## Quick Setup

Follow the main setup guide in `../README.md` with these local-specific considerations:

### 1. Create Kind Cluster

```bash
cd init-cluster/local-kind
kind create cluster --config kind-config.yaml
```

### 2. Follow Main Setup

Complete steps 2-5 from the main README:
- Install ArgoCD
- Access ArgoCD
- Create Crossplane Application
- Deploy EKSaC Components

### 3. Configure AWS Credentials (Local Kind Specific)

**Important**: Local Kind clusters cannot use IRSA (IAM Roles for Service Accounts). You must manually configure AWS credentials.

#### Option A: Direct AWS Credentials

1. **Create AWS credentials file**:
   ```bash
   # Create credentials file (replace with your actual AWS credentials)
   cat > 01-aws-credentials.txt << EOF
   [default]
   aws_access_key_id = YOUR_ACCESS_KEY_ID
   aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
   EOF
   ```

2. **Create Kubernetes secret**:
   ```bash
   kubectl create secret \
     generic aws-secret \
     -n crossplane-system \
     --from-file=creds=./01-aws-credentials.txt
   ```

3. **Create ProviderConfig for Secret-based authentication**:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: aws.upbound.io/v1beta1
   kind: ProviderConfig
   metadata:
     name: default
   spec:
     credentials:
       source: Secret
       secretRef:
         namespace: crossplane-system
         name: aws-secret
         key: creds
   EOF
   ```

#### Option B: Role Assumption (Recommended)

For better security, use role assumption:

1. **Create IAM role in AWS** with necessary permissions for EKS/EC2/IAM operations

2. **Configure credentials with role assumption**:
   ```bash
   cat > 01-aws-credentials.txt << EOF
   [default]
   aws_access_key_id = YOUR_ACCESS_KEY_ID
   aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
   EOF
   ```

3. **Create the secret**:
   ```bash
   kubectl create secret \
     generic aws-secret \
     -n crossplane-system \
     --from-file=creds=./01-aws-credentials.txt
   ```

4. **Create ProviderConfig with role assumption**:
   ```bash
   kubectl apply -f - <<EOF
   apiVersion: aws.upbound.io/v1beta1
   kind: ProviderConfig
   metadata:
     name: default
   spec:
     credentials:
       source: Secret
       secretRef:
         namespace: crossplane-system
         name: aws-secret
         key: creds
     assumeRoleChain:
       - roleARN: "arn:aws:iam::YOUR_ACCOUNT_ID:role/eksac-crossplane-iam-role"
   EOF
   ```

**Note**: Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID. The role `eksac-crossplane-iam-role` should be created in AWS with the necessary permissions for Crossplane operations.

## Verification

```bash
# Check providers are healthy
kubectl get providers -n eksac

# Check ProviderConfig is created and using secrets
kubectl get providerconfig default -o yaml

# Verify the secret exists
kubectl get secret aws-secret -n crossplane-system

# Test creating a simple AWS resource
kubectl apply -f - <<EOF
apiVersion: ec2.aws.crossplane.io/v1beta1
kind: VPC
metadata:
  name: test-vpc
spec:
  forProvider:
    cidrBlock: 10.0.0.0/16
    region: ap-southeast-1
  providerConfigRef:
    name: default
EOF

# Check if VPC is being created
kubectl get vpc test-vpc
```

## Differences from Production EKS

| Aspect | Local Kind | Production EKS |
|--------|------------|----------------|
| **Authentication** | Manual secrets | IRSA (automatic) |
| **Security** | Credentials in cluster | No stored credentials |
| **Setup** | Manual patching | Automated via values.yaml |
| **Maintenance** | Manual credential rotation | Automatic via AWS |

## Troubleshooting

### Provider Not Healthy
```bash
# Check provider logs
kubectl logs -n eksac deployment/provider-aws-ec2 -f

# Check provider config
kubectl describe providerconfig default-aws-ec2 -n eksac
```

### Credential Issues
```bash
# Check if secret exists
kubectl get secret aws-secret -n crossplane-system

# Verify secret content
kubectl get secret aws-secret -n crossplane-system -o yaml

# Test AWS credentials manually
aws sts get-caller-identity --profile default
```

### ProviderConfig Not Found
```bash
# List all provider configs
kubectl get providerconfigs -n eksac

# Check if providers created the configs
kubectl get providers -n eksac -o wide
```

## Cleanup

When done testing:

```bash
# Delete test resources first
kubectl delete vpc test-vpc

# Follow main cleanup guide
# Delete applications via ArgoCD
# Delete Kind cluster: kind delete cluster --name eksac-dev
```

## Security Notes

⚠️ **Important Security Considerations**:

1. **Never commit credentials** to Git repositories
2. **Use role assumption** instead of direct access keys when possible
3. **Rotate credentials regularly**
4. **Limit IAM permissions** to minimum required for testing
5. **Delete credentials** when no longer needed

## Next Steps

After setup is complete:
1. Test creating network resources: `kubectl apply -f ../../eks-cluster/00-eksac-public-network.yaml`
2. Test creating EKS clusters: `kubectl apply -f ../../eks-cluster/01-eksac-cluster01.yaml`
3. Monitor in ArgoCD UI: `http://localhost:8080`
