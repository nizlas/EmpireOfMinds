# Empire of Minds — FastAPI authority server (production image)
# Build from repo root: docker build -t empire-server ./server

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

# Canonical map content (committed derived copy synced from repo-root
# content/maps by tools/content/sync_map_content.py) -> /app/content/maps
COPY content/ ./content/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
