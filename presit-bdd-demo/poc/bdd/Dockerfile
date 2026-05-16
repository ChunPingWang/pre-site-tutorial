# Stage 1: deps
FROM maven:3.9-eclipse-temurin-17-alpine AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q || true

# Stage 2: build (compile tests + bake into local m2)
FROM deps AS build
COPY src/ src/
RUN mvn test-compile -q

# Stage 3: runtime
FROM maven:3.9-eclipse-temurin-17-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache curl jq && \
    curl -LsS "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl
COPY --from=build /app /app
COPY --from=build /root/.m2 /root/.m2
RUN mkdir -p /reports
ENTRYPOINT ["mvn"]
CMD ["test"]
