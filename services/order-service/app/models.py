from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from decimal import Decimal
import uuid


@dataclass
class Order:
    userId: str
    items: list
    orderId: str = field(default_factory=lambda: str(uuid.uuid4()))
    status: str = "PENDING"
    totalAmount: Decimal = Decimal("0")
    createdAt: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updatedAt: str = field(default_factory=lambda: datetime.now(timezone.utc).isoformat())

    def to_dict(self):
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "Order":
        return cls(**{k: v for k, v in data.items() if k in cls.__dataclass_fields__})
