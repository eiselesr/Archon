# Ollama Docker Setup

Run LLM models locally with Ollama in a Docker container.

## Quick Start

```bash
# Start Ollama
docker compose up -d

# Pull a model (examples)
docker compose exec ollama ollama pull llama3.2
docker compose exec ollama ollama pull mistral
docker compose exec ollama ollama pull codellama

# List installed models
docker compose exec ollama ollama list

# Test the API
curl http://localhost:11434/api/tags

# View logs
docker compose logs -f

# Stop service
docker compose down
```

## Configuration

Copy `.env.example` to `.env` to customize:

```bash
cp .env.example .env
```

### GPU Support (NVIDIA)

Uncomment the `deploy` section in `docker-compose.yml` to enable GPU acceleration:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
```

Requirements:
- NVIDIA GPU
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed

## Connecting Archon to Ollama

In Archon's settings, configure:

- **Ollama Base URL**: `http://localhost:11434` (host) or `http://host.docker.internal:11434` (from Docker)
- **Provider**: Select "Ollama"
- **Model**: Choose from your pulled models

## Model Management

### Pull Popular Models

```bash
# Chat models
docker compose exec ollama ollama pull llama3.2      # 2B/3B - Fast, efficient
docker compose exec ollama ollama pull mistral       # 7B - Balanced
docker compose exec ollama ollama pull mixtral       # 8x7B - High quality

# Code models
docker compose exec ollama ollama pull codellama     # 7B/13B/34B - Code generation
docker compose exec ollama ollama pull deepseek-coder # 1.3B/6.7B - Efficient coding

# Embedding models (for RAG)
docker compose exec ollama ollama pull nomic-embed-text
docker compose exec ollama ollama pull mxbai-embed-large
```

### Remove Models

```bash
docker compose exec ollama ollama rm model-name
```

## Networking

### Standalone (Default)
Ollama runs on its own `ollama-network` bridge network.

### Connect to Archon Network
To allow Archon containers to communicate directly with Ollama:

```yaml
networks:
  ollama-network:
    external: true
    name: archon_app-network
```

Then Archon can use `http://ollama:11434` as the base URL.

## Troubleshooting

### Check if Ollama is running
```bash
curl http://localhost:11434/api/version
```

### View available models
```bash
curl http://localhost:11434/api/tags
```

### Performance Issues
- Enable GPU support if you have an NVIDIA GPU
- Use smaller models for faster inference (llama3.2:1b, llama3.2:3b)
- Increase Docker resource limits (CPU/Memory)

## Resources

- [Ollama Documentation](https://github.com/ollama/ollama)
- [Model Library](https://ollama.com/library)
- [Docker Hub](https://hub.docker.com/r/ollama/ollama)
