# Railway Deployment Guide - Qdrant Version

Complete guide voor het deployen en testen van de Qdrant versie op Railway.

## Stap 1: Push Branch naar GitHub

```bash
# Check huidige status
git status

# Commit eventuele wijzigingen
git add test-local-docker.sh
git commit -m "Add local Docker test script"

# Push railway-unified branch
git push origin railway-unified
```

## Stap 2: Railway Service Aanmaken

### Optie A: Via Railway Dashboard (Aanbevolen voor eerste keer)

1. Ga naar [railway.app](https://railway.app)
2. Open je bestaande project (waar ChromaDB draait)
3. Click **"+ New"** → **"GitHub Repo"**
4. Selecteer repository: `jaapjunior`
5. **Belangrijk:** Selecteer branch `railway-unified` (niet main!)
6. Railway detecteert automatisch `railway.json` en `Dockerfile.combined`

### Optie B: Via Railway CLI

```bash
# Zorg dat je op de juiste branch zit
git checkout railway-unified

# Login
railway login

# Link aan bestaand project (als je die al hebt)
railway link

# Of: maak nieuw project
railway init

# Deploy
railway up
```

## Stap 3: Environment Variables Instellen

In Railway Dashboard → Service Settings → Variables:

```bash
# Runtime
NODE_ENV=production
PORT=3000

# Database (localhost want combined container)
QDRANT_URI=http://localhost:6333
DB_PATH=/app/data/jaapjunior.db

# API Keys (gebruik je echte keys!)
OPENAI_API_KEY=sk-...
JINAAI_API_KEY=jina_...
ANTHROPIC_API_KEY=sk-ant-...

# Security (gebruik sterke secrets!)
JWT_SECRET=<genereer-een-sterke-secret>
API_TOKEN=<genereer-een-sterke-token>
SHARED_PASSWORD=<jouw-wachtwoord>
```

**Tip:** Gebruik `openssl rand -hex 32` om sterke secrets te genereren.

## Stap 4: Deployment Monitoren

Railway bouwt automatisch. Dit duurt ~5-10 minuten.

### Via Dashboard:
- Ga naar "Deployments" tab
- Kijk naar build logs
- Wacht tot status "Success" is

### Via CLI:
```bash
railway logs
```

Je ziet output zoals:
```
Starting Qdrant...
Qdrant HTTP listening on 6333
Qdrant ready!
Starting API...
Started server: http://0.0.0.0:3000
```

## Stap 5: Haal Railway URL Op

### Via Dashboard:
- Ga naar Settings → Networking
- Kopieer de "Public Domain" (bijv. `your-app.railway.app`)

### Via CLI:
```bash
railway domain
```

## Stap 6: Test de Deployment

Gebruik het test script:

```bash
# Maak test script executable
chmod +x test-railway.sh

# Run test (vervang URL met jouw Railway domain)
RAILWAY_URL="https://your-app.railway.app" ./test-railway.sh
```

## Verwachte Testresultaten

```
==========================================
   Railway Test (Qdrant + API)
==========================================

1. Health check...
✅ API is healthy

2. Login...
✅ Login successful

3. Test cs-wmo agent...
   Vraag: 'Wat zijn contractstandaarden?'
   Response tijd: 15-30s (eerste keer, met indexing)
✅ Agent werkt correct met Qdrant

Antwoord (eerste 200 chars):
[ZOEKTERMEN (Vector Search)]
...

==========================================
   ✅ Alle tests geslaagd!
==========================================
```

## Troubleshooting

### Build Failed
```bash
# Check build logs
railway logs

# Veelvoorkomende problemen:
# - Dockerfile.combined niet gevonden → Check railway.json path
# - Out of memory → Upgrade Railway plan
```

### Container Crasht
```bash
# Check runtime logs
railway logs --follow

# Check voor:
# - Missing environment variables
# - Qdrant startup errors
# - Port binding issues
```

### API Keys Werken Niet
```bash
# Verify environment variables zijn gezet
railway variables

# Let op: Variables moeten EXACT overeenkomen met wat de app verwacht
```

### Qdrant Niet Bereikbaar
```bash
# Check QDRANT_URI in environment variables
# Moet zijn: http://localhost:6333 (voor combined container)

# In logs moet je zien:
# "Qdrant HTTP listening on 6333"
# "Qdrant ready!"
```

## Data Persistence

Railway gebruikt **Volumes** voor persistent storage:
- `/app/data` - SQLite database
- `/app/qdrant_storage` - Qdrant vector data

Deze data blijft behouden tussen deployments.

## Parallel Draaien met ChromaDB

Je hebt nu 2 services:
1. **Oude service** - ChromaDB versie (blijft draaien)
2. **Nieuwe service** - Qdrant versie (nieuwe deployment)

Beide hebben hun eigen URL en draaien onafhankelijk.

## Kosten

Railway Free tier:
- $5 credit/maand
- ~500 uur runtime

Voor productie: upgrade naar Pro ($20/maand)

## Rollback

Als er problemen zijn:
```bash
# Via CLI
railway rollback

# Via Dashboard
Deployments → Select previous deployment → "Redeploy"
```

## Volgende Stappen

Na succesvolle test:
1. Update frontend config om naar nieuwe Railway URL te wijzen
2. Test grondig met verschillende vragen
3. Monitor performance en kosten
4. Overweeg oude ChromaDB service te deprovision (als alles werkt)
