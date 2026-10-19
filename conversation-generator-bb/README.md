# Extractor

Contenedor que extrae las conversaciones de un día desde el sistema origen (simulado) y las deja como CSV en el contenedor `raw` del Data Lake.

## Uso

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `--date` | ayer (UTC) | Fecha `YYYY-MM-DD` |
| `--count` | 300–800 | Cantidad de conversaciones |
| `--output` | `adls` | `adls` (Data Lake) o `local` (disco) |
| `--local-dir` | `output` | Carpeta para `--output local` |

| Variable de entorno | Uso |
|---------------------|-----|
| `EXTRACT_DATE` / `EXTRACT_COUNT` | Alternativa a `--date` / `--count` (así se lanza el job a demanda en Azure) |
| `SOURCE_API_KEY` | API key del sistema origen (en Azure viene de Key Vault). Mínimo 16 caracteres |
| `STORAGE_ACCOUNT_URL` | `https://<cuenta>.blob.core.windows.net` (Azure, Managed Identity) |
| `AZURE_STORAGE_CONNECTION_STRING` | Alternativa para el emulador Azurite en local |

La misma fecha siempre genera los mismos datos y sobrescribe el archivo: la extracción es **idempotente**.

## Desarrollo local

```powershell
# desde la raíz del repo
python -m venv .venv
.\.venv\Scripts\python -m pip install -r extractor\requirements-dev.txt

cd conversation-generator-bb
..\.venv\Scripts\python -m pytest -q

$env:SOURCE_API_KEY = "demo-key-1234567890"
..\.venv\Scripts\python -m extractor --date 2026-10-01 --output local --local-dir ..\output
```

## Docker

```powershell
cd conversation-generator-bb
docker build -t extractor .
docker run --rm -e SOURCE_API_KEY=demo-key-1234567890 -v "${PWD}\..\output:/app/output" extractor --date 2026-10-01 --output local
```

### Con Azurite (emulador de Storage)

```powershell
docker network create demo
docker run -d --name azurite --network demo mcr.microsoft.com/azure-storage/azurite azurite-blob --blobHost 0.0.0.0

$conn = "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;BlobEndpoint=http://azurite:10000/devstoreaccount1;"
docker run --rm --network demo -e SOURCE_API_KEY=demo-key-1234567890 -e AZURE_STORAGE_CONNECTION_STRING=$conn extractor --date 2026-10-01

docker rm -f azurite; docker network rm demo
```

La key de Azurite es la clave pública y documentada del emulador, no un secreto.
