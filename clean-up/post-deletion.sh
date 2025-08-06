#!/bin/bash
# post-delete-cleanup.sh

CLUSTER_NAME="andy-cluster-xplane-eks-cluster"
REGION="ap-southeast-1"

# Clean up EKS cluster and associated resources
echo "Checking for EKS cluster: $CLUSTER_NAME"
EKS_CLUSTER=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query 'cluster.name' --output text 2>/dev/null || echo "")

if [ ! -z "$EKS_CLUSTER" ] && [ "$EKS_CLUSTER" != "None" ]; then
  echo "Found EKS cluster: $EKS_CLUSTER"
  
  # Delete node groups first
  echo "Checking for node groups..."
  NODE_GROUPS=$(aws eks list-nodegroups --region $REGION --cluster-name $CLUSTER_NAME --query 'nodegroups' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$NODE_GROUPS" ]; then
    echo "Found node groups: $NODE_GROUPS"
    for ng in $NODE_GROUPS; do
      echo "Deleting node group: $ng"
      aws eks delete-nodegroup --region $REGION --cluster-name $CLUSTER_NAME --nodegroup-name $ng
    done
    
    # Wait for node groups to be deleted
    echo "Waiting for node groups to be deleted..."
    for ng in $NODE_GROUPS; do
      aws eks wait nodegroup-deleted --region $REGION --cluster-name $CLUSTER_NAME --nodegroup-name $ng
      echo "Node group $ng deleted."
    done
  else
    echo "No node groups found."
  fi
  
  # Delete Fargate profiles
  echo "Checking for Fargate profiles..."
  FARGATE_PROFILES=$(aws eks list-fargate-profiles --region $REGION --cluster-name $CLUSTER_NAME --query 'fargateProfileNames' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$FARGATE_PROFILES" ]; then
    echo "Found Fargate profiles: $FARGATE_PROFILES"
    for fp in $FARGATE_PROFILES; do
      echo "Deleting Fargate profile: $fp"
      aws eks delete-fargate-profile --region $REGION --cluster-name $CLUSTER_NAME --fargate-profile-name $fp
    done
    
    # Wait for Fargate profiles to be deleted
    echo "Waiting for Fargate profiles to be deleted..."
    for fp in $FARGATE_PROFILES; do
      aws eks wait fargate-profile-deleted --region $REGION --cluster-name $CLUSTER_NAME --fargate-profile-name $fp
      echo "Fargate profile $fp deleted."
    done
  else
    echo "No Fargate profiles found."
  fi
  
  # Delete addons
  echo "Checking for EKS addons..."
  ADDONS=$(aws eks list-addons --region $REGION --cluster-name $CLUSTER_NAME --query 'addons' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$ADDONS" ]; then
    echo "Found addons: $ADDONS"
    for addon in $ADDONS; do
      echo "Deleting addon: $addon"
      aws eks delete-addon --region $REGION --cluster-name $CLUSTER_NAME --addon-name $addon
    done
    
    # Wait for addons to be deleted
    echo "Waiting for addons to be deleted..."
    sleep 30  # Give some time for addons to start deletion
  else
    echo "No addons found."
  fi
  
  # Finally delete the cluster
  echo "Deleting EKS cluster: $CLUSTER_NAME"
  aws eks delete-cluster --region $REGION --name $CLUSTER_NAME
  
  # Wait for cluster to be deleted
  echo "Waiting for EKS cluster to be deleted..."
  aws eks wait cluster-deleted --region $REGION --name $CLUSTER_NAME
  echo "EKS cluster $CLUSTER_NAME deleted."
else
  echo "No EKS cluster found with name: $CLUSTER_NAME"
fi

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

# Clean up orphaned EFS filesystems
echo "Checking for orphaned EFS filesystems..."
ORPHANED_EFS=$(aws efs describe-file-systems \
  --region $REGION \
  --query "FileSystems[?Tags[?Key=='kubernetes.io/cluster/$CLUSTER_NAME' && Value=='owned']].FileSystemId" \
  --output text)

if [ ! -z "$ORPHANED_EFS" ]; then
  echo "Found orphaned EFS filesystems: $ORPHANED_EFS"
  for efs_id in $ORPHANED_EFS; do
    echo "Deleting mount targets for EFS: $efs_id"
    # First, delete all mount targets
    MOUNT_TARGETS=$(aws efs describe-mount-targets \
      --region $REGION \
      --file-system-id $efs_id \
      --query 'MountTargets[].MountTargetId' --output text)
    
    for mt in $MOUNT_TARGETS; do
      echo "Deleting mount target: $mt"
      aws efs delete-mount-target --region $REGION --mount-target-id $mt
    done
    
    # Wait for mount targets to be deleted
    echo "Waiting for mount targets to be deleted..."
    while [ $(aws efs describe-mount-targets --region $REGION --file-system-id $efs_id --query 'length(MountTargets)' --output text) -gt 0 ]; do
      echo "Still waiting for mount targets to be deleted..."
      sleep 10
    done
    
    # Now delete the EFS filesystem
    echo "Deleting EFS filesystem: $efs_id"
    aws efs delete-file-system --region $REGION --file-system-id $efs_id
    echo "Deleted EFS filesystem: $efs_id"
  done
else
  echo "No orphaned EFS filesystems found."
fi

# Clean up orphaned S3 buckets
echo "Checking for orphaned S3 buckets..."
# Look for buckets with cluster name in the bucket name or tags
ORPHANED_S3_BUCKETS=$(aws s3api list-buckets \
  --query "Buckets[?contains(Name, '$CLUSTER_NAME')].Name" \
  --output text)

# Also check for buckets with cluster tags
ALL_BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text)
for bucket in $ALL_BUCKETS; do
  # Check if bucket has cluster tag
  BUCKET_TAGS=$(aws s3api get-bucket-tagging --bucket $bucket 2>/dev/null || echo "")
  if echo "$BUCKET_TAGS" | grep -q "$CLUSTER_NAME"; then
    ORPHANED_S3_BUCKETS="$ORPHANED_S3_BUCKETS $bucket"
  fi
done

if [ ! -z "$ORPHANED_S3_BUCKETS" ]; then
  echo "Found orphaned S3 buckets: $ORPHANED_S3_BUCKETS"
  for bucket in $ORPHANED_S3_BUCKETS; do
    echo "Emptying S3 bucket: $bucket"
    # First empty the bucket (delete all objects and versions)
    aws s3 rm s3://$bucket --recursive 2>/dev/null || echo "Could not empty bucket $bucket"
    
    # Delete all object versions if versioning is enabled
    aws s3api delete-objects --bucket $bucket \
      --delete "$(aws s3api list-object-versions --bucket $bucket \
      --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
      --output json 2>/dev/null)" 2>/dev/null || echo "No versions to delete in $bucket"
    
    # Delete all delete markers
    aws s3api delete-objects --bucket $bucket \
      --delete "$(aws s3api list-object-versions --bucket $bucket \
      --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
      --output json 2>/dev/null)" 2>/dev/null || echo "No delete markers in $bucket"
    
    # Now delete the bucket
    echo "Deleting S3 bucket: $bucket"
    aws s3api delete-bucket --bucket $bucket --region $REGION 2>/dev/null || echo "Could not delete bucket $bucket (may have remaining objects or policies)"
    echo "Attempted to delete S3 bucket: $bucket"
  done
else
  echo "No orphaned S3 buckets found."
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