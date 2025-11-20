#!/bin/bash

# Azure Herindexering Script voor Jaap Junior
# Dit script kan worden gebruikt door beheerders om agents opnieuw te indexeren
# Versie: 1.0

set -e

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuratie
RG="chatbot_jaapjunior_rg"
API_APP="jaapjunior-api"
QDRANT_APP="jaapjunior-qdrant"

# Functies
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help functie
show_help() {
    cat << EOF
${BLUE}Azure Herindexering Script${NC}

Dit script herindexeert agents door de API container te herstarten.
Na herstart worden agents opnieuw geïndexeerd bij eerste gebruik.

${YELLOW}Gebruik:${NC}
    $0 [optie]

${YELLOW}Opties:${NC}
    -h, --help          Toon deze help
    -s, --status        Toon status van API en Qdrant
    -r, --restart       Herstart API (forceert herindexering bij eerste gebruik)
    -f, --full          Volledige herindexering (wist Qdrant collections + herstart API)
    -a, --agent AGENT   Wis specifieke agent collection (jw, wmo, cs-wmo)

${YELLOW}Voorbeelden:${NC}
    # Toon status
    $0 --status

    # Snelle herindexering (alleen API herstarten)
    $0 --restart

    # Volledige herindexering (wist alle data + herstart)
    $0 --full

    # Herindexeer alleen cs-wmo agent
    $0 --agent cs-wmo

${YELLOW}Let op:${NC}
    - Voor --full en --agent heb je toegang tot de Qdrant container nodig
    - De API heeft ongeveer 30 seconden nodig om op te starten
    - Herindexering gebeurt automatisch bij eerste query naar een agent
EOF
}

# Status functie
show_status() {
    log_info "=== Huidige Status ==="
    echo ""

    # API Status
    log_info "API Status:"
    API_STATUS=$(az containerapp show \
        --name "$API_APP" \
        --resource-group "$RG" \
        --query 'properties.runningStatus' \
        -o tsv 2>/dev/null || echo "UNKNOWN")

    API_REPLICAS=$(az containerapp replica list \
        --name "$API_APP" \
        --resource-group "$RG" \
        --query 'length([])' \
        -o tsv 2>/dev/null || echo "0")

    echo "  Status: $API_STATUS"
    echo "  Replicas: $API_REPLICAS"
    echo ""

    # Qdrant Status
    log_info "Qdrant Status:"
    QDRANT_STATUS=$(az containerapp show \
        --name "$QDRANT_APP" \
        --resource-group "$RG" \
        --query 'properties.runningStatus' \
        -o tsv 2>/dev/null || echo "UNKNOWN")

    echo "  Status: $QDRANT_STATUS"
    echo ""

    # API URL
    API_URL=$(az containerapp show \
        --name "$API_APP" \
        --resource-group "$RG" \
        --query 'properties.configuration.ingress.fqdn' \
        -o tsv 2>/dev/null)

    if [ -n "$API_URL" ]; then
        log_info "API URL: http://$API_URL"
    fi

    echo ""
}

# Restart API functie
restart_api() {
    log_info "Herstarten van API container..."
    log_warning "Dit forceert herindexering bij eerste gebruik van elke agent"
    echo ""

    # Vraag bevestiging
    read -p "Weet je zeker dat je wilt herstarten? (ja/nee): " confirm
    if [ "$confirm" != "ja" ]; then
        log_info "Geannuleerd"
        exit 0
    fi

    # Herstart API
    az containerapp restart \
        --name "$API_APP" \
        --resource-group "$RG" \
        --output none || {
            log_error "Herstart gefaald"
            exit 1
        }

    log_success "API herstart succesvol"
    log_info "Wachten op API opstart (30 seconden)..."
    sleep 30

    # Check status
    API_STATUS=$(az containerapp show \
        --name "$API_APP" \
        --resource-group "$RG" \
        --query 'properties.runningStatus' \
        -o tsv 2>/dev/null || echo "UNKNOWN")

    if [ "$API_STATUS" == "Running" ]; then
        log_success "API is actief"
        log_info "Agents worden opnieuw geïndexeerd bij eerste gebruik"
    else
        log_warning "API status: $API_STATUS - Check logs voor details"
    fi
}

