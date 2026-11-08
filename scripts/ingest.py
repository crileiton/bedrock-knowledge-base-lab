"""Lanza un ingestion job en la Knowledge Base y espera a que termine.

La ingesta es una operación (no infraestructura), por eso no está en Terraform.
Se ejecuta cada vez que cambian los documentos del data source: Bedrock
procesa solo lo nuevo, lo modificado y lo eliminado (sincronización incremental).

Uso:
    python scripts/ingest.py [--kb vectorial|managed] [--perfil real] [--region us-east-2]
"""

import argparse
import sys
import time

from botocore.exceptions import ClientError

from comun import PERFIL_POR_DEFECTO, REGION_POR_DEFECTO, datos_kb, sesion

ESTADOS_FINALES = {"COMPLETE", "FAILED", "STOPPED"}


def esperar_data_source(cliente, kb_id: str, ds_id: str, intervalo: int = 10) -> None:
    """En una Managed KB el data source se crea de forma asíncrona: hay que
    esperar a que esté AVAILABLE antes de sincronizar."""
    while True:
        estado = cliente.get_data_source(knowledgeBaseId=kb_id, dataSourceId=ds_id)["dataSource"]["status"]
        if estado == "AVAILABLE":
            return
        if estado in {"DELETE_UNSUCCESSFUL", "FAILED"}:
            raise RuntimeError(f"El data source está en estado {estado}")
        print(f"  data source: {estado}, esperando...")
        time.sleep(intervalo)


def ejecutar_ingesta(cliente, kb_id: str, ds_id: str, intervalo: int = 10) -> dict:
    """Inicia la ingesta y consulta su estado hasta que llegue a un estado final."""
    esperar_data_source(cliente, kb_id, ds_id, intervalo)
    job = cliente.start_ingestion_job(knowledgeBaseId=kb_id, dataSourceId=ds_id)["ingestionJob"]
    job_id = job["ingestionJobId"]
    print(f"Ingestion job iniciado: {job_id}")

    while job["status"] not in ESTADOS_FINALES:
        time.sleep(intervalo)
        job = cliente.get_ingestion_job(
            knowledgeBaseId=kb_id, dataSourceId=ds_id, ingestionJobId=job_id
        )["ingestionJob"]
        print(f"  estado: {job['status']}")

    return job


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--kb", choices=["vectorial", "managed"], default="vectorial")
    parser.add_argument("--perfil", default=PERFIL_POR_DEFECTO)
    parser.add_argument("--region", default=REGION_POR_DEFECTO, help="Región de la KB vectorial.")
    args = parser.parse_args()

    kb_id, ds_id, region = datos_kb(args.kb, args.region)
    print(f"KB {args.kb}: {kb_id} ({region})")
    cliente = sesion(args.perfil, region).client("bedrock-agent")

    try:
        job = ejecutar_ingesta(cliente, kb_id, ds_id)
    except (ClientError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    stats = job.get("statistics", {})
    print(f"\nEstado final: {job['status']}")
    print(f"  documentos escaneados:          {stats.get('numberOfDocumentsScanned', 0)}")
    print(f"  metadatos escaneados:           {stats.get('numberOfMetadataDocumentsScanned', 0)}")
    print(f"  documentos nuevos indexados:    {stats.get('numberOfNewDocumentsIndexed', 0)}")
    print(f"  documentos modificados:         {stats.get('numberOfModifiedDocumentsIndexed', 0)}")
    print(f"  documentos eliminados:          {stats.get('numberOfDocumentsDeleted', 0)}")
    print(f"  documentos fallidos:            {stats.get('numberOfDocumentsFailed', 0)}")
    for razon in job.get("failureReasons", []):
        print(f"  razón de fallo: {razon}", file=sys.stderr)

    return 0 if job["status"] == "COMPLETE" else 1


if __name__ == "__main__":
    sys.exit(main())
