provider "aws" {
  region     = "us-east-1"
  access_key = "XXXXXXXXXXXXXXXX" 
  secret_key = "ZZZZZZZZZZZZZZZZ"
}

#Create admin user in account and download access key, 
# Use these credentials for access key and secret key in Provider section

# 1. Create vpc

resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.1.0.0/16"
  tags = {
    Name = "production"
  }
}

# 2. Create Internet Gateway

resource "aws_internet_gateway" "int-gw" {
  vpc_id = aws_vpc.prod-vpc.id
}
# 3. Create Custom Route Table

resource "aws_route_table" "prod-route-table" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.int-gw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.int-gw.id
  }

  tags = {
    Name = "Prod"
  }
}

# 4. Create a Subnet 
# 4.1 Create a Subnet-1 
resource "aws_subnet" "sub1" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.1.0.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Sub1"
  }
}

# 4.2 Create a Subnet-2 
resource "aws_subnet" "sub2" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.1.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Sub2"
  }
}

# 4.3 Create a Subnet-3 
resource "aws_subnet" "sub3" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.1.2.0/24"
  availability_zone = "us-east-1c"

  tags = {
    Name = "Sub3"
  }
}

# 4.4 Create a Subnet-4 
resource "aws_subnet" "sub4" {
  vpc_id            = aws_vpc.prod-vpc.id
  cidr_block        = "10.1.3.0/24"
  availability_zone = "us-east-1d"

  tags = {
    Name = "Sub4"
  }
}


# 5 Associate subnet with Route Table
# 5.1 Associate sub1 with Route Table
resource "aws_route_table_association" "pubRouteSub1" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.prod-route-table.id
}
# 5.2 Associate sub2 with Route Table
resource "aws_route_table_association" "pubRouteSub2" {
  subnet_id      = aws_subnet.sub2.id
  route_table_id = aws_route_table.prod-route-table.id
}


# 6. Create Security Group to allow port 22,80,443
# 6.1 Create Security Group to allow port 22,80,443
resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow Web inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# 6.2 Create Security Group to allow port 22
resource "aws_security_group" "rhel_svr" {
  name        = "Rhel_ssh_traffic"
  description = "Allow ssh inbound traffic"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Rhel_ssh_SG"
  }
}

# 7. Create a network interface with an ip in the subnet that was created in step 4

resource "aws_network_interface" "ssh-server-nic" {
  subnet_id       = aws_subnet.sub2.id
  private_ips     = ["10.1.1.6"]  
  security_groups = [aws_security_group.rhel_svr.id]
}

# 8. Assign an elastic IP to the network interface created in step 7

resource "aws_eip" "one" {
  vpc                       = true
  network_interface         = aws_network_interface.ssh-server-nic.id
  associate_with_private_ip = "10.1.1.6"
  depends_on                = [aws_internet_gateway.int-gw]
}

output "server_public_ip" {
  value = aws_eip.one.public_ip
}

# 9. Create Ubuntu server and install/enable apache2

resource "aws_instance" "rhel-server" {
  ami               = "ami-0fec38350591dcf2c"    #Red Hat Enterprise Linux 7.9
  instance_type     = "t2.micro"
  availability_zone = "us-east-1b"
  key_name          = "demoTerraform"
 # Create a 20G root volume
  root_block_device {
    volume_size = 20
    volume_type = "gp2"
  }
  
  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.ssh-server-nic.id
  }

  tags = {
    Name = "rhel-server"
  }
}

resource "aws_alb" "demo-alb" {
  name = "Terraform-Demo-ALB"
  internal = false
  security_groups = [aws_security_group.allow_web.id]
  subnets = [aws_subnet.sub3.id,aws_subnet.sub4.id]
}

resource "aws_launch_configuration" "demo-lconfig" {
  image_id = "ami-0fec38350591dcf2c"    #"ami-07ba5ee1184c364ef"    #Custome AMI for Rhel Server
  instance_type = "t2.micro"
  user_data =  "#!/bin/bash\n sudo yum install update -y \n sudo yum install httpd -y \n sudo service httpd start \n sudo bash -c 'echo your very first web server > /var/www/html/index.html \n sudo bash -c 'echo Health Test > /var/www/html/health.html"
  security_groups = [aws_security_group.allow_web.id]
}

resource "aws_autoscaling_group" "demo-auto-scale-gp" {
  name = "demo-auto-scale"
  min_size = 2
  max_size = 6
  desired_capacity = 2
  launch_configuration = aws_launch_configuration.demo-lconfig.name
  #target_group_arns         = [aws_lb_target_group.alb-tg.arn]
  vpc_zone_identifier = [aws_subnet.sub3.id,aws_subnet.sub4.id]
}

resource "aws_alb_target_group" "alb-tg" {
  name = "demo-alb-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.prod-vpc.id
  # Register the ASG instances with the target group
  target_type = "instance"
           
  health_check {
    path = "/health.html"
    interval = 30
    timeout = 5
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.demo-auto-scale-gp.name
  alb_target_group_arn = aws_alb_target_group.alb-tg.arn
}

resource "aws_alb_listener" "alb-listener" {
  load_balancer_arn = aws_alb.demo-alb.arn
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_alb_target_group.alb-tg.arn
  }
}

resource "aws_s3_bucket" "demo_bucket" {
  bucket = "demo-bucket-012923"
}

resource "aws_s3_bucket_object" "objectlogs" {
  bucket = aws_s3_bucket.demo_bucket.id
  key    = "logs/"
}

resource "aws_s3_bucket_object" "objectimages" {
  bucket = aws_s3_bucket.demo_bucket.id
  key    = "images/"
}

resource "aws_s3_bucket_lifecycle_configuration" "s3lc-config" {
  bucket = aws_s3_bucket.demo_bucket.id

  rule {
    id      = "rule1"
    status  = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 180
    }
  }
}
output "server_private_ip" {
  value = aws_instance.rhel-server.private_ip

}

output "server_id" {
  value = aws_instance.rhel-server.id
}