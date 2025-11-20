# Herindexering Handleiding voor Beheerders

Deze handleiding legt uit hoe een beheerder agents kan herindexeren zonder ontwikkelaarkennis.

## Wat is herindexering?

Herindexering betekent dat de documenten opnieuw worden verwerkt en in de vector database (Qdrant) worden opgeslagen. Dit is nodig wanneer:

- Brondocumenten zijn aangepast
- Er problemen zijn met zoekresultaten
- Na een grote update van het systeem

## Wanneer vindt indexering plaats?

**Belangrijk**: Documenten worden NIET automatisch bij elke herstart geïndexeerd!

- **Bij startup**: Niets gebeurt, API start snel op
- **Bij eerste gebruik**: Wanneer een gebruiker voor het eerst een vraag stelt aan een agent, wordt die agent geïndexeerd
- **Daarna**: De agent blijft in het geheugen en gebruikt de geïndexeerde data

## Herindexering Opties

### Optie 1: Simpele Herstart (AANBEVOLEN)

Dit is de **simpelste en veiligste** methode voor beheerders.

#### Via Azure Portal:

1. Open https://portal.azure.com
2. Navigeer naar "Container Apps"
3. Zoek "jaapjunior-api"
4. Klik op "Restart" bovenaan
5. Wacht 30 seconden
6. Agents worden automatisch opnieuw geïndexeerd bij eerste gebruik

#### Via Azure CLI:

```bash
# Download het script
cd ~/jaapjunior/scripts

# Toon status
./azure-reindex.sh --status

# Herstart API (simpelste optie)
./azure-reindex.sh --restart
```

**Voordelen:**
- ✅ Simpel en snel
- ✅ Geen data verloren
- ✅ Veilig voor productie
- ✅ Minimale downtime (30 seconden)

**Nadelen:**
- ⚠️ Herindexering gebeurt pas bij eerste gebruik van elke agent
- ⚠️ Eerste query per agent kan traag zijn

---

### Optie 2: Volledige Herindexering (GEAVANCEERD)

Dit wist alle Qdrant collections en forceert complete herindexering.

⚠️ **WAARSCHUWING**: Gebruik dit alleen als er echt problemen zijn!

```bash
./azure-reindex.sh --full
```

**Wanneer gebruiken:**
- Na grote updates van brondocumenten
- Als zoekresultaten incorrect zijn
- Na Qdrant problemen

**Proces:**
1. Script vraagt bevestiging (typ 'WISSEN')
2. Je krijgt instructies om Qdrant collections te verwijderen via dashboard
3. API wordt herstart
4. Agents worden opnieuw geïndexeerd bij eerste gebruik

---

### Optie 3: Specifieke Agent Herindexeren

Herindexeer alleen één specifieke agent:

```bash
# Herindexeer alleen cs-wmo agent
./azure-reindex.sh --agent cs-wmo

# Of andere agents
./azure-reindex.sh --agent jw
./azure-reindex.sh --agent wmo
```

---

## Via Azure Portal (Zonder Script)

### Stap 1: Login in Azure Portal
1. Open https://portal.azure.com
2. Login met je Azure account

### Stap 2: Zoek Container App
1. Zoek bovenaan naar "Container Apps"
2. Klik op "jaapjunior-api"

### Stap 3: Herstart de Container
**Via Revisions (Enige correcte methode):**
1. Klik op "Revisions and replicas" in het linkermenu
2. Selecteer de actieve revision (meestal de bovenste met een groen vinkje)
3. Klik op "Restart" bovenaan
4. Bevestig de herstart
5. Wacht 30-60 seconden

**⚠️ BELANGRIJK**: Gebruik NIET de "Stop" knop in Overview - de container start mogelijk niet automatisch opnieuw op!

### Stap 4: Verifieer (Optioneel)
1. Klik op "Log stream" in het menu
2. Wacht tot je ziet: `Started server: http://localhost:3000`
3. Test de applicatie

---

## Veelgestelde Vragen

### Q: Hoe weet ik of herindexering nodig is?
**A**: Herindexering is nodig als:
- Brondocumenten zijn aangepast
- Zoekresultaten zijn incorrect of verouderd
- Na een grote systeem update
- Als agents niet correct reageren

### Q: Hoe lang duurt herindexering?
**A**:
- **API restart**: 30 seconden
- **Eerste query na restart**: 30-120 seconden per agent (afhankelijk van aantal documenten)
- **Volgende queries**: Snel (< 5 seconden)

### Q: Verliezen we data bij herindexering?
**A**:
- Bij **simpele herstart**: Nee, Qdrant behoudt alle data
- Bij **volledige herindexering**: Ja, maar data wordt automatisch opnieuw opgebouwd bij eerste gebruik

### Q: Kunnen gebruikers nog steeds de app gebruiken tijdens herindexering?
**A**:
- Tijdens **API restart**: Nee, 30 seconden downtime
- Tijdens **eerste indexering**: Ja, maar eerste query is traag

### Q: Wat als herindexering faalt?
**A**:
1. Check de logs in Azure Portal (Log stream)
2. Zorg dat Qdrant container actief is
3. Herstart opnieuw indien nodig
4. Contact ontwikkelaar als probleem blijft

### Q: Moet ik alle agents herindexeren?
**A**: Nee! Bij een simpele herstart worden agents alleen opnieuw geïndexeerd wanneer ze daadwerkelijk worden gebruikt.

---

## Troubleshooting

### Probleem: API start niet op na herstart
**Oplossing:**
1. Check Qdrant status in Azure Portal
2. Verifieer dat Qdrant ingress enabled is
3. Check API logs voor errors
4. Contact ontwikkelaar

### Probleem: Agent blijft hangen bij eerste query
**Oplossing:**
1. Wacht 2 minuten (indexering kan lang duren)
2. Als timeout: check API logs
3. Verifieer Qdrant connectie
4. Overweeg volledige herindexering

### Probleem: "ConnectionRefused" error in logs
**Oplossing:**
1. Check of Qdrant container actief is
2. Verifieer Qdrant ingress: `./azure-reindex.sh --status`
3. Contact ontwikkelaar om ingress te fixen

---

## Script Overzicht

Het `azure-reindex.sh` script biedt verschillende opties:

```bash
# Toon help
./azure-reindex.sh --help

# Toon status van API en Qdrant
./azure-reindex.sh --status

# Simpele herstart (AANBEVOLEN)
./azure-reindex.sh --restart

# Volledige herindexering (GEAVANCEERD)
./azure-reindex.sh --full

# Herindexeer specifieke agent
./azure-reindex.sh --agent cs-wmo
```

---

## Contact

Bij problemen of vragen:
1. Check eerst de logs in Azure Portal
2. Probeer simpele herstart
3. Contact de ontwikkelaar met:
   - Beschrijving van het probleem
   - Screenshots van errors
   - Timestamp van wanneer het probleem optrad
