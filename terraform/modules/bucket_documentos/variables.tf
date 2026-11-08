variable "bucket_name" {
  description = "Nombre del bucket S3."
  type        = string
}

variable "source_dir" {
  description = "Directorio local con los documentos que se suben al bucket."
  type        = string
}

variable "key_prefix" {
  description = "Prefijo de las claves de los objetos en S3 (termina en /)."
  type        = string
  default     = "documentos/"
}
