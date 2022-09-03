

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket = "skam-tfstate"
    key    = "terraform.tfstate"
    region = "eu-west-3"
  }
}

provider "aws" {
  region  = "eu-west-3"
}

variable "ssh_public_key_file_path" {
  type = string
}

locals {
  tags = {
    Name = "skam-website"
  }
  availability_zone =  "eu-west-3a"
}

resource "aws_iam_role" "iam_role" {
  name = "${local.tags.Name}-role"
  tags = {
    Name = local.tags.Name
  }
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# iam role policy resource
resource "aws_iam_role_policy" "policy" {
  name = "${local.tags.Name}-policy"
  role = aws_iam_role.iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["ec2:*"],
      "Resource": ["*"]
    }
  ]
}
EOF
}

resource "aws_ebs_volume" "volume" {
  size              = 15
  type              = "gp3"
  availability_zone = local.availability_zone
  tags = {
    Name = local.tags.Name
  }
}


resource "aws_key_pair" "key_pair" {
  public_key = file(var.ssh_public_key_file_path)
  key_name   = "${local.tags.Name}-key"
  tags = {
    Name = local.tags.Name
  }
}
resource "aws_security_group" "security_group" {
  name        = "${local.tags.Name}_security_group"
  description = "Allow SSH, HTTP and HTTPS traffic"
  tags = {
    Name = local.tags.Name
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${local.tags.Name}-instance-profile"
  role = aws_iam_role.iam_role.name
  tags = {
    Name = local.tags.Name
  }
}

resource "aws_volume_attachment" "volume_attachment" {
  device_name = "/dev/xvdf"
  instance_id = aws_instance.skam_website.id
  volume_id   = aws_ebs_volume.volume.id
}

resource "aws_instance" "skam_website" {
  ami           = "ami-09e513e9eacab10c1"
  availability_zone = local.availability_zone
  instance_type = "t2.micro"
  key_name      = aws_key_pair.key_pair.key_name
  security_groups = [aws_security_group.security_group.name]
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  user_data = file("../server-bootstrap.sh")
  tags = {
    Name = local.tags.Name
  }
}