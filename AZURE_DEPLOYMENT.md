# Azure Deployment Strategie - Jaap Junior met Qdrant

## Overzicht

Dit document beschrijft de werkende deployment strategie voor Jaap Junior naar Azure Container Apps met Qdrant als vector database.

## Architectuur

### Components
- **API Backend** (`jaapjunior-api`): Node.js/Bun API met LlamaIndex en Qdrant integration
- **Frontend** (`jaapjunior`): Vue.js applicatie met Nginx proxy
- **Qdrant** (`jaapjunior-qdrant`): Vector database voor RAG (Retrieval Augmented Generation)
- **ChromaDB** (`jaapjunior-chromadb`): Legacy component (niet gebruikt in Azure deployment)

### Netwerk Configuratie
- **Frontend**: External ingress (publiek toegankelijk)
  - URL: `https://jaapjunior.bluerock-7a3df5c8.westeurope.azurecontainerapps.io`
- **API**: Internal ingress (alleen binnen Azure environment)
  - URL: `http://jaapjunior-api.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io` (ZONDER port!)
- **Qdrant**: Internal ingress op port 6333
  - URL: `http://jaapjunior-qdrant.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io:6333`

## Deployment Proces

### Stap 1: Build en Push API Image

```bash
# Build API image in Azure Container Registry
az acr build \
  --registry jaapjuniorregistry \
  --image jaapjunior-api:latest \
  --file packages/api/Dockerfile \
  --platform linux/amd64 \
  .
```

**Waarom**: Azure Container Registry (ACR) build zorgt ervoor dat de image gebouwd wordt met de juiste architectuur en direct beschikbaar is voor deployment.

### Stap 2: Deploy API naar Azure Container App

```bash
# Update API container met nieuwe image
az containerapp update \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --image jaapjuniorregistry.azurecr.io/jaapjunior-api:latest
```

**Waarom**: Update commando zorgt voor zero-downtime deployment met automatische health checks.

### Stap 3: Verifieer Qdrant Ingress

```bash
# Check of Qdrant internal ingress enabled is
az containerapp ingress show \
  --name jaapjunior-qdrant \
  --resource-group chatbot_jaapjunior_rg
```

Als ingress NIET enabled is:
```bash
# Enable internal ingress voor Qdrant
az containerapp ingress enable \
  --name jaapjunior-qdrant \
  --resource-group chatbot_jaapjunior_rg \
  --type internal \
  --target-port 6333 \
  --transport http
```

**Waarom**: Zonder ingress kunnen containers in Azure elkaar niet bereiken, zelfs niet binnen hetzelfde environment.

### Stap 4: Restart API (indien nodig)

```bash
# Restart API om reconnectie met Qdrant te forceren
az containerapp revision restart \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --revision $(az containerapp show --name jaapjunior-api --resource-group chatbot_jaapjunior_rg --query 'properties.latestRevisionName' -o tsv)
```

**Waarom**: Na het enablen van Qdrant ingress moet de API opnieuw opstarten om de verbinding tot stand te brengen.

### Stap 5: Verifieer Deployment

```bash
# Check API logs voor errors
az containerapp logs show \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --tail 50
```

Verwachte output: `Started server: http://localhost:3000` zonder ConnectionRefused errors.

## Kritieke Configuratie

### API Environment Variables
```bash
QDRANT_URI=http://jaapjunior-qdrant:6333  # Gebruik hostname, niet FQDN binnen environment
DB_PATH=/app/data/jaapjunior.db
JWT_SECRET=secretref:jwt-secret
API_TOKEN=secretref:api-token
SHARED_PASSWORD=secretref:shared-password
OPENAI_API_KEY=secretref:openai-api-key
ANTHROPIC_API_KEY=secretref:anthropic-api-key
JINAAI_API_KEY=secretref:jinaai-api-key
```

### Qdrant Ingress Configuration
```json
{
  "external": false,
  "targetPort": 6333,
  "transport": "Http",
  "fqdn": "jaapjunior-qdrant.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io"
}
```

### Frontend API Backend Configuration
```bash
API_BACKEND_URL=http://jaapjunior-api.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io
```

**BELANGRIJK**: Voeg GEEN port nummer toe aan deze URL! Azure internal networking regelt port mapping automatisch via ingress.

## Veelvoorkomende Problemen

### 1. ConnectionRefused naar Qdrant
**Symptoom**: `Unable to connect. code: "ConnectionRefused"`
**Oorzaak**: Qdrant heeft geen ingress enabled
**Oplossing**: Voer Stap 3 uit om ingress te enablen

### 2. Docker Cache Issues Lokaal
**Symptoom**: Code wijzigingen worden niet opgepikt
**Oorzaak**: Docker layer caching
**Oplossing**:
```bash
docker system prune -af --volumes
docker-compose build --no-cache api
```

