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
| `terraform/` | Infraestructura (S3, S3 Vectors, IAM, KB vectorial en `us-east-2` y Managed KB en `us-east-1`) |
| `terraform/modules/bucket_documentos/` | Bucket S3 seguro reutilizable, uno por región |
| `docs-fuente/` | Documentos ficticios que se ingieren en la KB |
| `scripts/` | Ingesta y consultas a la KB |

## Uso

```bash
# 1. Infraestructura
cd terraform
terraform init
terraform apply
cd ..

# 2. Entorno de Python
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements.txt

# 3. Ingesta (repetir cada vez que cambien los documentos)
.venv/bin/python scripts/ingest.py --kb vectorial
.venv/bin/python scripts/ingest.py --kb managed

# 4. Consultas
.venv/bin/python scripts/query.py retrieve "¿Cuántos días tengo para devolver un café?"
.venv/bin/python scripts/query.py generate "¿Cuánto cuesta el plan anual?"
.venv/bin/python scripts/query.py generate "¿Cuánto dura el secado honey?" --categoria produccion
.venv/bin/python scripts/query.py retrieve "¿Cuántos días tengo para devolver un café?" --kb managed
.venv/bin/python scripts/query.py agentic "¿Cuánto cuesta el plan anual con café honey y puedo devolverlo?" --kb managed

# 5. Limpieza
cd terraform && terraform destroy
```

## Conceptos clave para el examen

| Concepto | Qué se ve en este laboratorio |
|---|---|
| Data source | Bedrock lee los documentos de S3, no los copia; cambios en S3 requieren una nueva ingesta |
| Chunking | Tamaño fijo de 300 tokens con 20 % de solapamiento; no se puede cambiar sin recrear el data source |
| Embeddings | Titan Text Embeddings V2 a 1024 dimensiones; la dimensión debe coincidir con la del índice |
| Vector store | S3 Vectors con distancia coseno; el texto del chunk va en metadatos no filtrables |
| Rol de servicio | Trust policy con `aws:SourceAccount` y `aws:SourceArn` (confused deputy) |
| `Retrieve` | Devuelve los K chunks más parecidos con su score, aunque no sean relevantes |
| `RetrieveAndGenerate` | Pasa los chunks a un LLM y devuelve una respuesta con citas; si no hay contexto útil, se niega a responder |
| Filtrado por metadatos | `.metadata.json` junto a cada documento; el filtro se aplica antes de la búsqueda semántica |
| Cuotas | Con cuota 0 de inferencia, la ingesta falla con `429` aunque IAM esté bien |

## KB vectorial vs Managed KB

El laboratorio crea las dos con los mismos documentos para compararlas.

| | KB vectorial (`VECTOR`) | Managed KB (`MANAGED`) |
|---|---|---|
| Vector store | Lo eliges y lo creas tú (aquí, S3 Vectors) | Lo administra Bedrock |
| Embeddings | Eliges el modelo y las dimensiones | Modelo administrado sin costo extra (o uno propio de 1024 dims) |
| Chunking | Lo configuras tú y no se puede cambiar | Automático y consciente de la estructura (respeta secciones) |
| Permisos del rol | Modelo de embeddings + S3 + vector store | Solo leer la fuente |
| Data source | `s3_configuration` | Conector administrado (`MANAGED_KNOWLEDGE_BASE_CONNECTOR`) |
| Configuración de búsqueda | `vectorSearchConfiguration` | `managedSearchConfiguration` (con re-ranking) |
| `RetrieveAndGenerate` | Sí | **No**: se usa `AgenticRetrieveStream` |
| Recuperación agéntica (multi-hop) | No | Sí |
| Regiones | Casi todas | Solo algunas (no `us-east-2`) |
| Ingesta de 3 documentos | ~10 s | ~2,5 min (parsing multimodal) |

## Seguridad

- No hay IDs de cuenta, ARNs ni credenciales en el código: se obtienen en tiempo de ejecución.
- El estado de Terraform (`*.tfstate`) y los `*.tfvars` están en `.gitignore`.
- Los buckets bloquean el acceso público, cifran en reposo y exigen TLS.
- El rol de la KB sigue el principio de mínimo privilegio y tiene protección contra *confused deputy*.
