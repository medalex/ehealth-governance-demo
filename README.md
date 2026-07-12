# eHealth Governance Demo

A blockchain-based electronic health record demo using OriginTrail DKG v8, Zero-Knowledge Proofs (Groth16), a self-sovereign identity layer (MFSSIA), and a k-of-n DAO that resolves semantic conflicts by governance vote.

---

## Architecture

```
 Patient Portal   Lab System   Hospital System   Pharmacy System
     :3008           :3009          :3006             :3007
       |               |              |                 |
   patient-api      lab-api      hospital-api      pharmacy-api
     :3001           :3002          :3003             :3004
                       |              |                 |  verify + record
                       └──────────────┤                 ▼
                                      |            evm  :3010 / :8546
                                zkp-prover :3005  ┌───────────────────────────┐
                              (Groth16 proof) ───▶│ Groth16 on-chain verifier  │
                                      |           │ Decision Registry (audit)  │
                                      |           │ MinimalGovernance DAO → /dao│
                                      |           └─────────────▲─────────────┘
                        ┌─────────────┴───────────┐            │ propose / vote
                  mfssia-ehealth :4000         dkg-node        │ (semantic conflicts:
                 (Governance API, theory T,   :8545 / :8900    │  numeric bridges)
                  bridges, SPARQL, DAO gate) ─────────────────┘
                                    |         (OriginTrail DKG — anchors
                              PostgreSQL :5432  policies, credentials, bridges)

                         Monitor + Governance UI
                              ehealth-portal :3000     DAO monitor: :3010/dao
```

**Three governance layers:**
- **ZKP (privacy)** — `zkp-prover` proves a prescription is valid without revealing patient data.
- **DKG (theory T)** — `mfssia-ehealth` anchors governance-approved policies, doctor credentials, and numeric alignment bridges in the OriginTrail knowledge graph.
- **DAO (conflict resolution)** — `evm` runs a k-of-n `MinimalGovernance` contract. Semantic conflicts (e.g. a lab metric arriving in an unmapped unit) are auto-escalated: members vote on the missing bridge, and only DAO-approved bridges are published to the DKG. Live at `:3010/dao`.

---

## Quick Start

### One command

```bash
docker compose up -d
```

All images are pulled automatically from `ghcr.io/medalex/*` — no source code needed.

The startup order is managed automatically:
- `postgres` and `dkg-node` start first
- `mfssia-ehealth` waits until DKG node is healthy (~2 min)
- All APIs wait until `mfssia-ehealth` is ready
- Frontend apps start immediately

Check that everything is up:
```bash
docker compose ps
```

---

## Services

### Infrastructure

| Service | Port | Description |
|---|---|---|
| `dkg-node` | 8545, 8900 | OriginTrail DKG v8 node with 5 local Hardhat blockchain nodes. Anchors all Knowledge Assets on-chain. |
| `postgres` | 5432 | PostgreSQL database for MFSSIA |
| `mfssia-ehealth` | 4000 | Governance API — publishes clinical policies, doctor credentials and numeric bridges to DKG, runs SPARQL queries, and escalates semantic conflicts to the DAO |
| `evm` | 3010, 8546 | Dedicated EVM (Ganache) hosting the Groth16 on-chain verifier, an append-only Decision Registry, and the `MinimalGovernance` DAO. Serves the DAO monitor at `/dao` (propose / vote / approve numeric bridges) |

### APIs

| Service | Port | Description |
|---|---|---|
| `patient-api` | 3001 | Patient registry — stores patient demographics and medical history |
| `lab-api` | 3002 | Lab service — creates lab results and publishes them as Knowledge Assets to DKG |
| `hospital-api` | 3003 | Hospital service — manages doctors, prescriptions, and allergy records. Calls ZKP prover to validate each prescription |
| `pharmacy-api` | 3004 | Pharmacy service — receives prescriptions from hospital, verifies ZKP proof before dispensing |
| `zkp-prover` | 3005 | Zero-Knowledge Proof engine (Groth16 / Circom). Validates prescriptions against allergy records, drug approval list, and dosage policies without revealing patient data |

### Frontend Apps

| Service | Port | Description |
|---|---|---|
| `patient-app` | 3008 | Patient portal — view personal medical records and history |
| `lab-app` | 3009 | Lab technician UI — submit lab results for a patient |
| `hospital-app` | 3006 | Doctor UI — issue prescriptions with ZKP proof generation, manage allergy records, register doctor credentials on DKG |
| `pharmacy-app` | 3007 | Pharmacist UI — receive and verify prescriptions |
| `ehealth-portal` | 3000 | Real-time system monitor and DKG governance UI (publish/query clinical policies) |

---

## Demo Scenarios

### Test patient

All scenarios use the pre-seeded patient **Emily Carter**:
- Patient ID: `00000000-0000-0000-0000-000000000001`
- Date of birth: 1985-03-15 (age 41)
- Allergies: **Penicillin** (seeded in hospital DB)
- Active consents: `hospital-1`, `lab-1`, `pharmacy-1`

