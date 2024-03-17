FROM alpine:latest

RUN apk add curl openjdk8

RUN curl -o server.zip https://servers.technicpack.net/Technic/servers/tekkit-2/Tekkit-2_Server_v1.2.1.zip \
    && unzip server -d /server \
    && rm server.zip
WORKDIR server
RUN echo eula=true > eula.txt
ADD ops.json .
ADD server.properties .
CMD ["java", "-server", "-Xmx8G", "-Dfml.queryResult=confirm", "-jar", "forge-1.12.2-14.23.5.2860.jar", "nogui"]
