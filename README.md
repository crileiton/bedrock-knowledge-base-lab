# Laboratorio: Amazon Bedrock Knowledge Bases con Terraform

Laboratorio práctico para entender **Amazon Bedrock Knowledge Bases (KB)** como preparación para la certificación **AWS Certified Generative AI Developer – Professional**.

Toda la infraestructura se crea con Terraform. Las consultas a la KB se hacen con scripts de Python (boto3).

## Arquitectura

```
 docs-fuente/*.md ──► S3 (bucket de documentos)
                          │
                          ▼  Ingestion job
                 ┌──────────────────────────┐
                 │  Bedrock Knowledge Base  │  1. Parsing
                 │  (tipo VECTOR)           │  2. Chunking
                 │                          │  3. Embeddings (Titan Text v2)
                 └────────────┬─────────────┘
                              ▼
                 S3 Vectors (vector bucket + índice)
                              ▲
   Retrieve / RetrieveAndGenerate (bedrock-agent-runtime)
```

## Requisitos

- Terraform >= 1.9
- AWS CLI v2 con un perfil configurado. El perfil está fijo como `real` en `terraform/providers.tf` y en `scripts/comun.py`; cámbialo por el tuyo
- Python 3.10+ con `boto3` reciente
- Bedrock disponible en la región (por defecto `us-east-2`)
- **Cuota de inferencia** en la cuenta para el modelo de embeddings y el modelo generativo. Revísala en Service Quotas (servicio `bedrock`): si es 0, la ingesta falla con `429 Too many requests` aunque los permisos de IAM estén bien

## Estructura

| Ruta | Contenido |
|---|---|
| `terraform/` | Infraestructura (S3, S3 Vectors, IAM, Knowledge Base) |
| `docs-fuente/` | Documentos ficticios que se ingieren en la KB |
| `scripts/` | Ingesta y consultas a la KB |

## Seguridad

- No hay IDs de cuenta, ARNs ni credenciales en el código: se obtienen en tiempo de ejecución.
- El estado de Terraform (`*.tfstate`) y los `*.tfvars` están en `.gitignore`.
- Los buckets bloquean el acceso público, cifran en reposo y exigen TLS.
- El rol de la KB sigue el principio de mínimo privilegio y tiene protección contra *confused deputy*.
