FROM bash:latest

RUN apk update \
    && apk add --no-cache --update python3\
    && apk add --no-cache --update jq py-pip coreutils\
    && rm -rf /var/cache/apk/* \
    && pip install awscli

ADD entrypoint.sh /entrypoint.sh

RUN ["chmod", "+x", "/entrypoint.sh"]

ENTRYPOINT ["/entrypoint.sh"]