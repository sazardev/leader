# Java with Temurin: build with Maven, run on the JRE
# target: Dockerfile
FROM maven:3.9-eclipse-temurin-{{java}} AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q || true
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:{{java}}-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
