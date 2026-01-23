# Project Eagle Eye: Cloud-Native Observability & Self-Healing Infrastructure

> **SRE-driven observability solution for multi-tier Kubernetes applications with GitOps-based automated remediation**

---

## Executive Summary

Project Eagle Eye provides comprehensive observability for cloud-native applications running on Kubernetes, implementing the Golden Signals framework through Grafana Alloy telemetry collection and Prometheus Remote Write protocol. The platform enables SRE teams to detect and auto-remediate infrastructure drift with GitOps-powered ArgoCD orchestration.

**Key Deliverables:**
- Multi-tier application monitoring (Nginx + Redis)
- Dynamic service discovery with Kubernetes API integration
- Standardized metric relabeling for high-cardinality analysis
- Zero-trust security model with RBAC and TLS encryption
- GitOps-ready automation pipeline (Phase 2)

---

---

## Quick Start

### Prerequisites

- **Kubernetes**: v1.24+ (with API server accessibility)
- **Grafana Cloud Account**: Active subscription (CA-East-0 region)
- **kubectl**: Configured with cluster admin access
- **CLI Tools**: git, git-credential-helper

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/KrishnaKondra18/project-eagle-eye.git
   cd project-eagle-eye
   ```

2. **Set Grafana Cloud credentials:**
   ```bash
   export GRAFANA_CLOUD_API_TOKEN="your_api_token_here"
   export GRAFANA_CLOUD_ORG_ID="your_org_id"
   ```

3. **Create monitoring namespace and secrets:**
   ```bash
   kubectl create namespace monitoring
   kubectl create secret generic grafana-cloud-credentials \
     --from-literal=api-token=$GRAFANA_CLOUD_API_TOKEN \
     --from-literal=org-id=$GRAFANA_CLOUD_ORG_ID \
     -n monitoring
   ```

4. **Deploy the monitoring stack:**
   ```bash
   kubectl apply -f k8s-app/monitoring.yaml
   ```

5. **Verify deployment:**
   ```bash
   # Check Alloy DaemonSet rollout
   kubectl rollout status daemonset/grafana-alloy -n monitoring --timeout=5m
   
   # Verify pod status
   kubectl get pods -n monitoring -l app=grafana-alloy
   
   # Check logs for connectivity
   kubectl logs -l app=grafana-alloy -n monitoring --tail=50
   ```

### Validation Checklist

- [ ] Alloy pods running on all nodes: `kubectl get pods -n monitoring -o wide`
- [ ] Zero errors in logs: `kubectl logs -l app=grafana-alloy -n monitoring | grep -i error`
- [ ] Metrics flowing to Grafana Cloud: Check "Data Sources" in Grafana UI
- [ ] Guestbook app accessible: `kubectl port-forward -n guestbook-spoke svc/nginx 8080:80`

---

## Technical Implementation

### 1. Telemetry Collection Architecture

**Grafana Alloy** acts as a lightweight agent deployed via DaemonSet, implementing three core functions:

#### Dynamic Service Discovery
```yaml
discovery.kubernetes {
  role = "pod"
  selectors = [
    {
      role  = "pod"
      label = "app=nginx,app=redis"
    },
  ]
}
```
- Automatically detects pod lifecycle events (creation, deletion, node migration)
- Eliminates static configuration drift
- Real-time adaptation to cluster topology changes

#### Metric Relabeling Pipeline
```yaml
prometheus.relabel "normalize_labels" {
  forward_to = [prometheus.remote_write.grafana_cloud.receiver]
  
  rule {
    source_labels = ["__meta_kubernetes_namespace"]
    target_label  = "namespace"
  }
  
  rule {
    source_labels = ["__meta_kubernetes_pod_name"]
    target_label  = "pod"
  }
}
```
- Transforms internal Kubernetes metadata into standardized labels
- Enables cross-cluster metric correlation
- Reduces cardinality explosion from pod IP addresses

#### TLS-Secured Remote Write
```yaml
prometheus.remote_write "grafana_cloud" {
  endpoint {
    url = "https://prometheus-blocks-prod-us-central1.grafana-cloud.com/api/prom/push"
    
    tls_config {
      server_name = "prometheus-blocks-prod-us-central1.grafana-cloud.com"
    }
    
    headers = {
      "X-Scope-OrgID" = env("GRAFANA_CLOUD_ORG_ID")
    }
  }
}
```

### 2. Golden Signals Implementation

| Signal | Metric | Source | Query |
|--------|--------|--------|-------|
| **Traffic** | `nginx_ingress_requests_total` | Nginx scrape | `rate(nginx_requests_total[5m])` |
| **Saturation** | `container_memory_usage_bytes` | Kubelet | `container_memory_usage_bytes{pod=~".*"}` |
| **Errors** | `nginx_ingress_requests_total{status=~"4..\|5.."}` | Nginx | `rate(requests_total{status=~"[45].."}[5m])` |
| **Availability** | `up{job="kubelet"}` | Kubelet probe | `up{namespace="guestbook-spoke"}` |

### 3. Security Model

#### RBAC Principle of Least Privilege
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: grafana-alloy
rules:
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["grafana-cloud-credentials"]
  verbs: ["get"]
```

**Permissions Granted:**
- `pods.get, list, watch` - Service discovery only
- `nodes.get, list, watch` - Node-level telemetry
- `secrets.get` - Credential retrieval (scoped to specific secret)

**Permissions Denied:**
- No pod creation/deletion
- No secret modification
- No cluster administrative access

#### Data Protection
- **In-Transit**: TLS 1.2+ for Prometheus Remote Write
- **In-Storage**: Encrypted at Grafana Cloud (managed)
- **Credential Management**: Kubernetes Secrets with restricted RBAC