### 3. API kan Qdrant niet vinden
**Symptoom**: DNS resolution errors
**Oorzaak**: Verkeerde hostname in QDRANT_URI
**Oplossing**: Gebruik `http://jaapjunior-qdrant:6333` (hostname), niet de FQDN

### 4. 504 Gateway Timeout / Login werkt niet
**Symptoom**: Frontend kan API niet bereiken, 504 Gateway Timeout errors, login faalt
**Oorzaak**: Port nummer (`:3000`) toegevoegd aan API_BACKEND_URL
**Oplossing**:
- Verwijder het port nummer uit API_BACKEND_URL environment variable
- Gebruik: `http://jaapjunior-api.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io` (ZONDER `:3000`)
- Azure internal ingress regelt port mapping automatisch
- Update de frontend container app:
  ```bash
  az containerapp update \
    --name jaapjunior \
    --resource-group chatbot_jaapjunior_rg \
    --set-env-vars API_BACKEND_URL="http://jaapjunior-api.internal.bluerock-7a3df5c8.westeurope.azurecontainerapps.io"
  ```

### 5. Qdrant ConnectionRefused met `:6333` port
**Symptoom**: `Unable to connect. code: "ConnectionRefused"` met `:6333` in de URL path
**Oorzaak**: De @llamaindex/qdrant library voegt automatisch `:6333` toe aan URLs, maar Azure internal ingress accepteert geen expliciete ports
**Oplossing**: Code fix in `packages/api/src/agent.ts` om de port te strippen voor Azure URLs
- Zie `getQdrantConfig()` functie in `packages/api/src/agent.ts:28-36`
- De functie detecteert Azure URLs (`.internal.` of `.azurecontainerapps.io`) en verwijdert de `:6333` port

### 6. Qdrant Indexing Hangt / Timeout
**Symptoom**: "Failed to obtain server version" error, indexing proces hangt, stream timeout na 90+ seconden
**Oorzaak**: @llamaindex/qdrant client library compatibiliteitsprobleem met Qdrant server, of zeer langzame embedding generation voor grote document sets
**Status**: **NOG NIET OPGELOST**
**Mogelijke oplossingen**:
- Reduce document set size voor initiële testing
- Check Qdrant server logs voor errors
- Overweeg alternatieve vector store (ChromaDB werkte eerder wel)
- Verhoog timeouts in de client
- Pre-create Qdrant collections met juiste configuratie

## Verschillen Lokaal vs Azure

| Aspect | Lokaal (Docker Compose) | Azure (Container Apps) |
|--------|------------------------|------------------------|
| Networking | Bridge network | Azure internal networking |
| Qdrant URL | `http://qdrant:6333` | `http://jaapjunior-qdrant:6333` |
| Ingress vereist | Nee | Ja (voor inter-container communicatie) |
| Persistence | Named volumes | Azure File Shares (optioneel) |
| API Port | 3001 | 3000 |
| Frontend Port | 5174 | 80 |

## Testing

### Lokaal Testen
```bash
# Start alle services
docker-compose up -d

# Test API
curl http://localhost:3001/api/v1

# Test met authenticatie
TOKEN=$(curl -s -X POST http://localhost:3001/api/v1/auth \
  -H "Content-Type: application/json" \
  -d '{"password": "test123"}' | jq -r '.jwt')

curl -X POST http://localhost:3001/api/v1/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"message": "Wat is de Wmo?", "agentId": "cs-wmo"}'
```

### Azure Testen
```bash
# Test via publieke frontend
open https://jaapjunior.bluerock-7a3df5c8.westeurope.azurecontainerapps.io

# Check API logs
az containerapp logs show \
  --name jaapjunior-api \
  --resource-group chatbot_jaapjunior_rg \
  --follow
```

## Belangrijke Wijzigingen t.o.v. ChromaDB

1. **Vector Store**: Gebruikt Qdrant in plaats van ChromaDB
   - Package: `@llamaindex/qdrant` in plaats van `chromadb`

2. **Ingress Requirement**: Qdrant vereist ingress voor interne communicatie

3. **Port**: Qdrant gebruikt port 6333 (ChromaDB gebruikte 8000)

4. **Index Creation**: Gebeurt on-demand bij eerste query naar een agent

## Resources

- Resource Group: `chatbot_jaapjunior_rg`
- Azure Region: `West Europe`
- Container Registry: `jaapjuniorregistry.azurecr.io`
- Environment: `jaapjunior-env`

## Volgende Stappen

Voor toekomstige deployments:
1. Gebruik het `scripts/azure-deploy-qdrant.sh` script (zie volgende sectie)
2. Test altijd eerst lokaal met docker-compose
3. Verifieer dat `packages/api/src/` geen legacy ChromaDB code bevat
4. Check dat Qdrant ingress enabled blijft na environment updates
