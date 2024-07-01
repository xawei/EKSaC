# XNetwork (xnetworks.comsumable.trustbank.sg)

## Anatomy of XNetwork
This is the EKSaC network component which includes:
- 1 VPC with CIDR provided in the `XR`
- 3 public subnets with CIDRs provided in the `XR`
- 1 Internet Gateway
- 1 RouteTable with
  - 1 Route to route all traffic to Internet Gateway
  - 3 RouteTableAssociation for public subnets
- 1 EIP for NatGateway
- 1 NatGateway
- Update the Default RouteTable to route all traffic to NatGateway.  Since the Default RouteTable routes all traffic to NatGateway, when new subnets are created the traffic will all route through NatGateway.

## Example of XNetwork (XR)
```yaml
apiVersion: consumable.trustbank.sg/v1alpha1
kind: xNetwork
metadata:
  name: sandbox-eksac01
spec:
  name: sandbox-eksac01
  location: "ap-southeast-1"
  vpcCidr: "10.0.0.0/22"
  subnets:
    public:
      z1Cidr: "10.0.0.0/28"
      z2Cidr: "10.0.0.16/28"
      z3Cidr: "10.0.0.32/28"
---
apiVersion: consumable.trustbank.sg/v1alpha1
kind: Network
metadata:
  name: sandbox-eksac01
spec:
  name: sandbox-eksac01
  resourceRef:
    apiVersion: consumable.trustbank.sg/v1alpha1
    kind: xNetwork
    name: sandbox-eksac01
```

Take note that the above is a workaround for ArgoCD due to the `XR` mutation that cause ArgoCD to have some warning.  Even though the mutation can be ignored in ArgoCD, it is decided that creating a `Claim` separated from `XR` is a better solution.  Instead of the above combined `Claim` and `XR` yamls, we can just create a `Claim`:
```yaml
apiVersion: consumable.trustbank.sg/v1alpha1
kind: Network
metadata:
  name: sandbox-eksac01
spec:
  name: sandbox-eksac01
  location: "ap-southeast-1"
  vpcCidr: "10.0.0.0/22"
  subnets:
    public:
      z1Cidr: "10.0.0.0/28"
      z2Cidr: "10.0.0.16/28"
      z3Cidr: "10.0.0.32/28"
  resourceRef:
    apiVersion: consumable.trustbank.sg/v1alpha1
    kind: xNetwork
    name: sandbox-eksac01
```