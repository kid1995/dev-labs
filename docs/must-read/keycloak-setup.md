# Keycloak Lab Setup

This documents the Keycloak configuration needed for the lab to simulate the corporate OIDC endpoint (`employee.login.int.signal-iduna.org`).

## Why this is complex

The hint-service (and all sda-services) use `c4-soft springaddons` for OIDC. The security flow is:

```
1. JWT token arrives with 'iss' (issuer) and 'sub' (subject) claims
2. Spring matches 'iss' against ops[0].iss in application.yml (= AUTH_URL env var)
3. Spring fetches OIDC discovery at {iss}/.well-known/openid-configuration
4. WebSecurityConfig checks getAuthentication().getName() (= 'sub' claim) against AUTH_USERS
```

Three things must align:
- Token `iss` claim == app's `AUTH_URL` (exact match, no trailing slash difference)
- Token `sub` claim == one of the values in `AUTH_USERS`
- OIDC discovery endpoint must be reachable from the pod

## Corporate vs Lab

| | Corporate | Lab |
|---|---|---|
| OIDC endpoint | `https://employee.login.int.signal-iduna.org/` | `http://keycloak:8080/realms/lab` |
| Token `sub` claim | Employee ID (e.g., `S000325`) | Keycloak UUID (e.g., `08210d1d-...`) |
| Token `preferred_username` | Employee ID | `admin` (needs custom mapper) |
| `AUTH_USERS` config | `S000325` | Must match the `sub` claim value |

## Realm: lab

Created via `config/keycloak/lab-realm.json` import on first start.

### Client: `8d12476c2684592b12515daab4ca0ddb72007118-E`

Same client ID as corporate. Configuration:

| Setting | Value | Why |
|---|---|---|
| Client Protocol | openid-connect | Standard OIDC |
| Access Type | public | No client secret needed (same as corporate) |
| Direct Access Grants | enabled | Allows `grant_type=password` for testing |
| Valid Redirect URIs | `*` | Lab only, corporate has strict redirect |

### Protocol Mappers (on the client)

These are **not included by default** in Keycloak 24 and must be added manually or via `lab-realm.json`:

#### 1. preferred_username mapper

By default, Keycloak 24 does NOT include `preferred_username` in access tokens (only in ID tokens). This mapper adds it.

```
Name:            preferred_username
Mapper Type:     User Property
User Attribute:  username
Token Claim:     preferred_username
Add to access token: ON
Add to ID token:     ON
Add to userinfo:     ON
```

kcadm command:
```bash
kcadm.sh create "clients/{CLIENT_UUID}/protocol-mappers/models" -r lab \
    -s 'name=preferred_username' \
    -s 'protocol=openid-connect' \
    -s 'protocolMapper=oidc-usermodel-property-mapper' \
    -s 'config."claim.name"=preferred_username' \
    -s 'config."user.attribute"=username' \
    -s 'config."jsonType.label"=String' \
    -s 'config."id.token.claim"=true' \
    -s 'config."access.token.claim"=true' \
    -s 'config."userinfo.token.claim"=true'
```

#### 2. sub-override mapper (optional)

In corporate, `sub` = employee ID (e.g., `S000325`). In Keycloak, `sub` = UUID by default.
This mapper overrides `sub` with the `employee_id` user attribute — but only works if the attribute is set on the user.

```
Name:            sub-override
Mapper Type:     User Attribute
User Attribute:  employee_id
Token Claim:     sub
Add to access token: ON
Add to ID token:     ON
```

**Current status:** Mapper exists but user attributes don't persist in Keycloak dev mode.
Workaround: `AUTH_USERS` in `values-lab-tst.yaml` uses the Keycloak UUID directly.

### Users

| Username | Password | Purpose | Corporate equivalent |
|---|---|---|---|
| admin | admin | Default test user | Employee S000325 |
| testuser | test | Secondary test user | Employee U116330 |

### Frontend URL (issuer alignment)

The token `iss` claim must match the app's `AUTH_URL` exactly. Keycloak uses the request URL as issuer by default.

Problem: You access Keycloak via `localhost:8180` (from host) but the app validates against `keycloak:8080` (K8s internal DNS).

Fix: Set the realm's frontend URL so the issuer is always `http://keycloak:8080`:

```bash
kcadm.sh update realms/lab -s "attributes.frontendUrl=http://keycloak:8080"
```

This makes the token issuer `http://keycloak:8080/realms/lab` regardless of how you access the token endpoint.

**Side effect:** After setting frontendUrl, the Keycloak admin console may redirect to `keycloak:8080` which is not reachable from your browser. Access admin via `localhost:8180` and ignore the redirect.

## Getting a token

```bash
# From host machine (via Docker Compose port mapping)
TOKEN=$(curl -sf -X POST "http://localhost:8180/realms/lab/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=8d12476c2684592b12515daab4ca0ddb72007118-E" \
    -d "username=admin" \
    -d "password=admin" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Use it
curl -H "Authorization: Bearer ${TOKEN}" http://localhost:18080/api/hints
```

## AUTH_USERS in Helm values

The `values-lab-tst.yaml` must set `authUsers` to match the JWT `sub` claim:

```yaml
jwt:
  # Must match getAuthentication().getName() which returns JWT 'sub' claim
  # Keycloak lab 'admin' user has sub = 08210d1d-6dc7-4bd0-8231-8f9749d3671d
  # Corporate users have sub = employee ID (e.g., S000325)
  authUsers: "08210d1d-6dc7-4bd0-8231-8f9749d3671d"
```

If the sub-override mapper works (requires `employee_id` attribute on user):
```yaml
jwt:
  authUsers: "S000325"
```

## Troubleshooting

### 401 Unauthorized
Token issuer doesn't match `AUTH_URL`. Check:
```bash
# Decode token
echo $TOKEN | cut -d. -f2 | python3 -c "import sys,base64,json; print(json.loads(base64.urlsafe_b64decode(sys.stdin.read().strip()+'=='))['iss'])"

# Compare with app config
kubectl -n elpa-elpa4 get configmap tst-hint -o jsonpath='{.data.AUTH_URL}'
```
They must match exactly (including trailing slash).

### Access Denied (not 401)
Token is valid but `sub` doesn't match `AUTH_USERS`. Check:
```bash
# Get sub from token
echo $TOKEN | cut -d. -f2 | python3 -c "import sys,base64,json; print(json.loads(base64.urlsafe_b64decode(sys.stdin.read().strip()+'=='))['sub'])"

# Compare with AUTH_USERS in configmap
kubectl -n elpa-elpa4 get configmap tst-hint -o jsonpath='{.data.AUTH_USERS}'
```

### preferred_username is null
Keycloak 24 doesn't include it in access tokens by default. Add the protocol mapper (see above).

### Keycloak admin console redirects to keycloak:8080
Expected after setting frontendUrl. Use `localhost:8180` directly and ignore redirects.
