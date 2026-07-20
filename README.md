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
| `hospital-app` | 3006 | Doctor UI — issue prescriptions with ZKP proof generation and manage allergy records (doctors are pre-seeded in the MFSSIA registry) |
| `pharmacy-app` | 3007 | Pharmacist UI — receive and verify prescriptions |
| `ehealth-portal` | 3000 | Real-time system monitor and DKG governance UI (publish/query clinical policies) |

---

## Demo Scenarios

### Test patient

All scenarios use the pre-seeded patient **Emily Carter**:
- Patient ID: `00000000-0000-0000-0000-000000000001`
- Date of birth: 1985-03-15
- Allergies: none initially (add via the Hospital app to demo contraindication)
- Consents: **none initially** — grant them in the Patient Portal (`hospital-1` to prescribe, `pharmacy-1` to dispense). Allow **~30 s** for DKG indexing after each grant, and confirm the **✓ in DKG** badge before using them.

> Doctors are **pre-seeded and already in the MFSSIA physician registry** (✓ MFSSIA in the Hospital app) — there is no "register doctor" step. The contraindication closure and the MFSSIA challenge set are seeded into the DKG on startup. **Clinical policies are DAO-governed** — proposed, voted and published to the DKG entirely in the DAO console (`http://localhost:3010/dao`); a policy cannot be anchored until the DAO approves it (see Scenario 3). The Governance UI (`:3000/governance.html`) is a read-only DKG viewer. The **Age** field is not used by the circuit.

---

### Scenario 1 — Happy path: Metformin prescription (ZKP PASS)

**Goal:** Show the full end-to-end flow with a valid prescription that passes all ZKP checks.

**Step 1 — Grant consent (Patient Portal)**

1. Open `http://localhost:3008` (Patient Portal) → **Emily Carter** → **Consents**
2. Grant `hospital-1` and `pharmacy-1`; wait ~30 s and confirm each shows **✓ in DKG**
3. Copy Emily's patient ID with the 📋 button

**Step 2 — Issue a prescription**

