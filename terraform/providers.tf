provider "aws" {
  region = var.region

  # Perfil fijo (no variable) a propósito: así no se puede apuntar a otra
  # cuenta por accidente desde un tfvars. Cámbialo por tu propio perfil.
  profile = "real"

  # Todas las etiquetas se aplican a cada recurso: facilita costos y limpieza.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Purpose   = "lab-certificacion-genai"
    }
  }
}
