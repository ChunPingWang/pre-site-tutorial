#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Pre-SIT 全流程自動化驗證腳本
# 對應工作計劃：Phase 1-4 完整端到端驗證
#
# 使用方式:
#   ./run-presit.sh              # 執行全部 Phase
#   ./run-presit.sh --phase 1    # 只執行 Phase 1
#   ./run-presit.sh --smoke      # 只執行 Smoke Test
#   ./run-presit.sh --report     # 只產出報告
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

# ─── 環境變數（可由 K8s ConfigMap 注入）───────────
export DB_HOST="${DB_HOST:-postgres-service.pre-sit.svc}"
export DB_PORT="${DB_PORT:-5432}"
export DB_NAME="${DB_NAME:-petclinic}"
export DB_USER="${DB_USER:-postgres}"
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export GATEWAY_URL="${GATEWAY_URL:-http://api-gateway.pre-sit.svc:8080}"
export REPORT_DIR="${REPORT_DIR:-/reports}"

# ─── 顏色輸出 ─────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; NC='\033[0m'

# ─── 計分器 ───────────────────────────────────────
TOTAL_PHASES=0
PASSED_PHASES=0
FAILED_PHASES=0
PHASE_RESULTS=()

print_banner() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Pre-SIT 容器化數據庫驗證系統${NC}"
    echo -e "${BLUE}  Spring PetClinic │ Kind + K8s │ ArgoCD${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_phase_header() {
    local phase_num=$1
    local phase_name=$2
    echo ""
    echo -e "${PURPLE}┌─────────────────────────────────────────────┐${NC}"
    echo -e "${PURPLE}│  Phase ${phase_num}: ${phase_name}${NC}"
    echo -e "${PURPLE}└─────────────────────────────────────────────┘${NC}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 前置檢查
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
preflight_check() {
    echo -e "${YELLOW}[前置檢查] 驗證環境就緒狀態...${NC}"

    # 1. kubectl 可用
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}[錯誤] kubectl 未安裝${NC}"; exit 1
    fi

    # 2. Kind 集群運行中
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}[錯誤] 無法連接 K8s 集群${NC}"; exit 1
    fi

    # 3. pre-sit namespace 存在
    if ! kubectl get namespace pre-sit &> /dev/null; then
        echo -e "${YELLOW}[建立] 建立 pre-sit 命名空間...${NC}"
        kubectl create namespace pre-sit
    fi

    # 4. 等待 DB 就緒
    echo -e "${YELLOW}[等待] 等待 PostgreSQL Pod 就緒...${NC}"
    kubectl wait --for=condition=Ready pod \
        -l app=postgres -n pre-sit --timeout=120s 2>/dev/null || {
        echo -e "${RED}[錯誤] PostgreSQL Pod 未在 120 秒內就緒${NC}"; exit 1
    }

    # 5. 等待應用就緒
    echo -e "${YELLOW}[等待] 等待應用 Pod 就緒...${NC}"
    for svc in customers-service vets-service visits-service api-gateway; do
        kubectl wait --for=condition=Ready pod \
            -l app=$svc -n pre-sit --timeout=180s 2>/dev/null || {
            echo -e "${RED}[錯誤] ${svc} Pod 未在 180 秒內就緒${NC}"; exit 1
        }
    done

    echo -e "${GREEN}[前置檢查] ✅ 所有前置條件滿足${NC}"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Phase 執行函式
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
run_phase() {
    local phase_num=$1
    local phase_name=$2
    local profile=$3

    print_phase_header "$phase_num" "$phase_name"
    TOTAL_PHASES=$((TOTAL_PHASES + 1))

    local start_time=$(date +%s)

    if mvn test -P "$profile" -q 2>&1 | tee "/tmp/phase${phase_num}.log"; then
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        PASSED_PHASES=$((PASSED_PHASES + 1))
        PHASE_RESULTS+=("✅ Phase ${phase_num}: ${phase_name} (${elapsed}s)")
        echo -e "${GREEN}[Phase ${phase_num}] ✅ 通過 (耗時 ${elapsed}s)${NC}"
        return 0
    else
        local end_time=$(date +%s)
        local elapsed=$((end_time - start_time))
        FAILED_PHASES=$((FAILED_PHASES + 1))
        PHASE_RESULTS+=("❌ Phase ${phase_num}: ${phase_name} (${elapsed}s)")
        echo -e "${RED}[Phase ${phase_num}] ❌ 失敗 (耗時 ${elapsed}s)${NC}"
        return 1
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Go/No-Go 決策
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
generate_decision() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Pre-SIT 驗證結果摘要${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    for result in "${PHASE_RESULTS[@]}"; do
        echo -e "  ${result}"
    done

    echo ""
    echo -e "  總計: ${TOTAL_PHASES} 個 Phase"
    echo -e "  通過: ${GREEN}${PASSED_PHASES}${NC}"
    echo -e "  失敗: ${RED}${FAILED_PHASES}${NC}"

    local pass_rate=0
    if [ $TOTAL_PHASES -gt 0 ]; then
        pass_rate=$((PASSED_PHASES * 100 / TOTAL_PHASES))
    fi
    echo -e "  通過率: ${pass_rate}%"
    echo ""

    # 產出 JSON 報告
    mkdir -p "$REPORT_DIR"
    cat > "${REPORT_DIR}/presit-decision.json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "total_phases": ${TOTAL_PHASES},
  "passed_phases": ${PASSED_PHASES},
  "failed_phases": ${FAILED_PHASES},
  "pass_rate": ${pass_rate},
  "decision": "$([ $FAILED_PHASES -eq 0 ] && echo 'GO' || echo 'NO-GO')",
  "details": {
    "phase_results": [
$(printf '      "%s",\n' "${PHASE_RESULTS[@]}" | sed '$ s/,$//')
    ]
  }
}
EOF

    # Go / No-Go 判定
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ $FAILED_PHASES -eq 0 ]; then
        echo -e "  ${GREEN}██████╗  ██████╗     ██╗${NC}"
        echo -e "  ${GREEN}██╔════╝ ██╔═══██╗   ██║${NC}"
        echo -e "  ${GREEN}██║  ███╗██║   ██║   ██║${NC}"
        echo -e "  ${GREEN}██║   ██║██║   ██║   ╚═╝${NC}"
        echo -e "  ${GREEN}╚██████╔╝╚██████╔╝   ██╗${NC}"
        echo -e "  ${GREEN} ╚═════╝  ╚═════╝    ╚═╝${NC}"
        echo ""
        echo -e "  ${GREEN}決策: ✅ GO — 可部署至 SIT 環境${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 0
    else
        echo -e "  ${RED}███╗   ██╗ ██████╗        ██████╗  ██████╗${NC}"
        echo -e "  ${RED}████╗  ██║██╔═══██╗      ██╔════╝ ██╔═══██╗${NC}"
        echo -e "  ${RED}██╔██╗ ██║██║   ██║█████╗██║  ███╗██║   ██║${NC}"
        echo -e "  ${RED}██║╚██╗██║██║   ██║╚════╝██║   ██║██║   ██║${NC}"
        echo -e "  ${RED}██║ ╚████║╚██████╔╝      ╚██████╔╝╚██████╔╝${NC}"
        echo -e "  ${RED}╚═╝  ╚═══╝ ╚═════╝        ╚═════╝  ╚═════╝${NC}"
        echo ""
        echo -e "  ${RED}決策: ❌ NO-GO — 需修復後重新驗證${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        exit 1
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 主程式
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
main() {
    print_banner

    local target_phase="${1:---all}"

    preflight_check

    case "$target_phase" in
        --phase)
            local phase_num="${2:-1}"
            case "$phase_num" in
                1) run_phase 1 "數據庫層驗證"     "phase-1" ;;
                2) run_phase 2 "應用層驗證"       "phase-2" ;;
                3) run_phase 3 "功能與集成驗證"   "phase-3" ;;
                4) run_phase 4 "端到端與決策"     "phase-4" ;;
                *) echo "未知 Phase: $phase_num"; exit 1 ;;
            esac
            ;;
        --smoke)
            run_phase 0 "Smoke Test" "smoke"
            ;;
        --all|*)
            run_phase 1 "數據庫層驗證"     "phase-1" || true
            run_phase 2 "應用層驗證"       "phase-2" || true
            run_phase 3 "功能與集成驗證"   "phase-3" || true
            run_phase 4 "端到端與決策"     "phase-4" || true
            ;;
    esac

    generate_decision
}

main "$@"
