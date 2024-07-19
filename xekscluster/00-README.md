# xEksCluster (xeksclusters.comsumable.trustbank.sg)

## Anatomy of xCluster
This is the EKSaC EKS cluster component which include:
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
- The Cluster Auth is also stored into a Kubernetes Secret in `eksac` namespace.  This is referenced by ProviderConfigs for Helm and Kubernetes to the target clustrer
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

## Example of xCluster (XR)
```yaml
apiVersion: consumable.trustbank.sg/v1alpha1
kind: xEksCluster
metadata:
  name: eksac-cluster01
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
---
apiVersion: consumable.trustbank.sg/v1alpha1
kind: EksCluster
metadata:
  name: eksac-cluster01
spec:
  name: eksac-cluster01
  resourceRef:
    apiVersion: consumable.trustbank.sg/v1alpha1
    kind: xEksCluster
    name: eksac-cluster01
```