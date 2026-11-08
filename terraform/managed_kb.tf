# ---------------------------------------------------------------------------
# Managed Knowledge Base (tipo MANAGED), para comparar con la KB vectorial.
# Bedrock administra el almacén de vectores, el parsing, el chunking, el
# modelo de embeddings y el re-ranker: no hay índice ni modelo que elegir.
# ---------------------------------------------------------------------------

# El bucket debe estar en la misma región que la KB.
module "docs_managed" {
  source = "./modules/bucket_documentos"
  providers = {
    aws = aws.managed_kb
  }

  bucket_name = "${local.name}-docs-mkb"
  source_dir  = "${path.module}/../docs-fuente"
}

# Rol de servicio. Misma protección contra confused deputy, pero en la
# región de la Managed KB.
data "aws_iam_policy_document" "managed_kb_trust" {
  statement {
    sid     = "AllowBedrockKnowledgeBases"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:bedrock:${var.managed_kb_region}:${local.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "managed_kb" {
  name               = "${local.name}-mkb-role"
  description        = "Rol de servicio de la Managed Knowledge Base del laboratorio"
  assume_role_policy = data.aws_iam_policy_document.managed_kb_trust.json
}

# Comparado con el rol de la KB vectorial, solo necesita leer los documentos:
# no invoca un modelo de embeddings propio ni escribe en un vector store.
data "aws_iam_policy_document" "managed_kb_permissions" {
  statement {
    sid       = "ListDocsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.docs_managed.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "ReadDocsObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.docs_managed.arn}/${module.docs_managed.key_prefix}*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role_policy" "managed_kb" {
  name   = "mkb-permisos"
  role   = aws_iam_role.managed_kb.id
  policy = data.aws_iam_policy_document.managed_kb_permissions.json
}

resource "aws_bedrockagent_knowledge_base" "managed" {
  provider = aws.managed_kb

  name        = "${local.name}-mkb"
  description = "Managed KB del laboratorio con los mismos documentos que la KB vectorial"
  role_arn    = aws_iam_role.managed_kb.arn

  knowledge_base_configuration {
    type = "MANAGED"

    managed_knowledge_base_configuration {
      # Embeddings administrados por AWS, sin costo por token.
      # CUSTOM permitiría elegir un modelo de Bedrock (float32, 1024 dims).
      embedding_model_type = "MANAGED"
    }
  }

  # Sin storage_configuration: el almacén lo administra Bedrock.

  depends_on = [aws_iam_role_policy.managed_kb]
}

resource "aws_bedrockagent_data_source" "managed_s3" {
  provider = aws.managed_kb

  name              = "${local.name}-mkb-s3-docs"
  knowledge_base_id = aws_bedrockagent_knowledge_base.managed.id

  # Una Managed KB usa conectores administrados, no la forma s3_configuration
  # de la KB vectorial. Tampoco se configura el chunking: lo hace Bedrock.
  data_source_configuration {
    type = "MANAGED_KNOWLEDGE_BASE_CONNECTOR"

    # Bedrock completa los valores que faltan (filterConfiguration, aclEnabled,
    # extracción de imágenes) y el provider marca la diferencia como error.
    # Por eso se declaran explícitamente con sus valores por defecto.
    managed_knowledge_base_connector_configuration {
      connector_parameters = jsonencode({
        type    = "S3"
        version = "1"
        connectionConfiguration = {
          bucketName           = module.docs_managed.bucket
          bucketOwnerAccountId = local.account_id
        }
        # Archivos más grandes se omiten en la sincronización.
        filterConfiguration = {
          maxFileSizeInMegaBytes = "500"
        }
        # ACL: filtrar resultados según los permisos del usuario en la fuente.
        aclEnabled = false
      })

      # Parsing multimodal: extrae y entiende las imágenes de los documentos.
      media_extraction_configuration {
        image_extraction_configuration {
          image_extraction_status = "ENABLED"
        }
      }
    }
  }
}
