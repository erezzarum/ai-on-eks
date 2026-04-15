```bash
unset CLUSTER_NAME
unset KARPENTER_NODE_IAM_ROLE
unset AZ
unset SUBNET_ID
unset SG_ID

export AZ="us-east-2a"
eval "$(
  terraform -chdir="./terraform/_LOCAL" output -json | jq -r --arg az "${AZ}" '
    "export CLUSTER_NAME=" + (.deployment_name.value),
    "export KARPENTER_NODE_IAM_ROLE=" + (.karpenter_node_iam_role.value),
    "export AZ=" + $az,
    "export SUBNET_ID=" + (.secondary_subnet_by_az.value[$az]),
    "export SG_ID=" + (.cluster_primary_security_group_id.value)
  '
)"

echo CLUSTER_NAME="$CLUSTER_NAME"
echo KARPENTER_NODE_IAM_ROLE="$KARPENTER_NODE_IAM_ROLE"
echo AZ="$AZ"
echo SUBNET_ID="$SUBNET_ID"
echo SG_ID="$SG_ID"
```

```bash
export DOLLAR='$'
envsubst < karpenter/p5.yaml | kubectl apply -f -
```

```yaml
kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
    name: fsxl-efa-${AZ}
provisioner: fsx.csi.aws.com
parameters:
    subnetId: "$SUBNET_ID"
    securityGroupIds: "$SG_ID"
    deploymentType: PERSISTENT_2
    perUnitStorageThroughput: "125"
    efaEnabled: "true"
    metadataConfigurationMode: "AUTOMATIC"
    automaticBackupRetentionDays: "0"
    fileSystemTypeVersion: "2.15"
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

kubectl apply -f - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fsxl-efa-${AZ}
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: fsxl-efa-${AZ}
  resources:
    requests:
      storage: 38400Gi
EOF
```