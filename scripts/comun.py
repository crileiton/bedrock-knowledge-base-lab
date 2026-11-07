"""Utilidades compartidas por los scripts del laboratorio."""

import subprocess
from pathlib import Path

import boto3

TERRAFORM_DIR = Path(__file__).resolve().parent.parent / "terraform"
PERFIL_POR_DEFECTO = "lab"
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
