# ---------------------------------------------------------------------------
# Vector store: Amazon S3 Vectors.
# Un "vector bucket" es un tipo de bucket distinto al S3 normal; dentro de él
# se crean índices, y cada índice guarda vectores de una sola dimensión.
# ---------------------------------------------------------------------------

resource "aws_s3vectors_vector_bucket" "kb" {
  vector_bucket_name = "${local.name}-vectores"

  # Cifrado en reposo con claves administradas por S3 (SSE-S3).
  # Para control total de la clave se usaría sse_type = "aws:kms" + kms_key_arn.
  encryption_configuration {
    sse_type = "AES256"
  }

  force_destroy = true
}

resource "aws_s3vectors_index" "kb" {
  vector_bucket_name = aws_s3vectors_vector_bucket.kb.vector_bucket_name
  index_name         = "${var.project_name}-indice"

  data_type = "float32"

  # Debe ser igual a las dimensiones con las que el modelo genera embeddings.
  dimension = var.embedding_dimensions

  # Coseno compara la dirección de los vectores (significado), no su magnitud.
  distance_metric = "cosine"

  # Bedrock guarda en cada vector el texto del chunk (AMAZON_BEDROCK_TEXT) y
  # metadatos internos (AMAZON_BEDROCK_METADATA). Son grandes y S3 Vectors
  # limita los metadatos filtrables a 2 KB por vector, así que se marcan como
  # no filtrables. Los metadatos de los .metadata.json siguen siendo filtrables.
  metadata_configuration {
    non_filterable_metadata_keys = ["AMAZON_BEDROCK_TEXT", "AMAZON_BEDROCK_METADATA"]
  }
}
