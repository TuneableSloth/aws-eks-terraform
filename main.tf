terraform {
  required_version = ">= 0.12.9, != 0.13.0"
}

provider "aws" {
  region  = var.region
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

resource "aws_security_group" "worker_group_mgmt_one" {
  name_prefix = "worker_group_mgmt_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

resource "aws_security_group" "all_worker_mgmt" {
  name_prefix = "all_worker_management"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
      "172.16.0.0/12",
      "192.168.0.0/16",
    ]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  name                 = "my-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source       = "terraform-aws-modules/eks/aws"
  cluster_name    = local.cluster_name
  cluster_version = "1.17"
  subnets         = module.vpc.private_subnets
  cluster_create_timeout = "1h"
  cluster_endpoint_private_access = true 
  vpc_id = module.vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t2.micro"
      asg_desired_capacity          = 2
      asg_min_size                  = 1
      asg_max_size                  = 4
      additional_security_group_ids = [aws_security_group.worker_group_mgmt_one.id]
    }
  ]

  worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  
  # windows workaround
  wait_for_cluster_interpreter = ["C:/Program Files/Git/bin/sh.exe", "-c"]
  wait_for_cluster_cmd         = "until curl -sk $ENDPOINT >/dev/null; do sleep 4; done"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# -----------------------------------------------
# Deploy Jenkins CI with Helm Chart
# -----------------------------------------------

locals {
  namespace = var.namespace
  jenkins   = var.jenkins_name
}

resource kubernetes_namespace this {
  metadata {
    name = var.namespace

    labels = {
      name        = var.namespace
      description = "Continuous-integration-continuous-delivery"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "jenkins_release" {
  name       = "helm-jenkins"
  repository = "https://tuneablesloth.github.io/helm-jenkins/"
  chart      = "jenkins-bb-prg"
  verify     = false
  timeout    = 3000
  namespace = "default"
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }
}