# Volledige herindexering (vereist Qdrant toegang)
full_reindex() {
    log_warning "=== VOLLEDIGE HERINDEXERING ==="
    log_warning "Dit wist alle Qdrant collections en herstart de API"
    log_warning "Alle agents worden opnieuw geïndexeerd bij eerste gebruik"
    echo ""

    # Vraag bevestiging
    read -p "Weet je ZEKER dat je alle data wilt wissen? (typ 'WISSEN' om te bevestigen): " confirm
    if [ "$confirm" != "WISSEN" ]; then
        log_info "Geannuleerd"
        exit 0
    fi

    # Get Qdrant FQDN
    QDRANT_FQDN=$(az containerapp show \
        --name "$QDRANT_APP" \
        --resource-group "$RG" \
        --query 'properties.configuration.ingress.fqdn' \
        -o tsv 2>/dev/null)

    if [ -z "$QDRANT_FQDN" ]; then
        log_error "Kan Qdrant URL niet vinden"
        exit 1
    fi

    QDRANT_URL="http://$QDRANT_FQDN"

    log_info "Verwijderen van collections..."

    # Verwijder alle collections
    for collection in "jaapjunior" "wmo" "cs-wmo"; do
        log_info "  Verwijderen $collection..."

        # Try to delete via Azure Container App exec (won't work interactively, but showing the approach)
        log_warning "  Handmatige stap nodig: Verwijder collection '$collection' via Qdrant dashboard of API"
        echo "    URL: $QDRANT_URL/dashboard"
        echo "    Of via API: curl -X DELETE $QDRANT_URL/collections/$collection"
    done

    echo ""
    log_info "Nadat je de collections hebt verwijderd, druk op Enter om de API te herstarten..."
    read

    # Herstart API
    restart_api
}

# Verwijder specifieke agent collection
delete_agent_collection() {
    local agent=$1

    # Valideer agent naam
    if [[ ! "$agent" =~ ^(jw|wmo|cs-wmo)$ ]]; then
        log_error "Ongeldige agent naam: $agent"
        log_info "Geldige agents: jw, wmo, cs-wmo"
        exit 1
    fi

    # Map agent naar collection naam
    local collection=""
    case $agent in
        "jw")
            collection="jaapjunior"
            ;;
        "wmo")
            collection="wmo"
            ;;
        "cs-wmo")
            collection="cs-wmo"
            ;;
    esac

    log_warning "=== HERINDEXEER AGENT: $agent ==="
    log_warning "Dit wist de '$collection' collection in Qdrant"
    echo ""

    # Vraag bevestiging
    read -p "Weet je zeker dat je '$agent' wilt herindexeren? (ja/nee): " confirm
    if [ "$confirm" != "ja" ]; then
        log_info "Geannuleerd"
        exit 0
    fi

    # Get Qdrant FQDN
    QDRANT_FQDN=$(az containerapp show \
        --name "$QDRANT_APP" \
        --resource-group "$RG" \
        --query 'properties.configuration.ingress.fqdn' \
        -o tsv 2>/dev/null)

    if [ -z "$QDRANT_FQDN" ]; then
        log_error "Kan Qdrant URL niet vinden"
        exit 1
    fi

    QDRANT_URL="http://$QDRANT_FQDN"

    log_info "Verwijderen van collection '$collection'..."
    log_warning "Handmatige stap: Verwijder de collection via Qdrant dashboard:"
    echo "  1. Open: $QDRANT_URL/dashboard"
    echo "  2. Selecteer collection: $collection"
    echo "  3. Klik op 'Delete Collection'"
    echo ""
    echo "Of via API:"
    echo "  curl -X DELETE $QDRANT_URL/collections/$collection"
    echo ""

    log_info "Nadat je de collection hebt verwijderd, druk op Enter om de API te herstarten..."
    read

    # Herstart API
    restart_api
}

# Check prerequisites
log_info "Verificatie van prerequisites..."

if ! command -v az &> /dev/null; then
    log_error "Azure CLI is niet geïnstalleerd"
    exit 1
fi

if ! az account show &> /dev/null; then
    log_error "Niet ingelogd in Azure. Run: az login"
    exit 1
fi

log_success "Prerequisites OK"
echo ""

# Parse argumenten
case "${1:-}" in
    -h|--help)
        show_help
        ;;
    -s|--status)
        show_status
        ;;
    -r|--restart)
        restart_api
        ;;
    -f|--full)
        full_reindex
        ;;
    -a|--agent)
        if [ -z "${2:-}" ]; then
            log_error "Agent naam is vereist"
            echo "Gebruik: $0 --agent <jw|wmo|cs-wmo>"
            exit 1
        fi
        delete_agent_collection "$2"
        ;;
    "")
        show_help
        ;;
    *)
        log_error "Onbekende optie: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
