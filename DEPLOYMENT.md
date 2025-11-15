# Deployment Guide

Dit project kan gedeployed worden op **Azure Container Apps** of **Railway** met dezelfde codebase.

## 🏗️ Architectuur

Beide platforms gebruiken het **combined container pattern**:
- **1 container** met Qdrant + API
- Qdrant draait op `localhost:6333` (internal)
- API draait op `PORT` (external)

**Dockerfile:** `packages/api/Dockerfile.combined`

---

## 🔵 Azure Container Apps Deployment

### Prerequisites
- Azure CLI geïnstalleerd
- Ingelogd: `az login`

### 1. Build Image
```bash
cd /Users/gstevens/jaapjunior

az acr build \
  --registry jaapjuniorregistry \
  --image jaapjunior-api:latest \
  --file packages/api/Dockerfile.combined \
  --platform linux/amd64 \
  .
```

### 2. Deploy to Container App
```bash
az containerapp update \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --image jaapjuniorregistry.azurecr.io/jaapjunior-api:latest
```

### 3. Set Environment Variables
```bash
az containerapp update \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --set-env-vars \
    "NODE_ENV=production" \
    "PORT=3000" \
    "QDRANT_URI=http://localhost:6333" \
    "DB_PATH=/app/data/jaapjunior.db" \
  --secrets \
    "shared-password=YOUR_PASSWORD" \
    "jwt-secret=YOUR_JWT_SECRET" \
    "api-token=YOUR_API_TOKEN" \
    "openai-api-key=YOUR_OPENAI_KEY" \
    "anthropic-api-key=YOUR_ANTHROPIC_KEY" \
    "jinaai-api-key=YOUR_JINA_KEY"
```

### 4. Verify
```bash
# Check logs
az containerapp logs show \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --tail 50

# Test endpoint
curl https://jaapjunior.bluerock-7a3df5c8.westeurope.azurecontainerapps.io/api/v1
```

---

## 🚂 Railway Deployment

### Prerequisites
- Railway account
- Railway CLI geïnstalleerd (optional)

### Method 1: Via Railway Dashboard

1. **Create New Project**
   - Go to [railway.app](https://railway.app)
   - "New Project" → "Deploy from GitHub repo"
   - Select `jaapjunior` repository

2. **Configure Build**
   - Railway detecteert automatisch `railway.json`
   - Build gebruikt `packages/api/Dockerfile.combined`

3. **Set Environment Variables**
   ```
   NODE_ENV=production
   PORT=3000
   QDRANT_URI=http://localhost:6333
   DB_PATH=/app/data/jaapjunior.db
   SHARED_PASSWORD=xxx
   JWT_SECRET=xxx
   API_TOKEN=xxx
   OPENAI_API_KEY=xxx
   ANTHROPIC_API_KEY=xxx
   JINAAI_API_KEY=xxx
   ```

4. **Deploy**
   - Push naar main branch
   - Railway build + deploy automatisch

### Method 2: Via Railway CLI

```bash
# Login
railway login

# Link project
railway link

# Set environment variables
railway variables set NODE_ENV=production
railway variables set PORT=3000
railway variables set QDRANT_URI=http://localhost:6333
# ... etc

# Deploy
railway up
```

### Verify
```bash
# Check logs
railway logs

# Test endpoint
curl https://your-app.railway.app/api/v1
```

---

## 🔀 Docker Compose (Local Development)

Voor lokale development kun je ook docker-compose gebruiken:

```bash
# Development mode (met hot reload)
docker-compose -f docker-compose.dev.yml up

# Production mode (combined container)
docker-compose -f docker-compose.prod.yml up
```

---

## 📊 Platform Comparison

| Feature | Azure Container Apps | Railway |
|---------|---------------------|---------|
| **Build** | ACR (remote) | In-platform |
| **Auto-deploy** | Manual / GitHub Actions | Automatic on push |
| **Scaling** | Manual / Auto-scale rules | Manual |
| **Logs** | Azure CLI / Portal | Railway CLI / Dashboard |
| **Cost** | Pay-per-use | $5/month starter |
| **Networking** | VNet, Private endpoints | Automatic HTTPS |

---

## 🐛 Troubleshooting

### Qdrant niet bereikbaar
**Symptoom:** `Connection refused to Qdrant`

**Fix:** Controleer `QDRANT_URI`:
- Combined container: `http://localhost:6333` ✅
- Separate containers: `http://qdrant:6333`

### Container start fails
**Symptoom:** Container crasht bij startup

**Fix:** Check logs voor Qdrant startup:
```bash
# Azure
az containerapp logs show --name jaapjunior-api --resource-group chatbot_jaapjunior_rg --tail 100

# Railway
railway logs
```

Verwachte output:
```
Starting Qdrant...
Qdrant ready!
Starting API...
Started server: http://localhost:3000
```

### API keys werken niet
**Symptoom:** `401 Unauthorized` of `Missing API key`

**Fix:** Verify environment variables zijn correct gezet als **secrets** (niet als plain text variables).

---

## 📝 Notes

- **Data persistence:** Zowel Azure als Railway hebben persistent storage voor `/app/data` en `/app/qdrant_storage`
- **Updates:** Push naar main branch → Azure: manual redeploy, Railway: auto-deploy
- **Rollback:** Azure: switch revision, Railway: redeploy previous version
