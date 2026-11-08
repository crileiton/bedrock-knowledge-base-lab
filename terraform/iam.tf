# ---------------------------------------------------------------------------
# Rol de servicio de la Knowledge Base.
# Bedrock asume este rol durante la ingesta y las consultas para leer los
# documentos, generar embeddings y leer/escribir vectores.
# ---------------------------------------------------------------------------

# Trust policy: quién puede asumir el rol.
data "aws_iam_policy_document" "kb_trust" {
  statement {
    sid     = "AllowBedrockKnowledgeBases"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    # Protección contra "confused deputy": Bedrock solo puede asumir el rol
    # cuando actúa para una knowledge base de esta cuenta y esta región,
    # no para recursos de otra cuenta que intenten usar este rol.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:bedrock:${local.region}:${local.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "kb" {
  name               = "${local.name}-kb-role"
  description        = "Rol de servicio de la Bedrock Knowledge Base del laboratorio"
  assume_role_policy = data.aws_iam_policy_document.kb_trust.json
}

# Permisos: qué puede hacer el rol una vez asumido (mínimo privilegio).
data "aws_iam_policy_document" "kb_permissions" {
  # 1) Generar embeddings: solo el modelo de embeddings elegido.
  statement {
    sid       = "InvokeEmbeddingModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = ["arn:${local.partition}:bedrock:${local.region}::foundation-model/${var.embedding_model_id}"]
  }

  # 2) Leer los documentos fuente: listar el bucket y leer solo el prefijo documentos/.
  statement {
    sid       = "ListDocsBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [module.docs.arn]

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
    resources = ["${module.docs.arn}/documentos/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  # 3) Vector store: escribir, borrar y consultar vectores solo en este índice.
  statement {
    sid    = "S3VectorsIndexAccess"
    effect = "Allow"
    actions = [
      "s3vectors:GetIndex",
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors",
      "s3vectors:QueryVectors",
    ]
    resources = [aws_s3vectors_index.kb.index_arn]
  }
}

resource "aws_iam_role_policy" "kb" {
  name   = "kb-permisos"
  role   = aws_iam_role.kb.id
  policy = data.aws_iam_policy_document.kb_permissions.json
}
