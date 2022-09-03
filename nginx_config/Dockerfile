FROM nginx:1.21.1

ENV STAGE $STAGE

COPY nginx.conf /etc/nginx/
COPY nginx-dev.conf /etc/nginx/
COPY init-container.sh .
COPY custom_error_pages /usr/share/nginx/html
CMD /bin/bash init-container.sh
