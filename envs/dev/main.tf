data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

module "web" {
  source = "git::https://github.com/Adam-Gouard/terraform-aws-novasphere-web.git?ref=v0.1.0"

  project               = "novasphere"
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnets
  ami_id                = data.aws_ami.al2023.id
  instance_type         = var.instance_type
  instance_profile_name = aws_iam_instance_profile.web.name
}
