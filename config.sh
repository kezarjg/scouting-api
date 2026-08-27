#!/usr/bin/env bash

# Save and set safe shell options
SAVED_OPTIONS="$(set +o)"
set -uo pipefail
trap 'eval "$SAVED_OPTIONS"' RETURN

# This script must be sourced to set environment variables in the parent shell.
# Usage:
#   export SCOUT_USERNAME=<username>
#   export SCOUT_PASSWORD=<password>
#   source config.sh

# Ensure the username and password are provided via environment variables
if [ -z "${SCOUT_USERNAME:-}" ] || [ -z "${SCOUT_PASSWORD:-}" ]; then
    echo "Error: SCOUT_USERNAME and SCOUT_PASSWORD must be set before sourcing this script."
    return 1  # Use 'return' instead of 'exit' to avoid killing the parent shell
fi

# Verify dependencies
for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is required but not installed." >&2
        return 1
    fi
done
unset cmd  # Unset the loop variable for cleanliness

# Construct the login URL dynamically based on the username
# The login endpoint moved from my.scouting.org to auth.scouting.org. The old host now
# answers 503 "Back-end server is at capacity" for every request on /api/*, including
# bogus usernames - verified against a browser HAR capture 2026-08-27.
LOGIN_URL="https://auth.scouting.org/api/users/${SCOUT_USERNAME}/authenticate"

# Send the login request using curl
# The body is JSON now, not form-urlencoded. jq builds it so passwords containing
# quotes/backslashes are escaped correctly.
LOGIN_BODY=$(jq -n --arg p "$SCOUT_PASSWORD" '{password:$p}')
HTTP_STATUS=$(curl -s -o /tmp/.scout_login.$$ -w '%{http_code}' -X POST "$LOGIN_URL" \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json; version=2" \
    -H "Origin: https://my.scouting.org" \
    -H "Referer: https://my.scouting.org/" \
    --data "$LOGIN_BODY")
RESPONSE=$(cat /tmp/.scout_login.$$ 2>/dev/null)
rm -f /tmp/.scout_login.$$
unset LOGIN_BODY

# Fail loudly on a non-2xx. The old version swallowed this: an empty body made jq emit
# "null", so the script returned 0 having exported nothing.
if [ "$HTTP_STATUS" -lt 200 ] || [ "$HTTP_STATUS" -ge 300 ]; then
    echo "Error: login failed with HTTP $HTTP_STATUS from $LOGIN_URL" >&2
    [ -n "$RESPONSE" ] && echo "$RESPONSE" | head -c 300 >&2 && echo >&2
    return 1
fi

# Extract the Bearer token and userId from the JSON response using jq
BEARER_TOKEN=$(echo "$RESPONSE" | jq -r '.token')
USER_ID=$(echo "$RESPONSE" | jq -r '.account.userId')
# personGuid is the identifier for /persons/{personGuid}/* and /organizations/* routes.
# userId is a DIFFERENT identifier, required by /advancements/youth/{userId}/* and
# /advancements/v2/youth/{youthId}/*. Both are needed; they are not interchangeable.
PERSON_GUID=$(echo "$RESPONSE" | jq -r '.personGuid')

# Check if the token and userId were found
if [ "$BEARER_TOKEN" != "null" ] && [ "$USER_ID" != "null" ]; then
    # Set the environment variables
    export userId="$USER_ID"
    export TOKEN="$BEARER_TOKEN"
    export personGuid="$PERSON_GUID"
    
    # Optionally output the variables for debugging
    # echo "Bearer Token: $TOKEN"
    # echo "User ID: $USER_ID"
    
    # Unset intermediate variables for cleanliness
    unset RESPONSE
    unset BEARER_TOKEN
    unset USER_ID
    unset PERSON_GUID
    unset SCOUT_USERNAME
    unset SCOUT_PASSWORD
else
    echo "Failed to retrieve Bearer token or User ID."
    return 1
fi
