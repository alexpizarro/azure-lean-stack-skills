# staticwebapp.config.json reference

`frontend/public/staticwebapp.config.json` controls routing, auth, headers, and MIME types. Lives in the published output, not in source code paths.

## Minimal recommended config

```json
{
  "navigationFallback": {
    "rewrite": "/index.html",
    "exclude": ["/api/*", "/assets/*", "*.{css,js,png,svg,jpg,jpeg,ico,woff2}"]
  },
  "globalHeaders": {
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "geolocation=(), microphone=(), camera=()"
  },
  "mimeTypes": {
    ".json": "application/json"
  }
}
```

## Route protection

```json
{
  "routes": [
    {
      "route": "/admin/*",
      "allowedRoles": ["administrator"]
    },
    {
      "route": "/api/admin/*",
      "allowedRoles": ["administrator"]
    }
  ]
}
```

The `allowedRoles` mechanism uses SWA's built-in auth (`/.auth/login/aad`). For deeper auth needs (custom claims, ABAC), prefer a dedicated identity provider and validate in the Function code.

## Auth providers

SWA Free tier supports Microsoft (Entra), GitHub, X (Twitter). To enable:

```json
{
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/${TENANT_ID}/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID"
        }
      }
    }
  }
}
```

Then set the `AZURE_CLIENT_ID` app setting on the SWA. Custom auth requires Standard tier.

## CSP (Content Security Policy)

Skip CSP in `staticwebapp.config.json` if the app uses Vite — the build hashes scripts/styles and inline CSS may break with strict policies. Configure CSP server-side in Function handlers if you need it.

## Cache headers

For `frontend/dist/assets/*` (hashed bundles), SWA already serves cache-busting `Cache-Control: public, max-age=31536000, immutable`. For top-level `index.html`, SWA serves `no-cache`. Don't fight these defaults unless you have a reason.

## Local development

`vite.config.ts` proxies `/api/*` to `localhost:7071` (the Functions Core Tools port). No need to import `staticwebapp.config.json` locally — Vite handles routing.

```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      '/api': 'http://localhost:7071'
    }
  }
});
```

Run both:
- Frontend: `cd frontend && npm run dev`
- API:      `cd api && npm start`     (compiles TS, then runs `func start`)
