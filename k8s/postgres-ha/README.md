# Optional CloudNativePG PostgreSQL HA

These manifests define the optional `DB_MODE=ha` database for the bookstore demo. They do **not** replace the default single-PostgreSQL Deployment.

Install the CloudNativePG operator first:

```bash
./scripts/k8s-install-cnpg.sh
```

Then deploy the app in HA mode:

```bash
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh
```

CloudNativePG creates the service names used by the backend from the cluster name `bookstore-postgres`:

- `bookstore-postgres-rw`: read-write service that follows the current primary
- `bookstore-postgres-ro`: read-only service for ready replicas
- `bookstore-postgres-r`: service for all ready instances

The backend uses `bookstore-postgres-rw` in HA mode so all reads and writes preserve strong consistency.
