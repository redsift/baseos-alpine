FROM alpine:3.8 as rocksdb

RUN echo "@testing http://nl.alpinelinux.org/alpine/edge/testing" >>/etc/apk/repositories
RUN apk add --update --no-cache curl build-base linux-headers git perl bash gflags-dev@testing snappy-dev zlib-dev bzip2-dev lz4-dev zstd-dev

ARG ROCKSDB_DIST_VERSION="5.17.2"
ARG ROCKSDB_DIST_SHA256="101f05858650a810c90e4872338222a1a3bf3b24de7b7d74466814e6a95c2d28"

RUN echo "${ROCKSDB_DIST_SHA256}  rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz" > rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz.sha256
RUN curl -L -o rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz -s https://github.com/facebook/rocksdb/archive/v${ROCKSDB_DIST_VERSION}.tar.gz
RUN sha256sum -csw rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz.sha256
RUN tar -zxf rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz -C /usr/local/share
RUN rm rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz rocksdb-${ROCKSDB_DIST_VERSION}.tar.gz.sha256

WORKDIR /usr/local/share/rocksdb-${ROCKSDB_DIST_VERSION}

RUN make static_lib && strip --strip-debug librocksdb.a 

RUN mkdir -p /usr/lib && cp -dp librocksdb.* /usr/lib/
RUN mkdir -p /usr/include/rocksdb && cp -a include/* /usr/include/rocksdb/

FROM alpine:3.8

LABEL maintainer="Deepak Prabhakara <deepak@redsift.io>"

# Install rocksdb library
COPY --from=rocksdb /usr/lib/librocksdb.a /usr/lib/

# Set home
ENV HOME /root

# s6 overlay
ENV S6_VERSION=v1.18.1.5

RUN apk --update upgrade \
    && apk add --no-cache bash openssl inotify-tools iproute2 ca-certificates curl ncurses snappy-dev zlib-dev bzip2-dev lz4-dev zstd-dev \
    && curl -sL https://github.com/just-containers/s6-overlay/releases/download/${S6_VERSION}/s6-overlay-amd64.tar.gz -o /tmp/s6-overlay.tar.gz \
    && tar xvfz /tmp/s6-overlay.tar.gz -C / \
    && rm -f /tmp/s6-overlay.tar.gz \
    && mkdir -p /etc/cont-finish.d \
    && mkdir -p /etc/cont-init.d \
    && mkdir -p /etc/fix-attrs.d \
    && mkdir -p /etc/services.d

# Copy static config across
COPY root /

# pkg-config is needed for nanomsg
ENV PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

# Install nanomsg
ENV NANO_MSG=1.1.2

RUN apk add --no-cache build-base cmake \
    && cd /tmp \
    && curl -sL https://github.com/nanomsg/nanomsg/archive/$NANO_MSG.tar.gz | tar xz \
    && cd /tmp/nanomsg-$NANO_MSG && mkdir build && cd build && cmake .. && cmake --build . && cmake --build . --target install \
    && rm -rf /tmp/nanomsg-$NANO_MSG \
    && apk del build-base cmake

# Due to 0.9 rename to nanomsg, some older bindings break so alias nanomsg.pc to libnanomsg.pc - should be removed later
# Can't make CMAKE_INSTALL_LIBDIR point to the right place
RUN mv /usr/local/lib64/* /usr/local/lib \
    && rm -Rf /usr/local/lib64 \
    && ln -s /usr/local/lib/pkgconfig/nanomsg.pc /usr/local/lib/pkgconfig/libnanomsg.pc

# Prompt and shell settings

# RFC 5424 log levels http://en.wikipedia.org/wiki/Syslog#Severity_levels
# defaults to notice, overwrite with -e LOG_LEVEL=7

# Change the onetime and fixup stage to terminate on error

ENV TERM=xterm-color LOG_LEVEL=5 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 S6_KEEP_ENV=1

# S6 default entry point is the init added from the overlay
ENTRYPOINT [ "/custom-init" ]
