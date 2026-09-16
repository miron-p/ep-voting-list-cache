# European Parliament voting-list cache

This public repository contains only documents already published by the European Parliament. It supports the public demonstration of the S&D plenary-team voting-list tool when Parliament's publication site does not accept requests from the web application's hosting network.

The application source, S&D voting indications, `.sdvl` workspaces and user documents are **not** stored here.

## How it works

- An authorized Windows workstation reads Parliament's public voting-list page. Parliament currently refuses the same request from tested cloud-hosting networks.
- It conditionally checks every published DOCX using the server's ETag or Last-Modified value when available.
- It records the original URL, publication label, content hash and retrieval time in `cache/manifest.json`.
- It retains public document versions so the plenary tool can identify revised files by both label and bytes.
- `scripts/Publish-EpCache.ps1` updates the public cache and publishes changed public files to this repository.

No session workspace, committee-team draft or S&D indication is uploaded by the updater.

## Public sources

- Voting lists: <https://www.europarl.europa.eu/plenary/en/votes.html>
- Document metadata used by the main app: <https://data.europarl.europa.eu/>

All cached documents retain their European Parliament source URL in the manifest.
