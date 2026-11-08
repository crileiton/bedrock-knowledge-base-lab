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

# Segundo provider para la Managed KB, que no está disponible en todas las
# regiones. Los recursos lo eligen con `provider = aws.managed_kb`.
provider "aws" {
  alias   = "managed_kb"
  region  = var.managed_kb_region
  profile = "real"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Purpose   = "lab-certificacion-genai"
    }
  }
}
