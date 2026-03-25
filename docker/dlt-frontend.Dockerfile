# Pre-built Dockerfile for dlt-manager frontend
# Expects: frontend already built via npx ng build --configuration production
#
# [LAB SIMULATION] Base image replaced:
#   Original: prod.docker.system.local/baseimages/sda-nginx-1-alpine:69 (internal registry)
#   Lab:      nginx:1-alpine (public Docker Hub)
# [LAB SIMULATION] Nginx config simplified:
#   Original: base image includes CSP headers, sub_filter for URL replacement, SSL config
#   Lab:      minimal nginx config with SPA fallback, no CSP/SSL
# [LAB SIMULATION] @signal-iduna/ui packages:
#   Original: npm ci from internal Verdaccio at npmrepo.system.local
#   Lab:      node_modules copied from local machine (packages pre-installed)
FROM nginx:1-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy built Angular app
COPY dist/dltmanager-ui/browser/ /usr/share/nginx/html/

# Nginx config
RUN cat > /etc/nginx/conf.d/default.conf << 'NGINX'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
}
NGINX

# [LAB SIMULATION] Web Components fix for @signal-iduna/ui:
#   Problem: Angular bundles the SI web components with stripped CSS (tree-shaking removes styles),
#   while the scripts bundle has the full Lit components with all CSS (padding, background, etc.).
#   The modulepreload hints cause Angular's chunks to register stripped components BEFORE
#   the scripts bundle, so the button renders as unstyled 19px-tall text.
#
#   Fix: Remove the `export` statement from scripts bundle so it can load as a synchronous classic
#   script (not module). This ensures web components register with FULL CSS styles BEFORE
#   Angular's module chunks execute. Then guard customElements.define so Angular's stripped
#   re-registration is silently skipped (keeping the full-CSS versions).
#
#   Step 1: Strip the trailing `export{...}` from scripts bundle (it's not needed — components
#           self-register via customElements.define, the export is only for tree-shaking)
RUN SCRIPTS=$(ls /usr/share/nginx/html/scripts-*.js 2>/dev/null | head -1) && \
    if [ -n "$SCRIPTS" ]; then \
      sed -i 's|export{[^}]*};$||' "$SCRIPTS"; \
    fi
#   Step 2: Change scripts from defer to synchronous (no type="module", no defer)
#           so it runs BEFORE any module scripts
RUN sed -i 's|<script src="scripts-\([^"]*\)\.js" defer></script>|<script src="scripts-\1.js"></script>|g' /usr/share/nginx/html/index.html
#   Step 3: Guard customElements.define — scripts bundle registers first with full CSS,
#           Angular chunks re-registration is silently skipped
RUN sed -i 's|</head>|<script>const _origDefine=customElements.define.bind(customElements);customElements.define=function(n,c,o){if(!customElements.get(n))_origDefine(n,c,o);}</script></head>|' /usr/share/nginx/html/index.html

# [LAB SIMULATION] Runtime URL substitution:
#   Original: sda-nginx base image uses sub_filter to replace NOT_SET_BACKEND_URL / NOT_SET_AUTH_URL
#   Lab:      entrypoint script uses sed to replace placeholders + hardcoded production OIDC URL
#   Replaced URLs:
#     NOT_SET_BACKEND_URL → $BACKEND_URL (e.g. http://localhost:8082)
#     NOT_SET_AUTH_URL → $AUTH_URL (e.g. http://localhost:8180/realms/lab)
#     https://employee.login.int.signal-iduna.org/ → $AUTH_URL (hardcoded in Angular chunks)
RUN cat > /docker-entrypoint.d/90-env-subst.sh << 'SCRIPT'
#!/bin/sh
if [ -n "$BACKEND_URL" ]; then
    find /usr/share/nginx/html -name '*.js' -exec \
        sed -i "s|NOT_SET_BACKEND_URL|${BACKEND_URL}|g" {} \;
fi
if [ -n "$AUTH_URL" ]; then
    find /usr/share/nginx/html -name '*.js' -exec \
        sed -i "s|NOT_SET_AUTH_URL|${AUTH_URL}|g" {} \;
    find /usr/share/nginx/html -name '*.js' -exec \
        sed -i "s|https://employee.login.int.signal-iduna.org/|${AUTH_URL}|g" {} \;
fi
SCRIPT
RUN chmod +x /docker-entrypoint.d/90-env-subst.sh


EXPOSE 80
