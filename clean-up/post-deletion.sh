#!/bin/bash
# post-delete-cleanup.sh

CLUSTER_NAME="andy-cluster-xplane-eks-cluster"
REGION="ap-southeast-1"

# Set AWS CLI timeout
export AWS_CLI_READ_TIMEOUT=60
export AWS_CLI_CONNECT_TIMEOUT=30

# Function to check AWS CLI connectivity
check_aws_connectivity() {
  echo "Checking AWS connectivity..."
  if ! aws sts get-caller-identity --region $REGION --output text >/dev/null 2>&1; then
    echo "ERROR: Cannot connect to AWS. Please check your credentials and network connection."
    exit 1
  fi
  echo "AWS connectivity confirmed."
}

# Check AWS connectivity first
check_aws_connectivity

# Clean up EKS cluster and associated resources FIRST
echo "Checking for EKS cluster: $CLUSTER_NAME"
echo "This may take a moment..."

# Check if cluster exists (increased timeout)
EKS_CLUSTER=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query 'cluster.name' --output text 2>/dev/null || echo "")

if [ ! -z "$EKS_CLUSTER" ] && [ "$EKS_CLUSTER" != "None" ] && [ "$EKS_CLUSTER" != "null" ]; then
  echo "Found EKS cluster: $EKS_CLUSTER"
  
  # Delete node groups first
  echo "Checking for node groups..."
  NODE_GROUPS=$(aws eks list-nodegroups --region $REGION --cluster-name $CLUSTER_NAME --query 'nodegroups' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$NODE_GROUPS" ] && [ "$NODE_GROUPS" != "None" ]; then
    echo "Found node groups: $NODE_GROUPS"
    for ng in $NODE_GROUPS; do
      echo "Deleting node group: $ng"
      aws eks delete-nodegroup --region $REGION --cluster-name $CLUSTER_NAME --nodegroup-name $ng
    done
    
    # Wait for node groups to be deleted
    echo "Waiting for node groups to be deleted..."
    for ng in $NODE_GROUPS; do
      echo "Waiting for node group $ng to be deleted..."
      aws eks wait nodegroup-deleted --region $REGION --cluster-name $CLUSTER_NAME --nodegroup-name $ng || echo "Timeout or error waiting for $ng deletion"
      echo "Node group $ng deletion process completed."
    done
  else
    echo "No node groups found."
  fi
  
  # Delete Fargate profiles
  echo "Checking for Fargate profiles..."
  FARGATE_PROFILES=$(aws eks list-fargate-profiles --region $REGION --cluster-name $CLUSTER_NAME --query 'fargateProfileNames' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$FARGATE_PROFILES" ] && [ "$FARGATE_PROFILES" != "None" ]; then
    echo "Found Fargate profiles: $FARGATE_PROFILES"
    for fp in $FARGATE_PROFILES; do
      echo "Deleting Fargate profile: $fp"
      aws eks delete-fargate-profile --region $REGION --cluster-name $CLUSTER_NAME --fargate-profile-name $fp
    done
    
    # Wait for Fargate profiles to be deleted
    echo "Waiting for Fargate profiles to be deleted..."
    for fp in $FARGATE_PROFILES; do
      echo "Waiting for Fargate profile $fp to be deleted..."
      aws eks wait fargate-profile-deleted --region $REGION --cluster-name $CLUSTER_NAME --fargate-profile-name $fp || echo "Timeout or error waiting for $fp deletion"
      echo "Fargate profile $fp deletion process completed."
    done
  else
    echo "No Fargate profiles found."
  fi
  
  # Delete addons
  echo "Checking for EKS addons..."
  ADDONS=$(aws eks list-addons --region $REGION --cluster-name $CLUSTER_NAME --query 'addons' --output text 2>/dev/null || echo "")
  
  if [ ! -z "$ADDONS" ] && [ "$ADDONS" != "None" ]; then
    echo "Found addons: $ADDONS"
    for addon in $ADDONS; do
      echo "Deleting addon: $addon"
      aws eks delete-addon --region $REGION --cluster-name $CLUSTER_NAME --addon-name $addon
    done
    
    # Wait for addons to be deleted
    echo "Waiting for addons to be deleted..."
    sleep 60  # Give more time for addons to start deletion
  else
    echo "No addons found."
  fi
  
  # Finally delete the cluster
  echo "Deleting EKS cluster: $CLUSTER_NAME"
  aws eks delete-cluster --region $REGION --name $CLUSTER_NAME
  
  # Don't wait for cluster deletion here - let it run in background
  echo "EKS cluster deletion initiated. Continuing with other cleanup..."
else
  echo "No EKS cluster found with name: $CLUSTER_NAME"
fi

# Clean up any orphaned EC2 instances using AWS EKS cluster tag
echo "Checking for orphaned EC2 instances with EKS cluster tag..."
ORPHANED_INSTANCES=$(aws ec2 describe-instances \
  --region $REGION \
  --filters "Name=tag:aws:eks:cluster-name,Values=$CLUSTER_NAME" \
            "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")

if [ ! -z "$ORPHANED_INSTANCES" ]; then
  echo "Terminating orphaned instances: $ORPHANED_INSTANCES"
  aws ec2 terminate-instances --region $REGION --instance-ids $ORPHANED_INSTANCES
  echo "Instance termination initiated. Continuing with other cleanup..."
else
  echo "No orphaned instances found."
fi

# Clean up Crossplane managed resources
echo "Cleaning up Crossplane managed resources..."

# List of Crossplane resource types to clean up
CROSSPLANE_RESOURCES=(
  "object.kubernetes.crossplane.io"
  "release.helm.crossplane.io"
  "clusterauth.eks.aws.upbound.io"
  "accesspolicyassociation.eks.aws.upbound.io"
  "accessentry.eks.aws.upbound.io"
  "cluster.eks.aws.upbound.io"
)

# Function to remove finalizers and delete resources
cleanup_crossplane_resource() {
  local resource_type=$1
  echo "Checking for $resource_type resources..."
  
  # Get all resources of this type
  local resources=$(kubectl get $resource_type -o name 2>/dev/null || echo "")
  
  if [ ! -z "$resources" ]; then
    echo "Found $resource_type resources: $resources"
    
    for resource in $resources; do
      echo "Processing $resource..."
      
      # Remove finalizers
      echo "Removing finalizers from $resource"
      kubectl patch $resource -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || echo "Could not patch $resource"
      
      # Delete the resource
      echo "Deleting $resource"
      kubectl delete $resource --timeout=60s 2>/dev/null || echo "Could not delete $resource"
    done
  else
    echo "No $resource_type resources found."
  fi
}

# Clean up each resource type
for resource_type in "${CROSSPLANE_RESOURCES[@]}"; do
  cleanup_crossplane_resource $resource_type
done

# Wait a bit for resources to be cleaned up
echo "Waiting for Crossplane resources to be cleaned up..."
sleep 30

# Check if EKS cluster deletion is complete
echo "Checking EKS cluster deletion status..."
EKS_STATUS=$(aws eks describe-cluster --region $REGION --name $CLUSTER_NAME --query 'cluster.status' --output text 2>/dev/null || echo "DELETED")

if [ "$EKS_STATUS" != "DELETED" ] && [ ! -z "$EKS_STATUS" ] && [ "$EKS_STATUS" != "None" ]; then
  echo "EKS cluster is still being deleted (status: $EKS_STATUS). Waiting for completion..."
  aws eks wait cluster-deleted --region $REGION --name $CLUSTER_NAME || echo "Timeout or error waiting for cluster deletion"
  echo "EKS cluster $CLUSTER_NAME deletion process completed."
else
  echo "EKS cluster $CLUSTER_NAME has been deleted."
fi

# Check if EC2 instances are terminated
if [ ! -z "$ORPHANED_INSTANCES" ]; then
  echo "Waiting for EC2 instances to terminate..."
  aws ec2 wait instance-terminated --region $REGION --instance-ids $ORPHANED_INSTANCES || echo "Timeout or error waiting for instance termination"
  echo "All orphaned instances termination process completed."
fi

# Clean up orphaned EBS volumes
echo "Checking for orphaned EBS volumes..."
ORPHANED_VOLUMES=$(aws ec2 describe-volumes \
  --region $REGION \
  --filters "Name=tag:kubernetes.io/cluster/$CLUSTER_NAME,Values=owned" \
            "Name=status,Values=available" \
  --query 'Volumes[].VolumeId' --output text 2>/dev/null || echo "")

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
  --output text 2>/dev/null || echo "")

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
    timeout_count=0
    while [ $(aws efs describe-mount-targets --region $REGION --file-system-id $efs_id --query 'length(MountTargets)' --output text) -gt 0 ] && [ $timeout_count -lt 30 ]; do
      echo "Still waiting for mount targets to be deleted..."
      sleep 10
      ((timeout_count++))
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
  --output text 2>/dev/null || echo "")

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
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")

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