1. Open `http://localhost:3006` (Hospital app) → **New Prescription**
2. Doctor: `James Wilson`; Patient ID: *(paste Emily's UUID)*; Drug: `Metformin`; Dosage: `8`
3. Click **Sign & Generate ZKP Proof**
4. The MFSSIA gate runs first (C-DOC-AUTH + C-DOC-AUTHZ), then the prover runs the Groth16 circuit (credential ∈ registry, no contraindication, dose ≤ max, lab policy, nonce)
5. Result: **✓ PASS — Metformin 8**

**Step 3 — Send to pharmacy, verify and dispense**

1. Click **→ Send to Pharmacy**
2. Open `http://localhost:3007` (Pharmacy app) → find the prescription → **Verify**
   (public inputs are pinned to DKG and the proof is verified **on-chain**; no registry write yet)
3. Click **Dispense** — the pharmacy checks the `pharmacy-1` consent, then records the decision in the **on-chain registry** and marks it Dispensed

**Monitor:** Open `http://localhost:3000` — the timeline shows the ZKP PASS, the MFSSIA access-gate grant, and the **On-Chain Decision Log** entry (ACCEPT) that appears only after dispensing. Click it for details.

---

### Scenario 2 — Allergy block (ZKP FAIL → not issued)

**Goal:** Show that the ZKP circuit rejects a prescription when the patient is allergic to the drug, and that a rejected decision is **never issued and never reaches the pharmacy**.

1. In the Hospital app → **Patient Allergies**, fill **all** fields and click **Add Allergy**:
   - Patient ID: `00000000-0000-0000-0000-000000000001`
   - Substance: `Penicillin`
   - **Code: `372687004`** — required; the greyed `372687004 / PCN-001` is only a placeholder, type the code in
   - Code system: `SNOMED-CT`
   - Source: `hospital-1`
2. **New Prescription**: `James Wilson`, Emily's UUID, Drug `Amoxicillin` (a β-lactam — a Penicillin allergy also contraindicates it, proven against the DKG contraindication closure), Dosage `8`
3. Click **Sign & Generate ZKP Proof**
4. Result: **ZKP ✗ FAIL** — the circuit detected a contraindication (`Penicillin allergy contraindicates Amoxicillin`). The API responds **`422 Unprocessable Entity`** with `outcome: false` and the rejection reasons.
5. The prescription is **not issued**: the hospital keeps a local audit record of the rejected decision (outcome + reasons), but the UI shows it as *rejected* and offers **no "→ Send to Pharmacy" action**. A rejected proof therefore cannot be dispensed — and even if replayed to the pharmacy, its on-chain re-verification fails (defence in depth).

> Only an **accepted** proof returns `201 Created` and becomes a dispensable prescription with a "→ Send to Pharmacy" button.

---

### Scenario 3 — Policy-based dosage block (DAO → ZKP)

**Goal:** A clinical policy goes through **DAO governance** (proposed → voted → published) and then enforces in the ZKP circuit. Every policy is DAO-gated: it cannot be anchored in the DKG until the DAO approves it. **Everything happens in the DAO console** — the Governance UI is just a read-only DKG viewer.

**Step 1 — Propose, vote and publish (DAO console)**

1. Open the DAO console `http://localhost:3010/dao` → **③ Propose policy** → pick **"Metformin — block if adult dose > 2000 mg"** from the preset dropdown → **Propose policy**
2. In **Proposals**, **Vote** to quorum (2 of 3) → status becomes **Approved**
3. Click **Publish → DKG** on the approved proposal — it anchors the policy in the DKG

**Step 2 — Confirm it is live**

Wait **~30 s** (DKG indexing), then check the Governance viewer `http://localhost:3000/governance.html` → **Policies in DKG**, or `curl http://localhost:4000/api/rx-governance/policies`.

**Step 3 — Prescribe over the limit**

1. Hospital app → **New Prescription**: `James Wilson`, Emily's UUID, Drug `Metformin`, Dosage `2500`
2. **Sign & Generate ZKP Proof** → **✗ FAIL**, with the reason shown to the doctor:
   `Dosage 2500 exceeds the maximum 2000 for Metformin`
   (Dosage `8` passes — the limit is 2000.)

> CLI equivalent of Step 1: `POST /api/rx-governance/policies/propose` → `POST http://localhost:3010/governance/vote {id,member}` ×2 → `POST /api/rx-governance/policies`.
Scenario 4 reuses the **Metformin — block if eGFR < 30** preset to show a numeric unit conflict auto-resolved by a DAO bridge.

---

> **Consent enforcement** (patient must grant consent to the requesting org before any
> data access) is demonstrated end-to-end through the UI in the Live table — **D2**
> (authorization gate, `C-DOC-AUTHZ`) and **D8** (consent-first dispensing). The same check
> guards `POST /api/results` (lab-api), `POST /api/prescriptions` (hospital-api) and
> `POST /{id}/dispense` (pharmacy-api).

---

### Scenario 4 — Numerical semantic conflict → DAO auto-resolution (eGFR: CKD-EPI vs Cockcroft-Gault)

**Goal:** This is the paper's running-case numerical conflict. The hospital's Metformin policy
requires **eGFR ≥ 30** computed via **CKD-EPI** in `mL/min/1.73m²`, while an independent
laboratory reports renal function as **creatinine clearance via Cockcroft-Gault** in `mL/min`.
Both describe the same clinical quantity but cannot be compared against the policy threshold
without an alignment axiom. When the hospital assembles the data for a prescription, the mismatch
surfaces as a **numeric semantic conflict**, is **auto-escalated to the DAO**, and is resolved by a
**k-of-n governance vote** that publishes the missing numeric bridge to the DKG — after which the
same prescription proceeds. The conflict is detected **inside the running prescription flow**.

**Why it conflicts (theory T).** A metric is "under numeric governance" once theory T fixes its
governed scale. The DKG holds an eGFR canonical-scale axiom (`mL/min/1.73m²`, CKD-EPI), so a value
already on that scale passes untouched; a Cockcroft-Gault value in `mL/min` has no bridge to it and
cannot be evaluated (open-world: *undefined*, not *false*) → conflict.

**Actors / ports:** DAO console `:3010/dao` · Lab app `:3009` · Hospital app `:3006`.

**Steps (all through the UI):**

1. **Establish the governed scale (once).** In the **DAO console** (`http://localhost:3010/dao`) →
   **② Propose bridge**, pick the **"eGFR — canonical scale (identity ×1)"** preset from the dropdown →
   **Propose bridge**, vote **M0** + **M1** → **Publish → DKG**.
   This fixes CKD-EPI `mL/min/1.73m²` as eGFR's governed scale. *(For a fresh stack this can also
   be pre-seeded via `POST /rx-governance/bridges?direct=true`.)*

