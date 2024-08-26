# xEksComponent (xekscomponents.comsumable.trustbank.sg)

## List of Components in this Cluster
1.  [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
1.  [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
1.  [Istio](https://istio.io/latest/)
    1.  `cacerts` is pre-generated with a self-signed intermediate CA
    1.  Istio is installed with `ambient` profile
    1.  The DaemonSets are patch to "not" run on Fargate
    1.  Istio is configured with meshID="mesh1", network="network1", clusterID=<clusterRef> in the XR
    1.  ** To create cross cluster access, please issue the command:
        ```
        istioctl -n istio-system create-remote-secret \
          --context="eksac-cluster02" \
          --name=eksac-cluster02 | \
          kubectl -n istio-system apply -f - --context=eksac-cluster01

        istioctl -n istio-system create-remote-secret \
          --context="eksac-cluster01" \
          --name=eksac-cluster01 | \
          kubectl -n istio-system apply -f - --context=eksac-cluster02
        ```