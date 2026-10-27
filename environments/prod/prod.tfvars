environment = "prod"
aws_region  = "us-east-1"

vpc_cidr             = "10.2.0.0/16"
public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24"]
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24"]

key_name       = "devops"
instance_type  = "t3.large"
instance_count = 2

kubernetes_version = "1.29"
node_instance_type = "t3.large"
node_desired_count = 3
node_min_count     = 2
node_max_count     = 8

db_username       = "admin"
db_instance_class = "db.t3.medium"
replica_count     = 2

bucket_name_prefix = "terraform-learning"

# REQUIRED in prod — add real email(s) to receive CloudWatch alarm notifications
alert_email_addresses = ["ops@example.com"]
