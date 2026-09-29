#!/usr/bin/env python3
import argparse
import os
from collections import Counter, defaultdict
from typing import Dict, List, Optional, Tuple

import hdbscan
import numpy as np
import umap
from scipy.spatial.distance import cosine as cosine_distance
from sentence_transformers import SentenceTransformer
from sklearn.preprocessing import normalize

from rumba_ml_utils import (
    chunks,
    column_exists,
    ensure_similarity_table,
    fetch_dicts,
    get_db_connection,
    now_iso,
    parse_pg_vector,
    quote_ident,
    setup_logger,
    table_exists,
    timed,
    upsert_directus_meta,
    vector_to_pg,
)


DB_URL = os.environ.get("RUMBA_DB_URL", "postgresql://localhost/rumba_dev")
DIRECTUS_URL = os.environ.get("DIRECTUS_URL", "http://127.0.0.1:8055")
DIRECTUS_TOKEN = os.environ.get("DIRECTUS_ADMIN_TOKEN")
MODEL_NAME = os.environ.get("RUMBA_ML_MODEL", "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
EXERCISE_TABLE = os.environ.get("RUMBA_EX_EXERCISE_TABLE", "exercise")
LEARNER_PROFILE_TABLE = os.environ.get("RUMBA_EX_LEARNER_PROFILE_TABLE", "learnerprofile")
SIMILARITY_TABLE = os.environ.get("RUMBA_EX_SIMILARITY_TABLE", "profile_exercise_similarity")
LOG_PATH = os.environ.get("RUMBA_ML_LOG_PATH", "rumba-ex-ml-pipeline.log")
DEFAULT_DYSLEXIA_TYPES = [
    "phonologique",
    "orthographique",
    "syntaxique",
    "comprehension",
    "memoire_de_travail",
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Pipeline ML RUMBA.EX")
    parser.add_argument("--dry-run", action="store_true", help="Charge et analyse sans aucune ecriture DB/Directus")
    parser.add_argument("--skip-directus", action="store_true", help="Ne met pas a jour Directus")
    parser.add_argument("--batch-size", type=int, default=32, help="Taille de batch pour sentence-transformers")
    args = parser.parse_args()

    logger = setup_logger(LOG_PATH)
    start = timed()
    logger.info("Demarrage pipeline RUMBA.EX%s", " (dry-run)" if args.dry_run else "")

    conn = get_db_connection(DB_URL)
    try:
        validate_database_shape(conn)
        model = SentenceTransformer(MODEL_NAME)
        logger.info("Modele charge: %s", MODEL_NAME)

        pending = fetch_pending_embedding_rows(conn)
        logger.info("%s exercices detectes pour synchronisation embedding", len(pending))

        processed_embeddings = 0
        if pending and not args.dry_run:
            processed_embeddings = update_missing_embeddings(conn, model, pending, args.batch_size, logger)
        elif pending:
            logger.info("Dry-run: embeddings non calcules et non ecrits")

        exercises, embeddings = load_all_embeddings(conn)
        logger.info("%s exercices avec embedding disponibles", len(exercises))

        if not exercises:
            logger.warning("Aucun embedding disponible, pipeline arrete apres la verification")
            return 0

        normalized_embeddings = normalize(embeddings)
        cluster_labels, cluster_names = compute_clusters(exercises, normalized_embeddings, logger)
        umap_coords = compute_umap(normalized_embeddings, logger)
        nearest_neighbors = compute_nearest_neighbors(exercises, normalized_embeddings)

        if args.dry_run:
            logger.info("Dry-run: aucune ecriture profile_exercise_similarity ni Directus")
        else:
            update_profile_exercise_similarity(conn, exercises, normalized_embeddings, logger)
            if args.skip_directus:
                logger.info("Mise a jour Directus ignoree (--skip-directus)")
            else:
                update_directus_metadata(exercises, cluster_labels, cluster_names, umap_coords, nearest_neighbors, logger)

        elapsed = timed() - start
        cluster_count = len({label for label in cluster_labels if label >= 0})
        logger.info(
            "Pipeline termine : %s exercices traites, %s clusters, duree %.2fs",
            processed_embeddings,
            cluster_count,
            elapsed,
        )
        return 0
    finally:
        conn.close()


def validate_database_shape(conn) -> None:
    if not table_exists(conn, EXERCISE_TABLE):
        raise RuntimeError(f"La table PostgreSQL {EXERCISE_TABLE} est introuvable")
    for column in ("exercise_id", "title", "content", "embedding"):
        if not column_exists(conn, EXERCISE_TABLE, column):
            raise RuntimeError(f"Colonne manquante dans {EXERCISE_TABLE}: {column}")


def fetch_pending_embedding_rows(conn) -> List[Dict]:
    has_needs_sync = column_exists(conn, EXERCISE_TABLE, "embedding_needs_sync")
    where = "embedding IS NULL"
    if has_needs_sync:
        where = "embedding IS NULL OR COALESCE(embedding_needs_sync, FALSE) = TRUE"

    return fetch_dicts(
        conn,
        f"""
        SELECT exercise_id::text AS exercise_id, title, content
        FROM {quote_ident(EXERCISE_TABLE)}
        WHERE {where}
        ORDER BY exercise_id
        """,
    )


def update_missing_embeddings(conn, model, rows: List[Dict], batch_size: int, logger) -> int:
    has_needs_sync = column_exists(conn, EXERCISE_TABLE, "embedding_needs_sync")
    has_updated_at = column_exists(conn, EXERCISE_TABLE, "embedding_updated_at")
    updated = 0

    for batch in chunks(rows, batch_size):
        texts = [build_exercise_text(row) for row in batch]
        vectors = model.encode(texts, normalize_embeddings=True, batch_size=batch_size)

        with conn.cursor() as cur:
            for row, vector in zip(batch, vectors):
                set_clauses = ["embedding = %s::vector"]
                params = [vector_to_pg(vector)]
                if has_needs_sync:
                    set_clauses.append("embedding_needs_sync = FALSE")
                if has_updated_at:
                    set_clauses.append("embedding_updated_at = NOW()")
                params.append(row["exercise_id"])
                cur.execute(
                    f"""
                    UPDATE {quote_ident(EXERCISE_TABLE)}
                    SET {", ".join(set_clauses)}
                    WHERE exercise_id = %s
                    """,
                    params,
                )
                updated += 1
        conn.commit()
        logger.info("Embeddings mis a jour: %s/%s", updated, len(rows))

    return updated


def load_all_embeddings(conn) -> Tuple[List[Dict], np.ndarray]:
    rows = fetch_dicts(
        conn,
        f"""
        SELECT exercise_id::text AS exercise_id, domain, level, embedding::text AS embedding
        FROM {quote_ident(EXERCISE_TABLE)}
        WHERE embedding IS NOT NULL
        ORDER BY exercise_id
        """,
    )
    exercises = []
    vectors = []
    for row in rows:
        vector = parse_pg_vector(row.get("embedding"))
        if vector is None or vector.shape[0] != 384:
            continue
        exercises.append(row)
        vectors.append(vector)

    if not vectors:
        return [], np.zeros((0, 384), dtype=np.float32)
    return exercises, np.vstack(vectors).astype(np.float32)


def compute_clusters(exercises: List[Dict], embeddings_normalized: np.ndarray, logger) -> Tuple[np.ndarray, Dict[int, str]]:
    if len(exercises) < 5:
        labels = np.full((len(exercises),), -1, dtype=int)
        logger.info("HDBSCAN ignore: moins de 5 exercices")
        return labels, {}

    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=5,
        min_samples=2,
        metric="euclidean",
        cluster_selection_method="eom",
    )
    labels = clusterer.fit_predict(embeddings_normalized)
    cluster_names = build_cluster_labels(exercises, labels)
    logger.info("%s clusters HDBSCAN detectes", len(cluster_names))
    return labels, cluster_names


def compute_umap(embeddings_normalized: np.ndarray, logger) -> np.ndarray:
    if embeddings_normalized.shape[0] < 3:
        logger.info("UMAP ignore: moins de 3 exercices")
        return np.zeros((embeddings_normalized.shape[0], 2), dtype=np.float32)

    reducer = umap.UMAP(
        n_components=2,
        n_neighbors=min(15, embeddings_normalized.shape[0] - 1),
        min_dist=0.1,
        metric="cosine",
        random_state=42,
    )
    return reducer.fit_transform(embeddings_normalized)


def compute_nearest_neighbors(exercises: List[Dict], embeddings_normalized: np.ndarray) -> Dict[str, List[Dict]]:
    similarities = embeddings_normalized @ embeddings_normalized.T
    neighbors_by_id = {}
    for index, exercise in enumerate(exercises):
        order = np.argsort(similarities[index])[::-1]
        neighbors = []
        for neighbor_index in order:
            if neighbor_index == index:
                continue
            neighbors.append({
                "uuid": str(exercises[neighbor_index]["exercise_id"]),
                "score": float(similarities[index][neighbor_index]),
            })
            if len(neighbors) >= 20:
                break
        neighbors_by_id[str(exercise["exercise_id"])] = neighbors
    return neighbors_by_id


def update_profile_exercise_similarity(conn, exercises: List[Dict], embeddings_normalized: np.ndarray, logger) -> None:
    ensure_similarity_table(conn, SIMILARITY_TABLE)
    learner_profiles = load_learner_profile_embeddings(conn, exercises, embeddings_normalized, logger)
    rows_written = 0

    with conn.cursor() as cur:
        for dyslexia_type, learner_embedding in learner_profiles.items():
            learner_embedding = normalize(learner_embedding.reshape(1, -1))[0]
            for exercise, exercise_embedding in zip(exercises, embeddings_normalized):
                similarity = 1 - cosine_distance(learner_embedding, exercise_embedding)
                cur.execute(
                    f"""
                    INSERT INTO {quote_ident(SIMILARITY_TABLE)} (dyslexia_type, exercise_id, cosine_sim, updated_at)
                    VALUES (%s, %s, %s, NOW())
                    ON CONFLICT (dyslexia_type, exercise_id)
                    DO UPDATE SET cosine_sim = EXCLUDED.cosine_sim, updated_at = NOW()
                    """,
                    (dyslexia_type, exercise["exercise_id"], float(similarity)),
                )
                rows_written += 1
    conn.commit()
    logger.info("profile_exercise_similarity mis a jour: %s lignes", rows_written)


def load_learner_profile_embeddings(conn, exercises: List[Dict], embeddings_normalized: np.ndarray, logger) -> Dict[str, np.ndarray]:
    profiles = {}
    if table_exists(conn, LEARNER_PROFILE_TABLE):
        columns = detect_learner_profile_columns(conn)
        if columns:
            type_col, embedding_col = columns
            rows = fetch_dicts(
                conn,
                f"""
                SELECT {quote_ident(type_col)}::text AS dyslexia_type, {quote_ident(embedding_col)}::text AS embedding
                FROM {quote_ident(LEARNER_PROFILE_TABLE)}
                WHERE {quote_ident(embedding_col)} IS NOT NULL
                """,
            )
            for row in rows:
                vector = parse_pg_vector(row.get("embedding"))
                if vector is not None and vector.shape[0] == 384:
                    profiles[str(row["dyslexia_type"]).strip().lower()] = vector

    if profiles:
        logger.info("%s profils apprenants charges depuis %s", len(profiles), LEARNER_PROFILE_TABLE)
        return profiles

    logger.info("Aucun learnerprofile exploitable, fallback par domaines d'exercices")
    return build_fallback_profile_embeddings(exercises, embeddings_normalized)


def detect_learner_profile_columns(conn) -> Optional[Tuple[str, str]]:
    type_candidates = ["dyslexia_type", "profile_type", "type", "name"]
    embedding_candidates = ["embedding", "profile_embedding", "embedding_vector", "profil_learner_embedding"]
    type_col = next((col for col in type_candidates if column_exists(conn, LEARNER_PROFILE_TABLE, col)), None)
    embedding_col = next((col for col in embedding_candidates if column_exists(conn, LEARNER_PROFILE_TABLE, col)), None)
    if type_col and embedding_col:
        return type_col, embedding_col
    return None


def build_fallback_profile_embeddings(exercises: List[Dict], embeddings_normalized: np.ndarray) -> Dict[str, np.ndarray]:
    profile_types = set(DEFAULT_DYSLEXIA_TYPES)
    for exercise in exercises:
        domain = str(exercise.get("domain") or "").strip().lower()
        if domain:
            profile_types.add(domain)

    global_mean = embeddings_normalized.mean(axis=0)
    profiles = {}
    for profile_type in profile_types:
        matched_indices = [
            index for index, exercise in enumerate(exercises)
            if profile_type in str(exercise.get("domain") or "").lower()
        ]
        if matched_indices:
            profiles[profile_type] = embeddings_normalized[matched_indices].mean(axis=0)
        else:
            profiles[profile_type] = global_mean
    return profiles


def update_directus_metadata(
    exercises: List[Dict],
    cluster_labels: np.ndarray,
    cluster_names: Dict[int, str],
    umap_coords: np.ndarray,
    nearest_neighbors: Dict[str, List[Dict]],
    logger,
) -> None:
    if not DIRECTUS_TOKEN:
        raise RuntimeError("DIRECTUS_ADMIN_TOKEN est requis pour synchroniser Directus")

    now = now_iso()
    for index, exercise in enumerate(exercises):
        exercise_id = str(exercise["exercise_id"])
        cluster_id = int(cluster_labels[index])
        payload = {
            "cluster_id": None if cluster_id < 0 else cluster_id,
            "cluster_label": None if cluster_id < 0 else cluster_names.get(cluster_id),
            "umap_x": float(umap_coords[index][0]) if len(umap_coords) else None,
            "umap_y": float(umap_coords[index][1]) if len(umap_coords) else None,
            "nearest_neighbors": nearest_neighbors.get(exercise_id, []),
            "last_ml_run": now,
        }
        upsert_directus_meta(
            exercise_id,
            payload,
            directus_url=DIRECTUS_URL,
            directus_token=DIRECTUS_TOKEN,
        )
    logger.info("rumba_ex_exercises_meta synchronise dans Directus: %s items", len(exercises))


def build_cluster_labels(exercises: List[Dict], labels: np.ndarray) -> Dict[int, str]:
    grouped = defaultdict(list)
    for exercise, label in zip(exercises, labels):
        if label >= 0:
            grouped[int(label)].append(exercise)

    names = {}
    for cluster_id, items in grouped.items():
        domain = most_common_text([item.get("domain") for item in items]) or "general"
        level = most_common_text([item.get("level") for item in items]) or "niveau"
        names[cluster_id] = f"{domain}-{level}-cluster{cluster_id}"
    return names


def most_common_text(values) -> Optional[str]:
    clean = [str(value).strip() for value in values if value is not None and str(value).strip()]
    if not clean:
        return None
    return Counter(clean).most_common(1)[0][0]


def build_exercise_text(row: Dict) -> str:
    return f"{row.get('title') or ''} {row.get('content') or ''}".strip()


if __name__ == "__main__":
    raise SystemExit(main())
