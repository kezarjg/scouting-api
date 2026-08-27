# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project documents the Scouting America APIs using OpenAPI specification. It uses Optic for API traffic capture and specification validation.

## Commands

```bash
# Install dependencies
npm install

# Test API against OpenAPI spec
npm run openapi-test

# Update spec with captured traffic (interactive mode)
npm run openapi-update

# Set up authentication (required for authenticated endpoints).
# Preferred: create .env (gitignored) from .env.example; the request script loads it itself.
cp .env.example .env && chmod 600 .env   # then fill in SCOUT_USERNAME / SCOUT_PASSWORD

# Or export and source manually:
export SCOUT_USERNAME=<username>
export SCOUT_PASSWORD=<password>
source config.sh

# Optional, for the unit roster and per-youth requests:
export ORG_GUID=<unit organizationGuid>
export YOUTH_USER_ID=<integer userId>
```

## Architecture

- **api.scouting.org/openapi.yaml** - Main OpenAPI 3.0.3 specification
- **api.scouting.org-command.sh** - Test request definitions using HTTPie syntax
- **config.sh** - Authentication script. Logs in against `auth.scouting.org` (NOT `my.scouting.org`,
  which now returns 503 for all `/api/*`) and exports `TOKEN`, `userId` and `personGuid`
- **.env** - Gitignored credentials file (`SCOUT_USERNAME`, `SCOUT_PASSWORD`); template in `.env.example`
- **optic.yml** - Optic configuration for API traffic capture
- **postman/** - Backup of Postman collection

## Workflow for Adding New Endpoints

1. Add test request in `api.scouting.org-command.sh`
2. Run `npm run openapi-test` to validate
3. Run `npm run openapi-update` to interactively document new endpoints
4. Verify with `npm run openapi-test`

## Dependencies

Runtime: Node.js, HTTPie 3.2.2+ (`http` command), curl, jq

HTTPie must be 3.2.2 or newer; older builds (including Debian 12's `httpie` package) fail on startup
against urllib3 2.x. Install with `pip install --user --upgrade httpie`.

## Identifiers

Three distinct, non-interchangeable identifiers appear in paths:

- `personGuid` (GUID) - `/persons/{personGuid}/*`, `/organizations/*`
- `userId` (integer) - `/advancements/youth/{userId}/*`
- `sbUserId` / `userId` (integer) - `/advancements/v2/youth/{youthId}/*`

Passing a GUID where an integer is expected returns `400 expected type: Integer, found: String`.
