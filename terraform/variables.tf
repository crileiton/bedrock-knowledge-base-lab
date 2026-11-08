variable "region" {
  description = "Región de AWS donde se despliega el laboratorio."
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Prefijo para nombrar los recursos."
  type        = string
  default     = "kb-lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Usa solo minúsculas, números y guiones (3 a 20 caracteres)."
  }
}

variable "embedding_model_id" {
  description = "Modelo de embeddings que convierte cada chunk en un vector."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Dimensiones del vector. Debe coincidir en el modelo de embeddings y en el índice vectorial."
  type        = number
  default     = 1024

  # Titan Text Embeddings V2 admite 256, 512 o 1024 dimensiones.
  validation {
    condition     = contains([256, 512, 1024], var.embedding_dimensions)
    error_message = "Titan Text Embeddings V2 solo admite 256, 512 o 1024 dimensiones."
  }
}

variable "managed_kb_region" {
  description = "Región de la Managed KB. Debe ser una región donde exista el servicio (p. ej. us-east-1 o us-west-2)."
  type        = string
  default     = "us-east-1"
}
