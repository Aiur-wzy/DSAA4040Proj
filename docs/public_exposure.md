# Public Exposure Guide

For public demo access on a cloud host:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-expose-demo.sh
```

Open:

```text
http://<server-public-ip>:3000
```

Requirements:
- Cloud firewall/security group allows inbound TCP `3000`.
- NodePort service is reachable internally before exposure.

See `docs/demo_manual.md` for full demo sequence.
