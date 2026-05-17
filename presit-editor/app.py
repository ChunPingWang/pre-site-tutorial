import json
import os
import re
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

import git
import psycopg2
import psycopg2.extras
from fastapi import Body, FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from kubernetes import client, config

WORKSPACE = Path("/workspace/repo")
REPORTS_DIR = Path("/reports")
FEATURES_BASE = "presit-bdd-demo/features"

REPO_URL = os.getenv("GIT_REPO_URL", "https://github.com/ChunPingWang/pre-site-tutorial.git")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
GIT_USER = os.getenv("GIT_USER", "presit-editor")
GIT_EMAIL = os.getenv("GIT_EMAIL", "presit-editor@presit.local")

PG_HOST = os.getenv("PG_HOST", "postgres-service.pre-sit.svc")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_DB   = os.getenv("PG_DB", "petclinic")
PG_USER = os.getenv("PG_USER_DB", "postgres")
PG_PASS = os.getenv("PG_PASSWORD", "petclinic")


def _auth_url() -> str:
    if GITHUB_TOKEN:
        return REPO_URL.replace("https://", f"https://{GITHUB_TOKEN}@")
    return REPO_URL


def _repo() -> git.Repo:
    return git.Repo(WORKSPACE)


def _init_repo():
    WORKSPACE.parent.mkdir(parents=True, exist_ok=True)
    if (WORKSPACE / ".git").exists():
        repo = _repo()
        repo.remotes.origin.set_url(_auth_url())
        repo.remotes.origin.pull()
    else:
        git.Repo.clone_from(_auth_url(), WORKSPACE)
    repo = _repo()
    with repo.config_writer() as cw:
        cw.set_value("user", "name", GIT_USER)
        cw.set_value("user", "email", GIT_EMAIL)


@asynccontextmanager
async def lifespan(app: FastAPI):
    _init_repo()
    yield


app = FastAPI(title="Pre-SIT Gherkin Editor", lifespan=lifespan)


# ── Feature CRUD ──────────────────────────────────────────────────────────────

@app.get("/api/features")
def list_features():
    features_dir = WORKSPACE / FEATURES_BASE
    if not features_dir.exists():
        return []
    files = sorted(features_dir.rglob("*.feature"))
    return [
        {"path": str(f.relative_to(features_dir)), "name": f.stem}
        for f in files
    ]


@app.get("/api/features/{feature_path:path}")
def get_feature(feature_path: str):
    target = WORKSPACE / FEATURES_BASE / feature_path
    if not target.exists():
        raise HTTPException(404, "Feature not found")
    return {"path": feature_path, "content": target.read_text(encoding="utf-8")}


@app.put("/api/features/{feature_path:path}")
def save_feature(feature_path: str, body: dict = Body(...)):
    content = body.get("content", "")
    target = WORKSPACE / FEATURES_BASE / feature_path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    repo = _repo()
    rel = str(target.relative_to(WORKSPACE))
    repo.index.add([rel])
    repo.index.commit(f"feat(gherkin): update {feature_path} via presit-editor")
    repo.remotes.origin.set_url(_auth_url())
    repo.remotes.origin.push()
    return {"status": "ok"}


@app.post("/api/features/{feature_path:path}")
def create_feature(feature_path: str, body: dict = Body(...)):
    content = body.get("content", f'# language: zh-TW\n功能: {Path(feature_path).stem}\n\n  場景: 新場景\n    假設 ...\n    當 ...\n    那麼 ...\n')
    target = WORKSPACE / FEATURES_BASE / feature_path
    if target.exists():
        raise HTTPException(409, "Feature already exists")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    repo = _repo()
    rel = str(target.relative_to(WORKSPACE))
    repo.index.add([rel])
    repo.index.commit(f"feat(gherkin): create {feature_path} via presit-editor")
    repo.remotes.origin.set_url(_auth_url())
    repo.remotes.origin.push()
    return {"status": "created"}


