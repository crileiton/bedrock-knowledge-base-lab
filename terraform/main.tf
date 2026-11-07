# Datos de la cuenta obtenidos en tiempo de ejecución: así el código
# no contiene IDs de cuenta y se puede publicar sin exponerlos.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

# Los nombres de bucket son globales; un sufijo aleatorio evita colisiones
# sin usar el ID de cuenta en el nombre.
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  name       = "${var.project_name}-${random_id.suffix.hex}"
}
