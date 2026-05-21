resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet"
  subnet_ids = [aws_subnet.private.id]

  tags = {
    Name = "${var.app_name}-db-subnet"
  }
}

resource "aws_secretsmanager_secret" "main" {
  name = "${var.app_name}-db-password"
}

resource "aws_secretsmanager_secret_version" "main" {
  secret_id                = aws_secretsmanager_secret.main.id
  secret_string_wo         = var.db_password
  secret_string_wo_version = var.db_password_version
}

ephemeral "aws_secretsmanager_secret_version" "main" {
  secret_id = aws_secretsmanager_secret_version.main.secret_id
}

resource "aws_db_instance" "main" {
  identifier           = "${var.app_name}-db"
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  storage_type         = "gp3"
  db_name              = "pawtrack"
  username             = var.db_username
  password_wo          = ephemeral.aws_secretsmanager_secret_version.main.secret_string
  password_wo_version  = aws_secretsmanager_secret_version.main.secret_string_wo_version
  parameter_group_name = "default.postgres15"
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "${var.app_name}-db"
  }
}