2. **Two labs report eGFR on different scales.** In the **Lab app** (`:3009`), enter Emily's UUID and
   add two results using the LOINC dropdown:
   - **`33914-3 · eGFR CKD-EPI`** — value `45`, unit `mL/min/1.73m²` → Save
   - **`2164-2 · eGFR Cockcroft-Gault`** — value `57`, unit `mL/min` → Save

3. **Attempt the prescription.** In the **Hospital app** (`:3006`), issue **Metformin** for Emily.
   The CKD-EPI value reconciles; the **Cockcroft-Gault `mL/min` value has no bridge → HTTP 409**:

   ```json
   {
     "error": "Semantic conflict on 'eGFR': 'mL/min' has no numeric bridge to the governed scale 'mL/min/1.73m²'.",
     "conflict": true,
     "metric": "eGFR",
     "governedUnit": "mL/min/1.73m²",
     "escalatedToDao": true,
     "proposalId": 0,
     "resolution": "Approve the auto-created bridge proposal in the DAO, publish it, then re-issue the prescription."
   }
   ```

   The Hospital app shows **⚠ Semantic conflict** with a link to the DAO console. mfssia has already
   opened the missing bridge as a DAO proposal, with a candidate factor (`0.91`, a representative
   body-surface-area normalisation) from the reference table.

4. **Resolve via the DAO.** In the **DAO console**, the auto-created proposal
   `bridge eGFR mL/min→mL/min/1.73m² ×0.91` is listed. Vote **M0** + **M1** → `✓ approved` →
   **Publish → DKG**. The Cockcroft-Gault→CKD-EPI bridge is now part of theory T.

5. **Re-issue the prescription.** Issue Metformin again. Both eGFR values now normalise onto
   `mL/min/1.73m²`, the conflict is gone, and the reconciled value feeds the `Pol(Metformin, eGFR, ≥, 30)`
   check as the flow proceeds to ZKP proof generation.

**REST equivalent (what the hospital calls internally):**

```bash
# CKD-EPI value — reconciles (200)
curl -s -X POST http://localhost:4000/api/rx-governance/bridges/normalize \
  -H "Content-Type: application/json" \
  -d '{"metric":"eGFR","value":45,"unit":"mL/min/1.73m²"}'
# → {"normalized":45,"governedUnit":"mL/min/1.73m²"}

# Cockcroft-Gault value — conflict, auto-escalated to the DAO (409)
curl -s -X POST http://localhost:4000/api/rx-governance/bridges/normalize \
  -H "Content-Type: application/json" \
  -d '{"metric":"eGFR","value":57,"unit":"mL/min"}'
# → 409 { "escalation": { "escalated": true, "proposalId": 0,
#          "bridge": { "fromUnit":"mL/min","toUnit":"mL/min/1.73m²","factor":0.91 } } }
```

> **Note.** Metric/unit matching is case- and micro-sign-insensitive (`eGFR`≈`egfr`,
> `μmol/L`≈`µmol/L`≈`umol/L`), so values entered from the Lab app dropdowns reconcile against theory T
> without manual normalisation. The candidate factor is only a *suggestion* — the DAO members verify
> and vote; the reference table never decides authoritatively. Concentration bridges
> (e.g. `creatinine μmol/L → mg/dL`) work identically as a generalisation of the same mechanism.

---

### Scenario 5 — Terminological semantic conflict → DAO auto-resolution (SNOMED-CT vs local vocab)

**Goal:** The paper's second data-level conflict. A private laboratory annotates a patient's
allergy under its **local allergen vocabulary**, while the governed knowledge base recognises the
concept via a governance-approved rx concept. Without an **rx:alignsTo** axiom, the system cannot
decide whether the locally-coded allergy denotes the governed concept — so the dependent
contraindication statement is *undefined*. The missing alignment is **auto-escalated to the DAO**,
approved by vote, and published as a **terminology bridge** to the DKG. SNOMED-CT is treated as the
canonical system and passes through unchanged.

**Actors / ports:** DAO console `:3010/dao` · Hospital app `:3006`.

**Steps (all through the UI):**

1. **Record a locally-coded allergy.** In the **Hospital app** (`:3006`) → **Allergies** tab, add for
   Emily: Substance `Penicillin`, Code `PCN-001`, **Code system `AllergyDB-Local`**, Source e.g.
   `Regional Lab`. (A `SNOMED-CT`-coded allergy would be canonical and would *not* conflict.)

