variable "skip_final_snapshot" {
  type    = bool
  default = false
}

resource "aws_rds_cluster" "default" {
  cluster_identifier        = "aurora-cluster-demo"
  engine                    = "aurora-mysql"
  engine_version            = "5.7.mysql_aurora.2.11.3"
  database_name             = "mydb"
  master_username           = "foo"
  master_password           = "must_be_eight_characters"
  backup_retention_period   = 5
  preferred_backup_window   = "07:00-09:00"
  db_subnet_group_name      = aws_db_subnet_group.db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.db_sg.id]
  storage_encrypted         = true
  final_snapshot_identifier = "aurora-cluster-demo-final-snapshot"
  skip_final_snapshot = var.skip_final_snapshot
}