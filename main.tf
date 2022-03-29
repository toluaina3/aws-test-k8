module "vpc" {
  source           = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-module-vpc"
  vpc-cidr-block   = "192.168.1.0/24"
  tag-name         = "test-vpc"
}

# attach internet gateway to the vpc for public subnet internet connection
module "internet-gateway" {
  source      = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-module-internet-gateway"
  ig-vpc-id   = module.vpc.vpc-network-id
  tag-name    = "test-internet-gateway"
}

# public subnet facing the internet
module "public-subnet" {
  source                  = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-modules-subnets"
  subnet-az               = "eu-west-2a"
  subnet-route-cidr       = "192.168.1.0/27"
  vpc-network             = module.vpc.vpc-network-id
  map-public-ip           = true
  tag-name                = "public-subnet-1"
}

module "public-subnet-2" {
  source                  = "./.terraform/modules/alb-frontend-public-subnet"
  subnet-az               = "eu-west-2b"
  subnet-route-cidr       = "192.168.1.32/27"
  vpc-network             = module.vpc.vpc-network-id
  map-public-ip           = true
  tag-name                = "public-subnet-2"
}

module "private-subnet" {
  source                  = "./.terraform/modules/alb-frontend-public-subnet"
  subnet-az               = "eu-west-2a"
  subnet-route-cidr       = "192.168.1.64/27"
  vpc-network             = module.vpc.vpc-network-id
  map-public-ip           = false
  tag-name                = "private-subnet-1"
}

module "private-subnet-2" {
  source                  = "./.terraform/modules/alb-frontend-public-subnet"
  subnet-az               = "eu-west-2b"
  subnet-route-cidr       = "192.168.1.96/27"
  vpc-network             = module.vpc.vpc-network-id
  map-public-ip           = false
  tag-name                = "private-subnet-2"
}

# nat gateway is in a public subnet, route private subnet traffic to the internet
resource "aws_nat_gateway" "private-nat-gateway" {
  subnet_id = module.public-subnet.subnet-id
  allocation_id        = ""
  tags                 = {
    Name               = "nat-gateway-private-subnet"
        }
}

# route table for the public subnets. public subnets route to the internet
module "route-table-public" {
  source            = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-module-route-table"
  vpc-network       = module.vpc.vpc-network-id
  route-cidr        = "0.0.0.0/0"
  route_gateway_id  = module.internet-gateway.internet-gateway-id
  tag-name          =  "route-table-public-subnets"

}

# route association of public-subnet to the public route table
module "route-table-public-route-assoc" {
  source         = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-module-route-association"
  route-table-id = module.route-table-public.route-table-id
  subnet-id      = module.public-subnet.subnet-id
}

# route association of public-subnet-2 to the public route table
module "route-table-public-2-route-assoc" {
  source         = "github.com/Bigbotteam/aws-terraform-modules.git?ref=aws-module-route-association"
  route-table-id = module.route-table-public.route-table-id
  subnet-id      = module.public-subnet-2.subnet-id

}

# create the kubernetes label and metadata
module "label" {
    source = "cloudposse/label/null"
    # Cloud Posse recommends pinning every module to a specific version
    # version  = "x.x.x"

    namespace  = "test-deployment"
    name       = "test-app"
    stage      = "test"
    attributes = ["cluster"]
    tags       = {
      Name = "testlabel"
    }
}
      locals {
    tags = { "kubernetes.io/cluster/${module.label.id}" = "shared" }
  }

# create the kubernetes cluster, deployed to the created vpc and deployed to the private subnet
 module "eks_cluster" {
    source                = "cloudposse/eks-cluster/aws"
    vpc_id                = module.vpc.vpc-network-id
    subnet_ids            = [module.private-subnet.subnet-id]
    oidc_provider_enabled = true
    context               = module.label.context
   region                 = var.AWS_REGION
 }

# worker nodes to join the eks_cluster
 module "eks_workers" {
    source = "cloudposse/eks-workers/aws"
    attributes                         = ["worker"]
    instance_type                      = "t3a.large"
    vpc_id                             = module.vpc.vpc-network-id
    subnet_ids                         = [module.private-subnet.subnet-id]
    health_check_type                  = true
    min_size                           = 1
    max_size                           = 2
    cluster_name                       = module.eks_cluster.eks_cluster_id
    cluster_endpoint                   = module.eks_cluster.eks_cluster_endpoint
    cluster_certificate_authority_data = module.eks_cluster.eks_cluster_certificate_authority_data
    context = module.label.context
  }

