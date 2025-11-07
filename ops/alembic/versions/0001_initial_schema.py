"""Initial schema bootstrap"""

from __future__ import annotations

from pathlib import Path

from alembic import op


revision = "0001_initial_schema"
down_revision = None
branch_labels = None
depends_on = None


SCHEMA_FILE = Path(__file__).resolve().parents[2] / "sql" / "schema.sql"


def _load_batches() -> list[str]:
    if not SCHEMA_FILE.exists():
        raise FileNotFoundError(f"Cannot locate schema file at {SCHEMA_FILE}")

    batches = []
    current: list[str] = []
    for raw_line in SCHEMA_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        if line.strip().upper() == "GO":
            if current:
                batches.append("\n".join(current).strip())
                current = []
        else:
            current.append(raw_line)
    if current:
        batches.append("\n".join(current).strip())
    return [batch for batch in batches if batch]


def upgrade() -> None:
    for batch in _load_batches():
        op.execute(batch)


def downgrade() -> None:
    raise NotImplementedError("Downgrades are not supported for this project.")
