FROM python:3-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        default-mysql-client \
        postgresql-client \
        rclone \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY bin/ /app

RUN pip install --no-cache-dir -r /app/requirements.txt

WORKDIR /app
CMD [ "/app/entrypoint.sh" ]
