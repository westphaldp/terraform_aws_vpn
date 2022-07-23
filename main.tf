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

variable "aws_ssh_key" {
  type = string
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

resource "aws_route_table" "rt00" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw00.id
  }

  tags = {
    Name = "${var.tag_environment}-rt00"
  }
}

resource "aws_route_table_association" "rt00_subnet00" {
  route_table_id = aws_route_table.rt00.id
  subnet_id      = aws_subnet.subnet00.id
}

# Not entirely sure the gateway association is the right thing to do. (Gateway route tables)[https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html#gateway-route-tables]
#resource "aws_route_table_association" "rt00_igw00" {
#  route_table_id = aws_route_table.rt00.id
#  gateway_id     = aws_internet_gateway.igw00.id
#}

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

resource "aws_instance" "jumphost00" {
  # CentOS 7
  #ami                         = "ami-011939b19c6bd1492"
  # Rocky-8-ec2-8.6-20220515.0.x86_64-d6577ceb-8ea8-4e0e-84c6-f098fc302e82
  ami                         = "ami-004b161a1cceb1ceb"
  # Rocky-9-EC2-9.0-20220706.0.x86_64-3f230a17-9877-4b16-aa5e-b1ff34ab206b
  #ami                         = "ami-0ae4df53d376e5d3b"
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
