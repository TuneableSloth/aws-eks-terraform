variable "region" {
  default     = "eu-west-1"
  description = "AWS region"
}

locals {
  cluster_name = "my-bb-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

variable "namespace" {
  default        = "jenkins"
  description = "Namespace to where deploy CI/CD"
}

variable "jenkins_name" {
  default        = "jenkins"
  description = "Multiple applications to deploy"
}