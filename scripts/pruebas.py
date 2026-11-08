"""Ejecuta la batería de pruebas contra la KB vectorial y la Managed KB.

Mide la latencia de cada consulta (varias repeticiones) y lee el historial de
ingestion jobs. Guarda los resultados en resultados/pruebas.json sin IDs de
cuenta, ARNs ni IDs de recursos, para poder publicarlos.

Uso:
    python scripts/pruebas.py [--repeticiones 3]
"""

import argparse
import json
import statistics
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from botocore.exceptions import ClientError

from comun import PERFIL_POR_DEFECTO, REGION_POR_DEFECTO, datos_kb, sesion
from query import MODELO_GENERATIVO_POR_DEFECTO, agentic, configuracion_busqueda, generar, nombre_documento, recuperar

SALIDA = Path(__file__).resolve().parent.parent / "resultados" / "pruebas.json"

# modo "respuesta": RetrieveAndGenerate en la KB vectorial y
# AgenticRetrieveStream en la Managed KB (que no soporta RetrieveAndGenerate).
CASOS = [
    {
        "id": "P1",
        "titulo": "Recuperación de un dato puntual",
        "modo": "retrieve",
        "pregunta": "¿Cuántos días tengo para devolver un café y qué condiciones debe cumplir?",
    },
    {
        "id": "P2",
        "titulo": "Respuesta generada con citas",
        "modo": "respuesta",
        "pregunta": "¿Cuántos días tengo para devolver un café y qué condiciones debe cumplir?",
    },
    {
        "id": "P3",
        "titulo": "Filtro por metadatos que excluye la respuesta",
        "modo": "retrieve",
        "pregunta": "¿Cuántos días dura el secado del proceso honey?",
        "categoria": "atencion-cliente",
    },
    {
        "id": "P4",
        "titulo": "Filtro por metadatos que incluye la respuesta",
        "modo": "retrieve",
        "pregunta": "¿Cuántos días dura el secado del proceso honey?",
        "categoria": "produccion",
    },
    {
        "id": "P5",
        "titulo": "Pregunta multi-hop (requiere tres documentos)",
        "modo": "respuesta",
        "pregunta": (
            "Quiero el café que se hace con proceso honey pero en suscripción anual. "
            "¿Cuánto pagaría, qué recibo de regalo y puedo devolverlo si no me gusta?"
        ),
    },
    {
        "id": "P6",
        "titulo": "Pregunta fuera del alcance de los documentos",
        "modo": "respuesta",
        "pregunta": "¿Tienen tienda física en Medellín y cuál es su horario de atención?",
    },
]


def chunks(resultados: list[dict]) -> list[dict]:
    return [
        {
            "documento": nombre_documento(r["location"]),
            "score": round(r["score"], 3),
            "categoria": r.get("metadata", {}).get("categoria"),
            "inicio_texto": " ".join(r["content"]["text"].split())[:160],
        }
        for r in resultados
    ]


def ejecutar_caso(caso: dict, tipo_kb: str, cliente, kb_id: str, model_arn: str) -> dict:
    """Ejecuta un caso una vez y devuelve la parte publicable del resultado."""
    busqueda = configuracion_busqueda(tipo_kb, 3, caso.get("categoria"))

    if caso["modo"] == "retrieve":
        return {"api": "Retrieve", "chunks": chunks(recuperar(cliente, kb_id, caso["pregunta"], busqueda))}

    if tipo_kb == "vectorial":
        r = generar(cliente, kb_id, model_arn, caso["pregunta"], busqueda)
        return {
            "api": "RetrieveAndGenerate",
            "respuesta": r["output"]["text"],
            "documentos_citados": sorted(
                {nombre_documento(ref["location"]) for c in r.get("citations", []) for ref in c["retrievedReferences"]}
            ),
        }

    resultado, pasos = agentic(cliente, kb_id, caso["pregunta"])
    generada = resultado.get("generatedResponse", {})
    documentos = resultado.get("results", [])
    return {
        "api": "AgenticRetrieveStream",
        "respuesta": generada.get("answer", ""),
        "pasos_agente": pasos,
        "documentos_citados": sorted(
            {
                documentos[ref["resultIndex"]].get("metadata", {}).get("_document_title", "?")
                for c in generada.get("citations", [])
                for ref in c["references"]
                if ref["resultIndex"] < len(documentos)
            }
        ),
    }


