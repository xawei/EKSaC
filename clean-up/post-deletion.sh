#!/bin/bash
# post-delete-cleanup.sh

CLUSTER_NAME="andy-cluster-xplane-eks-cluster"
REGION="ap-southeast-1"

# Clean up any orphaned EC2 instances using AWS EKS cluster tag
echo "Checking for orphaned EC2 instances with EKS cluster tag..."
ORPHANED_INSTANCES=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ ! -z "$ORPHANED_INSTANCES" ]; then
  echo "Terminating orphaned instances: $ORPHANED_INSTANCES"
  aws ec2 terminate-instances --region $REGION --instance-ids $ORPHANED_INSTANCES
  echo "Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --region $REGION --instance-ids $ORPHANED_INSTANCES
  echo "All orphaned instances terminated."
else
  echo "No orphaned instances found."
fi

# Clean up orphaned EBS volumes
echo "Checking for orphaned EBS volumes..."
ORPHANED_VOLUMES=$(aws ec2 describe-volumes \
  --region $REGION \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
            "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text)

if [ ! -z "$ORPHANED_VOLUMES" ]; then
  echo "Deleting orphaned volumes: $ORPHANED_VOLUMES"
  for volume in $ORPHANED_VOLUMES; do
    aws ec2 delete-volume --region $REGION --volume-id $volume
    echo "Deleted volume: $volume"
  done
else
  echo "No orphaned volumes found."
fi

# Clean up orphaned security groups (optional)
echo "Checking for orphaned security groups..."
ORPHANED_SGS=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)

if [ ! -z "$ORPHANED_SGS" ]; then
  echo "Found orphaned security groups: $ORPHANED_SGS"
  for sg in $ORPHANED_SGS; do
    echo "Attempting to delete security group: $sg"
    aws ec2 delete-security-group --region $REGION --group-id $sg 2>/dev/null || echo "Could not delete $sg (may have dependencies)"
  done
else
  echo "No orphaned security groups found."
fi

echo "Post-deletion cleanup completed."