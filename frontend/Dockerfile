FROM node:17-alpine3.12

WORKDIR /frontend

ARG STAGE
ENV STAGE $STAGE
ENV PATH /frontend/node_modules/.bin:$PATH


RUN wget https://github.com/sass/dart-sass/releases/download/1.54.8/dart-sass-1.54.8-linux-x64.tar.gz && \
    tar -xvf dart-sass-1.54.8-linux-x64.tar.gz && \
    rm dart-sass-1.54.8-linux-x64.tar.gz && \
    cp dart-sass/sass /usr/local/bin/ && \
    rm -rf dart-sass

# modifications to metadata files should invalidate the install step
COPY package.json package.json
RUN yarn install

# modifications to source files should invalidate the build step
COPY . /frontend/
RUN /bin/sh ./scripts/build.sh "$STAGE"
ENTRYPOINT /bin/sh ./scripts/start_container.sh "$STAGE"