def medir(caso: dict, tipo_kb: str, cliente, kb_id: str, model_arn: str, repeticiones: int) -> dict:
    """Repite el caso para medir latencia; guarda la salida de la primera ejecución."""
    latencias, salida = [], None
    for _ in range(repeticiones):
        inicio = time.perf_counter()
        resultado = ejecutar_caso(caso, tipo_kb, cliente, kb_id, model_arn)
        latencias.append(round(time.perf_counter() - inicio, 2))
        salida = salida or resultado
    return {**salida, "latencias_s": latencias, "latencia_mediana_s": round(statistics.median(latencias), 2)}


def historial_ingesta(cliente, kb_id: str, ds_id: str) -> list[dict]:
    paginador = cliente.get_paginator("list_ingestion_jobs")
    trabajos = []
    for pagina in paginador.paginate(
        knowledgeBaseId=kb_id, dataSourceId=ds_id, sortBy={"attribute": "STARTED_AT", "order": "ASCENDING"}
    ):
        for t in pagina["ingestionJobSummaries"]:
            stats = t.get("statistics", {})
            trabajos.append(
                {
                    "estado": t["status"],
                    "inicio_utc": t["startedAt"].astimezone(timezone.utc).isoformat(timespec="seconds"),
                    "duracion_s": round((t["updatedAt"] - t["startedAt"]).total_seconds(), 1),
                    "escaneados": stats.get("numberOfDocumentsScanned", 0),
                    "nuevos": stats.get("numberOfNewDocumentsIndexed", 0),
                    "modificados": stats.get("numberOfModifiedDocumentsIndexed", 0),
                    "eliminados": stats.get("numberOfDocumentsDeleted", 0),
                    "fallidos": stats.get("numberOfDocumentsFailed", 0),
                }
            )
    return trabajos


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repeticiones", type=int, default=3)
    parser.add_argument("--perfil", default=PERFIL_POR_DEFECTO)
    parser.add_argument("--region", default=REGION_POR_DEFECTO, help="Región de la KB vectorial.")
    args = parser.parse_args()

    informe = {
        "fecha_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "repeticiones_por_caso": args.repeticiones,
        "modelo_generativo_kb_vectorial": MODELO_GENERATIVO_POR_DEFECTO,
        "kbs": {},
        "casos": [],
    }

    try:
        conexiones = {}
        for tipo in ("vectorial", "managed"):
            kb_id, ds_id, region = datos_kb(tipo, args.region)
            s = sesion(args.perfil, region)
            cuenta = s.client("sts").get_caller_identity()["Account"]
            conexiones[tipo] = (
                s.client("bedrock-agent-runtime"),
                kb_id,
                f"arn:aws:bedrock:{region}:{cuenta}:inference-profile/{MODELO_GENERATIVO_POR_DEFECTO}",
            )
            informe["kbs"][tipo] = {
                "region": region,
                "ingestas": historial_ingesta(s.client("bedrock-agent"), kb_id, ds_id),
            }

        for caso in CASOS:
            fila = {k: v for k, v in caso.items()}
            for tipo, (cliente, kb_id, model_arn) in conexiones.items():
                print(f"{caso['id']} [{tipo}] {caso['titulo']}...", flush=True)
                fila[tipo] = medir(caso, tipo, cliente, kb_id, model_arn, args.repeticiones)
            informe["casos"].append(fila)
    except (ClientError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    SALIDA.parent.mkdir(exist_ok=True)
    SALIDA.write_text(json.dumps(informe, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nResultados guardados en {SALIDA.relative_to(SALIDA.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