@app.delete("/api/features/{feature_path:path}")
def delete_feature(feature_path: str):
    target = WORKSPACE / FEATURES_BASE / feature_path
    if not target.exists():
        raise HTTPException(404, "Feature not found")
    repo = _repo()
    rel = str(target.relative_to(WORKSPACE))
    repo.index.remove([rel], working_tree=True)
    repo.index.commit(f"feat(gherkin): delete {feature_path} via presit-editor")
    repo.remotes.origin.set_url(_auth_url())
    repo.remotes.origin.push()
    return {"status": "deleted"}


# ── Test Results ──────────────────────────────────────────────────────────────

@app.get("/api/results")
def get_decision():
    f = REPORTS_DIR / "presit-decision.json"
    if not f.exists():
        return {"status": "no_results"}
    return json.loads(f.read_text())


@app.get("/api/results/{phase}")
def get_phase_results(phase: int):
    f = REPORTS_DIR / f"phase-{phase}" / "cucumber-report.json"
    if not f.exists():
        raise HTTPException(404, f"No results for phase {phase}")
    return json.loads(f.read_text())


# ── Pipeline Trigger ──────────────────────────────────────────────────────────

def _k8s_custom():
    try:
        config.load_incluster_config()
    except config.ConfigException:
        config.load_kube_config()
    return client.CustomObjectsApi()


@app.post("/api/run")
def trigger_pipeline():
    api = _k8s_custom()
    workflow = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Workflow",
        "metadata": {"generateName": "presit-pipeline-", "namespace": "argo"},
        "spec": {"workflowTemplateRef": {"name": "presit-pipeline"}},
    }
    result = api.create_namespaced_custom_object(
        group="argoproj.io", version="v1alpha1",
        namespace="argo", plural="workflows", body=workflow,
    )
    return {"status": "triggered", "name": result["metadata"]["name"]}


@app.get("/api/run/status")
def pipeline_status():
    api = _k8s_custom()
    workflows = api.list_namespaced_custom_object(
        group="argoproj.io", version="v1alpha1",
        namespace="argo", plural="workflows",
        label_selector="workflows.argoproj.io/workflow-template=presit-pipeline",
    )
    items = workflows.get("items", [])
    if not items:
        return {"phase": "None"}
    latest = sorted(items, key=lambda x: x["metadata"]["creationTimestamp"])[-1]
    return {
        "name": latest["metadata"]["name"],
        "phase": latest.get("status", {}).get("phase", "Unknown"),
        "startedAt": latest.get("status", {}).get("startedAt"),
        "finishedAt": latest.get("status", {}).get("finishedAt"),
    }


# ── Report Generation ─────────────────────────────────────────────────────────

def _extract_table_names() -> list[str]:
    """Parse .feature files for DB table names from DataTable rows with a 'table_name' column."""
    tables: set[str] = set()
    features_dir = WORKSPACE / FEATURES_BASE
    if not features_dir.exists():
        return []
    for feat_file in features_dir.rglob("*.feature"):
        text = feat_file.read_text(encoding="utf-8")
        header_col_idx: int | None = None
        for line in text.splitlines():
            stripped = line.strip()
            # Reset header when leaving a DataTable block
            if not stripped.startswith("|"):
                header_col_idx = None
                continue
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if header_col_idx is None:
                for j, cell in enumerate(cells):
                    if cell.lower() in ("table_name", "tablename", "資料表", "table", "表名"):
                        header_col_idx = j
                        break
            else:
                if len(cells) > header_col_idx:
                    val = cells[header_col_idx]
                    if val and re.match(r"^[a-z_][a-z0-9_]*$", val):
                        tables.add(val)
    return sorted(tables)


