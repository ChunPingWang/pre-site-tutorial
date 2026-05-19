# Stage 1: deps
FROM maven:3.9-eclipse-temurin-17-alpine AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q || true

# Stage 2: build
FROM deps AS build
COPY src/ src/
RUN mvn test-compile -q

# Stage 3: runtime
# 需要 Docker CLI（TC 用 Docker socket）和 kubectl（Phase 2-4 用）
FROM maven:3.9-eclipse-temurin-17-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache curl jq && \
    curl -LsS "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" \
         -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl
COPY --from=build /app /app
COPY --from=build /root/.m2 /root/.m2
RUN mkdir -p /reports
# TC 透過 /var/run/docker.sock 與 Docker daemon 通訊（K8s Job 以 hostPath 掛載）
ENV TESTCONTAINERS_RYUK_DISABLED=true
ENTRYPOINT ["mvn"]
CMD ["test"]
