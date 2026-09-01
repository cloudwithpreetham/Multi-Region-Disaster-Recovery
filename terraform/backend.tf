# Remote state backend — bucket/table created by terraform/bootstrap/.
# Run bootstrap once first, grab its outputs, fill in the values below,
# then `terraform init -migrate-state` here to move local state over.
#
# Backend blocks can't use variables, so these are hardcoded — update
# after running bootstrap:
#   bucket = <state_bucket_name output>
#   dynamodb_table = <lock_table_name output>

terraform {
  backend "s3" {
    bucket         = "multi-region-dr-tfstate-799997637340"
    key            = "multi-region-dr/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "multi-region-dr-tfstate-lock"
    encrypt        = true
  }
}
