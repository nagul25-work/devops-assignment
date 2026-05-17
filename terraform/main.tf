terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket       = "devops-assignment-tfstate-regal"
    key          = "devops-assignment/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}



provider "aws" {
  region = "ap-south-1"
}