---

### Scenario 1 — Happy path: Metformin prescription (ZKP PASS)

**Goal:** Show the full end-to-end flow with a valid prescription that passes all ZKP checks.

**Step 1 — Register a doctor credential on DKG**

1. Open `http://localhost:3006` (Hospital app)
2. Go to **Doctors** tab → select a doctor → click **Register on DKG**
3. Wait for the UAL to appear — this anchors the doctor's credential to the blockchain

**Step 2 — Submit a lab result**

1. Open `http://localhost:3009` (Lab app)
2. Fill in:
   - Patient ID: `00000000-0000-0000-0000-000000000001`
   - LOINC code: `62238-1` (eGFR)
   - Metric: `eGFR`
   - Formula: `CKD-EPI` (enum value `0`)
   - Value: `85`
   - Unit: `mL/min/1.73m²`
3. Submit — the result is saved and published as a Knowledge Asset to DKG

**Step 3 — Issue a prescription**

1. Open `http://localhost:3006` (Hospital app) → **Prescriptions** tab
2. Fill in:
   - Patient ID: `00000000-0000-0000-0000-000000000001`
   - Drug ID: `105` (Metformin)
   - Dosage: `500mg`
   - Patient age: `41`
3. Submit
4. The ZKP prover runs the Groth16 circuit — checks drug approval, no Penicillin allergy on Metformin, dosage within default limit (65535 mg)
5. Result: `outcome: true` — prescription created with a valid ZKP proof

**Step 4 — Send to pharmacy and dispense**

1. In Hospital app — click **Send to Pharmacy** on the prescription
2. Open `http://localhost:3007` (Pharmacy app)
3. Find the prescription → click **Verify** (re-verifies ZKP proof locally)
4. Click **Dispense** — prescription is marked as dispensed

**Monitor:** Open `http://localhost:3000` — the Event Timeline should show the ZKP PASS event with statement hash.

---

### Scenario 2 — Allergy block (ZKP FAIL)

**Goal:** Show that the ZKP circuit rejects a prescription when the patient is allergic to the drug.

1. Open `http://localhost:3006` (Hospital app) → **Prescriptions** tab
2. Fill in:
   - Patient ID: `00000000-0000-0000-0000-000000000001`
   - Drug ID: `103` (Penicillin)
   - Dosage: `500mg`
   - Patient age: `41`
3. Submit
4. Result: `outcome: false` — the ZKP circuit detected a contraindication (Emily has a Penicillin allergy in the hospital DB)
5. The prescription is saved with `outcome: false`; the Pharmacy UI will reject dispensing it

---

### Scenario 3 — Policy-based dosage block (ZKP FAIL via DKG governance)

**Goal:** Show how a clinical policy published to DKG flows into the ZKP prover and blocks an over-limit prescription.

**Step 1 — Publish a dosage restriction policy**

1. Open `http://localhost:3000/governance.html` (Governance UI)
2. Go to **Publish Policy** tab
3. Fill in:
   - Policy ID: `pol:metformin-egfr`
   - Medication: `metformin`
   - Clinical condition: `eGFR`
   - Operator: `>=`
   - Threshold: `30`
   - Max dosage: `200` (mg — lower than the default 65535)
4. Click **Publish to DKG** — the policy is anchored as a Knowledge Asset on the blockchain

**Step 2 — Issue a high-dosage Metformin prescription**

1. Open `http://localhost:3006` (Hospital app) → **Prescriptions** tab
2. Fill in:
   - Patient ID: `00000000-0000-0000-0000-000000000001`
   - Drug ID: `105` (Metformin)
   - Dosage: `500mg`
   - Patient age: `41`
3. Submit
4. The hospital-api fetches the active policy from DKG (threshold: 200 mg), passes it to the ZKP prover
5. Result: `outcome: false` — the Groth16 circuit rejects `500mg > 200mg` policy limit

**To restore normal behavior** — publish a new policy with max dosage `65535` (or `0` = no limit), or restart `hospital-api` to clear cached policies.

---

### Scenario 4 — Consent enforcement

**Goal:** Show that APIs block access if the patient has not granted consent to the requesting organisation.

The consent check is enforced at the API level by querying `patient-api` before saving any data.

**Test via REST (no UI needed):**

```bash
# This should return 403 — unknown patient has no consent for lab-1
curl -s -X POST http://localhost:3002/api/results \
  -H "Content-Type: application/json" \
  -d '{
    "patientId": "00000000-0000-0000-0000-000000000099",
    "loincCode": "62238-1",
    "metric": "eGFR",
    "formula": 0,
    "value": 85,
    "unit": "mL/min/1.73m²",
    "measuredBy": "Lab Tech"
  }'
# → {"error":"Patient ... has not granted consent to lab-1"}

# This should return 201 — Emily Carter has consent for lab-1
curl -s -X POST http://localhost:3002/api/results \
  -H "Content-Type: application/json" \
  -d '{
    "patientId": "00000000-0000-0000-0000-000000000001",
    "loincCode": "62238-1",
    "metric": "eGFR",
    "formula": 0,
    "value": 85,
    "unit": "mL/min/1.73m²",
    "measuredBy": "Lab Tech"
  }'
# → 201 Created
```

