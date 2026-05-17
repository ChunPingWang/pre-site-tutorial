import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import git
from fastapi import Body, FastAPI, HTTPException
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from kubernetes import client, config

WORKSPACE = Path("/workspace/repo")
REPORTS_DIR = Path("/reports")
FEATURES_BASE = "presit-bdd-demo/features"

REPO_URL = os.getenv("GIT_REPO_URL", "https://github.com/ChunPingWang/pre-site-tutorial.git")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")
GIT_USER = os.getenv("GIT_USER", "presit-editor")
GIT_EMAIL = os.getenv("GIT_EMAIL", "presit-editor@presit.local")


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


# Serve static UI (must be last)
app.mount("/", StaticFiles(directory="static", html=True), name="static")
