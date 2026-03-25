# Pre-built Dockerfile for hint-service
# Expects: hint-service already built via ./gradlew :hint-service:installDist
#
# [LAB SIMULATION] Base image replaced:
#   Original: prod.docker.system.local/baseimages/sda-jre21-alpine:100 (internal registry)
#   Lab:      eclipse-temurin:21-jre-alpine (public Docker Hub)
# [LAB SIMULATION] Build process simplified:
#   Original: multi-step Jenkins pipeline builds, pushes to dev.docker.system.local
#   Lab:      pre-built locally, no registry push
# [LAB SIMULATION] Permissions script removed:
#   Original: /tmp/setPermissions.sh from base image
#   Lab:      manual addgroup/adduser + chown
FROM eclipse-temurin:21-jre-alpine

WORKDIR /java
RUN addgroup -S java && adduser -S java -G java

COPY hint-service/build/install/hint-service/ /java/
COPY hint-service/src/main/resources/application.yml /java/config/

RUN chown -R java:java /java
USER java

EXPOSE 8080 8081
ENTRYPOINT ["/java/bin/hint-service"]
