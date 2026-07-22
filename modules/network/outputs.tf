output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "gateway_task_security_group_id" {
  value = aws_security_group.gateway_task.id
}

output "admin_console_security_group_id" {
  value = aws_security_group.admin_console.id
}

output "database_security_group_id" {
  value = aws_security_group.database.id
}
