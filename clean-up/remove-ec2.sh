aws ec2 terminate-instances \
    --region ap-southeast-1 \
    --instance-ids $(aws ec2 describe-instances \
        --region ap-southeast-1 \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)