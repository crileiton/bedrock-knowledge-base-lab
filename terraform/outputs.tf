output "docs_bucket" {
  description = "Bucket S3 con los documentos fuente."
  value       = aws_s3_bucket.docs.bucket
}
