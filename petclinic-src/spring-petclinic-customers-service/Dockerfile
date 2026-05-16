FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S app && adduser -S -G app app
USER app
WORKDIR /app
COPY target/spring-petclinic-customers-service-*.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java","-jar","/app/app.jar"]
