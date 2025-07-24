# EKS Claims Chart

A Helm chart for deploying Crossplane EKS cluster and network claims with dynamic namespace creation.

## Overview

This chart creates:
- A network claim in the `eksac` namespace
- An EKS cluster claim in a dynamically created namespace
- The EKS cluster namespace follows the pattern: `<claim-name>-xplane-eks-cluster`

## Installation

### Prerequisites

- Kubernetes cluster with Crossplane installed
- EKS and Network Crossplane XRDs deployed
- Proper RBAC permissions for claim creation

### Install the chart

```bash
# Install with default values
helm install my-eks-claims ./eks-claims-chart

# Install with custom values
helm install my-eks-claims ./eks-claims-chart -f custom-values.yaml

# Install for local Kind development
helm install my-eks-claims ./eks-claims-chart -f values-local-kind.yaml
```

## Configuration

### EKS Cluster Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `eksCluster.enabled` | Enable EKS cluster claim creation | `true` |
| `eksCluster.claimName` | Name of the EKS cluster claim | `cluster01` |
| `eksCluster.clusterName` | Name of the EKS cluster | `cluster01` |
| `eksCluster.location` | AWS region | `ap-southeast-1` |
| `eksCluster.networkRef` | Reference to network claim | `andy-network` |
| `eksCluster.nodeSize` | Node instance size | `small` |
| `eksCluster.minNodeCount` | Minimum number of nodes | `1` |
| `eksCluster.tags` | Resource tags | See values.yaml |

### Network Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `network.enabled` | Enable network claim creation | `true` |
| `network.claimName` | Name of the network claim | `andy-network` |
| `network.namespace` | Namespace for network claim | `eksac` |
| `network.location` | AWS region | `ap-southeast-1` |
| `network.vpcCidr` | VPC CIDR block | `10.0.0.0/22` |
| `network.subnets.public` | Public subnet configurations | See values.yaml |
| `network.tags` | Resource tags | See values.yaml |

## Examples

### Basic Usage

```yaml
# Custom values for production cluster
eksCluster:
  claimName: "prod-cluster"
  clusterName: "production"
  nodeSize: "medium"
  minNodeCount: 3
  tags:
    owner: "platform-team"
    environment: "production"

network:
  claimName: "prod-network"
  vpcCidr: "10.1.0.0/22"
  tags:
    owner: "platform-team"
    environment: "production"
```

This will create:
- Namespace: `prod-cluster-xplane-eks-cluster`
- EKS cluster claim: `prod-cluster` in the above namespace
- Network claim: `prod-network` in `eksac` namespace

### Multiple Environments

```bash
# Development
helm install dev-eks ./eks-claims-chart -f values-local-kind.yaml

# Production  
helm install prod-eks ./eks-claims-chart \
  --set eksCluster.claimName=prod-cluster \
  --set eksCluster.clusterName=production \
  --set network.claimName=prod-network
```

## Namespace Strategy

The chart creates a dedicated namespace for each EKS cluster using the pattern:
```
<eksCluster.claimName>-xplane-eks-cluster
```

This provides:
- **Isolation**: Each cluster gets its own namespace
- **Organization**: Clear naming convention
- **Management**: Easy to identify which namespace belongs to which cluster

## Resource Dependencies

1. **Network Claim** is created first in the `eksac` namespace
2. **EKS Cluster Namespace** is created dynamically
3. **EKS Cluster Claim** references the network and is placed in its dedicated namespace

## Cleanup

```bash
# Uninstall the chart
helm uninstall my-eks-claims

# Note: This will delete the claims but may leave the dynamically created namespace
# Clean up the namespace manually if needed:
kubectl delete namespace <claim-name>-xplane-eks-cluster
```

## Troubleshooting

### Check claim status
```bash
# Check network claim
kubectl get networkclaim -n eksac

# Check EKS cluster claim  
kubectl get eksclusterclaim -n <claim-name>-xplane-eks-cluster

# Check all namespaces created by the chart
kubectl get namespaces -l chart=eks-claims
```

### Common Issues

1. **Claims not creating**: Check if XRDs are properly installed
2. **Namespace conflicts**: Ensure claim names are unique
3. **RBAC issues**: Verify service account has permissions to create claims

## Chart Development

### Testing locally
```bash
# Dry run to see generated manifests
helm template my-eks-claims ./eks-claims-chart

# Install with debug
helm install my-eks-claims ./eks-claims-chart --debug --dry-run
``` 