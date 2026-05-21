# Repository Cleanup Report

Date: 2026-05-21

## Scope and Safety
Conservative cleanup was applied to remove clearly generated artifacts while preserving source code, deployment manifests, demo/test scripts, and report materials used by final submission workflows.

## A) Kept (required)
- Core project directories: `backend/`, `frontend/`, `database/`, `k8s/`, `k8s/postgres-ha/`, `scripts/`, `docs/`, `report/`.
- All active deployment/demo/test scripts referenced by current README and HA workflows (except one missing script noted below).
- All Kubernetes manifests, Dockerfiles, `docker-compose.yml`, and main project docs (`README.md`, `TODO.md`, `docs/distributed_network_flow.md`, `docs/demo_manual.md`).
- CNPG main-path scripts and manifests used by distributed HA demo (`k8s-prepare-cnpg-local-storage.sh`, `k8s-distributed-ha-rebuild-all.sh`, `k8s-rebuild-and-deploy.sh`, status/failover/evidence scripts).

## B) Archived
- `guide.txt` -> `archive/old-docs/guide.txt`
  - Reason: empty/obsolete helper note file; not referenced by README/docs/scripts.

## C) Deleted
- `frontend/node_modules/`
  - Reason: generated dependency directory; should not be versioned.
- No additional cache/log/temp artifacts were found during pattern cleanup.

## D) Manual Review Needed
- `scripts/k8s-preload-images.sh` is referenced in the required-script checklist but **does not exist** in repository.
  - Action: decide whether to add this script or formally adjust documentation/checklists.
- Optional legacy recovery helpers still present (e.g., CNPG fix/reset helpers). They were kept to avoid breaking workflows and should be reviewed for final scope trimming if desired.

## README / Docs Consistency
- README documentation links currently resolve to existing docs files for:
  - `docs/distributed_network_flow.md`
  - `docs/demo_manual.md`
- `TODO.md` exists in repository.
- No README links were changed in this cleanup.

## Script Reference Consistency
- Verified required scripts list against repository.
- Missing item: `scripts/k8s-preload-images.sh`.
- All other required scripts in the provided list are present.

## .gitignore Update
Updated `.gitignore` to include common generated/cache/runtime artifacts and keep `.env.example` tracked:
- Python cache dirs/files, mypy/pytest/ruff caches
- node modules and frontend build output
- env files with `!.env.example`
- logs and local temp/runtime files
- OS/editor junk files

## Validation Performed
- `git status --short`
- `git diff --check`
- `bash -n scripts/*.sh`
- `bash -n scripts/lib/*.sh`
- `find backend -name '*.py' -print0 | xargs -0 python -m py_compile`
- `npm --prefix frontend run build`

All commands completed except `npm --prefix frontend run build`, which failed in the cleaned repository because frontend dependencies were not installed (`vite: not found`).
