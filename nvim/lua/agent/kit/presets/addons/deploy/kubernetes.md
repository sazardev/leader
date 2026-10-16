<!-- name: Kubernetes (Helm) -->
<!-- desc: Helm chart with probes, resources, HPA and PodDisruptionBudget; config from ConfigMaps and Secrets -->
<!-- for: server backend !mobile -->

## Stack

| Deploy | Kubernetes with a Helm chart in `deploy/chart/` (Deployment, Service, Ingress, HPA, PDB) | Standard platform when the organisation already runs a cluster |

## Project layout

```
deploy/chart/
  Chart.yaml
  values.yaml                  image, replicas, resources, env (non-secret), ingress host
  templates/                   deployment.yaml, service.yaml, ingress.yaml, hpa.yaml, pdb.yaml
```

## Conventions

- Liveness probe on `GET /healthz`, readiness on `GET /readyz`; the app shuts down gracefully on SIGTERM within `terminationGracePeriodSeconds`.
- Every container sets CPU/memory requests and a memory limit; runs as non-root with a read-only root filesystem.
- Secrets come from Kubernetes Secrets (or an external secrets operator), never from `values.yaml`.
- The image tag is the git SHA; `latest` is never deployed.

## Commands

| Deploy | `helm upgrade --install app deploy/chart -f deploy/chart/values.yaml --set image.tag=$(git rev-parse --short HEAD)` |
| Lint chart | `helm lint deploy/chart` |

## Rules for agents

- Never put secrets in `values.yaml` or templates.
- A new environment variable is added to `values.yaml` (or the Secret) and to startup validation in the same change.
- Never remove resource requests or probes to make a deploy pass.
