# eHealth Governance Demo

A blockchain-based electronic health record demo using OriginTrail DKG v8, Zero-Knowledge Proofs (Groth16), and a self-sovereign identity layer (MFSSIA).

The system is split into two Docker Compose stacks:

- **`docker-compose.yml`** (this repo) — DKG blockchain infrastructure
- **`docker-compose.demo.yml`** — eHealth application services

---

## Architecture

```
Patient Portal  Lab System  Hospital System  Pharmacy System
    :3008           :3009         :3006            :3007
      |               |             |                |
  patient-api     lab-api      hospital-api    pharmacy-api
    :3001           :3002         :3003            :3004
                      |             |                |
                      └─────────────┴────────────────┘
                                    |
                              zkp-prover :3005
                          (Groth16 ZKP circuit)
                                    |
                      ┌─────────────┴────────────────┐
                  mfssia-ehealth :4000           dkg-node
                 (Governance API / DKG client)   :8545 / :8900
                                    |
                              PostgreSQL :5432

                         Monitor + Governance UI
                              ehealth-portal :3000
```

---

## Quick Start

### One command

```bash
docker compose -f docker-compose.demo.yml up -d
```

All images are pulled automatically from `ghcr.io/medalex/*` — no source code needed.

The startup order is managed automatically:
- `postgres` and `dkg-node` start first
- `mfssia-ehealth` waits until DKG node is healthy (~2 min)
- All APIs wait until `mfssia-ehealth` is ready
- Frontend apps start immediately

Check that everything is up:
```bash
docker compose -f docker-compose.demo.yml ps
```

---

## Services

### DKG Infrastructure (`docker-compose.yml`)

| Service | Port | Description |
|---|---|---|
| `dkg-node` | 8545, 8900 | OriginTrail DKG v8 node with 5 local Hardhat blockchain nodes. Anchors all Knowledge Assets on-chain. |
| `postgres` | 5432 | PostgreSQL database for MFSSIA |
| `mfssia-ehealth` | 4000 | Governance API — publishes clinical policies and doctor credentials to DKG, runs SPARQL queries on the knowledge graph |

### eHealth Applications (`docker-compose.demo.yml`)

#### APIs

| Service | Port | Description |
|---|---|---|
| `patient-api` | 3001 | Patient registry — stores patient demographics and medical history |
| `lab-api` | 3002 | Lab service — creates lab results and publishes them as Knowledge Assets to DKG |
| `hospital-api` | 3003 | Hospital service — manages doctors, prescriptions, and allergy records. Calls ZKP prover to validate each prescription |
| `pharmacy-api` | 3004 | Pharmacy service — receives prescriptions from hospital, verifies ZKP proof before dispensing |
| `zkp-prover` | 3005 | Zero-Knowledge Proof engine (Groth16 / Circom). Validates prescriptions against allergy records, drug approval list, and dosage policies without revealing patient data |

#### Frontend Apps

| Service | Port | Description |
|---|---|---|
| `patient-app` | 3008 | Patient portal — view personal medical records and history |
| `lab-app` | 3009 | Lab technician UI — submit lab results for a patient |
| `hospital-app` | 3006 | Doctor UI — issue prescriptions with ZKP proof generation, manage allergy records, register doctor credentials on DKG |
| `pharmacy-app` | 3007 | Pharmacist UI — receive and verify prescriptions |
| `ehealth-portal` | 3000 | Real-time system monitor and DKG governance UI (publish/query clinical policies) |

---

## Demo Flow

1. **Lab** (`localhost:3009`) — submit a lab result (e.g. eGFR) for a patient. It gets anchored to DKG.
2. **Hospital** (`localhost:3006`) — doctor issues a prescription. The ZKP prover:
   - Checks drug is on the approved list
   - Checks patient has no allergy to the drug
   - Checks dosage is within policy limits
   - Returns `outcome: true/false` + a zero-knowledge proof
3. **Hospital → Pharmacy** — if ZKP passes, click "Send to Pharmacy"
4. **Pharmacy** (`localhost:3007`) — pharmacist sees the prescription and verifies the proof before dispensing

**To trigger a ZKP FAIL** — prescribe Penicillin (drug 103) to patient `00000000-0000-0000-0000-000000000001` (Emily Carter). She has a Penicillin allergy seeded in the hospital database.

---

## Monitoring

Open `http://localhost:3000` to see:
- Live service health status
- Real-time event timeline (new prescriptions, lab results, DKG publications)
- Latest ZKP proof details (statement hash, public signals)
- DKG doctor credentials

Open `http://localhost:3000/governance.html` to:
- Publish clinical policies to DKG (drug dosage limits, clinical conditions)
- Query all Knowledge Assets via SPARQL
- Read individual assets by UAL

---

## Useful Commands

```bash
# Check all demo services
docker compose -f docker-compose.demo.yml ps

# Stream logs from hospital API
docker compose -f docker-compose.demo.yml logs -f hospital-api

# Pull latest images and restart
docker compose -f docker-compose.demo.yml pull
docker compose -f docker-compose.demo.yml up -d

# Stop everything
docker compose -f docker-compose.demo.yml down
docker compose down
```
