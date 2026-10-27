# terraform init \
#   -backend-config="bucket=terraform-state-YOUR_ACCOUNT_ID-test" \
#   -backend-config="key=test/terraform.tfstate" \
#   -backend-config="region=us-east-1" \
#   -backend-config="dynamodb_table=terraform-lock-test" \
#   -backend-config="encrypt=true"
