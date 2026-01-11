# 1. VPC - 1개
# 2. IGW - 1개
# 3. Subnet - 6개(Public 2개, was 2개, db 2개)
# 4. Nat Gateway - 1개
# 5. Route_Table - 2개 ()
# 6. Route_Table_Association - 6개(Public 2개, was 2개, db 2개)

terraform {
  required_version = ">= 1.0.0"

  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# ------------------------------------------------------------------------------
# 1. VPC 
# ------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.name}-vpc"
  }
}

# ------------------------------------------------------------------------------
# 2. Internet Gateway
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# ------------------------------------------------------------------------------
# 3. Subnets
# ------------------------------------------------------------------------------

# Public Subnets
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_a_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.name}-pub-a"
  }
}
resource "aws_subnet" "public_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_c_cidr
  availability_zone = "${var.region}c"

  tags = {
    Name = "${var.name}-pub-c"
  }
}

# Private Subnets (WAS)
resource "aws_subnet" "was_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.was_subnet_a_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.name}-was-a"
  }
}

resource "aws_subnet" "was_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.was_subnet_c_cidr
  availability_zone = "${var.region}c"

  tags = {
    Name = "${var.name}-was-c"
  }
}


# Private Subnets (DB)
resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_a_cidr
  availability_zone = "${var.region}a"

  tags = {
    Name = "${var.name}-db-a"
  }
}

resource "aws_subnet" "db_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_c_cidr
  availability_zone = "${var.region}c"

  tags = {
    Name = "${var.name}-db-c"
  }
}

# ------------------------------------------------------------------------------
# 4. Nat Gateway
# ------------------------------------------------------------------------------
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = { 
    Name = "${var.name}-nat-eip" 
  }
  
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "${var.name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.gw]
}

# ------------------------------------------------------------------------------
# 5. Route Table
# ------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.name}-private-rt" }
}
# ------------------------------------------------------------------------------
# 6. Association
# ------------------------------------------------------------------------------
resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "was_a" {
  subnet_id      = aws_subnet.was_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "was_c" {
  subnet_id      = aws_subnet.was_c.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "db_c" {
  subnet_id      = aws_subnet.db_c.id
  route_table_id = aws_route_table.private.id
}