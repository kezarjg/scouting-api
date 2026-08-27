#!/usr/bin/env bash

# Bootstrap authentication. Order matters: load .env and mint a token FIRST, then verify.
# (The previous version tested $TOKEN before sourcing config.sh, so it could never
# bootstrap itself and always failed when invoked by `optic capture`.)

# Credentials come from .env (gitignored) unless already exported.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "${SCOUT_USERNAME:-}" ] || [ -z "${SCOUT_PASSWORD:-}" ]; then
    if [ -f "$SCRIPT_DIR/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        . "$SCRIPT_DIR/.env"
        set +a
    fi
fi

# Mint a token unless one was passed in from the environment.
if [ -z "${TOKEN:-}" ] || [ -z "${userId:-}" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/config.sh"
fi

if [ -z "${TOKEN:-}" ] || [ -z "${userId:-}" ]; then
    echo "Error: Authentication not set up. Provide credentials one of two ways:" >&2
    echo "  1. Create .env with SCOUT_USERNAME and SCOUT_PASSWORD, or" >&2
    echo "  2. export SCOUT_USERNAME / SCOUT_PASSWORD and 'source config.sh' first." >&2
    exit 1
fi

# HTTPie doesnt support defining requests in a dedicated file, but we can still script it

CMD="http"
OPTS="--ignore-stdin"
 
# advancements/ranks
## get all ranks as a JSON object
"$CMD" "$OPTS" "$OPTIC_PROXY"/advancements/ranks

## ranks invalid parameter
"$CMD" "$OPTS" "$OPTIC_PROXY"/advancements/ranks\?foo

## rank requirements
"$CMD" "$OPTS" "$OPTIC_PROXY"/advancements/ranks/1/requirements

# advancements/youth
# The two requests below previously carried a trailing slash. Optic matches
# paths literally, so "/advancements/youth/123457890/" did not match the
# documented "/advancements/youth/{userId}" template and both were reported as
# "requests did not match a documented path" - which also meant the 401 case
# was never checked against the spec. Verified 2026-08-27: the trailing slash
# changes nothing server-side (401 unauthenticated, 404 authenticated, with or
# without it), so dropping it costs no coverage and gains the 401 check.

## authorization failure -> 401 Missing JWT Token
"$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/youth/123457890"

## not found -> 404. Verified 2026-08-27: this endpoint returns 404 for EVERY
## userId, including the signed-in user's own, so no request here elicits a
## 200. The third request in this block was dropped: it was labelled "method
## not allowed" but was byte-identical to this one and also returned 404. No
## method (POST/PUT/DELETE/PATCH) produces a 405 on this path, so the 405
## documented in openapi.yaml for it looks stale.
"$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/youth/${userId}" "Authorization: Bearer ${TOKEN}"

## leadership history
"$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/youth/${userId}/leadershipPositionHistory" "Authorization: Bearer ${TOKEN}"

# data lookups
## get all countries as a JSON object
"$CMD" "$OPTS" "$OPTIC_PROXY"/lookups/address/countries


# ============================================================
# Unit roster endpoints
# ------------------------------------------------------------
# These need two identifiers that config.sh does not export:
#   personGuid - the "pgu" claim inside the JWT
#   ORG_GUID   - the unit's organizationGuid; set it yourself, e.g.
#                export ORG_GUID=<your-unit-organizationGuid>  (find it via the toolkits call below)
# ============================================================

## personGuid is exported by config.sh (from the login response). Fall back to decoding
## the JWT's "pgu" claim if a TOKEN was supplied directly without running config.sh.
if [ -z "${personGuid:-}" ]; then
    b64_pad() { p=$(( ${#1} % 4 )); [ "$p" -ne 0 ] && printf '%s%s' "$1" "$(printf '=%.0s' $(seq $((4-p))))" || printf '%s' "$1"; }
    personGuid=$(b64_pad "$(printf '%s' "$TOKEN" | cut -d. -f2)" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '.pgu')
fi

## organizations the signed-in user belongs to (source of ORG_GUID)
"$CMD" "$OPTS" "${OPTIC_PROXY}/persons/v2/${personGuid}/toolkits" "Authorization: Bearer ${TOKEN}"

if [ -n "${ORG_GUID:-}" ]; then
  # --- roster: my.scouting "organization manager" pair -------------------
  ## adult roster (POST; filter body required). Matches the Roster Report person set.
  "$CMD" "$OPTS" POST "${OPTIC_PROXY}/organizations/v2/${ORG_GUID}/orgAdults" \
    "Authorization: Bearer ${TOKEN}" \
    filterData:='{"firstName":"","lastName":"","position":"","positionStatus":"active","registered":"all"}'

  ## youth roster (POST; same filter shape)
  "$CMD" "$OPTS" POST "${OPTIC_PROXY}/organizations/v2/${ORG_GUID}/orgYouths" \
    "Authorization: Bearer ${TOKEN}" \
    filterData:='{"firstName":"","lastName":"","position":"","positionStatus":"active","registered":"all"}'

  ## unauthenticated -> 401
  "$CMD" "$OPTS" POST "${OPTIC_PROXY}/organizations/v2/${ORG_GUID}/orgYouths" \
    filterData:='{"firstName":"","lastName":"","position":"","positionStatus":"active","registered":"all"}'

  # --- roster: unit endpoints (richer; return {..., users:[...]}) --------
  ## unit adults - envelope object, NOT a bare array
  "$CMD" "$OPTS" "${OPTIC_PROXY}/organizations/v2/units/${ORG_GUID}/adults" "Authorization: Bearer ${TOKEN}"

  ## unit youths - carries address/phone/age/rank inline
  "$CMD" "$OPTS" "${OPTIC_PROXY}/organizations/v2/units/${ORG_GUID}/youths" "Authorization: Bearer ${TOKEN}"

  ## youth-to-parent join table (only source of guardian contact details)
  "$CMD" "$OPTS" "${OPTIC_PROXY}/organizations/v2/units/${ORG_GUID}/parents" "Authorization: Bearer ${TOKEN}"

  ## dens / patrols
  "$CMD" "$OPTS" "${OPTIC_PROXY}/organizations/v2/units/${ORG_GUID}/subUnits" "Authorization: Bearer ${TOKEN}"

  ## key 3 leaders
  "$CMD" "$OPTS" "${OPTIC_PROXY}/organizations/v2/${ORG_GUID}/key3" "Authorization: Bearer ${TOKEN}"
else
  echo "ORG_GUID not set - skipping unit roster requests." >&2
fi

# ============================================================
# Per-person detail (renewal block, contact fallback, advancement)
# ============================================================

## full profile envelope: profile, addresses, phones, emails, organizationPositions, ...
"$CMD" "$OPTS" "${OPTIC_PROXY}/persons/${personGuid}/profile" "Authorization: Bearer ${TOKEN}"

## positions: carries ExpiryDt and the isYearlyMembership* / renewalOptOut* renewal flags
"$CMD" "$OPTS" "${OPTIC_PROXY}/persons/${personGuid}/positions" "Authorization: Bearer ${TOKEN}"

## communication-topic subscriptions (bare array; no Scout Life flag)
"$CMD" "$OPTS" "${OPTIC_PROXY}/persons/${personGuid}/subscriptions" "Authorization: Bearer ${TOKEN}"

## advancement: youthId is the INTEGER sbUserId/userId, not a GUID
if [ -n "${YOUTH_USER_ID:-}" ]; then
  "$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/v2/youth/${YOUTH_USER_ID}/ranks" "Authorization: Bearer ${TOKEN}"
  "$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/v2/youth/${YOUTH_USER_ID}/meritBadges" "Authorization: Bearer ${TOKEN}"
  "$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/v2/youth/${YOUTH_USER_ID}/awards" "Authorization: Bearer ${TOKEN}"
fi

## passing a personGuid where an integer is expected -> 400
"$CMD" "$OPTS" "${OPTIC_PROXY}/advancements/v2/youth/${personGuid}/ranks" "Authorization: Bearer ${TOKEN}"
