environment = "test"
aws_region  = "us-east-1"

vpc_cidr             = "10.1.0.0/16"
public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

key_name       = "devops"
instance_type  = "t3.medium"
instance_count = 1

kubernetes_version = "1.29"
node_instance_type = "t3.medium"
node_desired_count = 2
node_min_count     = 1
node_max_count     = 4

db_username       = "admin"
db_instance_class = "db.t3.small"
replica_count     = 2

bucket_name_prefix    = "terraform-learning"
alert_email_addresses = []
