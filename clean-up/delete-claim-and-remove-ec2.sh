# switch to control plane cluster and execute
kubectl delete basecomponent.consumable.trustbank.sg --all -n eksac
kubectl delete eksclusterv3.consumable.trustbank.sg --all -n eksac
kubectl delete networkkcl.consumable.trustbank.sg --all -n eksac

# sleep for 10 seconds
sleep 30

aws ec2 terminate-instances \
    --region ap-southeast-1 \
    --instance-ids $(aws ec2 describe-instances \
        --region ap-southeast-1 \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)