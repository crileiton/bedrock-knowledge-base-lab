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
