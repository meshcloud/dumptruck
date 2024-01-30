FROM python:3-slim

RUN useradd dumptruck --uid 2000 --user-group

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        default-mysql-client \
        postgresql-client \
        rclone \
        curl \
    && rm -rf /var/lib/apt/lists/*

COPY bin/ /app
RUN chmod -R 777 /app

RUN pip install --no-cache-dir -r /app/requirements.txt

WORKDIR /app

USER 2000
CMD [ "/app/entrypoint.sh" ]
