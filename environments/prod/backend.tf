# terraform init \
#   -backend-config="bucket=terraform-state-YOUR_ACCOUNT_ID-prod" \
#   -backend-config="key=prod/terraform.tfstate" \
#   -backend-config="region=us-east-1" \
#   -backend-config="dynamodb_table=terraform-lock-prod" \
#   -backend-config="encrypt=true"
