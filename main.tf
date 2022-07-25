terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}


variable "tag_environment" {
  type    = string
  default = "terraform_aws_vpn"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpn_site_ip" {
  type     = string
  nullable = false
}

variable "vpn_bgp_asn" {
  type     = number
  default  = 65000
  nullable = false
}

variable "vpn_routes" {
  type = list(string)
  default = [
    "192.168.1.0/24"
  ]
  nullable = false
}

variable "aws_ssh_key" {
  type     = string
  nullable = false
}


provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Name        = "${var.tag_environment}"
      Environment = var.tag_environment
    }
  }
}


# Networking

resource "aws_key_pair" "ssh_key" {
  key_name   = "${var.tag_environment}-ssh_key"
  public_key = var.aws_ssh_key
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.255.0.0/16"

  tags = {
    Name = "${var.tag_environment}-vpc"
  }
}

resource "aws_subnet" "subnet00" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.255.1.0/24"

  tags = {
    Name = "${var.tag_environment}-subnet00"
  }
}

resource "aws_internet_gateway" "igw00" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.tag_environment}-igw00"
  }
}

resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw00.id
  }

  dynamic "route" {
    for_each = var.vpn_routes
    content {
      cidr_block = route.value
      gateway_id = aws_vpn_gateway.vgw00.id
    }
  }

  tags = {
    Name = "${var.tag_environment}-rtb_main"
  }
}

## VPN Connections

resource "aws_vpn_gateway" "vgw00" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.tag_environment}-vgw00"
  }
}

resource "aws_customer_gateway" "cgw00" {
  bgp_asn    = var.vpn_bgp_asn
  ip_address = var.vpn_site_ip
  type       = "ipsec.1"

  tags = {
    Name = "${var.tag_environment}-cgw00"
  }
}

resource "aws_vpn_connection" "vpn00" {
  vpn_gateway_id      = aws_vpn_gateway.vgw00.id
  customer_gateway_id = aws_customer_gateway.cgw00.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "${var.tag_environment}-vpn00"
  }
}

resource "aws_vpn_connection_route" "vpn_route" {
  for_each               = toset(var.vpn_routes)
  destination_cidr_block = each.key
  vpn_connection_id      = aws_vpn_connection.vpn00.id
}

## Network Access Controls

# by default, deny all traffic outside of the subnet
resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id

  tags = {
    Name = "${var.tag_environment}-nacl_default"
  }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

resource "aws_network_acl" "nacl00" {
  vpc_id = aws_vpc.vpc.id

  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  egress {
    protocol   = "tcp"
    rule_no    = 200
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 190
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  tags = {
    Name = "${var.tag_environment}-nacl00"
  }
}

resource "aws_network_acl_association" "nacl00_subnet00" {
  network_acl_id = aws_network_acl.nacl00.id
  subnet_id      = aws_subnet.subnet00.id
}

# by default, don't allow any traffic
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.tag_environment}-sg_default"
  }
}

resource "aws_security_group" "outbound_all_inbound_ssh" {
  name        = "outbound_all_inbound_ssh"
  description = "Allow all outbound traffic and only SSH inbound."
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH from Internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.tag_environment}-outbound_all_inbound_ssh"
  }
}


# EC2 Instances

data "aws_ami" "centos-7-marketplace" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS Linux 7 x86_64 HVM EBS ENA *"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["aws-marketplace"]
}

data "aws_ami" "centos-7-official" {
  most_recent = true

  filter {
    name   = "name"
    values = ["CentOS 7*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["125523088429"]
}

data "aws_ami" "rocky-8-marketplace" {
  most_recent = true

  filter {
    name   = "name"
    values = ["Rocky-8-ec2-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["aws-marketplace"]
}

data "aws_ami" "rocky-8-official" {
  most_recent = true

  filter {
    name   = "name"
    values = ["Rocky-8-ec2-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["792107900819"]
}

resource "aws_instance" "jumphost00" {
  ami                         = data.aws_ami.rocky-8-official.id
  instance_type               = "t3a.nano"
  ebs_optimized               = true
  key_name                    = aws_key_pair.ssh_key.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.subnet00.id
  private_ip                  = "10.255.1.10"

  vpc_security_group_ids = [
    aws_security_group.outbound_all_inbound_ssh.id
  ]

  tags = {
    Name = "${var.tag_environment}-jumphost00"
  }
}
