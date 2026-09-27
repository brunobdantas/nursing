# Clinical Releases

`clinical-release-v1.json` is generated from the official ANVISA open
medication dataset by the GitHub Actions clinical data pipeline.

The mobile app uses this public HTTPS file as its production bootstrap/fallback
source. The file is never hand-edited. RAW ingestion, entity resolution,
clinical curation, fail-closed validation and release serialization run before
publication.
