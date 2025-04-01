# AWS Multi-Tier VPC Security Challenge

## Overview
This repository documents my journey completing Challenge 2: "Set Up a Multi-Tier VPC with Security Controls" using Terraform. The challenge involved creating a secure network architecture with properly isolated components and appropriate security controls.

## Challenge Requirements

### 🛠 Task
- Create a VPC with:
  - Public subnet (for web server)
  - Private subnet (for database)
- Deploy EC2 in the public subnet and RDS in the private subnet
- Set up security groups/firewall rules ensuring:
  - Only the public subnet can access the internet
  - Private subnet can only be accessed from the public subnet
  - Database is only accessible via the application (not the internet)
- Configure CloudTrail to log activity

### ✅ Success Criteria
- Database inaccessible directly from the internet
- Web server can access the database but not vice versa
- Cloud logs showing network activity and access logs

## Implementation Challenges and Solutions

### 1. Security Group Misconfigurations

**Issue:** Initially, I used a hardcoded security group ID and referenced non-existent VPC resources:

```terraform
resource "aws_security_group_rule" "example" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.example.cidr_block]  # Non-existent VPC reference
  security_group_id = "sg-123456"  # Hardcoded ID
}
```

**Solution:** Created proper security groups with appropriate ingress/egress rules for both web and database tiers:

```terraform
resource "aws_security_group" "web_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow HTTP from anywhere
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Initially allowed SSH from anywhere (security risk)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]  # Only web server can access DB
  }
}
```

### 2. Missing Internet Gateway & Route Tables

**Issue:** I created public and private subnets but didn't configure the necessary network components to enable internet access for the public subnet.

**Solution:** Added an Internet Gateway, route tables, and appropriate associations:

```terraform
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}
```

### 3. NAT Gateway Configuration

**Issue:** Initially placed the NAT Gateway in the private subnet instead of the public subnet, which is incorrect since the NAT Gateway itself needs internet access.

**Solution:** Moved the NAT Gateway to the public subnet and created appropriate route tables:

```terraform
# Elastic IP for NAT Gateway (was missing)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id  # Corrected to public subnet
  depends_on    = [aws_internet_gateway.gw]
}

# Added private route table to route through NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private_rt.id
}
```

### 4. RDS Configuration Issues

**Issue:** Used incorrect resource type for Aurora MySQL and missing subnet group configuration:

```terraform
resource "aws_rds_instance" "default" {  # Wrong resource type
  cluster_identifier      = "aurora-cluster-demo"
  engine                  = "aurora-mysql"
  # missing db_subnet_group_name and security group
  publicly_accessible     = false  # Resulted in "Unexpected attribute" error
}
```

**Solution:** Created a DB subnet group and used the correct resource type:

```terraform
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = [aws_subnet.private.id]
}

resource "aws_rds_cluster" "default" {  # Correct resource for Aurora
  cluster_identifier      = "aurora-cluster-demo"
  engine                  = "aurora-mysql"
  engine_version          = "8.0.mysql_aurora.3.03.1"  # Updated to newer version
  database_name           = "mydb"
  master_username         = "foo"
  master_password         = "must_be_eight_characters"
  db_subnet_group_name    = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids  = [aws_security_group.db_sg.id]
  storage_encrypted       = true
  # removed publicly_accessible as it's not applicable to clusters
}
```

### 5. CloudTrail Implementation

**Issue:** Initially used aws_cloudtrail_event_data_store without proper configuration for logging.

**Solution:** Implemented proper CloudTrail with S3 bucket for logs:

```terraform
resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "my-cloudtrail-bucket"
}

resource "aws_cloudtrail" "cloudtrail" {
  name                  = "cloudtrail-logs"
  s3_bucket_name        = aws_s3_bucket.cloudtrail_bucket.id
  is_multi_region_trail = true
  enable_logging        = true
}
```

### 6. EC2 Network Configuration

**Issue:** Initially deployed EC2 without specifying subnet or security group:

```terraform
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  # missing subnet_id and security_groups
}
```

**Solution:** Added proper network configuration:

```terraform
resource "aws_instance" "web" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  subnet_id       = aws_subnet.public.id
  security_groups = [aws_security_group.web_sg.id]
}

# Added Elastic IP for web server
resource "aws_eip" "web_eip" {
  domain = "vpc"
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.web.id
  allocation_id = aws_eip.web_eip.id
}
```

## Key Learnings

1. **Network Design**: Properly configuring the network flow is crucial - understanding how traffic flows through IGW, NAT, and route tables.

2. **Security Best Practices**:
   - Restrict SSH access to specific IPs rather than allowing it from everywhere
   - Use security groups to implement the principle of least privilege
   - Ensure private resources (like databases) are inaccessible from the internet

3. **Resource Dependencies**: Understanding which AWS resources depend on others is important for proper deployment order.

4. **RDS Configuration**: Aurora MySQL requires using aws_rds_cluster, not aws_rds_instance.

5. **CloudTrail Setup**: Properly configured logging is essential for monitoring and security auditing.

## Final Architecture

The final architecture consists of:

- VPC with public and private subnets
- EC2 instance in the public subnet with Elastic IP
- Aurora MySQL cluster in the private subnet
- Internet Gateway for public subnet internet access
- NAT Gateway in the public subnet to allow private subnet outbound access
- Route tables directing traffic appropriately
- Security groups restricting access based on principle of least privilege
- CloudTrail logging all activity to an S3 bucket

## Security Improvements for Production

For a production environment, consider these additional improvements:

1. Set up more restrictive CIDR blocks for SSH access
2. Implement a bastion host for secure admin access
3. Add network ACLs as an additional security layer
4. Encrypt sensitive data in transit and at rest
5. Implement VPC flow logs for more detailed network traffic analysis
6. Set up CloudWatch alarms for suspicious activities
7. Implement AWS Config for compliance monitoring

## Conclusion

This challenge taught me valuable lessons about AWS networking, security, and infrastructure as code. The final solution meets all the requirements while implementing AWS best practices for security and reliability.
