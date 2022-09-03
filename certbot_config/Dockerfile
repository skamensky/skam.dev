FROM certbot/certbot:v1.21.0

ENV STAGE $STAGE

COPY init-container.sh .
ENTRYPOINT /bin/sh init-container.sh
