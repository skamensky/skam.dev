FROM certbot/certbot:v1.21.0

ENV STAGE $STAGE

# for the first time challenge we use a standalone server
EXPOSE 80
COPY init-container.sh .
ENTRYPOINT /bin/sh init-container.sh
