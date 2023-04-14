terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "3.57.0"
    }
  }
}


provider "aws" {
  profile    = "jfk"
  region     = "us-east-1"
}

variable "secgr-dynamic-ports" {
  default = [22,80,443,8080,8082,8083,8084,8085]
}

variable "instance-type" {
  default = "t2.medium"
  sensitive = true
}

variable "ec2_type" {
  type    = string
  default = "ec2-user"

}

variable "ami_type" {
  default = "ami-069aabeee6f53e7bf" #redhat ami-016eb5d644c333ccb EC2 ami-069aabeee6f53e7bf
  # sensitive = true
}

variable "generated_key_name" {
  default = "tf-grav"

}


# creating of key
resource "tls_private_key" "gravitee-key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# creating of ssh key on AWS
resource "aws_key_pair" "generated_key" {
  key_name   = var.generated_key_name
  public_key = tls_private_key.gravitee-key.public_key_openssh
  tags = {
    Name = "aws-${var.generated_key_name}"
  }
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.generated_key.key_name}.pem"
  content  = tls_private_key.gravitee-key.private_key_pem
  provisioner "local-exec" {
    command = "chmod 400 ./${var.generated_key_name}.pem"
  }
}

resource "aws_security_group" "allow_ssh" {
  name        = "grac-sec-grp"
  description = "Allow SSH inbound traffic"

  dynamic "ingress" {
    for_each = var.secgr-dynamic-ports
    content {
      from_port = ingress.value
      to_port = ingress.value
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
  }
}

  egress {
    description = "Outbound Allowed"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "gravitee" {
  ami           = var.ami_type
  instance_type = var.instance-type
  key_name = var.generated_key_name
  vpc_security_group_ids = [ aws_security_group.allow_ssh.id ]
  tags = {
      Name = "gravitee-engine"
  }
  provisioner "file" {
      source      = "docker-compose-apim.yml"
      destination = "/home/docker-compose-apim.yml"

    connection {
      type        = "ssh"
      host        = self.public_ip
      user        = "ec2-user"
      private_key = "${file("${var.generated_key_name}.pem")}"
    }
  }
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install docker -y
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              # install docker-compose
              curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" \
              -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose
              docker-compose -f docker-compose-apim.yml up -d
              EOF

  
  depends_on = [aws_key_pair.generated_key]
}  

# resource "aws_volume_attachment" "ebs_att" {
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.gravitee.id
#   instance_id = aws_instance.gravitee.id
# }

# resource "aws_ebs_volume" "gravitee" {
#   availability_zone = "us-east-1a"
#   size              = 30
# }

output "myec2-public-ip" {
  value = aws_instance.gravitee.public_ip
}



output "master" {
  # sensitive = true
  description = "URL of ssh to gravitee server"
  value       = "ssh -i ${var.generated_key_name}.pem ${var.ec2_type}@${aws_instance.gravitee.public_ip}"

}
