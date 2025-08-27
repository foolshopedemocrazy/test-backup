resource "aws_security_group" "vulnerable_sg" {
  name        = "allow_all"
  description = "Allow all inbound traffic"
  vpc_id      = "vpc-12345678"

  # This is vulnerable - allows all traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
