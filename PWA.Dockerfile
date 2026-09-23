FROM alpine:3.20
RUN apk add --no-cache nginx unzip ca-certificates
COPY AURORA_Safari_PWA_v2.zip /tmp/aurora.zip
RUN rm -rf /usr/share/nginx/html/* && unzip -q /tmp/aurora.zip -d /usr/share/nginx/html && rm /tmp/aurora.zip
COPY pwa-nginx.conf /etc/nginx/http.d/default.conf
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
