# Distributed Network Flow

For the distributed HA Minikube profile (`MINIKUBE_PROFILE=bookstore-distributed`, `DB_MODE=ha`), public demo traffic can be forwarded to the frontend NodePort through host-level iptables rules.

```text
external browser
  -> http://<server-public-ip>:3000
  -> host-level iptables DNAT/MASQUERADE/FORWARD
  -> Minikube NodePort 192.168.49.2:30080
  -> frontend-service
  -> frontend Nginx
  -> public/admin/monitoring backend services
```

Public browser access depends on both:
- forwarding rules on the host, and
- cloud firewall/security group allowing inbound TCP on the selected public port (for example `3000`).

## Build Workflow Integration

- The distributed HA build workflow (`scripts/k8s-distributed-ha-rebuild-all.sh`) can optionally run demo exposure at the end when `EXPOSE_DEMO=1`.
- Exposure is skipped by default for safety.
- The workflow verifies frontend NodePort readiness before applying public forwarding rules.
- You can run `scripts/k8s-check-demo-exposure.sh` to verify internal NodePort health and iptables forwarding rules.
