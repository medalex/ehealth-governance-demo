# eHealth Governance Demo

Runs all eHealth demo services via Docker Compose.

## Quick start

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Fill in `.env` with real image names.

3. Pull images and start:
   ```bash
   docker compose pull
   docker compose up -d
   ```

## Commands

| Command | Description |
|---|---|
| `docker compose up -d` | Start all services in background |
| `docker compose down` | Stop and remove containers |
| `docker compose pull` | Pull latest images |
| `docker compose logs -f` | Stream logs |
| `docker compose ps` | Show container status |

## Services

| Service | Port | Description |
|---|---|---|
| dkg-node | 8900, 8545 | Blockchain node (OriginTrail DKG) |
| mfssia-ehealth | 4000 | Governance API |
| zkp-prover | 3005 | Zero-Knowledge Proof generator |
| patient | 3001 | Patient service |
| lab | 3002 | Lab service |
| hospital | 3003 | Hospital service |
| pharmacy | 3004 | Pharmacy service |
