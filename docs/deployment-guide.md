# Guía de Despliegue

Esta guía proporciona instrucciones paso a paso para desplegar el entorno Backstage GitOps en un clúster Kubernetes local usando kind y ArgoCD.

## Prerrequisitos

### Herramientas Requeridas
- **Docker**: Para ejecutar contenedores y kind
- **kubectl**: CLI para Kubernetes
- **kind**: Para crear clústeres Kubernetes locales
- **helm**: Para gestionar charts de Kubernetes
- **yarn**: Para gestión de dependencias de Node.js
- **git**: Para control de versiones

### Verificación de Prerrequisitos
```bash
# Verificar Docker
docker --version

# Verificar kubectl
kubectl version --client

# Verificar kind
kind --version

# Verificar helm
helm version

# Verificar yarn
yarn --version

# Verificar git
git --version
```

### Configuración del Entorno
```bash
# Configurar kubectl para usar Docker Desktop (macOS/Windows)
kubectl config use-context docker-desktop

# O configurar para kind (si ya tienes un clúster corriendo)
kubectl config use-context kind-backstage-gitops
```

## Configuración Inicial

### 1. Clonar el Repositorio
```bash
git clone https://github.com/your-org/backstage-gitops.git
cd backstage-gitops
```

### 2. Configurar Credenciales
Crea un archivo `.env` o configura las variables de entorno necesarias:

```bash
# Variables de entorno requeridas
export GITHUB_TOKEN=your_github_token
export DOCKERHUB_USERNAME=your_dockerhub_username
export DOCKERHUB_PASSWORD=your_dockerhub_password
```

### 3. Crear Secrets de Kubernetes
```bash
# Crear namespace para Backstage
kubectl create namespace backstage-system

# Crear secret con credenciales
kubectl create secret generic backstage-secrets \
  --from-literal=github-token=$GITHUB_TOKEN \
  --from-literal=dockerhub-username=$DOCKERHUB_USERNAME \
  --from-literal=dockerhub-password=$DOCKERHUB_PASSWORD \
  -n backstage-system
```

## Despliegue Paso a Paso

### Paso 1: Crear Cluster kind
```bash
# Crear clúster con configuración personalizada
kind create cluster --config infra/kind/kind-config.yaml --name backstage-gitops

# Verificar que el clúster esté corriendo
kubectl cluster-info --context kind-backstage-gitops
```

### Paso 2: Instalar ArgoCD
```bash
# Aplicar manifiestos de ArgoCD
kubectl apply -f infra/argocd/install.yaml

# Esperar a que los pods estén ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Obtener contraseña inicial de ArgoCD
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

### Paso 3: Acceder a ArgoCD UI (Opcional)
```bash
# Port forward para acceder a ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Acceder en: https://localhost:8080
# Usuario: admin
# Contraseña: [contraseña del paso anterior]
```

### Paso 4: Desplegar Backstage
```bash
# Aplicar la aplicación ArgoCD
kubectl apply -f infra/argocd/backstage-application.yaml

# Verificar estado de sincronización
kubectl get applications -n argocd

# Esperar a que Backstage esté desplegado
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=backstage -n backstage-system --timeout=600s
```

### Paso 5: Verificar Despliegue
```bash
# Verificar pods
kubectl get pods -n backstage-system

# Verificar servicios
kubectl get services -n backstage-system

# Verificar deployments
kubectl get deployments -n backstage-system
```

### Paso 6: Acceder a Backstage
```bash
# Port forward para acceder a Backstage
kubectl port-forward svc/backstage -n backstage-system 8000:8000

# Acceder en: http://localhost:8000
```

## Configuración de CI/CD

### Configurar GitHub Secrets
En tu repositorio de GitHub, configura los siguientes secrets:

1. Ve a **Settings** > **Secrets and variables** > **Actions**
2. Agrega los siguientes secrets:
   - `DOCKERHUB_USERNAME`: Tu usuario de DockerHub
   - `DOCKERHUB_PASSWORD`: Tu contraseña/token de DockerHub
   - `GITHUB_TOKEN`: Token de GitHub (automático)

### Primer Push
```bash
# Hacer commit inicial
git add .
git commit -m "Initial commit: Backstage GitOps setup"

# Push para activar CI/CD
git push origin main
```

### Verificar CI/CD
1. Ve a la pestaña **Actions** en GitHub
2. Deberías ver el workflow ejecutándose
3. Una vez completado, la imagen Docker se publicará en DockerHub
4. ArgoCD detectará el cambio y actualizará automáticamente

## Desarrollo Local

### Opción 1: Con DevContainer
1. Abre el proyecto en VS Code
2. Cuando se pregunte, haz clic en "Reopen in Container"
3. El entorno se configurará automáticamente

### Opción 2: Configuración Manual
```bash
# Instalar dependencias
cd backstage
yarn install

# Ejecutar en modo desarrollo
yarn start

# Acceder en: http://localhost:3000
```

## Troubleshooting

### Problemas Comunes

#### 1. Cluster kind no se crea
```bash
# Verificar Docker está corriendo
docker ps

