# Arquitectura Técnica

## Visión General

Este documento describe la arquitectura técnica del sistema Backstage GitOps, incluyendo componentes, flujos de datos y decisiones de diseño.

## Componentes Principales

### 1. Cluster Kubernetes (kind)
- **Propósito**: Proporcionar un entorno Kubernetes local para desarrollo y pruebas
- **Configuración**: Single-node cluster con ingress controller
- **Namespaces**:
  - `argocd`: ArgoCD y sus componentes
  - `backstage-system`: Aplicación Backstage
  - `kube-system`: Componentes del sistema Kubernetes

### 2. ArgoCD (GitOps Controller)
- **Versión**: Latest stable
- **Componentes**:
  - `argocd-application-controller`: Gestiona aplicaciones
  - `argocd-repo-server`: Servidor de repositorios
  - `argocd-server`: API y UI de ArgoCD
- **Configuración**: Auto-sync habilitado, prune automático

### 3. Backstage Application
- **Frontend**: Puerto 8000 (NodePort)
- **Backend**: Puerto 4001 (ClusterIP)
- **Base de datos**: SQLite en memoria (desarrollo)
- **Configuración**: Gestionada vía ConfigMaps

### 4. CI/CD Pipeline (GitHub Actions)
- **Triggers**: Push a main, Pull Requests
- **Pasos**:
  1. Build de Backstage
  2. Construcción de imagen Docker
  3. Push a DockerHub
  4. Actualización del Helm chart
  5. Commit automático

## Flujo de Datos

### Despliegue Inicial
```
GitHub Repo → ArgoCD Application → Helm Chart → Kubernetes Resources
```

### Actualización Continua
```
Código → GitHub Actions → DockerHub → ArgoCD Sync → Kubernetes Update
```

### Acceso Usuario
```
Usuario → Ingress (80/443) → Service → Pod → Backstage App
```

## Decisiones de Diseño

### 1. Elección de kind
- **Razón**: Entorno local consistente y reproducible
- **Alternativas consideradas**: minikube, k3s
- **Ventajas**: Rápido setup, integración con Docker

### 2. ArgoCD como GitOps Tool
- **Razón**: Declarative GitOps, integración nativa con Kubernetes
- **Alternativas consideradas**: Flux, Jenkins X
- **Ventajas**: UI intuitiva, amplio soporte de comunidad

### 3. Helm Charts
- **Razón**: Empaquetado y versionado de aplicaciones Kubernetes
- **Estructura**: Chart reusable con valores configurables
- **Ventajas**: Mantenibilidad, reusabilidad

### 4. Multi-stage Docker Build
- **Razón**: Optimización de tamaño de imagen y seguridad
- **Etapas**:
  - `base`: Instalación de dependencias
  - `production`: Imagen final optimizada
- **Ventajas**: Imágenes más pequeñas, mejor seguridad

### 5. ConfigMaps para Configuración
- **Razón**: Separación de código y configuración
- **Implementación**: app-config.yaml inyectado como volumen
- **Ventajas**: Configuración externalizada, hot-reload

## Diagramas de Arquitectura

### Diagrama de Componentes
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Developer     │    │   GitHub        │    │   DockerHub     │
│   Workstation   │────│   Actions       │────│   Registry      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │   ArgoCD        │    │   Kubernetes    │
│   (GitOps)      │────│   Application   │────│   Cluster       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                     │
                                                     ▼
                                           ┌─────────────────┐
                                           │   Backstage     │
                                           │   Application   │
                                           └─────────────────┘
```

### Diagrama de Red
```
Internet
    │
    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Ingress   │─────│  Services   │─────│    Pods     │
│  (80/443)   │     │ (ClusterIP) │     │ (Backstage) │
└─────────────┘     └─────────────┘     └─────────────┘
    │                       │
    │                       │
    ▼                       ▼
┌─────────────┐     ┌─────────────┐
│ Frontend    │     │ Backend     │
│ (Port 8000) │     │ (Port 4001) │
└─────────────┘     └─────────────┘
```

## Seguridad

### Principios
- **Least Privilege**: Mínimos permisos necesarios
- **Secrets Management**: Credenciales en Kubernetes secrets
- **Network Policies**: Segmentación de tráfico (futuro)
- **Image Security**: Scans automáticos (futuro)

### Configuración Actual
- Service accounts con RBAC mínimo
- Secrets para credenciales sensibles
- Non-root containers
- Read-only root filesystem donde sea posible

## Escalabilidad

### Limitaciones Actuales
- Single-node cluster (kind)
- SQLite como base de datos
- Recursos limitados del host

### Mejoras Futuras
- Multi-node cluster
- PostgreSQL/MySQL
- Horizontal Pod Autoscaling
- Ingress controller avanzado

## Monitoreo y Observabilidad

### Métricas Actuales
- Health checks HTTP
- Liveness/Readiness probes
- Logs de aplicación

### Mejoras Futuras
- Prometheus metrics
- Grafana dashboards
- Distributed tracing
- Log aggregation

## Dependencias Externas

| Servicio | Propósito | Configuración |
|----------|-----------|---------------|
| DockerHub | Registry de imágenes | Credenciales en secrets |
| GitHub | Control de versiones | Token en secrets |
| GitHub Actions | CI/CD | Configurado en repo |

## Variables de Configuración

### Helm Values
```yaml
image:
  repository: your-dockerhub-username/backstage-gitops
  tag: "latest"

service:
  type: ClusterIP
  ports:
    - name: backend
      port: 4001
    - name: frontend
      port: 8000

env:
  - name: BACKSTAGE_BASE_URL
    value: "http://localhost:8000"
```

### ConfigMap (app-config.yaml)
```yaml
app:
  title: Backstage GitOps
  baseUrl: http://localhost:8000

backend:
  baseUrl: http://localhost:4001
  listen:
    port: 4001

integrations:
  github:
    - host: github.com
      token: ${GITHUB_TOKEN}
```

## Próximos Pasos

1. **Implementar ApplicationSets** para entornos múltiples
2. **Agregar monitoring** con Prometheus/Grafana
3. **Configurar backup** de base de datos
4. **Implementar network policies** para seguridad
5. **Agregar tests automatizados** en el pipeline
6. **Configurar HTTPS** con cert-manager