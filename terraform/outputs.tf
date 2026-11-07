output "docs_bucket" {
  description = "Bucket S3 con los documentos fuente."
  value       = aws_s3_bucket.docs.bucket
}

output "vector_bucket" {
  description = "Vector bucket de S3 Vectors."
  value       = aws_s3vectors_vector_bucket.kb.vector_bucket_name
}

output "vector_index" {
  description = "Índice vectorial donde Bedrock escribe los embeddings."
  value       = aws_s3vectors_index.kb.index_name
}

output "kb_role_name" {
  description = "Rol IAM que asume Bedrock para la Knowledge Base."
  value       = aws_iam_role.kb.name
}
