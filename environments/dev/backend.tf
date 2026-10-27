# ==============================================================================
# ENVIRONMENT: dev — Backend Configuration
#
# CONCEPT: Remote state backend
# Terraform stores its state (.tfstate) remotely in S3 so that:
#   1. Multiple team members share the same state
#   2. State is never lost if your laptop dies
#   3. DynamoDB provides a lock so two applies can't run simultaneously
#
# SETUP (one-time, before first apply):
#   1. Create S3 bucket:   aws s3api create-bucket --bucket terraform-state-dev-<yourname>
#   2. Enable versioning:  aws s3api put-bucket-versioning ...
#   3. Create DynamoDB:    aws dynamodb create-table --table-name terraform-lock-dev ...
#
# Each environment (dev/test/prod) uses a DIFFERENT key (state file path)
# so their states are completely isolated.
# ==============================================================================

# Note: The actual backend block is declared in providers.tf using `backend "s3" {}`
# with an empty body. The values below are passed at init time:
#
#   terraform init \
#     -backend-config="bucket=terraform-state-YOUR_ACCOUNT-dev" \
#     -backend-config="key=dev/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=terraform-lock-dev" \
#     -backend-config="encrypt=true"
#
# OR store them in this file and fill in your values:

# Uncomment and fill in to hard-code the backend (not recommended for shared repos):
#
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-YOUR_ACCOUNT_ID-dev"
#     key            = "dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-lock-dev"
#     encrypt        = true
#   }
# }
