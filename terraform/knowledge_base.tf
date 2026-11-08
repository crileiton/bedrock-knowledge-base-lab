# ---------------------------------------------------------------------------
# Knowledge Base (tipo VECTOR, administrada por el cliente).
# Une las piezas: modelo de embeddings + vector store + rol de servicio.
# ---------------------------------------------------------------------------

resource "aws_bedrockagent_knowledge_base" "kb" {
  name        = "${local.name}-kb"
  description = "KB del laboratorio con documentos ficticios de una cooperativa cafetera"
  role_arn    = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.embedding_model_id}"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          # Debe coincidir con la dimensión del índice de S3 Vectors.
          dimensions          = var.embedding_dimensions
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.kb.index_arn
    }
  }

  # La KB valida el acceso al vector store al crearse: los permisos del rol
  # deben existir antes.
  depends_on = [aws_iam_role_policy.kb]
}

# ---------------------------------------------------------------------------
# Data Source: de dónde lee la KB y cómo parte los documentos en chunks.
# ---------------------------------------------------------------------------

resource "aws_bedrockagent_data_source" "s3" {
  name              = "${local.name}-s3-docs"
  knowledge_base_id = aws_bedrockagent_knowledge_base.kb.id

  # DELETE: al borrar el data source se borran también sus vectores.
  # RETAIN los conservaría en el vector store.
  data_deletion_policy = "DELETE"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn              = module.docs.arn
      bucket_owner_account_id = local.account_id
      inclusion_prefixes      = ["documentos/"]
    }
  }

  # La estrategia de chunking NO se puede cambiar después de crear el data
  # source: habría que borrarlo, recrearlo y volver a ingerir.
  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}
