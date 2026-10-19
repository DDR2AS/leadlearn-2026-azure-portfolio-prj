"""Punto de entrada: extrae las conversaciones de una fecha y las deja en raw/."""

import argparse
import logging
import os
import sys
from datetime import date, datetime, timedelta, timezone

from extractor.random_chat_source import AuthenticationError, SimulatedSource
from extractor.writers import AdlsWriter, LocalWriter, to_csv

log = logging.getLogger("extractor")


def parse_date(value: str) -> date:
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError:
        raise argparse.ArgumentTypeError(f"Fecha inválida '{value}', usa YYYY-MM-DD")


def positive_int(value: str) -> int:
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("--count debe ser mayor que 0")
    return number


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="extractor",
        description="Extrae conversaciones del sistema origen y las sube como CSV a raw/.",
    )
    parser.add_argument(
        "--date",
        type=parse_date,
        default=os.environ.get("EXTRACT_DATE"),
        help="Fecha YYYY-MM-DD (env EXTRACT_DATE; default: ayer, UTC)",
    )
    parser.add_argument(
        "--count",
        type=positive_int,
        default=os.environ.get("EXTRACT_COUNT"),
        help="Cantidad de conversaciones (env EXTRACT_COUNT; default: 300-800)",
    )
    parser.add_argument("--output", choices=["adls", "local"], default="adls", help="Destino del CSV")
    parser.add_argument("--local-dir", default="output", help="Carpeta para --output local")
    return parser


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    args = build_parser().parse_args(argv)
    day = args.date or (datetime.now(timezone.utc).date() - timedelta(days=1))

    try:
        source = SimulatedSource(os.environ.get("SOURCE_API_KEY"))
    except AuthenticationError as exc:
        log.error("No se pudo autenticar contra el sistema origen: %s", exc)
        return 2

    conversations = source.extract(day, args.count)
    log.info("Extraídas %d conversaciones del %s", len(conversations), day)

    writer = LocalWriter(args.local_dir) if args.output == "local" else AdlsWriter()
    destination = writer.write(day, to_csv(conversations))
    log.info("CSV guardado en %s", destination)
    return 0


if __name__ == "__main__":
    sys.exit(main())
