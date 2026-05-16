# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT BDD Test Runner Docker Image
#
# 構建指令:
#   docker build -t localhost:5000/presit-bdd-runner:latest -f Dockerfile .
#   docker push localhost:5000/presit-bdd-runner:latest
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Stage 1: 依賴下載
FROM maven:3.9-eclipse-temurin-17-alpine AS deps
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Stage 2: 打包
FROM deps AS build
COPY features/    features/
COPY step-definitions/ step-definitions/
COPY runners/     runners/
RUN mvn test-compile -q

# Stage 3: 最終運行鏡像
FROM maven:3.9-eclipse-temurin-17-alpine AS runtime
WORKDIR /app

# 安裝 kubectl (供 Phase 2 Pod 狀態查詢)
RUN apk add --no-cache curl && \
    curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/

COPY --from=build /app /app
COPY --from=build /root/.m2 /root/.m2
COPY scripts/run-presit.sh /app/scripts/
RUN chmod +x /app/scripts/run-presit.sh

# 報告輸出目錄
RUN mkdir -p /reports

ENTRYPOINT ["/app/scripts/run-presit.sh"]
