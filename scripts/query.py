"""Consulta la Knowledge Base con Retrieve o con RetrieveAndGenerate.

  retrieve  Devuelve los chunks más parecidos a la pregunta con su score.
            No llama a ningún LLM: tú decides qué hacer con los chunks.
  generate  Recupera los chunks, los pasa a un LLM y devuelve una respuesta
            redactada con citas a los documentos fuente.

Uso:
    python scripts/query.py retrieve "¿Cuántos días tengo para devolver un café?"
    python scripts/query.py generate "¿Cuánto cuesta el plan anual?" --categoria atencion-cliente
"""

import argparse
import sys

from botocore.exceptions import ClientError

from comun import PERFIL_POR_DEFECTO, REGION_POR_DEFECTO, sesion, terraform_output

# Perfil de inferencia cross-region (prefijo "us."): Bedrock reparte las
# peticiones entre regiones de EE. UU. para tener más capacidad.
MODELO_GENERATIVO_POR_DEFECTO = "us.anthropic.claude-haiku-4-5-20251001-v1:0"


def configuracion_busqueda(resultados: int, categoria: str | None) -> dict:
    """Arma la vectorSearchConfiguration, con filtro por metadatos si se pide."""
    config = {"numberOfResults": resultados}
    if categoria:
        # El filtro se aplica ANTES de la búsqueda semántica: solo se comparan
        # los chunks de documentos con esa categoría (de los .metadata.json).
        # S3 Vectors no soporta startsWith ni stringContains: usar equals, in, etc.
        config["filter"] = {"equals": {"key": "categoria", "value": categoria}}
    return {"vectorSearchConfiguration": config}


def recuperar(cliente, kb_id: str, pregunta: str, busqueda: dict) -> list[dict]:
    respuesta = cliente.retrieve(
        knowledgeBaseId=kb_id,
        retrievalQuery={"text": pregunta},
        retrievalConfiguration=busqueda,
    )
    return respuesta["retrievalResults"]


def generar(cliente, kb_id: str, model_arn: str, pregunta: str, busqueda: dict) -> dict:
    return cliente.retrieve_and_generate(
        input={"text": pregunta},
        retrieveAndGenerateConfiguration={
            "type": "KNOWLEDGE_BASE",
            "knowledgeBaseConfiguration": {
                "knowledgeBaseId": kb_id,
                "modelArn": model_arn,
                "retrievalConfiguration": busqueda,
                "generationConfiguration": {
                    # Fijar maxTokens evita reservar la salida máxima del modelo
                    # contra la cuota de tokens por minuto.
                    "inferenceConfig": {"textInferenceConfig": {"maxTokens": 512, "temperature": 0}},
                },
            },
        },
    )


def nombre_documento(ubicacion: dict) -> str:
    return ubicacion["s3Location"]["uri"].rsplit("/", 1)[-1]


def imprimir_chunks(resultados: list[dict]) -> None:
    if not resultados:
        print("Sin resultados.")
    for i, r in enumerate(resultados, 1):
        texto = " ".join(r["content"]["text"].split())
        print(f"\n[{i}] score={r['score']:.3f}  doc={nombre_documento(r['location'])}")
        print(f"    metadatos: categoria={r['metadata'].get('categoria')}")
        print(f"    {texto[:300]}{'...' if len(texto) > 300 else ''}")


def imprimir_respuesta(respuesta: dict) -> None:
    print("\nRespuesta:\n" + respuesta["output"]["text"])
    print("\nCitas:")
    for i, cita in enumerate(respuesta.get("citations", []), 1):
        fragmento = cita["generatedResponsePart"]["textResponsePart"]["text"]
        docs = sorted({nombre_documento(ref["location"]) for ref in cita["retrievedReferences"]})
        print(f"  [{i}] \"{fragmento[:90]}{'...' if len(fragmento) > 90 else ''}\"")
        print(f"      fuentes: {', '.join(docs) or 'ninguna'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("modo", choices=["retrieve", "generate"])
    parser.add_argument("pregunta")
    parser.add_argument("--resultados", type=int, default=3, help="Número de chunks a recuperar (K).")
    parser.add_argument("--categoria", help="Filtra por el metadato 'categoria' (p. ej. produccion).")
    parser.add_argument("--modelo", default=MODELO_GENERATIVO_POR_DEFECTO, help="ID del perfil de inferencia.")
    parser.add_argument("--perfil", default=PERFIL_POR_DEFECTO)
    parser.add_argument("--region", default=REGION_POR_DEFECTO)
    args = parser.parse_args()

    s = sesion(args.perfil, args.region)
    kb_id = terraform_output("knowledge_base_id")
    cliente = s.client("bedrock-agent-runtime")
    busqueda = configuracion_busqueda(args.resultados, args.categoria)

    try:
        if args.modo == "retrieve":
            imprimir_chunks(recuperar(cliente, kb_id, args.pregunta, busqueda))
        else:
            # Los perfiles de inferencia se referencian por ARN con el ID de la
            # cuenta, que se obtiene en tiempo de ejecución.
            cuenta = s.client("sts").get_caller_identity()["Account"]
            model_arn = f"arn:aws:bedrock:{args.region}:{cuenta}:inference-profile/{args.modelo}"
            imprimir_respuesta(generar(cliente, kb_id, model_arn, args.pregunta, busqueda))
    except ClientError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
