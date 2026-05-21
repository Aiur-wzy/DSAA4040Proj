# Troubleshooting Reference

## High-value issues

1. **Stale images on Minikube**
   - Rebuild images, load into profile, restart rollout.
   - Preferred script: `./scripts/k8s-rebuild-and-deploy.sh`.

2. **CNPG initdb permission denied**
   - Preferred fix:
     ```bash
     MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-prepare-cnpg-local-storage.sh
     ```
   - Fallback auto-fix: `AUTO_FIX_CNPG_PVC_PERMISSIONS=1 ...`
   - `FORCE_DELETE_DANGLING_CNPG_PVC` is last-resort fresh-init only.

3. **ImagePullBackOff**
   - Identify exact missing image/tag.
   - Pull/load to the same Minikube profile.

4. **metrics-server missing**
   - Run `./scripts/k8s-fix-metrics-server.sh`.

5. **Public access failure**
   - Validate NodePort first, then expose script, then firewall/security-group rules.
