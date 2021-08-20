provider "aws" {
  profile    = "default"
  region     = "us-east-1"
}
variable "ingressrules" {
  type    = list(number)
  default = [22, 8080]
}
resource "aws_vpc" "Vpc" {
  cidr_block       = "172.20.0.0/16"

  tags = {
    Name = "Vpc"
  }
}
resource "aws_subnet" "PublicSubnet" {
  vpc_id     = aws_vpc.Vpc.id
  cidr_block = "172.20.10.0/24"
  map_public_ip_on_launch = "true"
  tags = {
        Name = "PublicSubnet"
  }
}
resource "aws_subnet" "PrivateSubnet" {
  vpc_id     = aws_vpc.Vpc.id
  cidr_block = "172.20.20.0/24"
  tags = {
        Name = "PrivateSubnet"
  }
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.Vpc.id

  tags = {
    Name = "igw"
  }
}
resource "aws_eip" "Eip" {
  vpc                       = true
  tags = {
        Name = "Eip"
  }
}
resource "aws_nat_gateway" "ngw" {
  subnet_id     = aws_subnet.PublicSubnet.id
  allocation_id = aws_eip.Eip.id
  tags = {
    Name = "ngw"
  }
}
resource "aws_route_table" "PublicRouteTable" {
  vpc_id = aws_vpc.Vpc.id
  tags = {
        Name = "PublicRouteTable"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table" "PrivateRouteTable" {
  vpc_id = aws_vpc.Vpc.id
  tags = {
        Name = "PrivateRouteTable"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.ngw.id
  }
}
resource "aws_route_table_association" "PublicSubnetAssociation" {
    subnet_id = aws_subnet.PublicSubnet.id
    route_table_id = aws_route_table.PublicRouteTable.id
}
resource "aws_route_table_association" "PrivateSubnetAssociation" {
    subnet_id = aws_subnet.PrivateSubnet.id
    route_table_id = aws_route_table.PrivateRouteTable.id
}
resource "aws_security_group" "Sg_VM1" {
  name        = "Sg_VM1"
  vpc_id        = aws_vpc.Vpc.id
  dynamic "ingress" {
    iterator = port
    for_each = var.ingressrules
    content {
      from_port   = port.value
      to_port     = port.value
      protocol    = "TCP"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "Terraform" = "true"
  }
}
data "aws_ami" "amazon_linux" {
 most_recent = true
 owners = ["amazon"]
 filter {
   name   = "owner-alias"
   values = ["amazon"]
 }
 filter {
   name   = "name"
   values = ["amzn2-ami-hvm*"]
 }
}
resource "aws_key_pair" "app_key" {
  key_name   = "APP-KEY"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC+y2hkjlKou07791Qhr04dTq2iK7hTz+2Q22N6sZoQsW/17glGVrBHoIUuqErD3jOWd/+NEpquLtyWQHVGCL7FPeF8P7STsNVdyK0uMDQRuTdUW6Idl3fvxbJdMrZLrZ/Qt36EhI723w91YdJunGZG2CH3clZwPH0wOm+aE9h/QR5nhXpz069F1B878qgSbuZ4eBRq1eKHDPo+igL7ArITQ5w/WqbLVidrsPtxUtRLQwGgkCxlqutG8EkH/PBL/fZyLHgGjlclmLUpneRe16BK4QEHuEjsxdmstm8svzG+uQEKiiobifLFEQYzUxAANJf6A0T2rXt3SgvOXNkoZxE3 APP-KEY"
}
resource "aws_instance" "VM1" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  associate_public_ip_address = true
  subnet_id     = aws_subnet.PublicSubnet.id
  vpc_security_group_ids = [aws_security_group.Sg_VM1.id]
  key_name = aws_key_pair.app_key.id
  provisioner "remote-exec"  {
    inline  = [
      "sudo amazon-linux-extras install -y java-openjdk11",
      "sudo yum install -y jenkins",
      "sudo yum -y install wget",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io.key",
      "sudo yum upgrade -y",
      "sudo yum install jenkins -y",
      "sudo systemctl start jenkins",
      "sudo wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm",
      "sudo yum install -y epel-release-latest-7.noarch.rpm",
      "sudo yum update -y",
      "sudo yum install git python python-devel python-pip openssl ansible -y",
      "sudo wget https://repos.fedorapeople.org/repos/dchen/apache-maven/epel-apache-maven.repo -O /etc/yum.repos.d/epel-apache-maven.repo",
      "sudo sed -i s/\\$releasever/6/g /etc/yum.repos.d/epel-apache-maven.repo",
      "sudo yum install -y apache-maven"
      ]
  connection {
      host        = self.public_ip
      user        = "ec2-user"
      type        = "ssh"
      private_key = "${file("/home/ec2-user/private_key.pem")}"
      timeout     = "1m"
      agent       =  false
    }
  }
 tags = {
    Name = "MASTER"
  }
}
resource "aws_instance" "VM2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.PrivateSubnet.id
  vpc_security_group_ids = [aws_security_group.Sg_VM1.id]
  key_name = aws_key_pair.app_key.id
  provisioner "remote-exec"  {
    inline  = [
          "sudo amazon-linux-extras install tomcat8.5 -y",
      "sudo systemctl start tomcat"
      ]
  connection {
      host        = self.private_ip
      user        = "ec2-user"
      type        = "ssh"
      private_key = "${file("/home/ec2-user/private_key.pem")}"
      timeout     = "1m"
      agent       =  false
    }
  }
 tags = {
    Name = "Node"
  }
}