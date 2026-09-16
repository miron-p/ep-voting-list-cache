# European Parliament voting-list cache

This public repository contains only documents already published by the European Parliament. It supports the public demonstration of the S&D plenary-team voting-list tool when Parliament's publication site does not accept requests from the web application's hosting network.

The application source, S&D voting indications, `.sdvl` workspaces and user documents are **not** stored here.

## How it works

- A standard GitHub-hosted Windows runner reads Parliament's public voting-list page.
- It conditionally checks every published DOCX using the server's ETag or Last-Modified value when available.
- It records the original URL, publication label, content hash and retrieval time in `cache/manifest.json`.
- It retains public document versions so the plenary tool can identify revised files by both label and bytes.
- The workflow can also be started manually from the repository's **Actions** page.

The scheduled job normally runs every ten minutes during weekday plenary working hours in the `Europe/Brussels` timezone and once each evening. GitHub may delay scheduled jobs during periods of high load.

## Public sources

- Voting lists: <https://www.europarl.europa.eu/plenary/en/votes.html>
- Document metadata used by the main app: <https://data.europarl.europa.eu/>

All cached documents retain their European Parliament source URL in the manifest.
