#############################
# main.tf – Komplettes Skript
#############################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#############################
# Variablen
#############################

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1" # Frankfurt
}

variable "project_name" {
  description = "Prefix für alle Ressourcen"
  type        = string
  default     = "m346-nextcloud"
}

variable "vpc_cidr" {
  description = "CIDR Block für die VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR Block für das Public Subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 Instance Type für Web- und DB-Server"
  type        = string
  default     = "t3.micro"
}

variable "ssh_allowed_cidr" {
  description = "IP-Bereich, der per SSH verbinden darf"
  type        = string
  # TODO: Eigene öffentliche IP eintragen, nicht 0.0.0.0/0 im echten Betrieb
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Name eines bestehenden AWS Key Pairs"
  type        = string
}

variable "ami_id" {
  description = "AMI ID (z.B. Ubuntu 22.04 in eurer Region)"
  type        = string
}

#############################
# Provider
#############################

provider "aws" {
  region = var.aws_region
}

#############################
# Netzwerk (VPC, Subnet, Routing)
#############################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

#############################
# Security Groups
#############################

# Webserver: HTTP/HTTPS von überall, SSH nur von eurer IP
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Security Group für Webserver"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (für späteres TLS)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Alles raus erlaubt
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# DB-Server: DB-Port nur vom Web-SG, SSH von eurer IP
resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Security Group für DB-Server"
  vpc_id      = aws_vpc.main.id

  # MySQL / MariaDB
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  # Alles raus erlaubt
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

#############################
# EC2-Instanzen
#############################

# Webserver-Instanz
resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = var.key_name

  # Hier wird euer vorhandenes Web-Init-Skript eingebunden
  user_data = file("${path.module}/init_webserver.sh")

  tags = {
    Name = "${var.project_name}-web"
    Role = "web"
  }
}

# DB-Instanz
resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = var.key_name

  # Hier wird euer vorhandenes DB-Init-Skript eingebunden
  user_data = file("${path.module}/init_database.sh")

  tags = {
    Name = "${var.project_name}-db"
    Role = "db"
  }
}

#############################
# Outputs
#############################

output "web_public_ip" {
  description = "Öffentliche IP des Webservers (für Nextcloud-Installer)"
  value       = aws_instance.web.public_ip
}

output "web_public_dns" {
  description = "Öffentlicher DNS-Name des Webservers"
  value       = aws_instance.web.public_dns
}

output "db_private_ip" {
  description = "Private IP des DB-Servers (für DB-Host im Nextcloud-Installer)"
  value       = aws_instance.db.private_ip
}
