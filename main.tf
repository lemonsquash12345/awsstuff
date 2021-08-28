# make a change

# # taken from here:https://medium.com/appgambit/terraform-aws-vpc-with-private-public-subnets-with-nat-4094ad2ab331
# with an instance added, connect to instance using rdp and password obtained via aws console
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Tutorials.WebServerDB.CreateVPC.html#CHAP_Tutorials.WebServerDB.CreateVPC.AdditionalSubnets
#
terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# provider
provider "aws" {
  region     = "eu-west-2"
}

# Create a VPC

resource "aws_vpc" "epVPC" {
  cidr_block = "10.2.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "epVPC"
  }
}

#Create internet gateway

resource "aws_internet_gateway" "epInternetGateway" {
  vpc_id = aws_vpc.epVPC.id
  tags = {
    Name = "epInternetGateway"
  }
}

#Create Elastic IP

resource "aws_eip" "epElasticIP" {
  network_border_group = "eu-west-2"
  vpc = true
  depends_on = [aws_internet_gateway.epInternetGateway]
  tags = {
    Name = "epElasticIP"
  }
}

#Create NAT gateway

resource "aws_nat_gateway" "epNATGateway" {
  allocation_id = aws_eip.epElasticIP.id
  subnet_id     = aws_subnet.epPublicSubnet.id
  depends_on = [aws_internet_gateway.epInternetGateway]
  tags = {
    Name = "epNATGateway"
  }
}

# Create subnets

resource "aws_subnet" "epPublicSubnet" {
  vpc_id     = aws_vpc.epVPC.id
  cidr_block = "10.2.1.0/24"
  availability_zone = "eu-west-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "epPublicSubnet"
  }
}

resource "aws_subnet" "epPrivateSubnet1" {
  vpc_id     = aws_vpc.epVPC.id
  cidr_block = "10.2.2.0/24"
  availability_zone = "eu-west-2a"
  map_public_ip_on_launch = false
  tags = {
    Name = "epPrivateSubnet1"
  }
}

resource "aws_subnet" "epPrivateSubnet2" {
  vpc_id     = aws_vpc.epVPC.id
  cidr_block = "10.2.3.0/24"
  availability_zone = "eu-west-2b"
  map_public_ip_on_launch = false
  tags = {
    Name = "epPrivateSubnet2"
  }
}

#route table for public subnet

resource "aws_route_table" "epPublicRT" {
  vpc_id = aws_vpc.epVPC.id
  route = [ 
    {
     destination_cidr_block = "0.0.0.0/0"
     gateway_id             = aws_internet_gateway.epInternetGateway.id
    }
  ]
  tags = {
    Name = "epPublicRouteTable"
  }

}


#Create New route table for private subnet

resource "aws_route_table" "epPrivateRT" {
  vpc_id = aws_vpc.epVPC.id
  
  route = [ 
   {
     destination_cidr_block = "0.0.0.0/0"
     nat_gateway_id         = aws_nat_gateway.epNATGateway.id
    }
  ] 

  tags = {
    Name = "epRouteTable"
  }
}

#Route for internet gateway

#resource "aws_route" "epIGRoute" {
#  route_table_id         = aws_route_table.epPublicRT.id
#  destination_cidr_block = "0.0.0.0/0"
#  gateway_id             = aws_internet_gateway.epInternetGateway.id
#}

#Route for NAT gateway

#resource "aws_route" "epNATRoute" {
#  route_table_id         = aws_route_table.epPrivateRT.id
#  destination_cidr_block = "0.0.0.0/0"
#  nat_gateway_id         = aws_nat_gateway.epNATGateway.id
#}

#Associate public subnet with public route table

resource "aws_route_table_association" "epPublicTRAss" {
  subnet_id      = aws_subnet.epPublicSubnet.id
  route_table_id = aws_route_table.epPublicRT.id
}

#Associate private subnet with private route table

resource "aws_route_table_association" "epPrivate1" {
  subnet_id      = aws_subnet.epPrivateSubnet1.id
  route_table_id = aws_route_table.epPrivateRT.id
}

resource "aws_route_table_association" "epPrivate2" {
  subnet_id      = aws_subnet.epPrivateSubnet2.id
  route_table_id = aws_route_table.epPrivateRT.id
}

#Create security groups

resource "aws_security_group" "epPublicSG" {
   vpc_id = aws_vpc.epVPC.id
   name = "epPublicSG"
   description = "tcp 3389 ingress rule for epPublicSG"
   depends_on = [aws_vpc.epVPC]
   ingress {
      from_port   = 3389
      to_port     = 3389
      protocol    = "TCP"
      cidr_blocks = ["86.185.26.203/32"]
   }  
   egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
   }
  
   tags = {
    Name = "epPublicSG"
  }
}

resource "aws_security_group" "epPrivateSG" {
   vpc_id = aws_vpc.epVPC.id
   name = "epPrivateSG"
   description = "tcp 3389 ingress rule for epPrivateSG"
   depends_on = [aws_vpc.epVPC]
   ingress {
      from_port   = 1433    #MSSQL
      to_port     = 1433
      protocol    = "TCP"
      cidr_blocks = ["10.2.0.0/16"]
   }  
   egress {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
   }
  
   tags = {
    Name = "epPublicSG"
  }
}

resource "aws_db_subnet_group" "epDBSubnetGrp" {
  name       = "epdbsubnetgrp"
  description = "DB subnet group"
  subnet_ids = [aws_subnet.epPrivateSubnet1.id, aws_subnet.epPrivateSubnet2.id]

  tags = {
    Name = "epDBSubnetGrp"
  }
}

resource "aws_db_instance" "epDatabaseInstance" {
  allocated_storage    = 20
  engine               = "sqlserver-ex" # other options: sqlserver-ee,sqlserver-se,sqlserver-web
  instance_class       = "db.t3.small"
  username             = "foo"
  password             = "foobarbaz"
  skip_final_snapshot  = true
  db_subnet_group_name = "epdbsubnetgrp"
}

#************************************************
#Create instance
resource "aws_instance" "epPublicInstance" {
  ami           = "ami-0f34584723e6f6fa9" #London
  instance_type = "t2.micro"
  subnet_id = aws_subnet.epPublicSubnet.id
  key_name = "epDesktopKeyPair"
  vpc_security_group_ids = [aws_security_group.epPublicSG.id]
  tags = {
     Name = "epInstance"
  }
}

