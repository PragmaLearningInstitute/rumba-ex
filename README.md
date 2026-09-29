# RUMBA.EX — adaptive exercise selection

**Inspectable exercise recommendations for educational experimentation.** RUMBA.EX combines learner settings, a catalogue of exercises, semantic similarity and a diversity-aware ranking. This repository contains the browser application, Express API, embedding pipeline and native macOS implementation maintained by [Pragma Learning Institute](https://pragmalearninginstitute.com/).

[Try RUMBA.EX](https://pragmalearninginstitute.com/rumba-ex) · [Documentation on the PLI website](https://pragmalearninginstitute.com/outils/documentation) · [Guide français](docs/getting-started.fr.md) · [Algorithms](docs/algorithms.fr.md) · [Deployment](docs/deployment.fr.md)

## What is included?

| Component | Location | What it does |
| --- | --- | --- |
| Browser application | `web/rumba-ex-app.html` | Profile form, guest exercises, feedback, HTML/PDF/DOCX export |
| HTTP API | `server/rumba-ex-api/` | Directus authentication, profile ownership checks, PostgreSQL recommendations |
| ML pipeline | `server/rumba_ml_pipeline.py` | 384-dimensional embeddings, similarities, HDBSCAN groups, UMAP coordinates |
| Update worker | `server/rumba-ex-ml-worker.js` | PostgreSQL notifications and debounced pipeline execution |
| macOS application | `desktop/macos/` | SwiftUI interface, PostgreSQL or explicit local fallback, DOCX export |
| Schemas | `schema/`, `desktop/macos/sql/` | Development schema and integration-specific SQL |

The desktop, browser fallback and API are related implementations, not numerically identical engines. A missing server activates the browser's built-in exercise fallback. Its results must not be described as database retrieval or a live embedding calculation.

## Quick start: browser demonstration

Requires Python 3; no account, database or AI API key is needed for this demonstration.

```bash
git clone https://github.com/PragmaLearningInstitute/rumba-ex.git
cd rumba-ex
python3 -m http.server 8080 --bind 127.0.0.1 --directory web
```

Open [the local application](http://127.0.0.1:8080/rumba-ex-app.html), choose guest access, enter a fictional profile, select the difficulty areas and request exercises. If the API is unavailable, the interface uses its local catalogue. HTML export works locally; PDF/DOCX exports load third-party libraries on demand. Telemetry is disabled unless explicitly configured.

For the database-backed application and native build, follow the [installation guide](docs/getting-started.fr.md) and [deployment guide](docs/deployment.fr.md).

## Read the implementation

1. [From a learner profile to a ranked exercise list](docs/algorithms.fr.md): weighted responses, inverse softmax, similarity, reranking and feedback.
2. [Embeddings, clustering and the PCA/UMAP distinction](docs/embeddings.fr.md): actual pipeline, configuration and reproducibility.
3. [Deployment and data boundaries](docs/deployment.fr.md): API contracts, authentication, storage and environment variables.
4. [Scope, provenance and differences between versions](docs/provenance.fr.md): what was extracted and what is deliberately excluded.

## Research status

RUMBA.EX is an educational research tool. Its categories and scores are implementation choices; they are not a clinical diagnosis, a validated difficulty scale or proof of learning improvement. Human review of exercises remains necessary. See the [algorithm limitations](docs/algorithms.fr.md#limites-et-interprétation) before interpreting results.

## Contributing and citation

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md) and [CITATION.cff](CITATION.cff). Use fictional examples in issues. Do not upload learner records or connection credentials.

Code and original documentation are available under the [MIT license](LICENSE). Third-party packages and assets retain their own licenses. The name and logo identify the project and do not imply endorsement of forks.

Related projects: [RUMBA.RD](https://github.com/PragmaLearningInstitute/rumba-rd) · [Reading eye-tracking toolkit](https://github.com/PragmaLearningInstitute/reading-eye-tracking-toolkit).
