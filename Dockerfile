FROM python:3.6-stretch

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        mysql-client \
        mongo-tools \
        postgresql-client \
	&& rm -rf /var/lib/apt/lists/*

RUN wget "https://downloads.rclone.org/rclone-current-linux-amd64.deb" \
    && dpkg -i ./rclone-current-linux-amd64.deb \
    && rm ./rclone-current-linux-amd64.deb

COPY bin/ /app

RUN pip install --no-cache-dir -r /app/requirements.txt

WORKDIR /app
CMD [ "/app/entrypoint.sh" ]
