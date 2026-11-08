# Kotlin with Temurin: build with Gradle, run on the JRE
# target: Dockerfile
FROM gradle:8-jdk{{jvm}} AS build
WORKDIR /app
COPY . .
RUN gradle --no-daemon -q build -x test

FROM eclipse-temurin:{{jvm}}-jre
WORKDIR /app
COPY --from=build /app/build/libs/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
