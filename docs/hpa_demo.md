# HPA Demo Guide

## Prerequisites

- Core app path is working first (API + frontend).
- metrics-server is installed and healthy.

## Commands

```bash
./scripts/k8s-fix-metrics-server.sh
./scripts/k8s-hpa-demo.sh
```

## Notes

- Monitoring UI/API reads `/api/admin/cluster/status`.
- HPA demo is optional for final evidence but useful for autoscaling proof.
