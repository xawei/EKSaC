# switch to control plane cluster and execute
kubectl delete basecomponent.consumable.trustbank.sg --all -n eksac
kubectl delete eksclusterkcl.consumable.trustbank.sg --all -n eksac
kubectl delete networkkcl.consumable.trustbank.sg --all -n eksac
