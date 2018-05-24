FROM alpine:latest
LABEL maintainer "yann.autissier@gmail.com"
ARG VERSION_S3FS=v1.83

# Install s3fs-fuse and sftpserver
RUN apk upgrade --no-cache \
 && apk add --no-cache --virtual build-deps \
        alpine-sdk \
        automake \
        autoconf \
        curl-dev \
        fuse-dev \
        gnutls-dev \
        libxml2-dev \
        libgcrypt-dev \
 && git clone https://github.com/s3fs-fuse/s3fs-fuse \
 && cd s3fs-fuse \
 && git checkout tags/${VERSION_S3FS} -b ${VERSION_S3FS} \
 && ./autogen.sh \
 && ./configure --prefix=/usr --with-gnutls \
 && make install \
 && cd .. \
 && rm -rf s3fs-fuse \
 && apk del build-deps

# Install vsftpd and s3fs libraries
RUN apk add --no-cache \
        fuse \
        gnutls \
        lftp \
        libcurl \
        libgcrypt \
        libstdc++ \
        libxml2 \
        logrotate \
        openssh \
        openssl \
        vsftpd

RUN sed -i 's|/var/log/messages|/var/log/*.log|' /etc/logrotate.conf

RUN ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' \
 && ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N ''

COPY lftp-sync.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/lftp-sync.sh

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 21/tcp
EXPOSE 22/tcp
EXPOSE 65000/tcp
VOLUME ["/var/log"]
