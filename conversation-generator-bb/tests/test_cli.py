import csv

from extractor.cli import main
from extractor.random_chat_source import FIELDNAMES

API_KEY = "test-key-1234567890"


def test_output_local_crea_csv_particionado(tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_API_KEY", API_KEY)

    exit_code = main(["--date", "2026-10-01", "--count", "20", "--output", "local", "--local-dir", str(tmp_path)])

    target = tmp_path / "raw" / "conversations" / "fecha=2026-10-01" / "conversations_2026-10-01.csv"
    assert exit_code == 0
    with target.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 20
    assert list(rows[0]) == FIELDNAMES


def test_repetir_fecha_sobrescribe(tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_API_KEY", API_KEY)
    args = ["--date", "2026-10-01", "--count", "20", "--output", "local", "--local-dir", str(tmp_path)]

    main(args)
    main(args)

    files = list((tmp_path / "raw").rglob("*.csv"))
    assert len(files) == 1


def test_fecha_y_cantidad_desde_variables_de_entorno(tmp_path, monkeypatch):
    monkeypatch.setenv("SOURCE_API_KEY", API_KEY)
    monkeypatch.setenv("EXTRACT_DATE", "2026-09-15")
    monkeypatch.setenv("EXTRACT_COUNT", "5")

    assert main(["--output", "local", "--local-dir", str(tmp_path)]) == 0

    target = tmp_path / "raw" / "conversations" / "fecha=2026-09-15" / "conversations_2026-09-15.csv"
    with target.open(encoding="utf-8") as f:
        assert len(list(csv.DictReader(f))) == 5


def test_sin_api_key_falla(tmp_path, monkeypatch):
    monkeypatch.delenv("SOURCE_API_KEY", raising=False)

    assert main(["--output", "local", "--local-dir", str(tmp_path)]) == 2
