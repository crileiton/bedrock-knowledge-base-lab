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

# Los scripts de scripts/ leen estos dos valores con `terraform output -raw`.
output "knowledge_base_id" {
  description = "ID de la Knowledge Base."
  value       = aws_bedrockagent_knowledge_base.kb.id
}

output "data_source_id" {
  description = "ID del data source S3."
  value       = aws_bedrockagent_data_source.s3.data_source_id
}
