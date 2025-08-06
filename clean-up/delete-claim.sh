# switch to control plane cluster and execute
kubectl delete basecomponent.consumable.trustbank.sg/andy-cluster-base-components -n eksac
kubectl delete eksclusterkcl.consumable.trustbank.sg/andy-cluster -n eksac
kubectl delete networkkcl.consumable.trustbank.sg/andy-network -n eksac
