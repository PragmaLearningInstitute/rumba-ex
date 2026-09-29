import json
import logging
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np
import psycopg2
import psycopg2.extras
import requests


DEFAULT_DIRECTUS_URL = "http://127.0.0.1:8055"
DEFAULT_LOG_PATH = "rumba-ex-ml-pipeline.log"


def get_db_connection(db_url: str):
    return psycopg2.connect(db_url)


def setup_logger(log_path: str = DEFAULT_LOG_PATH) -> logging.Logger:
    logger = logging.getLogger("rumba-ml-pipeline")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    formatter = logging.Formatter("[%(asctime)s] %(levelname)s %(message)s")
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)

    target = Path(log_path)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(target)
    except OSError:
        fallback = Path.cwd() / "rumba-ex-ml-pipeline.log"
        file_handler = logging.FileHandler(fallback)
        logger.warning("Impossible d'ecrire dans %s, fallback vers %s", target, fallback)

    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    return logger


def quote_ident(identifier: str) -> str:
    if not identifier or not identifier.replace("_", "").isalnum() or identifier[0].isdigit():
        raise ValueError(f"Identifiant SQL invalide: {identifier}")
    return '"' + identifier.replace('"', '""') + '"'


def table_exists(conn, table_name: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT EXISTS (
              SELECT 1
              FROM information_schema.tables
              WHERE table_schema = 'public' AND table_name = %s
            )
            """,
            (table_name,),
        )
        return bool(cur.fetchone()[0])


def column_exists(conn, table_name: str, column_name: str) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT EXISTS (
              SELECT 1
              FROM information_schema.columns
              WHERE table_schema = 'public'
                AND table_name = %s
                AND column_name = %s
            )
            """,
            (table_name, column_name),
        )
        return bool(cur.fetchone()[0])


def fetch_dicts(conn, sql: str, params: Sequence[Any] = ()) -> List[Dict[str, Any]]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]


def vector_to_pg(values: Sequence[float]) -> str:
    clean_values = [float(v) for v in values]
    return "[" + ",".join(f"{value:.9f}" for value in clean_values) + "]"


def parse_pg_vector(value: Any) -> Optional[np.ndarray]:
    if value is None:
        return None
    if isinstance(value, np.ndarray):
        return value.astype(np.float32)
    if isinstance(value, (list, tuple)):
        return np.asarray(value, dtype=np.float32)

    text = str(value).strip()
    if not text:
        return None
    if text.startswith("[") and text.endswith("]"):
        text = text[1:-1]
    if not text:
        return None

    try:
        return np.asarray([float(part.strip()) for part in text.split(",")], dtype=np.float32)
    except ValueError:
        return None


def chunks(items: Sequence[Any], size: int) -> Iterable[Sequence[Any]]:
    for index in range(0, len(items), size):
        yield items[index:index + size]


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_similarity_table(conn, table_name: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            f"""
            CREATE TABLE IF NOT EXISTS {quote_ident(table_name)} (
              dyslexia_type TEXT NOT NULL,
              exercise_id UUID NOT NULL,
              cosine_sim DOUBLE PRECISION NOT NULL,
              updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
              PRIMARY KEY (dyslexia_type, exercise_id)
            )
            """
        )
    conn.commit()


def directus_headers(token: str) -> Dict[str, str]:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def directus_request(
    method: str,
    path: str,
    *,
    body: Optional[Dict[str, Any]] = None,
    directus_url: str = DEFAULT_DIRECTUS_URL,
    directus_token: Optional[str] = None,
    timeout: int = 20,
):
    if not directus_token:
        raise RuntimeError("DIRECTUS_ADMIN_TOKEN est requis pour mettre a jour Directus")

    url = f"{directus_url.rstrip('/')}/{path.lstrip('/')}"
    response = requests.request(
        method,
        url,
        headers=directus_headers(directus_token),
        data=json.dumps(body) if body is not None else None,
        timeout=timeout,
    )

    if response.status_code >= 400:
        error = RuntimeError(f"Directus {method} {path} a echoue: {response.status_code} {response.text[:300]}")
        error.status_code = response.status_code
        raise error

    if not response.text:
        return None
    return response.json()


def upsert_directus_meta(
    exercise_id: str,
    payload: Dict[str, Any],
    *,
    directus_url: str,
    directus_token: str,
) -> None:
    try:
        directus_request(
            "PATCH",
            f"/items/rumba_ex_exercises_meta/{exercise_id}",
            body=payload,
            directus_url=directus_url,
            directus_token=directus_token,
        )
    except RuntimeError as error:
        if getattr(error, "status_code", None) not in (403, 404):
            raise

        create_payload = {"exercise_uuid": exercise_id}
        create_payload.update(payload)
        directus_request(
            "POST",
            "/items/rumba_ex_exercises_meta",
            body=create_payload,
            directus_url=directus_url,
            directus_token=directus_token,
        )


def timed() -> float:
    return time.perf_counter()
