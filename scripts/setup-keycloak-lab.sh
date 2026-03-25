#!/bin/bash
set -e

# ================================================================
# setup-keycloak-lab.sh
# Configures Keycloak "lab" realm for K8s deployment.
#
# What it does:
#   1. Sets frontend URL so token issuer matches K8s internal DNS
#   2. Adds preferred_username mapper (Keycloak 24 omits it from access tokens)
#   3. Adds sub-override mapper (employee_id → sub, for corporate compatibility)
#
# Prerequisites: lab-keycloak container running, kcadm.sh available inside it
# See docs/keycloak-setup.md for full documentation.
# ================================================================

KEYCLOAK_CONTAINER="lab-keycloak"
REALM="lab"
CLIENT_ID_STRING="8d12476c2684592b12515daab4ca0ddb72007118-E"

# K8s internal DNS for Keycloak (must match AUTH_URL in Helm values)
KEYCLOAK_INTERNAL_URL="http://keycloak:8080"

echo
echo "=== Setup Keycloak Lab Realm ==="
echo

# Check container
if ! docker inspect "$KEYCLOAK_CONTAINER" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "  ❌ ${KEYCLOAK_CONTAINER} not running"
    exit 1
fi

KCADM="docker exec $KEYCLOAK_CONTAINER /opt/keycloak/bin/kcadm.sh"

# Login
$KCADM config credentials --server http://localhost:8080 --realm master --user admin --password admin 2>&1 | tail -1

# Step 1: Set frontend URL
echo "  Setting frontend URL to ${KEYCLOAK_INTERNAL_URL}..."
$KCADM update "realms/${REALM}" -s "attributes.frontendUrl=${KEYCLOAK_INTERNAL_URL}" 2>&1
echo "  ✅ Token issuer will be: ${KEYCLOAK_INTERNAL_URL}/realms/${REALM}"

# Step 2: Get client UUID
CLIENT_UUID=$($KCADM get "clients?clientId=${CLIENT_ID_STRING}" -r "$REALM" --fields id 2>&1 | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['id'])")
echo "  Client UUID: ${CLIENT_UUID}"

# Step 3: Check if mappers already exist
EXISTING=$($KCADM get "clients/${CLIENT_UUID}/protocol-mappers/models" -r "$REALM" --fields name 2>&1)

# Add preferred_username mapper
if echo "$EXISTING" | grep -q '"preferred_username"'; then
    echo "  ✅ preferred_username mapper exists"
else
    echo "  Adding preferred_username mapper..."
    $KCADM create "clients/${CLIENT_UUID}/protocol-mappers/models" -r "$REALM" \
        -s 'name=preferred_username' \
        -s 'protocol=openid-connect' \
        -s 'protocolMapper=oidc-usermodel-property-mapper' \
        -s 'config."claim.name"=preferred_username' \
        -s 'config."user.attribute"=username' \
        -s 'config."jsonType.label"=String' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' \
        -s 'config."userinfo.token.claim"=true' 2>&1
    echo "  ✅ preferred_username mapper created"
fi

# Add sub-override mapper
if echo "$EXISTING" | grep -q '"sub-override"'; then
    echo "  ✅ sub-override mapper exists"
else
    echo "  Adding sub-override mapper (employee_id → sub)..."
    $KCADM create "clients/${CLIENT_UUID}/protocol-mappers/models" -r "$REALM" \
        -s 'name=sub-override' \
        -s 'protocol=openid-connect' \
        -s 'protocolMapper=oidc-usermodel-attribute-mapper' \
        -s 'config."claim.name"=sub' \
        -s 'config."user.attribute"=employee_id' \
        -s 'config."jsonType.label"=String' \
        -s 'config."id.token.claim"=true' \
        -s 'config."access.token.claim"=true' 2>&1
    echo "  ✅ sub-override mapper created"
fi

echo
echo "=== Done ==="
echo
echo "Token endpoint: http://localhost:8180/realms/${REALM}/protocol/openid-connect/token"
echo "Token issuer:   ${KEYCLOAK_INTERNAL_URL}/realms/${REALM}"
echo
echo "Test:"
echo "  TOKEN=\$(curl -sf -X POST http://localhost:8180/realms/${REALM}/protocol/openid-connect/token \\"
echo "    -d grant_type=password -d client_id=${CLIENT_ID_STRING} \\"
echo "    -d username=admin -d password=admin | python3 -c \"import sys,json; print(json.load(sys.stdin)['access_token'])\")"
echo
