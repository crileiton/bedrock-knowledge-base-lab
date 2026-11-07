# ---------------------------------------------------------------------------
# Data source de la Knowledge Base: bucket S3 con los documentos originales.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "docs" {
  bucket = "${local.name}-docs"

  # Es un laboratorio: permite que `terraform destroy` borre el bucket con objetos.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "docs" {
  bucket = aws_s3_bucket.docs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "docs" {
  bucket = aws_s3_bucket.docs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "docs" {
  bucket = aws_s3_bucket.docs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "docs" {
  bucket = aws_s3_bucket.docs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Rechaza cualquier petición que no use HTTPS.
data "aws_iam_policy_document" "docs_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.docs.arn,
      "${aws_s3_bucket.docs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "docs" {
  bucket = aws_s3_bucket.docs.id
  policy = data.aws_iam_policy_document.docs_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.docs]
}

# Sube cada documento (y su archivo .metadata.json) de docs-fuente/.
# El etag hace que Terraform vuelva a subir el archivo si cambia su contenido.
resource "aws_s3_object" "docs" {
  for_each = fileset("${path.module}/../docs-fuente", "**")

  bucket = aws_s3_bucket.docs.id
  key    = "documentos/${each.value}"
  source = "${path.module}/../docs-fuente/${each.value}"
  etag   = filemd5("${path.module}/../docs-fuente/${each.value}")

  content_type = endswith(each.value, ".json") ? "application/json" : "text/markdown"
}
