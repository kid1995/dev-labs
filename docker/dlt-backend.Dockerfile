# Pre-built Dockerfile for dlt-manager backend
# Expects: backend already built via ./gradlew :backend:installDist
#
# [LAB SIMULATION] Base image replaced:
#   Original: prod.docker.system.local/baseimages/sda-jre21-alpine:8 (internal registry)
#   Lab:      eclipse-temurin:21-jre-alpine (public Docker Hub)
# [LAB SIMULATION] Build process simplified:
#   Original: Jenkins si_docker.buildImage() → pushes to dev.docker.system.local/elpa-dltmanager-tst/
#   Lab:      pre-built locally, tagged as lab/dlt-backend
# [LAB SIMULATION] Permissions script removed:
#   Original: /tmp/setPermissions.sh from base image sets file ownership
#   Lab:      manual addgroup/adduser + chown
FROM eclipse-temurin:21-jre-alpine

WORKDIR /java
ENV TZ=Europe/Berlin
ENV LANG=de_DE.UTF-8

RUN addgroup -S java && adduser -S java -G java

COPY backend/build/install/backend/ /java/
COPY backend/src/main/resources/application.yml /java/config/

RUN chown -R java:java /java
USER java

EXPOSE 8080 8081
ENTRYPOINT ["/java/bin/backend"]
