from datetime import date

import pytest

from extractor.random_chat_source import AuthenticationError, SimulatedSource

API_KEY = "test-key-1234567890"


def test_requiere_api_key():
    with pytest.raises(AuthenticationError):
        SimulatedSource(None)
    with pytest.raises(AuthenticationError):
        SimulatedSource("corta")


def test_extrae_la_cantidad_pedida_y_solo_de_esa_fecha():
    day = date(2026, 10, 1)
    conversations = SimulatedSource(API_KEY).extract(day, count=50)

    assert len(conversations) == 50
    assert all(c.fecha == "2026-10-01" for c in conversations)
    assert all(c.started_at.startswith("2026-10-01") for c in conversations)
    assert all(1 <= c.satisfaction <= 5 for c in conversations)


def test_misma_fecha_mismos_datos():
    source = SimulatedSource(API_KEY)
    day = date(2026, 10, 1)
    assert source.extract(day) == source.extract(day)


def test_fechas_distintas_datos_distintos():
    source = SimulatedSource(API_KEY)
    assert source.extract(date(2026, 10, 1), 10) != source.extract(date(2026, 10, 2), 10)