2. **Attempt the prescription.** Issue any prescription for Emily. While assembling the allergy
   evidence, the hospital resolves each non-canonical code via mfssia. `AllergyDB-Local:PCN-001` has
   no alignment axiom → **HTTP 409**:

   ```json
   {
     "error": "Terminological conflict on allergy 'Penicillin': code 'AllergyDB-Local:PCN-001' has no alignment to a governed concept.",
     "conflict": true,
     "conflictType": "terminology",
     "codeSystem": "AllergyDB-Local",
     "code": "PCN-001",
     "escalatedToDao": true,
     "proposalId": 1
   }
   ```

   mfssia has opened the missing alignment as a DAO proposal, with a candidate concept
   (`rx:Penicillin`) from the reference table.

3. **Resolve via the DAO.** In the **DAO console**, the proposal `align AllergyDB-Local:PCN-001 → rx:Penicillin`
   is listed (form **④**). Vote **M0** + **M1** → `✓ approved` → **Publish → DKG**. The rx:alignsTo
   axiom is now in theory T.

4. **Re-issue the prescription.** The local code now resolves to `rx:Penicillin`; the conflict is
   gone and the prescription proceeds (and, since Penicillin ⊑ β-lactam, the contraindication check
   then applies to β-lactam drugs as in Scenario 2).

**REST equivalent (what the hospital calls internally):**

```bash
# Local code with no alignment — conflict, auto-escalated to the DAO (409)
curl -s -X POST http://localhost:4000/api/rx-governance/terminology/align \
  -H "Content-Type: application/json" \
  -d '{"system":"AllergyDB-Local","code":"PCN-001","term":"penicillin"}'
# → 409 { "escalation": { "proposalId": 1,
#          "bridge": { "system":"AllergyDB-Local","code":"PCN-001","alignsTo":"rx:Penicillin" } } }

# After DAO approval + publish, the same call resolves (200)
# → {"alignsTo":"https://mfssia.io/ontology/prescription#Penicillin"}
```

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

Open `http://localhost:3000/governance.html` to inspect the DKG knowledge graph:
- **Query Policies** — SPARQL over all anchored `rx:ClinicalPolicy` assets
- **Query Credentials** — all doctor credentials registered on-chain (root_M)
- **Read by UAL** — read any raw Knowledge Asset (policy, credential, numeric/terminology bridge, lab result, allergy)

Open `http://localhost:3010/dao` for the **DAO Governance Console** — propose/vote/publish
numeric bridges, terminology alignments and clinical policies, and watch on-chain
proposal/vote/approval events live.

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
| D10 | Numerical Conflict → DAO | S6 | 1. In the **DAO console** (`:3010/dao`) ensure the eGFR canonical anchor is approved (governed scale = CKD-EPI `mL/min/1.73m²`).<br>2. In the **Lab app** (`:3009`) add Emily's eGFR from **CKD-EPI** (`45 mL/min/1.73m²`) and **Cockcroft-Gault** (`57 mL/min`).<br>3. In the **Hospital portal** attempt a **Metformin** prescription.<br>4. In the **DAO console** vote **M0**+**M1** on the auto-created `eGFR mL/min→mL/min/1.73m² ×0.91` bridge, then **Publish → DKG**.<br>5. Re-issue the prescription. | Step 3 → **409 numeric conflict**, bridge auto-escalated to DAO.<br>After step 4 (k-of-n approval) step 5 → reconciled eGFR feeds `Pol(Metformin,eGFR,≥,30)`, flow proceeds to ZKP |
| D11 | Terminological Conflict → DAO | S6 | 1. In the **Hospital portal** → Allergies, add Emily's `Penicillin` allergy with Code `PCN-001`, **Code system `AllergyDB-Local`**.<br>2. Attempt a prescription for Emily.<br>3. In the **DAO console** vote **M0**+**M1** on the auto-created `align AllergyDB-Local:PCN-001 → rx:Penicillin` proposal (form ④), then **Publish → DKG**.<br>4. Re-issue the prescription. | Step 2 → **409 terminological conflict**, rx:alignsTo auto-escalated to DAO.<br>After step 3 the local code resolves to rx:Penicillin, flow proceeds (and β-lactam contraindication then applies) |
