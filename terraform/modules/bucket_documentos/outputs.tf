output "bucket" {
  description = "Nombre del bucket."
  value       = aws_s3_bucket.this.bucket
}

output "arn" {
  description = "ARN del bucket."
  value       = aws_s3_bucket.this.arn
}

output "key_prefix" {
  description = "Prefijo donde están los documentos."
  value       = var.key_prefix
}