def _query_table_html(cur, table: str) -> str:
    try:
        cur.execute(f"SELECT * FROM {table} LIMIT 20")  # noqa: S608 – table name extracted from repo source
        columns = [desc[0] for desc in cur.description]
        rows = cur.fetchall()
    except Exception as exc:
        return f'<p class="db-error">查詢失敗：{exc}</p>'
    header = "".join(f"<th>{c}</th>" for c in columns)
    body = "".join(
        "<tr>" + "".join(f"<td>{v}</td>" for v in row) + "</tr>"
        for row in rows
    )
    count_note = f'<p class="db-count">共 {len(rows)} 筆（最多顯示 20 筆）</p>'
    return f'<table class="db-table"><thead><tr>{header}</tr></thead><tbody>{body}</tbody></table>{count_note}'


def _build_report_html(decision: dict, phase_results: dict, db_sections: list[tuple[str, str]]) -> str:
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Decision banner
    if decision and decision.get("decision"):
        is_go = "GO" in str(decision.get("decision", ""))
        dec_class = "go" if is_go else "nogo"
        decision_html = (
            f'<div class="decision-banner {dec_class}">'
            f'決策：{decision["decision"]}'
            f'&nbsp;｜&nbsp;通過率 {decision.get("pass_rate", "—")}%'
            f'（{decision.get("passed", "—")} / {decision.get("total", "—")} 場景通過）'
            f'</div>'
        )
    else:
        decision_html = '<div class="decision-banner pending">尚無測試結果</div>'

    # Scenario results
    scenarios_html = ""
    for phase_num in sorted(phase_results.keys()):
        scenarios_html += f"<h2>Phase {phase_num} 測試結果</h2>"
        for feature in phase_results[phase_num]:
            scenarios_html += f'<h3>📋 {feature.get("name", "—")}</h3><div class="scenario-list">'
            for element in feature.get("elements", []):
                if element.get("type") == "background":
                    continue
                steps = element.get("steps", [])
                passed = all(s.get("result", {}).get("status") == "passed" for s in steps)
                ms = int(sum(s.get("result", {}).get("duration", 0) for s in steps) / 1e6)
                icon = "🟢" if passed else "🔴"
                cls = "passed" if passed else "failed"
                failed_step = next((s for s in steps if s.get("result", {}).get("status") != "passed"), None)
                failed_info = f'<div class="smeta">失敗步驟：{failed_step["name"]}</div>' if failed_step else ""
                scenarios_html += (
                    f'<div class="scenario-card {cls}">'
                    f'<span class="icon">{icon}</span>'
                    f'<div class="info"><div class="sname">{element.get("name", "—")}</div>{failed_info}</div>'
                    f'<div class="duration">{ms} ms</div>'
                    f'</div>'
                )
            scenarios_html += "</div>"

    # DB sections
    db_html = ""
    if db_sections:
        db_html = "<h2>資料庫查詢結果</h2>"
        for table_name, table_html in db_sections:
            db_html += f"<h3>📊 {table_name}</h3>{table_html}"

    css = """
      body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:14px;background:#f5f5f5;color:#333;margin:0;padding:20px}
      .container{max-width:1200px;margin:0 auto}
      h1{font-size:22px;color:#1a1a2e;margin-bottom:4px}
      .meta{font-size:12px;color:#888;margin-bottom:24px}
      h2{font-size:16px;color:#1a1a2e;margin:24px 0 10px;border-bottom:2px solid #e5e7eb;padding-bottom:6px}
      h3{font-size:14px;color:#444;margin:16px 0 8px}
      .decision-banner{padding:14px 18px;border-radius:8px;font-weight:700;font-size:16px;margin-bottom:20px}
      .decision-banner.go{background:#dcfce7;color:#166534;border:1px solid #bbf7d0}
      .decision-banner.nogo{background:#fee2e2;color:#991b1b;border:1px solid #fecaca}
      .decision-banner.pending{background:#f3f4f6;color:#6b7280;border:1px solid #e5e7eb}
      .scenario-list{display:flex;flex-direction:column;gap:6px}
      .scenario-card{display:flex;align-items:flex-start;gap:10px;padding:10px 14px;background:#fff;border:1px solid #e5e7eb;border-radius:6px;border-left:4px solid #d1d5db}
      .scenario-card.passed{border-left-color:#22c55e}
      .scenario-card.failed{border-left-color:#ef4444}
      .icon{font-size:16px;flex-shrink:0}
      .info{flex:1}
      .sname{font-weight:500}
      .smeta{font-size:11px;color:#888;margin-top:2px}
      .duration{font-size:11px;color:#aaa;white-space:nowrap}
      .db-table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e5e7eb;font-size:12px;margin-top:4px}
      .db-table thead{background:#f3f4f6}
      .db-table th,.db-table td{padding:7px 10px;border:1px solid #e5e7eb;text-align:left}
      .db-table th{font-weight:600;color:#374151}
      .db-table tr:hover{background:#f9fafb}
      .db-count{font-size:11px;color:#9ca3af;margin:4px 0 0}
      .db-error{color:#9ca3af;font-style:italic;font-size:13px}
      @media print{body{background:#fff}}
    """

    return f"""<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="UTF-8">
<title>Pre-SIT 測試報告 {ts}</title>
<style>{css}</style>
</head>
<body>
<div class="container">
  <h1>🧪 Pre-SIT 綜合測試報告</h1>
  <div class="meta">產生時間：{ts}</div>
  {decision_html}
  {scenarios_html}
  {db_html}
</div>
</body>
</html>"""