---

## Configuration Guide

### Core Configuration File: `k8s-app/monitoring.yaml`

**Key sections:**

1. **Namespace & RBAC** - `monitoring` namespace with service account and ClusterRole bindings
2. **ConfigMap** - Alloy pipeline configuration (discovery, relabeling, remote write)
3. **DaemonSet** - Alloy deployment with resource limits and node affinity
4. **Secrets** - Grafana Cloud API credentials (created at install time)

### Environment Variables

| Variable | Required | Example | Purpose |
|----------|----------|---------|---------|
| `GRAFANA_CLOUD_API_TOKEN` | Yes | `glc_xxxxx` | Authentication to Grafana Cloud |
| `GRAFANA_CLOUD_ORG_ID` | Yes | `12345` | Tenant ID for metric routing |
| `ALLOY_LOG_LEVEL` | No | `info` | Debug logging (default: info) |

### Customization Examples

**Change cluster identifier:**
```yaml
rule {
  target_label = "cluster"
  replacement = "prod-us-east-1"
}
```

**Add namespace-level scrape interval:**
```yaml
discovery.kubernetes {
  role = "pod"
  namespaces = {
    names = ["guestbook-spoke", "default"]
  }
}
```

**Enable debug mode:**
```bash
kubectl set env daemonset/grafana-alloy ALLOY_LOG_LEVEL=debug -n monitoring
```

---

## Deployment & Operations

### Multi-Environment Deployment

**Dev/Staging:**
```bash
kubectl apply -f k8s-app/monitoring.yaml --context=staging-cluster
```

**Production:**
```bash
# Blue-green deployment strategy
kubectl apply -f k8s-app/monitoring.yaml --context=prod-us-east-1
kubectl apply -f k8s-app/monitoring.yaml --context=prod-us-west-2
```

### Health Checks

```bash
# Real-time metric count
kubectl exec -it -n monitoring daemonset/grafana-alloy -- \
  curl localhost:12345/metrics | grep prometheus_remote_write_

# Check node coverage
kubectl get daemonset -n monitoring grafana-alloy -o wide

# View recent errors
kubectl logs -n monitoring -l app=grafana-alloy --tail=100 | grep -i "error\|failed"
```

### Scaling Considerations

- **DaemonSet**: One pod per node (automatic scaling with cluster growth)
- **Memory per pod**: ~150-250MB typical; configure via `resources.limits`
- **Network bandwidth**: ~100KB/s per node (typical production)
- **Cardinality management**: Monitor metric count in Grafana Cloud dashboard

---

## Troubleshooting

### Alloy Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n monitoring -l app=grafana-alloy

# Verify resource availability
kubectl top nodes
kubectl top pods -n monitoring

# Check for scheduling constraints
kubectl get nodes --show-labels
```

### Metrics Not Appearing in Grafana

1. **Verify connectivity:**
   ```bash
   kubectl logs -n monitoring -l app=grafana-alloy | grep "Remote write started"
   ```

2. **Check authentication:**
   ```bash
   kubectl get secret -n monitoring grafana-cloud-credentials -o yaml
   ```

3. **Validate configuration:**
   ```bash
   kubectl get cm -n monitoring grafana-alloy-config -o yaml
   ```

### High Memory Usage

- Increase scrape interval: `prometheus.scrape.kubernetes { scrape_interval = "60s" }`
- Reduce label cardinality: Drop unnecessary labels in relabeling rules
- Monitor pod memory: `kubectl top pods -n monitoring`

---

## Roadmap

### ✅ Phase 1: Core Observability (Complete)
- [x] Multi-tier Application Deployment (Nginx + Redis)
- [x] Grafana Alloy Pipeline Integration
- [x] Kubernetes Service Discovery
- [x] Metric Relabeling & Label Normalization
- [x] TLS-secured Remote Write to Grafana Cloud
- [x] RBAC Security Model

### 🔄 Phase 2: GitOps & Automation (In Progress)
- [ ] ArgoCD Deployment & Application Repository
- [ ] Automated Application Sync with Health Checks
- [ ] Manual Sync Gating (approval workflow)
- [ ] Rollback Automation on Failed Deployments
- [ ] SLA tracking dashboard

### 📅 Phase 3: Intelligent Auto-Remediation (Planned Q2 2026)
- [ ] Horizontal Pod Autoscaler (HPA) based on SRE metrics
- [ ] Custom metrics adapter for Grafana cloud
- [ ] Automated node-level remediation policies
- [ ] Cross-cluster failover orchestration

### 🚀 Phase 4: Advanced Observability (Future)
- [ ] Distributed tracing integration (Tempo)
- [ ] Log aggregation pipeline (Loki)
- [ ] Anomaly detection with ML models
- [ ] Cost optimization recommendations

---

## Contributing & Support

### Report Issues
- **Bugs**: GitHub Issues with reproduction steps and logs
- **Features**: Discussion section with use-case context

### Local Development
```bash
# Validate YAML syntax
kubectl apply -f k8s-app/monitoring.yaml --dry-run=client

# Test on kind cluster
kind create cluster --name eagle-eye-test
kubectl apply -f k8s-app/monitoring.yaml
```

### Code Review Standards
- YAML linting (yamllint)
- RBAC validation (kubectl auth can-i)
- Resource quota compliance
- Security scanning before merge

---

## References & Documentation

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [Prometheus Remote Write Spec](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)
- [Kubernetes API Discovery](https://kubernetes.io/docs/concepts/services-networking/service/#discovering-services)
- [SRE Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/)

---

**Maintained by:** [@KrishnaKondra18](https://github.com/KrishnaKondra18)  
**Last Updated:** January 2026  
**Status:** Active Development