Same enforcement applies on `POST /api/prescriptions` (hospital-api, org `hospital-1`) and `POST /{id}/dispense` (pharmacy-api, org `pharmacy-1`).

---

### Scenario 5 — DKG governance: query and inspect Knowledge Assets

**Goal:** Show the DKG knowledge graph with published policies and credentials.

1. Open `http://localhost:3000/governance.html` (Governance UI)
2. **Query Policies** tab — runs a SPARQL query against the DKG and lists all anchored clinical policies
3. **Query Credentials** tab — lists all doctor credentials registered on-chain
4. **Read by UAL** — paste any UAL from the monitor or a previous publish and read the raw Knowledge Asset

---

### Recovering from a dkg-node crash

`hardhat1` (port 8545, staked) can crash and stop accepting transactions. When this happens:
- The monitor dot for **DKG / blockchain** turns **red**
- The Governance UI shows a pre-check error before any publish attempt

**Recovery:**

```bash
docker compose restart dkg-node
# Wait ~2 min for the node to become healthy, then:
docker compose restart mfssia-ehealth
```

The second restart clears the cached nonce in `mfssia-ehealth` so it re-syncs with the new chain state.

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
# Check all services
docker compose ps

# Stream logs from a service
docker compose logs -f hospital-api

# Pull latest images and restart
docker compose pull
docker compose up -d

# Stop everything
docker compose down
```

## Demo Scenarios (Live)

| # | Scenario | Article | Steps | Expected Result |
|---|---|---|---|---|
| D1 | Valid Prescription | S1 | 1. Open the Hospital portal.<br>2. Select patient **Emily Wilson**.<br>3. Choose medication **Metformin**.<br>4. Set dosage to **8**.<br>5. Click **Generate Prescription**.<br>6. Open the Pharmacy portal.<br>7. Verify the prescription.<br>8. Dispense the medication. | ✓ PASS → Status changes to **Verified** and then **Dispensed**; blockchain monitor shows **ACCEPT** |
| D2 | Authorization Gate | C-DOC-AUTHZ | 1. Open the Patient Portal.<br>2. Revoke consent for **hospital-1** from Emily’s permissions.<br>3. Return to the Hospital portal.<br>4. Attempt to generate a new prescription.<br>5. Restore consent after the demo. | 🔒 Access denied (**C-DOC-AUTHZ**) |
| D3 | Contraindication (β-lactam) | S5a / P2 | 1. Open the Hospital portal.<br>2. Select **Emily Wilson**.<br>3. Add **Penicillin allergy** to the patient profile.<br>4. Select medication **Amoxicillin**.<br>5. Attempt to generate the prescription. | ✗ FAIL → “Penicillin allergy contraindicates Amoxicillin” |
| D4 | Lab Policy (eGFR) | S10 / P6 | 1. Open the Lab service on port **3009**.<br>2. Update Emily’s eGFR value to **5**.<br>3. Wait ~30 seconds for synchronization.<br>4. Return to the Hospital portal.<br>5. Attempt to prescribe **Metformin**. | ✗ FAIL → “eGFR 5 < 30” |
| D5 | Dosage Limit Exceeded | P3 | 1. Open the Hospital portal.<br>2. Select **Emily Wilson**.<br>3. Choose **Metformin**.<br>4. Set dosage to **50**.<br>5. Generate the prescription. | ✗ FAIL → “Dosage 50 exceeds maximum 20” |
| D6 | Doctor Not Registered | S2 / C-DOC-AUTH | 1. Open the Hospital portal.<br>2. Select doctor **Alex Turner** (Intern, not registered in MFSSIA).<br>3. Select patient and medication.<br>4. Attempt to generate the prescription. | 🔒 Access denied (doctor not registered) |
| D7 | Replay Attack | S6 / R8 | 1. Complete a valid prescription issuance and dispensing flow.<br>2. Copy the generated proof or prescription ID.<br>3. Attempt to dispense the same prescription again. | ❌ On-chain **409 Conflict** (Replay detected) |
| D8 | Consent-First / On-Chain Enforcement | New | 1. Open the Patient Portal.<br>2. Remove consent for **pharmacy-1**.<br>3. Generate a valid prescription in the Hospital portal.<br>4. Verify it in the Pharmacy portal.<br>5. Attempt to dispense without consent.<br>6. Grant consent back.<br>7. Retry dispensing. | First attempt → **403 Forbidden**, no blockchain record.<br>Second attempt → successful dispense with blockchain entry created |
| D9 | Immutable Audit | R9 | 1. Open the Blockchain Monitor.<br>2. Locate a previously issued or dispensed prescription.<br>3. Click the corresponding on-chain log entry.<br>4. Inspect the audit metadata. | Shows `stmtHash`, outcome, transaction hash, medication; confirms **no patient data stored on-chain** |
