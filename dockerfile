# 
# build zweb-builder-frontend
#

FROM node:18-bullseye as zweb-builder-frontend

## clone frontend
WORKDIR /opt/zweb/zweb-builder-frontend
RUN cd /opt/zweb/zweb-builder-frontend
RUN pwd

ARG FE=main
RUN git clone -b ${FE} https://github.com/zilliangroup/zweb-builder.git /opt/zweb/zweb-builder-frontend/
RUN git submodule init; \
    git submodule update; 

RUN npm install -g pnpm
RUN whereis pnpm && whereis node

RUN pnpm install
RUN pnpm build-self


# 
# build zweb-builder-backend & zweb-builder-backend-ws
#

FROM golang:1.19-bullseye as zweb-builder-backend

## set env
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

## build
WORKDIR /opt/zweb/zweb-builder-backend
RUN cd  /opt/zweb/zweb-builder-backend
RUN ls -alh

ARG BE=main
RUN git clone -b ${BE} https://github.com/zilliangroup/zweb-builder-backend.git ./

RUN cat ./Makefile

RUN make all 

RUN ls -alh ./bin/* 



#
# build zweb-supervisor-backend & zweb-supervisor-backend-internal
#

FROM golang:1.19-bullseye as zweb-supervisor-backend

## set env
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

## build
WORKDIR /opt/zweb/zweb-supervisor-backend
RUN cd  /opt/zweb/zweb-supervisor-backend
RUN ls -alh

ARG SBE=main
RUN git clone -b ${SBE} https://github.com/zilliangroup/zweb-supervisor-backend.git ./

RUN cat ./Makefile

RUN make all 

RUN ls -alh ./bin/*


#
# build redis
#
FROM redis:6.2.7 as cache-redis

RUN ls -alh /usr/local/bin/redis*


#
# build minio
#
FROM minio/minio:edge as drive-minio

RUN ls -alh /opt/bin/minio

#
# build nginx
#
FROM nginx:1.24-bullseye as webserver-nginx

RUN ls -alh /usr/sbin/nginx; ls -alh /usr/lib/nginx; ls -alh /etc/nginx; ls -alh /usr/share/nginx;

#
# build envoy
#
FROM envoyproxy/envoy:v1.18.2 as ingress-envoy

RUN ls -alh /etc/envoy

RUN ls -alh /usr/local/bin/envoy* 
RUN ls -alh /usr/local/bin/su-exec 
RUN ls -alh /etc/envoy/envoy.yaml
RUN ls -alh  /docker-entrypoint.sh 


# 
# Assembly all-in-one image
#
FROM postgres:14.5-bullseye as runner


#
# init environment & install required debug & runtime tools
#
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    netbase \
    wget \
    telnet \
    gnupg \
    dirmngr \
    dumb-init \
    procps \
    gettext-base \
    ; \
    rm -rf /var/lib/apt/lists/*




# 
# init working folder and users
#
RUN mkdir /opt/zweb
RUN addgroup --system --gid 102 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 102 nginx \
    && adduser --group --system envoy \
    && adduser --group --system minio \
    && adduser --group --system redis \
    && adduser --group --system zweb \
    && cat /etc/group 

#
# copy zweb-builder-backend bin
#
COPY --from=zweb-builder-backend /opt/zweb/zweb-builder-backend /opt/zweb/zweb-builder-backend

#
# copy zweb-supervisor-backend bin
#
COPY --from=zweb-supervisor-backend /opt/zweb/zweb-supervisor-backend /opt/zweb/zweb-supervisor-backend

#
# copy zweb-builder-frontend
#
COPY --from=zweb-builder-frontend /opt/zweb/zweb-builder-frontend/apps/builder/dist /opt/zweb/zweb-builder-frontend


#
# copy gosu
#

RUN gosu --version; \
	gosu nobody true

#
# copy redis
#
RUN mkdir -p /opt/zweb/cache-data/; \
    mkdir -p /opt/zweb/redis/; \
    chown -fR redis:redis /opt/zweb/cache-data/; \
    chown -fR redis:redis /opt/zweb/redis/; 


COPY --from=cache-redis /usr/local/bin/redis-benchmark /usr/local/bin/redis-benchmark  
COPY --from=cache-redis /usr/local/bin/redis-check-aof /usr/local/bin/redis-check-aof  
COPY --from=cache-redis /usr/local/bin/redis-check-rdb /usr/local/bin/redis-check-rdb  
COPY --from=cache-redis /usr/local/bin/redis-cli       /usr/local/bin/redis-cli        
COPY --from=cache-redis /usr/local/bin/redis-sentinel  /usr/local/bin/redis-sentinel   
COPY --from=cache-redis /usr/local/bin/redis-server    /usr/local/bin/redis-server      

COPY scripts/redis-entrypoint.sh    /opt/zweb/redis  
RUN chmod +x /opt/zweb/redis/redis-entrypoint.sh


#
# copy minio
#
RUN mkdir -p /opt/zweb/drive/; \
    mkdir -p /opt/zweb/minio/; \
    chown -fR minio:minio /opt/zweb/drive/; \
    chown -fR minio:minio /opt/zweb/minio/;


COPY --from=drive-minio /opt/bin/minio /usr/local/bin/minio 

COPY scripts/minio-entrypoint.sh /opt/zweb/minio
RUN chmod +x /opt/zweb/minio/minio-entrypoint.sh


#
# copy nginx
#
RUN mkdir /opt/zweb/nginx

COPY --from=webserver-nginx /usr/sbin/nginx  /usr/sbin/nginx 
COPY --from=webserver-nginx /usr/lib/nginx   /usr/lib/nginx 
COPY --from=webserver-nginx /etc/nginx       /etc/nginx 
COPY --from=webserver-nginx /usr/share/nginx /usr/share/nginx 

COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/zweb-builder-frontend.conf /etc/nginx/conf.d/
COPY scripts/nginx-entrypoint.sh /opt/zweb/nginx

RUN set -x \
    && mkdir /var/log/nginx/ \
    && chmod 0777 /var/log/nginx/ \
    && mkdir /var/cache/nginx/ \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /tmp/nginx.pid \
    && chmod 0777 /tmp/nginx.pid \
    && rm /etc/nginx/conf.d/default.conf \
    && chmod +x /opt/zweb/nginx/nginx-entrypoint.sh \
    && chown -R $UID:0 /var/cache/nginx \
    && chmod -R g+w /var/cache/nginx \
    && chown -R $UID:0 /etc/nginx \
    && chmod -R g+w /etc/nginx

RUN nginx -t


#
# copy envoy
#
ENV ENVOY_UID 0 # set to root for envoy listing on 80 prot
ENV ENVOY_GID 0

RUN mkdir -p /opt/zweb/envoy \
    && mkdir -p /etc/envoy

COPY --from=ingress-envoy  /usr/local/bin/envoy* /usr/local/bin/
COPY --from=ingress-envoy  /usr/local/bin/su-exec  /usr/local/bin/
COPY --from=ingress-envoy  /etc/envoy/envoy.yaml  /etc/envoy/

COPY config/envoy/zweb-unit-ingress.yaml /opt/zweb/envoy
COPY scripts/envoy-entrypoint.sh /opt/zweb/envoy

RUN chmod +x /opt/zweb/envoy/envoy-entrypoint.sh \
    && ls -alh /usr/local/bin/envoy* \
    && ls -alh /usr/local/bin/su-exec \
    && ls -alh /etc/envoy/envoy.yaml


#
# init database 
#
RUN mkdir -p /opt/zweb/database/ \
    && mkdir -p /opt/zweb/postgres/

COPY scripts/postgres-entrypoint.sh  /opt/zweb/postgres
COPY scripts/postgres-init.sh /opt/zweb/postgres
RUN chmod +x /opt/zweb/postgres/postgres-entrypoint.sh \
    && chmod +x /opt/zweb/postgres/postgres-init.sh 


#
# add main scripts
#
COPY scripts/main.sh /opt/zweb/
COPY scripts/pre-init.sh /opt/zweb/
COPY scripts/post-init.sh /opt/zweb/
RUN chmod +x /opt/zweb/main.sh 
RUN chmod +x /opt/zweb/pre-init.sh 
RUN chmod +x /opt/zweb/post-init.sh 

#
# modify global permission
#  
COPY config/system/group /opt/zweb/
RUN cat /opt/zweb/group > /etc/group; rm /opt/zweb/group
RUN chown -fR zweb:root /opt/zweb
RUN chmod 775 -fR /opt/zweb

#
# run
#
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
EXPOSE 2022
CMD ["/opt/zweb/main.sh"]
