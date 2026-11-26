module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name           = "novasphere-${var.environment}"
  cidr           = "10.0.0.0/16"
  azs            = ["eu-west-3a", "eu-west-3b"]
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway      = false
  map_public_ip_on_launch = true
}
