terraform {
  required_version = ">= 1.0.0"

  required_providers {
    alks = {
      source  = "Cox-Automotive/alks"
      version = "~>2.8.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
  }
}
