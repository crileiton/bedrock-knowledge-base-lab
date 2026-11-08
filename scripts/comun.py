"""Utilidades compartidas por los scripts del laboratorio."""

import subprocess
from pathlib import Path

import boto3

TERRAFORM_DIR = Path(__file__).resolve().parent.parent / "terraform"
PERFIL_POR_DEFECTO = "real"
REGION_POR_DEFECTO = "us-east-2"


def terraform_output(nombre: str) -> str:
    """Lee un output de Terraform para no escribir IDs de recursos en el código."""
    resultado = subprocess.run(
        ["terraform", f"-chdir={TERRAFORM_DIR}", "output", "-raw", nombre],
        capture_output=True,
        text=True,
        check=True,
    )
    return resultado.stdout.strip()


def sesion(perfil: str, region: str) -> boto3.Session:
    return boto3.Session(profile_name=perfil, region_name=region)


def datos_kb(tipo: str, region_vectorial: str) -> tuple[str, str, str]:
    """Devuelve (kb_id, data_source_id, región) de la KB 'vectorial' o 'managed'."""
    if tipo == "managed":
        return (
            terraform_output("managed_knowledge_base_id"),
            terraform_output("managed_data_source_id"),
            terraform_output("managed_kb_region"),
        )
    return terraform_output("knowledge_base_id"), terraform_output("data_source_id"), region_vectorial
