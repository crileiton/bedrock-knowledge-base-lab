# Laboratorio: Amazon Bedrock Knowledge Bases — KB vectorial vs Managed KB

Laboratorio práctico de **Amazon Bedrock Knowledge Bases**, hecho como preparación para la certificación **AWS Certified Generative AI Developer – Professional**.

Se construyen con Terraform **dos Knowledge Bases sobre los mismos documentos** y se comparan con una batería de pruebas reproducible:

| | KB vectorial (customer-managed) | Managed KB |
|---|---|---|
| Qué controlas | Vector store, embeddings, chunking | Solo la fuente de datos |
| Vector store | Amazon S3 Vectors | Administrado por Bedrock |
| Respuestas | `RetrieveAndGenerate` | `AgenticRetrieveStream` (recuperación agéntica) |
| Región usada | `us-east-2` | `us-east-1` |

📊 **Resultados, tiempos y conclusiones:** [`docs/RESULTADOS.md`](docs/RESULTADOS.md)

💡 **Todo el laboratorio explicado de forma sencilla, con ejemplos de la vida diaria:** [`docs/EXPLICACION-SENCILLA.md`](docs/EXPLICACION-SENCILLA.md)

## Hallazgos principales

| | KB vectorial | Managed KB |
|---|---|---|
| Ingesta inicial (3 documentos) | 4,9 s | 152,2 s |
| `Retrieve` (mediana) | 0,49 s | 0,58 s |
| Respuesta simple (mediana) | 2,00 s | 5,41 s |
| Pregunta que cruza 3 documentos | ❌ Respuesta incorrecta (2,7 s) | ✅ Respuesta correcta (10,9 s) |
| Pregunta fuera de alcance | ✅ No inventa | ✅ No inventa |

En preguntas simples, la KB vectorial es más rápida e igual de precisa. En preguntas que requieren encadenar información de varios documentos, la recuperación agéntica de la Managed KB fue la única que respondió bien. El detalle está en [`docs/RESULTADOS.md`](docs/RESULTADOS.md).

## Arquitectura

```
                       docs-fuente/*.md (+ .metadata.json)
                                     │
                ┌────────────────────┴────────────────────┐
                ▼                                         ▼
    S3 docs bucket (us-east-2)                S3 docs bucket (us-east-1)
                │ data source S3                          │ conector S3 administrado
                ▼                                         ▼
  ┌───────────────────────────────┐        ┌───────────────────────────────┐
  │ KB vectorial (tipo VECTOR)    │        │ Managed KB (tipo MANAGED)     │
  │ - Chunking fijo 300 tok / 20% │        │ - Parsing multimodal          │
  │ - Titan Text Embeddings V2    │        │ - Chunking por estructura     │
  │   (1024 dims)                 │        │ - Embeddings y re-ranker      │
  └───────────────┬───────────────┘        │   administrados               │
                  ▼                        │ - Almacén administrado        │
  S3 Vectors (vector bucket + índice)      └───────────────┬───────────────┘
                  ▲                                        ▲
  Retrieve / RetrieveAndGenerate             Retrieve / AgenticRetrieveStream
  (Claude Haiku 4.5)                         (modelos administrados)
```

## Estructura del repositorio

| Ruta | Contenido |
|---|---|
| [`terraform/`](terraform) | Toda la infraestructura |
| ├─ `s3_documentos.tf` | Bucket de documentos de la KB vectorial |
| ├─ `s3_vectors.tf` | Vector bucket e índice de S3 Vectors |
| ├─ `iam.tf` | Rol de servicio de la KB vectorial |
| ├─ `knowledge_base.tf` | KB vectorial y su data source (chunking) |
| ├─ `managed_kb.tf` | Managed KB: bucket, rol, KB y conector |
| └─ `modules/bucket_documentos/` | Bucket S3 seguro reutilizable (uno por región) |
| [`docs-fuente/`](docs-fuente) | 3 documentos ficticios de una cooperativa cafetera, cada uno con su `.metadata.json` |
| [`scripts/`](scripts) | `ingest.py` (ingesta), `query.py` (consultas), `pruebas.py` (batería de pruebas) |
| [`resultados/pruebas.json`](resultados/pruebas.json) | Resultados crudos de la batería de pruebas |
| [`docs/RESULTADOS.md`](docs/RESULTADOS.md) | Pruebas, respuestas, tiempos, comparación y conclusiones |
| [`docs/EXPLICACION-SENCILLA.md`](docs/EXPLICACION-SENCILLA.md) | El laboratorio completo explicado sin tecnicismos |

