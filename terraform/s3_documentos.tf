# ---------------------------------------------------------------------------
# Data source de la KB vectorial: bucket S3 con los documentos originales.
# ---------------------------------------------------------------------------

module "docs" {
  source = "./modules/bucket_documentos"

  bucket_name = "${local.name}-docs"
  source_dir  = "${path.module}/../docs-fuente"
}

# Los recursos se crearon antes de existir el módulo. Los bloques `moved`
# le dicen a Terraform que son los mismos objetos con otra dirección, para
# que los mueva en el estado en vez de destruirlos y crearlos de nuevo.
moved {
  from = aws_s3_bucket.docs
  to   = module.docs.aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_public_access_block.docs
  to   = module.docs.aws_s3_bucket_public_access_block.this
}

moved {
  from = aws_s3_bucket_ownership_controls.docs
  to   = module.docs.aws_s3_bucket_ownership_controls.this
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.docs
  to   = module.docs.aws_s3_bucket_server_side_encryption_configuration.this
}

moved {
  from = aws_s3_bucket_versioning.docs
  to   = module.docs.aws_s3_bucket_versioning.this
}

moved {
  from = aws_s3_bucket_policy.docs
  to   = module.docs.aws_s3_bucket_policy.this
}

moved {
  from = aws_s3_object.docs
  to   = module.docs.aws_s3_object.this
}
