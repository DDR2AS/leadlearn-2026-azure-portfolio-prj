"""Sistema origen simulado (caja negra) de conversaciones de atención al cliente por medio de chat.
Se esta enfocando en tratar de procesar las conversaciones diarias

Para la demo genera conversaciones ficticias de forma determinista: la misma fecha siempre produce los mismos datos, para mantener la idempotencia
"""

import random
import uuid
from dataclasses import dataclass, fields
from datetime import date, datetime, time, timedelta

CHANNELS = ["web", "whatsapp", "telefono", "email"]
CHANNEL_WEIGHTS = [35, 40, 15, 10]

TOPICS = {
    "facturacion": [
        "Me cobraron dos veces el mismo pedido",
        "No me llegó la factura de mi compra",
        "Quiero cambiar el RUC de mi boleta",
    ],
    "envio": [
        "Hola, mi pedido no llegó",
        "¿Cuándo llega mi pedido?",
        "El repartidor no encontró mi dirección",
    ],
    "devolucion": [
        "Quiero devolver un producto",
        "El producto llegó dañado",
        "¿Cuánto demora el reembolso?",
    ],
    "producto": [
        "¿Tienen stock de este producto?",
        "¿Este producto tiene garantía?",
        "Necesito información técnica del producto",
    ],
    "cuenta": [
        "No puedo iniciar sesión",
        "Quiero actualizar mi correo",
        "Olvidé mi contraseña",
    ],
}

NUM_CUSTOMERS = 5000
NUM_AGENTS = 25
MIN_API_KEY_LENGTH = 16


class AuthenticationError(Exception):
    """La API key enviada al sistema origen no es válida."""


@dataclass(frozen=True)
class Conversation:
    conversation_id: str
    fecha: str
    started_at: str
    channel: str
    customer_id: str
    agent_id: str
    topic: str
    first_message: str
    duration_sec: int
    satisfaction: int


FIELDNAMES = [f.name for f in fields(Conversation)]


class SimulatedSource:
    """Simula la API del sistema origen. Requiere una API key para extraer."""

    def __init__(self, api_key: str | None):
        if not api_key or len(api_key) < MIN_API_KEY_LENGTH:
            raise AuthenticationError(
                f"API key ausente o inválida (mínimo {MIN_API_KEY_LENGTH} caracteres)"
            )
        self._api_key = api_key

    def extract(self, day: date, count: int | None = None) -> list[Conversation]:
        """Devuelve las conversaciones de un día. Mismo día → mismos datos."""
        rng = random.Random(day.toordinal())
        if count is None:
            count = rng.randint(300, 800)

        start_of_day = datetime.combine(day, time.min)
        conversations = []
        for _ in range(count):
            topic = rng.choice(list(TOPICS))
            started_at = start_of_day + timedelta(seconds=rng.randint(0, 86_399))
            conversations.append(
                Conversation(
                    conversation_id=str(uuid.UUID(int=rng.getrandbits(128), version=4)),
                    fecha=day.isoformat(),
                    started_at=started_at.isoformat(),
                    channel=rng.choices(CHANNELS, weights=CHANNEL_WEIGHTS)[0],
                    customer_id=f"CUST-{rng.randint(1, NUM_CUSTOMERS):05d}",
                    agent_id=f"AGT-{rng.randint(1, NUM_AGENTS):02d}",
                    topic=topic,
                    first_message=rng.choice(TOPICS[topic]),
                    duration_sec=rng.randint(30, 1800),
                    satisfaction=rng.choices([1, 2, 3, 4, 5], weights=[5, 10, 20, 35, 30])[0],
                )
            )
        conversations.sort(key=lambda c: c.started_at)
        return conversations
