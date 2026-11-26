terraform {
  backend "s3" {
    bucket       = "novasphere-tfstate-725800966484"
    key          = "novasphere/dev/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}
