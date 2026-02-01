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

# Set up authentication (required for authenticated endpoints)
export SCOUT_USERNAME=<username>
export SCOUT_PASSWORD=<password>
source config.sh
```

## Architecture

- **api.scouting.org/openapi.yaml** - Main OpenAPI 3.0.3 specification
- **api.scouting.org-command.sh** - Test request definitions using HTTPie syntax
- **config.sh** - Authentication script that fetches JWT token and sets `TOKEN` and `userId` env vars
- **optic.yml** - Optic configuration for API traffic capture
- **postman/** - Backup of Postman collection

## Workflow for Adding New Endpoints

1. Add test request in `api.scouting.org-command.sh`
2. Run `npm run openapi-test` to validate
3. Run `npm run openapi-update` to interactively document new endpoints
4. Verify with `npm run openapi-test`

## Dependencies

Runtime: Node.js, HTTPie (`http` command), curl, jq
