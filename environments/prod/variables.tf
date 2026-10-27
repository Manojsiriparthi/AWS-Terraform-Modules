variable "environment"          { type = string; default = "prod" }
variable "aws_region"           { type = string; default = "us-east-1" }
variable "vpc_cidr"             { type = string }
variable "public_subnet_cidrs"  { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "key_name"             { type = string; default = "devops" }
variable "public_key_path"      { type = string; default = "~/.ssh/id_rsa.pub" }
variable "instance_type"        { type = string }
variable "instance_count"       { type = number }
variable "kubernetes_version"   { type = string }
variable "node_instance_type"   { type = string }
variable "node_desired_count"   { type = number }
variable "node_min_count"       { type = number }
variable "node_max_count"       { type = number }
variable "db_instance_class"    { type = string }
variable "db_username"          { type = string; default = "admin" }
variable "replica_count"        { type = number }
variable "bucket_name_prefix"   { type = string; default = "terraform-learning" }
variable "alert_email_addresses" {
  description = "Email addresses for prod alerts (REQUIRED in prod)"
  type        = list(string)
}
