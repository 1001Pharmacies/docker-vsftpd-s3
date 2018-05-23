FROM alpine:latest
LABEL maintainer "yann.autissier@1001pharmacies.com"

# s3fs tag to checkout
ARG S3FS_VERSION=v1.82

# Install s3fs binary
RUN apk add --no-cache --virtual .fuse-builddeps \
        alpine-sdk \
        automake \
        autoconf \
        curl-dev \
        fuse-dev \
        libxml2-dev \
 && git clone https://github.com/s3fs-fuse/s3fs-fuse.git \
 && cd s3fs-fuse \
 && git checkout tags/${S3FS_VERSION} -b ${S3FS_VERSION} \
 && ./autogen.sh \
 && ./configure --prefix=/usr \
 && make \
 && make install \
 && cd .. \
 && rm -rf s3fs-fuse \
 && apk del .fuse-builddeps

# Install vsftpd and s3fs libraries
RUN apk add --no-cache \
        fuse \
        lftp \
        libcurl \
        libstdc++ \
        libxml2 \
        logrotate \
        openssl \
        vsftpd

RUN sed -i 's|/var/log/messages|/var/log/*.log|' /etc/logrotate.conf

COPY lftp-sync.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/lftp-sync.sh

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
VOLUME ["/var/log"]
