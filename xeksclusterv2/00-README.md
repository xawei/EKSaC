# xEksCluster v2 (xeksclusters.consumable.trustbank.sg)

## Crossplane v2 Namespaced Composite Resources

This is the updated version of xEksCluster for **Crossplane v2**, which takes advantage of the new **namespaced composite resources** feature. In Crossplane v2, composite resources can be created directly in namespaces, eliminating the need for separate Claims.

## Key Changes from v1

- **No Claims Required**: Create composite resources directly in namespaces
- **Simplified Architecture**: No need for separate Claim and XR resources
- **Namespace Isolation**: Resources are scoped to specific namespaces
- **Direct XR Creation**: Users can create XRs directly with `metadata.namespace`

## Anatomy of xEksCluster

This is the EKSaC EKS cluster component which includes:
- ProviderConfigs for
  - Helm to the target cluster
  - Kubernetes to the target cluster
- 3 private subnets which is connected to the DefaultRouteTable with 0.0.0.0/0 routed to NATGateway
- Resources to create an EKS cluster
  - IAM Role for EKS cluster
  - SecurityGroups and Rules for
    - Control Plane to Nodes communication
    - Nodes to Control Plane communication
    - Nodes to Nodes communication
    - Nodes egress
    - EKS cluster
    - coredns addon and customisation
    - VPC CNI addon and customisation
    - Kube Proxy addon and customisation
    - AWS EBS CSI addon requirements and customisation
      - IAM Role for AWS EBS CSI
    - OIDC provider for the EKS cluster
- The Cluster Auth is also stored into a Kubernetes Secret in `eksac` namespace. This is referenced by ProviderConfigs for Helm and Kubernetes to the target cluster
- Fargate for EKS cluster to run Karpenter
  - IAM Role for Fargate pod execution
  - Fargate profile for Karpenter
  - IAM Policy and Role for Karpenter
  - `aws-auth` ConfigMap data Karpenter
  - Helm installation of Karpenter
  - Karpenter related resources
    - default EC2NodeClass for Karpenter
    - arm64 NodePool for Karpenter
    - amd64 NodePool for Karpenter
  - Resources for restarting Karpenter hourly
    - Kubernetes Role, ServiceAccount and RoleBinding for restarting Karpenter deployment
    - Kubernetes Cronjob to restart Karpenter deployment hourly

## Example Usage (Crossplane v2)

### Creating a Namespaced XR

```yaml
apiVersion: consumable.trustbank.sg/v1alpha1
kind: xEksClusterV2
metadata:
  name: eksac-cluster01
  namespace: my-team-namespace  # XR is created in this namespace
spec:
  name: eksac-cluster01
  location: "ap-southeast-1"
  awsAccountId: "390945758345"
  vpcRef: sandbox-eksac01
  subnets:
    private:
      z1Cidr: "10.0.0.64/26"
      z2Cidr: "10.0.0.128/26"
      z3Cidr: "10.0.0.192/26"
  components:
    eks:
      version: "1.28"
    corednsAddOn:
      version: "v1.10.1-eksbuild.11"
    vpccniAddOn:
      version: "v1.18.2-eksbuild.1"
    kubeproxyAddOn:
      version: "v1.28.8-eksbuild.5"
    ebscsiAddOn:
      version: "v1.32.0-eksbuild.1"
    karpenterHelm:
      version: "0.37.0"
```

### Benefits of Crossplane v2 Approach

1. **Simplified Workflow**: No need to manage separate Claims and XRs
2. **Namespace Isolation**: Resources are scoped to specific namespaces for better organization
3. **Direct Control**: Users can directly create and manage composite resources
4. **Reduced Complexity**: Eliminates the claim-to-XR mapping complexity
5. **Better GitOps**: No ArgoCD warnings about XR mutations since there's no separate claim

## Deployment

Apply the XRD and Composition files:

```bash
kubectl apply -f 01-xrd-v2.yaml
kubectl apply -f 02-composition-v2.yaml
```

Then create your namespaced XR:

```bash
kubectl apply -f your-cluster-config.yaml
```

## Monitoring

Check the status of your XR:

```bash
kubectl get xeksclustersv2 -n my-team-namespace
kubectl describe xeksclusterv2 eksac-cluster01 -n my-team-namespace
```

## Available XRD and Composition Variations

This folder contains multiple XRD and Composition variations:

- `01-xrd-v2.yaml` - Standard XRD
- `01-xrd-kcl-v2.yaml` - KCL-based XRD
- `02-composition-v2.yaml` - Standard Composition
- `02-composition-kcl-v2.yaml` - KCL-based Composition

Choose the appropriate pair based on your templating preference and requirements. 