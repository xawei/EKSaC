# xNetwork v2 (xnetworks.consumable.trustbank.sg)

## Crossplane v2 Namespaced Composite Resources

This is the updated version of xNetwork for **Crossplane v2**, which takes advantage of the new **namespaced composite resources** feature. In Crossplane v2, composite resources can be created directly in namespaces, eliminating the need for separate Claims.

## Key Changes from v1

- **No Claims Required**: Create composite resources directly in namespaces
- **Simplified Architecture**: No need for separate Claim and XR resources
- **Namespace Isolation**: Resources are scoped to specific namespaces
- **Direct XR Creation**: Users can create XRs directly with `metadata.namespace`

## Anatomy of xNetwork

This is the EKSaC network component which includes:
- 1 VPC with CIDR provided in the `XR`
- 3 public subnets with CIDRs provided in the `XR`
- 1 Internet Gateway
- 1 RouteTable with
  - 1 Route to route all traffic to Internet Gateway
  - 3 RouteTableAssociation for public subnets
- 1 EIP for NatGateway
- 1 NatGateway
- Update the Default RouteTable to route all traffic to NatGateway. Since the Default RouteTable routes all traffic to NatGateway, when new subnets are created the traffic will all route through NatGateway.

## Example Usage (Crossplane v2)

### Creating a Namespaced XR

```yaml
apiVersion: consumable.trustbank.sg/v1alpha1
kind: xNetworkV2
metadata:
  name: sandbox-eksac01
  namespace: my-team-namespace  # XR is created in this namespace
spec:
  name: sandbox-eksac01
  location: "ap-southeast-1"
  vpcCidr: "10.0.0.0/22"
  subnets:
    public:
      z1Cidr: "10.0.0.0/28"
      z2Cidr: "10.0.0.16/28"
      z3Cidr: "10.0.0.32/28"
```

### Benefits of Crossplane v2 Approach

1. **Simplified Workflow**: No need to manage separate Claims and XRs
2. **Namespace Isolation**: Resources are scoped to specific namespaces for better organization
3. **Direct Control**: Users can directly create and manage composite resources
4. **Reduced Complexity**: Eliminates the claim-to-XR mapping complexity
5. **Better GitOps**: No ArgoCD warnings about XR mutations since there's no separate claim
6. **No Workarounds**: The v1 approach required workarounds for ArgoCD due to XR mutations

## Deployment

Apply the XRD and Composition files:

```bash
kubectl apply -f 01-xrd-v2.yaml
kubectl apply -f 02-composition-v2.yaml
```

Then create your namespaced XR:

```bash
kubectl apply -f your-network-config.yaml
```

## Monitoring

Check the status of your XR:

```bash
kubectl get xnetworksv2 -n my-team-namespace
kubectl describe xnetworkv2 sandbox-eksac01 -n my-team-namespace
```

## Available XRD Variations

This folder contains multiple XRD and Composition variations:

- `01-xrd-v2.yaml` - Standard XRD
- `01-xrd-kcl-v2.yaml` - KCL-based XRD
- `01-xrd-gotemplating-v2.yaml` - Go templating-based XRD
- `02-composition-v2.yaml` - Standard Composition
- `02-composition-kcl-v2.yaml` - KCL-based Composition
- `02-composition-gotemplating-v2.yaml` - Go templating-based Composition

Choose the appropriate pair based on your templating preference and requirements. 