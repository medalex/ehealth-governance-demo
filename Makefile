# Local development (builds from source)
up:
	docker compose -f docker-compose.yml -f docker-compose.override.yml up --build

down:
	docker compose down

# Production (pulls images from registry)
up-prod:
	docker compose up -d

pull:
	docker compose pull

logs:
	docker compose logs -f

ps:
	docker compose ps