Los documentos son **ficticios a propósito**: si el modelo responde con esos datos, la respuesta salió de la KB y no de su entrenamiento.

## Requisitos

- Terraform >= 1.9 y AWS provider >= 6.72 (versión con soporte para S3 Vectors y Managed KB)
- AWS CLI v2 con un perfil configurado. El perfil está fijo como `real` en [`terraform/providers.tf`](terraform/providers.tf) y en [`scripts/comun.py`](scripts/comun.py); **cámbialo por el tuyo**. Va fijo y no como variable para que nadie apunte a otra cuenta por accidente desde un `tfvars`
- Python 3.10+
- **Cuota de inferencia en Bedrock** para Titan Text Embeddings V2 y Claude Haiku 4.5. Revísala en Service Quotas (servicio `bedrock`): si es 0, la ingesta falla con `429` aunque IAM esté bien
- Regiones: `us-east-2` para la KB vectorial y una región con Managed KB (por defecto `us-east-1`)

## Cómo reproducir el laboratorio

```bash
# 1. Infraestructura (35 recursos en dos regiones)
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

# 4. Consultas manuales
.venv/bin/python scripts/query.py retrieve "¿Cuántos días tengo para devolver un café?"
.venv/bin/python scripts/query.py generate "¿Cuánto cuesta el plan anual?"
.venv/bin/python scripts/query.py generate "¿Cuánto dura el secado honey?" --categoria produccion
.venv/bin/python scripts/query.py retrieve "¿Cuántos días tengo para devolver un café?" --kb managed
.venv/bin/python scripts/query.py agentic "¿Cuánto cuesta el plan anual con café honey y puedo devolverlo?" --kb managed

# 5. Batería de pruebas completa (escribe resultados/pruebas.json)
.venv/bin/python scripts/pruebas.py --repeticiones 3

# 6. Limpieza: elimina todo en las dos regiones
cd terraform && terraform destroy
```

### Costo

Con 3 documentos y unas decenas de consultas, el costo total es de centavos de dólar. Nada cobra por estar encendido sin uso:
- S3 y S3 Vectors cobran por almacenamiento y peticiones.
- Titan y Claude cobran por token.
- La Managed KB cobra por almacenamiento y por llamada de recuperación.

Aun así, **ejecuta `terraform destroy` al terminar**.

## Conceptos para el examen

| Concepto | Qué se ve en este laboratorio |
|---|---|
| Data source | Bedrock **lee** los documentos de S3, no los copia; los cambios en S3 requieren una nueva ingesta, que es incremental |
| Chunking | Tamaño fijo de 300 tokens con 20 % de solapamiento; **no se puede cambiar** sin recrear el data source. El chunking por estructura de la Managed KB conserva las secciones completas |
| Embeddings | Titan Text Embeddings V2 a 1024 dimensiones; la dimensión debe coincidir con la del índice y no se puede cambiar |
| Vector store | S3 Vectors con distancia coseno; el texto del chunk va en metadatos **no filtrables** por el límite de 2 KB |
| Rol de servicio | Trust policy con `aws:SourceAccount` y `aws:SourceArn` (protección contra *confused deputy*); en la Managed KB el rol solo lee la fuente |
| `Retrieve` | En la KB vectorial devuelve siempre K resultados; con re-ranking, la Managed KB descarta los poco relevantes |
| `RetrieveAndGenerate` | Una búsqueda, un LLM y citas. No disponible en la Managed KB |
| `AgenticRetrieveStream` | Planificar → recuperar → evaluar → repetir. Resuelve preguntas multi-hop a cambio de más latencia |
| Filtrado por metadatos | `.metadata.json` junto a cada documento; el filtro se aplica **antes** de la búsqueda, por eso sirve como control de acceso por documento |
| Grounding | Ante preguntas fuera de alcance, las dos KB dicen que no tienen la información en vez de inventar |
| Cuotas | Con cuota 0 de inferencia, la ingesta falla con `429` aunque IAM esté bien |
| Regiones | La Managed KB solo está en algunas regiones, y el bucket debe estar en la misma región que la KB |

## Seguridad

- Ni el código ni los resultados contienen IDs de cuenta, ARNs, IDs de recursos ni credenciales: se obtienen en tiempo de ejecución.
- El estado de Terraform (`*.tfstate`), los `*.tfvars` y los entornos locales están en `.gitignore`.
- Los buckets bloquean el acceso público, cifran en reposo, guardan versiones y rechazan peticiones sin TLS.
- Los roles siguen el principio de mínimo privilegio (validados con IAM Access Analyzer) y tienen protección contra *confused deputy*.