# Limpiar clústers existentes
kind delete clusters --all

# Reintentar creación
kind create cluster --config infra/kind/kind-config.yaml --name backstage-gitops
```

#### 2. ArgoCD no instala correctamente
```bash
# Verificar estado de pods
kubectl get pods -n argocd

# Ver logs de ArgoCD
kubectl logs -n argocd deployment/argocd-application-controller

# Reinstalar si es necesario
kubectl delete -f infra/argocd/install.yaml
kubectl apply -f infra/argocd/install.yaml
```

#### 3. Backstage no se sincroniza
```bash
# Verificar estado de aplicación ArgoCD
kubectl get applications -n argocd backstage -o yaml

# Forzar sincronización
kubectl patch application backstage -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

#### 4. Problemas de conectividad
```bash
# Verificar servicios
kubectl get services -n backstage-system

# Verificar endpoints
kubectl get endpoints -n backstage-system

# Verificar logs de Backstage
kubectl logs -n backstage-system deployment/backstage
```

### Comandos de Debug

```bash
# Ver todos los recursos
kubectl get all -n backstage-system

# Ver eventos recientes
kubectl get events -n backstage-system --sort-by=.metadata.creationTimestamp

# Ver logs detallados
kubectl logs -n backstage-system deployment/backstage --follow

# Ver configuración de ArgoCD
kubectl get applications -n argocd -o wide

# Ver estado del clúster
kubectl cluster-info
```

## Scripts de Automatización

### Script de Bootstrap (bootstrap.sh)
```bash
#!/bin/bash
set -e

echo "🚀 Starting Backstage GitOps bootstrap..."

# Crear clúster
echo "📦 Creating kind cluster..."
kind create cluster --config infra/kind/kind-config.yaml --name backstage-gitops

# Instalar ArgoCD
echo "⚙️ Installing ArgoCD..."
kubectl apply -f infra/argocd/install.yaml

# Esperar ArgoCD
echo "⏳ Waiting for ArgoCD..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Desplegar Backstage
echo "🎯 Deploying Backstage..."
kubectl apply -f infra/argocd/backstage-application.yaml

echo "✅ Bootstrap complete!"
echo "🌐 Access Backstage at: http://localhost:8000"
echo "🔧 Access ArgoCD at: https://localhost:8080"
```

### Script de Limpieza
```bash
#!/bin/bash

echo "🧹 Cleaning up Backstage GitOps environment..."

# Eliminar aplicación ArgoCD
kubectl delete -f infra/argocd/backstage-application.yaml --ignore-not-found=true

# Eliminar ArgoCD
kubectl delete -f infra/argocd/install.yaml --ignore-not-found=true

# Eliminar namespace
kubectl delete namespace backstage-system --ignore-not-found=true
kubectl delete namespace argocd --ignore-not-found=true

# Eliminar clúster
kind delete cluster --name backstage-gitops

echo "✅ Cleanup complete!"
```

## Configuración Avanzada

### Personalizar Helm Values
Edita `charts/backstage/values.yaml` para personalizar:

```yaml
# Cambiar imagen
image:
  repository: your-registry/backstage
  tag: "v1.0.0"

# Cambiar recursos
resources:
  limits:
    cpu: 500m
    memory: 1Gi
  requests:
    cpu: 100m
    memory: 256Mi

# Configurar ingress
ingress:
  enabled: true
  hosts:
    - host: backstage.local
      paths:
        - path: /
```

### Configurar Base de Datos Externa
Para producción, configura PostgreSQL:

```yaml
# En values.yaml
env:
  - name: POSTGRES_HOST
    value: "postgres-service"
  - name: POSTGRES_PORT
    value: "5432"
  - name: POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: username
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: password
```

### Configurar HTTPS
```yaml
# Instalar cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# Configurar ingress con TLS
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: backstage-tls
      hosts:
        - backstage.yourdomain.com
```

## Monitoreo

### Health Checks
```bash
# Verificar health de Backstage
curl http://localhost:4001/healthcheck

# Verificar métricas de Kubernetes
kubectl top pods -n backstage-system
kubectl top nodes
```

### Logs Centralizados
```bash
# Ver logs en tiempo real
kubectl logs -n backstage-system deployment/backstage --follow

# Ver logs de ArgoCD
kubectl logs -n argocd deployment/argocd-application-controller --follow
```

## Próximos Pasos

Después del despliegue exitoso:

1. **Configurar integraciones**: GitHub, Jira, etc.
2. **Agregar plugins**: Catálogo de servicios, CI/CD, etc.
3. **Configurar autenticación**: OAuth, LDAP, etc.
4. **Implementar monitoreo**: Prometheus, Grafana
5. **Configurar backups**: Base de datos, configuraciones
6. **Documentar procesos**: Runbooks, procedimientos

## Soporte

Para soporte adicional:
- Revisa los logs de la aplicación
- Consulta la documentación de ArgoCD
- Revisa issues en GitHub
- Contacta al equipo de DevOps