FROM alpine:3.20

RUN apk add --no-cache openssl tzdata

WORKDIR /work

COPY entrypoint.sh /usr/local/bin/certgen
RUN chmod +x /usr/local/bin/certgen

ENTRYPOINT ["certgen"]