@app.post("/api/report/generate")
def generate_report():
    # Collect test results (read-only)
    decision = {}
    dec_file = REPORTS_DIR / "presit-decision.json"
    if dec_file.exists():
        decision = json.loads(dec_file.read_text())

    phase_results: dict[int, list] = {}
    for phase_num in range(1, 5):
        f = REPORTS_DIR / f"phase-{phase_num}" / "cucumber-report.json"
        if f.exists():
            phase_results[phase_num] = json.loads(f.read_text())

    # Extract table names from Gherkin source
    table_names = _extract_table_names()

    # Query PostgreSQL
    db_sections: list[tuple[str, str]] = []
    if table_names:
        try:
            conn = psycopg2.connect(
                host=PG_HOST, port=PG_PORT,
                dbname=PG_DB, user=PG_USER, password=PG_PASS,
                connect_timeout=5,
            )
            with conn.cursor() as cur:
                for table in table_names:
                    db_sections.append((table, _query_table_html(cur, table)))
            conn.close()
        except Exception as exc:
            db_sections.append(("連線錯誤", f'<p class="db-error">PostgreSQL 連線失敗：{exc}</p>'))

    # Write report to a writable location under /workspace
    report_dir = Path("/workspace/reports")
    report_dir.mkdir(parents=True, exist_ok=True)
    ts_file = datetime.now().strftime("%Y%m%d-%H%M%S")
    filename = f"comprehensive-report-{ts_file}.html"
    (report_dir / filename).write_text(_build_report_html(decision, phase_results, db_sections), encoding="utf-8")

    return {"status": "ok", "filename": filename, "url": f"/api/report/download/{filename}"}


@app.get("/api/report/list")
def list_reports():
    report_dir = Path("/workspace/reports")
    if not report_dir.exists():
        return []
    files = sorted(report_dir.glob("comprehensive-report-*.html"), reverse=True)
    return [{"filename": f.name, "url": f"/api/report/download/{f.name}"} for f in files[:10]]


@app.get("/api/report/download/{filename}")
def download_report(filename: str):
    if "/" in filename or ".." in filename:
        raise HTTPException(400, "Invalid filename")
    path = Path("/workspace/reports") / filename
    if not path.exists():
        raise HTTPException(404, "Report not found")
    return FileResponse(str(path), media_type="text/html", filename=filename,
                        headers={"Content-Disposition": f'attachment; filename="{filename}"'})


# Serve static assets at /static/ (keeps API routes unambiguous)
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/", include_in_schema=False)
def root():
    return FileResponse("static/index.html")
