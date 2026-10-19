"""Destinos del CSV: disco local (pruebas) o Data Lake (Azure / Azurite)."""

import csv
import io
import os
from dataclasses import asdict
from datetime import date
from pathlib import Path

from extractor.random_chat_source import FIELDNAMES, Conversation


def blob_path(day: date) -> str:
    """Ruta particionada por fecha dentro del contenedor raw."""
    d = day.isoformat()
    return f"conversations/fecha={d}/conversations_{d}.csv"


def to_csv(conversations: list[Conversation]) -> str:
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=FIELDNAMES, lineterminator="\n")
    writer.writeheader()
    writer.writerows(asdict(c) for c in conversations)
    return buffer.getvalue()


class LocalWriter:
    def __init__(self, base_dir: str | Path):
        self.base_dir = Path(base_dir)

    def write(self, day: date, content: str) -> str:
        target = self.base_dir / "raw" / blob_path(day)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
        return str(target)


class AdlsWriter:
    """Sube el CSV al contenedor raw.

    - AZURE_STORAGE_CONNECTION_STRING: conexión directa (emulador Azurite en local).
    - STORAGE_ACCOUNT_URL: cuenta real en Azure, autenticada con Managed Identity
      (DefaultAzureCredential), sin keys en el código.
    """

    def __init__(self, container: str = "raw"):
        from azure.storage.blob import BlobServiceClient

        connection_string = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
        account_url = os.environ.get("STORAGE_ACCOUNT_URL")

        if connection_string:
            service = BlobServiceClient.from_connection_string(connection_string)
        elif account_url:
            from azure.identity import DefaultAzureCredential

            service = BlobServiceClient(account_url, credential=DefaultAzureCredential())
        else:
            raise ValueError(
                "Define STORAGE_ACCOUNT_URL (Azure) o AZURE_STORAGE_CONNECTION_STRING (Azurite)"
            )

        self.container = service.get_container_client(container)
        if connection_string and not self.container.exists():
            self.container.create_container()

    def write(self, day: date, content: str) -> str:
        from azure.storage.blob import ContentSettings

        path = blob_path(day)
        self.container.upload_blob(
            path,
            content.encode("utf-8"),
            overwrite=True,
            content_settings=ContentSettings(content_type="text/csv; charset=utf-8"),
        )
        return f"{self.container.container_name}/{path}"
