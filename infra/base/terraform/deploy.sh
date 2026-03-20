#!/bin/bash
#
# deploy.sh — Terraform lifecycle wrapper for the AI on EKS infrastrucutre stack
#
# Manages S3 remote state backend creation, Terraform init/plan/apply/destroy, and local file cleanup.
#
# Prerequisites:
#   - AWS CLI configured with valid credentials (aws sts get-caller-identity must work)
#   - Terraform installed and available on PATH
#   - jq installed (used to parse AWS CLI JSON output)
#
# Commands:
#   ./deploy.sh bootstrap        Create the S3 bucket for Terraform remote state.
#                                 The bucket is created with versioning, AES-256 encryption,
#                                 and all public access blocked. Safe to run multiple times;
#                                 skips creation if the bucket already exists.
#                                 (default: ai-on-eks-tfstate-<account-id>-<region>)
#
#   ./deploy.sh init [upgrade]   Initialize Terraform with the S3 backend.
#                                 Pass "true" as a second argument to run with -upgrade
#                                 (useful after changing provider versions).
#
#   ./deploy.sh plan             Run terraform plan. Automatically includes
#                                 ../blueprint.tfvars if the file exists.
#
#   ./deploy.sh apply [auto]     Apply the infrastructure. Modules are applied in
#                                 dependency order (VPC, VPC Endpoints, EKS, Karpenter,
#                                 ArgoCD) before a final full apply to catch everything
#                                 else. Pass "false" to disable -auto-approve and get
#                                 an interactive confirmation prompt for each step.
#
#   ./deploy.sh destroy [auto]   Tear down all resources. kubectl_manifest resources
#                                 are destroyed first (except the ALB controller) to
#                                 avoid ordering issues, then the remaining infra is
#                                 destroyed. Pass "false" to disable -auto-approve.
#
#   ./deploy.sh cleanup          Remove local .terraform directories and
#                                 .terraform.lock.hcl files from the working tree.
#
#   --dry-run                     Can be added to any command to print the terraform
#                                 commands instead of executing them.
#                                 e.g. ./deploy.sh plan --dry-run
#
#   --var-file=<path>             Supply an additional .tfvars file. Can be specified
#                                 multiple times. Passed as -var-file to terraform.
#                                 e.g. ./deploy.sh plan --var-file=custom.tfvars
#
# Configuration:
#   The script reads configuration from environment variables and falls back to
#   sensible defaults. If ../blueprint.tfvars exists it is automatically passed
#   as -var-file to plan, apply, and destroy.
#
#   DEPLOYMENT_NAME  — Name of the stack. Resolved in order:
#                      1. DEPLOYMENT_NAME env var
#                      2. terraform output "deployment_name" (if state exists)
#                      3. "name" field in ../blueprint.tfvars
#                      4. Falls back to "ai-stack"
#   AWS_REGION       — Target AWS region (default: us-east-1)
#   TF_STATE_BUCKET  — S3 bucket for remote state
#                      (default: ai-on-eks-tfstate-<account-id>-<region>)
#   TF_STATE_PATH    — Key path inside the bucket
#                      (default: ai-on-eks/<deployment-name>.tfstate)
#
# Typical first-time workflow:
#   ./deploy.sh bootstrap   # one-time: create the state bucket
#   ./deploy.sh init        # initialize terraform
#   ./deploy.sh plan        # preview changes
#   ./deploy.sh apply       # deploy the stack
#
# Tear down:
#   ./deploy.sh destroy     # destroy all resources
#   ./deploy.sh cleanup     # optional: remove local terraform files
#

set -e
# set -x

