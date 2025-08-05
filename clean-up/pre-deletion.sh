#!/bin/bash
# pre-delete-cluster.sh

# Switch to eksac managed cluster and execute
# Maybe we can skip this pre-deletion, and just let post-deletion script to handle it

CLUSTER_NAME="andy-cluster-xplane-eks-cluster"

# 1. Delete LoadBalancer services first (they create AWS resources)
echo "Cleaning up LoadBalancer services..."
kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --timeout=300s

# 2. Scale down Karpenter NodePools (but don't wait for deletion)
echo "Scaling down Karpenter NodePools..."
kubectl patch nodepool infra-arm64 -p '{"spec":{"limits":{"cpu":"0"}}}' --type=merge
kubectl patch nodepool infra-amd64 -p '{"spec":{"limits":{"cpu":"0"}}}' --type=merge

echo "Pre-deletion cleanup completed. Karpenter will start draining nodes."
echo "You can now safely delete the cluster claims."