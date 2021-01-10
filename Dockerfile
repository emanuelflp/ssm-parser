FROM bash:latest

RUN apk add --no-cache --update jq python py-pip coreutils\
    && rm -rf /var/cache/apk/* \
    && pip install awscli \
    && apk --purge -v del py-pip

ADD entrypoint.sh /entrypoint.sh

RUN ["chmod", "+x", "/entrypoint.sh"]

ENTRYPOINT ["/entrypoint.sh"]