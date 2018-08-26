FROM python:3.6-stretch

RUN apt-get update && apt-get install -y --no-install-recommends mysql-client mongo-tools postgresql-client \
	&& rm -rf /var/lib/apt/lists/*

COPY bin/ /app

RUN cd /app && pip install --no-cache-dir -r requirements.txt

WORKDIR /app
ENTRYPOINT [ "/app/entrypoint.sh" ]