# Function to check if S3 bucket exists
check_s3_bucket() {
  local bucket_name="$1"
  local region="$2"
  if aws s3api head-bucket --bucket "$bucket_name" --region "$region" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Create S3 bucket for Terraform state backend
create_s3_backend() {
  local bucket_name="$1"
  local region="$2"

  if check_s3_bucket "$bucket_name" "$region"; then
    echo "S3 bucket $bucket_name already exists"
  else
    echo "Creating S3 bucket $bucket_name for Terraform state backend..."
    if [ "$region" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$bucket_name" --region "$region"
    else
      aws s3api create-bucket --bucket "$bucket_name" --region "$region" --create-bucket-configuration LocationConstraint=$region
    fi
    aws s3api put-bucket-ownership-controls --bucket "$bucket_name" --region "$region" --ownership-controls Rules="[{ObjectOwnership=BucketOwnerPreferred}]"
    aws s3api put-bucket-acl --bucket "$bucket_name" --region "$region" --acl private
    aws s3api put-public-access-block --bucket "$bucket_name" --region "$region" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    aws s3api put-bucket-versioning --bucket "$bucket_name" --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption --bucket "$bucket_name" --region "$region" --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }'
    echo "S3 bucket $bucket_name created successfully with versioning, encryption, and public access blocked"
  fi
}

terraform_init() {
    local bucket_name="$1"
    local region="$2"
    local tfstate_path="$3"
    local upgrade="${4:-false}"

    local init_args="-input=false -backend=true"
    if [[ "$upgrade" == "true" ]]; then
        init_args="$init_args -upgrade"
    fi
    cat > backend.tf <<EOF
terraform {
  backend "s3" {}
}
EOF

    terraform init \
      $init_args \
      -backend-config="region=$region" \
      -backend-config="bucket=$bucket_name" \
      -backend-config="key=$tfstate_path"
}

# Wrapper around the terraform binary.
# Automatically injects all var files from EXTRA_VAR_FILES.
# Usage: run_terraform <subcommand> [extra args...]
#   e.g. run_terraform plan -input=false
#        run_terraform apply -input=false -auto-approve -target="module.vpc"
run_terraform() {
    local args=("$@")

    for vf in "${EXTRA_VAR_FILES[@]}"; do
      args+=("-var-file=$vf")
    done

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      echo terraform "${args[@]}"
    else
      terraform "${args[@]}"
    fi
}

terraform_plan() {
    run_terraform plan -input=false
}

terraform_apply() {
    local auto_approve="${1:-true}"
    local targets=(
      "module.vpc"
      "module.vpc_endpoints"
      "module.eks"
      "module.karpenter"
      "module.argocd"
    )

    local base_args=(apply -input=false)

    if [[ "$auto_approve" == "true" ]]; then
        base_args+=(-auto-approve)
    fi

    if [[ ${#targets[@]} -gt 0 ]]; then
        for target in "${targets[@]:0}"; do
            echo "Applying module $target..."
            apply_output=$(run_terraform "${base_args[@]}" -target="$target" 2>&1 | tee /dev/tty)
            if [[ $DRY_RUN == "false" ]]; then
              if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
                echo "SUCCESS: Terraform apply of $target completed successfully"
              else
                echo "FAILED: Terraform apply of $target failed"
                exit 1
              fi
            fi
        done
    fi

    echo "Applying remaining resources..."
    apply_output=$(run_terraform "${base_args[@]}" 2>&1 | tee /dev/tty)
    if [[ $DRY_RUN == "false" ]]; then
      if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
        echo "SUCCESS: Terraform apply of all modules completed successfully"
      else
        echo "FAILED: Terraform apply of all modules failed"
        exit 1
      fi
    fi
}

terraform_destroy() {
  local auto_approve="${1:-true}"

  local base_args=(destroy -input=false)

  if [[ "$auto_approve" == "true" ]]; then
      base_args+=(-auto-approve)
  fi

  echo "Destroying Terraform $DEPLOYMENT_NAME"

  TMPFILE=$(mktemp)
  if terraform output -raw configure_kubectl > "$TMPFILE" 2>/dev/null && [[ ! $(cat "$TMPFILE") == *"No outputs found"* ]]; then
    source "$TMPFILE"
    kubectl delete rayjob -A --all || true
    kubectl delete rayservice -A --all || true
  else
    echo "No outputs found, skipping kubectl delete"
  fi
  rm -f "$TMPFILE"

  targets=($(terraform state list | grep "kubectl_manifest\." | grep -v "kubectl_manifest.aws_load_balancer_controller"))

  if [ ${#targets[@]} -gt 0 ]; then
    echo "Destroying kubectl_manifest resources..."
    local target_args=()
    for target in "${targets[@]}"; do
      target_args+=(-target="$target")
    done

    destroy_output=$(run_terraform "${base_args[@]}" "${target_args[@]}" 2>&1 | tee /dev/tty)
    if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
      echo "SUCCESS: Terraform destroy of kubectl_manifest resources completed successfully"
    else
      echo "FAILED: Terraform destroy of kubectl_manifest resources failed"
      exit 1
    fi
  fi

  echo "Destroying remaining resources..."
  destroy_output=$(run_terraform "${base_args[@]}" 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $destroy_output == *"Destroy complete"* ]]; then
    echo "SUCCESS: Terraform destroy of all modules completed successfully"
  else
    echo "FAILED: Terraform destroy of all modules failed"
    exit 1
  fi

  echo "Cleaning up PVCs and EBS volumes for deployment: $DEPLOYMENT_NAME"
  # Get the list of EBS volumes with the Blueprint tag
  VOLUME_IDS=$(aws ec2 describe-volumes --region "$AWS_REGION" --filters "Name=tag:kubernetes.io/cluster/${DEPLOYMENT_NAME},Values=owned" --query "Volumes[].VolumeId" --output text | tr '\t' '\n')

  if [ -n "$VOLUME_IDS" ]; then
    while IFS= read -r volume_id; do
      # Get the PVC name from the volume tags
      PVC_NAME=$(aws ec2 describe-volumes --region "$AWS_REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/name'].Value" --output text)
      PVC_NAMESPACE=$(aws ec2 describe-volumes --region "$AWS_REGION" --volume-ids "$volume_id" --query "Volumes[0].Tags[?Key=='kubernetes.io/created-for/pvc/namespace'].Value" --output text)

      echo "Deleting EBS volume: $volume_id, PVC: ${PVC_NAME}, Namespace: ${PVC_NAMESPACE}"
      aws ec2 delete-volume --region "$AWS_REGION" --volume-id "$volume_id"
    done <<< "$VOLUME_IDS"
  else
    echo "No EBS volumes found for deployment : $DEPLOYMENT_NAME"
  fi
}

terraform_cleanup() {
    echo "Cleanup terraform working files"
    find . -type d -name ".terraform" -prune -exec rm -rf {} \;
	  find . -type f -name ".terraform.lock.hcl" -prune -exec rm -f {} \;
    rm -f backend.tf
}

# Create the S3 bucket for Terraform state
bootstrap() {
    local bucket_name="$1"
    local region="$2"
    create_s3_backend "$bucket_name" "$region"
}

# Get the deployment name from terraform output, var files, environment variable or default
get_deployment_name() {
  local name

  # Try terraform output first (warning may appear on stdout, so filter it out)
  name=$(terraform output -raw deployment_name 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$name" ] && ! echo "$name" | grep -q "No outputs found"; then
    echo "$name"
    return
  fi

  # Fallback to var files (includes ../blueprint.tfvars if present)
  for vf in "${EXTRA_VAR_FILES[@]}"; do
    name=$(grep '^\s*name\s*=' "$vf" | awk -F'"' '{print $2}')
    [ -n "$name" ] && echo "$name" && return
  done

  # Fallback to DEPLOYMENT_NAME env var, then default: ai-stack
  echo "${DEPLOYMENT_NAME:-ai-stack}"
}

# Get the region to use for both tfstate and deployment
# First match:
# 1. "region" variable available in tfvars file supplied via "--var-file" (first match)
# 2. "AWS_REGION" environment variable set
# 3. default region: us-west-2
get_region() {
  local region

  # Try var files (includes ../blueprint.tfvars if present)
  for vf in "${EXTRA_VAR_FILES[@]}"; do
    region=$(grep '^\s*region\s*=' "$vf" | awk -F'"' '{print $2}')
    [ -n "$region" ] && echo "$region" && return
  done

  # Fallback to AWS_REGION env var, then default: us-west-2
  echo "${AWS_REGION:-us-west-2}"
}

# Parse --dry-run and --var-file flags from arguments
DRY_RUN="false"
EXTRA_VAR_FILES=()

# Auto-include ../blueprint.tfvars if it exists
if [ -f "../blueprint.tfvars" ]; then
  EXTRA_VAR_FILES+=("../blueprint.tfvars")
fi

args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="true" ;;
    --var-file=*)
      vf="${arg#--var-file=}"
      if [ ! -f "$vf" ]; then
        echo "ERROR: var-file '$vf' not found"
        exit 1
      fi
      EXTRA_VAR_FILES+=("$vf")
      ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

DEPLOYMENT_NAME="$(get_deployment_name)"
AWS_REGION="$(get_region)"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output json | jq -r '.Account')
TF_STATE_BUCKET="${TF_STATE_BUCKET:-ai-on-eks-tfstate-$AWS_ACCOUNT_ID-$AWS_REGION}" # default bucket name: ai-on-eks-tfstate-<AWS ACCOUNT ID>-<AWS REGION>
TF_STATE_PATH="${TF_STATE_PATH:-ai-on-eks/${DEPLOYMENT_NAME}.tfstate}" # default state key: <deployment-name>.tfstate

export TF_VAR_name="$DEPLOYMENT_NAME"
export TF_VAR_region="$AWS_REGION"

echo "Using DEPLOYMENT_NAME=${DEPLOYMENT_NAME}, AWS_REGION=${AWS_REGION} EXTRA_VAR_FILES=${EXTRA_VAR_FILES[@]}"
echo "Terraform state: s3://${TF_STATE_BUCKET}/${TF_STATE_PATH}"

# Parse command line arguments
case "${1:-}" in
  "init")
    echo "Initializing Terraform..."
    upgrade="${2:-false}"
    terraform_init "$TF_STATE_BUCKET" "$AWS_REGION" "$TF_STATE_PATH" "$upgrade"
    ;;
  "plan")
    echo "Planning Terraform changes..."
    terraform_plan
    ;;
  "apply")
    echo "Applying Terraform changes..."
    auto_approve="${2:-true}"
    terraform_apply "$auto_approve"
    ;;
  "destroy")
    echo "Destroying Terraform resources..."
    auto_approve="${2:-true}"
    terraform_destroy "$auto_approve"
    ;;
  "cleanup")
    echo "Cleaning up Terraform local files..."
    terraform_cleanup
    ;;
  "bootstrap")
    echo "Bootstrapping..."
    bootstrap "$TF_STATE_BUCKET" "$AWS_REGION"
    ;;
  *)
    echo "Usage: $0 [--dry-run] [--var-file=<path>] {init|plan|apply|destroy|cleanup|bootstrap}"
    echo "  --dry-run              - Print terraform commands instead of executing them"
    echo "  --var-file=<path>      - Additional .tfvars file (can be repeated)"
    echo "  init [upgrade]  - Initialize Terraform with S3 backend (pass 'true' for upgrade)"
    echo "  plan            - Plan Terraform changes"
    echo "  apply           - Apply Terraform changes"
    echo "  destroy         - Destroy Terraform resources"
    echo "  cleanup         - Clean up Terraform local files"
    echo "  bootstrap       - Create S3 bucket for Terraform state"
    exit 1
    ;;
esac
