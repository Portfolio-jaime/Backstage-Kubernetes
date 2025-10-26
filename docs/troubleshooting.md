# Guía de Troubleshooting y Recuperación

Esta guía proporciona soluciones a problemas comunes que pueden surgir durante el despliegue y operación del entorno Backstage GitOps.

## Problemas Comunes y Soluciones

### 1. Cluster kind no se crea

**Síntomas:**
- Error al ejecutar `./kind-setup.sh`
- Mensajes de error relacionados con Docker

**Soluciones:**

**Verificar Docker:**
```bash
# Verificar que Docker esté corriendo
docker info

# Verificar espacio en disco
docker system df

# Limpiar imágenes no utilizadas
docker system prune -a
```

**Verificar configuración de kind:**
```bash
# Verificar archivo de configuración
cat infra/kind/kind-config.yaml

# Verificar puertos disponibles
netstat -tulpn | grep -E ':80|:443|:8000|:4001'
```

**Recrear cluster:**
```bash
# Eliminar cluster existente
kind delete cluster --name backstage-gitops

# Recrear cluster
./kind-setup.sh
```

### 2. ArgoCD no se instala correctamente

**Síntomas:**
- Pods de ArgoCD no se crean
- Error en `kubectl get pods -n argocd`

**Soluciones:**

**Verificar instalación:**
```bash
# Verificar estado de ArgoCD
kubectl get all -n argocd

# Verificar logs de instalación
kubectl logs -n argocd deployment/argocd-application-controller

# Reinstalar ArgoCD
kubectl delete -f infra/argocd/install.yaml
kubectl apply -f infra/argocd/install.yaml
```

**Verificar contraseña inicial:**
```bash
# Obtener contraseña de admin
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

**Acceder a ArgoCD UI:**
```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Acceder en: https://localhost:8080
# Usuario: admin
# Contraseña: [contraseña obtenida arriba]
```

### 3. Backstage no se sincroniza en ArgoCD

**Síntomas:**
- Aplicación ArgoCD muestra estado "OutOfSync"
- Backstage no se despliega

**Soluciones:**

**Verificar estado de aplicación:**
```bash
# Verificar aplicaciones ArgoCD
kubectl get applications -n argocd

# Ver detalles de aplicación
kubectl describe application backstage -n argocd
```

**Forzar sincronización:**
```bash
# Sincronización manual
kubectl patch application backstage -n argocd --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Ver logs de sincronización
kubectl logs -n argocd deployment/argocd-application-controller --follow
```

**Verificar repositorio:**
```bash
# Verificar configuración de repositorio en ArgoCD
kubectl get configmap argocd-cm -n argocd -o yaml

# Actualizar URL del repositorio si es necesario
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"repositories":"- type: git\n  url: https://github.com/your-org/backstage-gitops\n  name: backstage-gitops"}}'
```

### 4. Backstage no inicia correctamente

**Síntomas:**
- Pods de Backstage en estado CrashLoopBackOff
- Errores en logs de Backstage

**Soluciones:**

**Verificar logs:**
```bash
# Ver logs de Backstage
kubectl logs -n backstage-system deployment/backstage --follow

# Ver logs anteriores
kubectl logs -n backstage-system deployment/backstage --previous
```

**Verificar configuración:**
```bash
# Verificar ConfigMap
kubectl get configmap -n backstage-system
kubectl describe configmap backstage-config -n backstage-system

# Verificar Secrets
kubectl get secrets -n backstage-system
```

**Verificar recursos:**
```bash
# Verificar límites de recursos
kubectl describe pod -n backstage-system -l app.kubernetes.io/name=backstage

# Verificar eventos
kubectl get events -n backstage-system --sort-by=.metadata.creationTimestamp
```

**Reiniciar despliegue:**
```bash
# Reiniciar pods
kubectl rollout restart deployment/backstage -n backstage-system

# Forzar re-despliegue
kubectl delete pod -n backstage-system -l app.kubernetes.io/name=backstage
```

### 5. Problemas de conectividad de red

**Síntomas:**
- No se puede acceder a Backstage en localhost:8000
- Errores de conexión

**Soluciones:**

**Verificar port forwarding:**
```bash
# Verificar port forwarding activo
kubectl port-forward svc/backstage -n backstage-system 8000:8000

# En otra terminal
curl http://localhost:8000
```

**Verificar servicios:**
```bash
# Verificar servicios
kubectl get services -n backstage-system

# Verificar endpoints
kubectl get endpoints -n backstage-system
```

**Verificar configuración de kind:**
```bash
# Verificar configuración de puertos en kind
docker ps | grep backstage-gitops

# Verificar port mapping
docker port backstage-gitops-control-plane
```

### 6. Problemas con CI/CD

**Síntomas:**
- GitHub Actions falla
- Imágenes Docker no se construyen

**Soluciones:**

**Verificar secrets de GitHub:**
```bash
# Verificar que los secrets estén configurados en GitHub
# Settings > Secrets and variables > Actions
# - DOCKERHUB_USERNAME
# - DOCKERHUB_PASSWORD
# - GITHUB_TOKEN (automático)
```

**Verificar workflow:**
```bash
# Verificar sintaxis del workflow
.github/workflows/ci-cd.yaml

# Ver logs de GitHub Actions
# Ir a la pestaña Actions en GitHub
```

**Verificar Docker build:**
```bash
# Probar build local
cd backstage
docker build -t backstage-test .

# Verificar Dockerfile
cat Dockerfile
```

### 7. Problemas de base de datos

**Síntomas:**
- Errores de SQLite
- Datos no persisten

**Soluciones:**

**Para desarrollo (SQLite):**
```bash
# Verificar permisos de archivo
kubectl exec -n backstage-system deployment/backstage -- ls -la /app/

# Reiniciar para recrear base de datos
kubectl rollout restart deployment/backstage -n backstage-system
```

**Para producción (PostgreSQL):**
```bash
# Verificar conexión a base de datos externa
kubectl logs -n backstage-system deployment/backstage | grep -i postgres

# Verificar configuración de base de datos
kubectl get configmap backstage-config -n backstage-system -o yaml
```

## Comandos de Diagnóstico

### Verificación General del Sistema
```bash
# Verificar estado general
kubectl cluster-info

# Verificar nodos
kubectl get nodes -o wide

# Verificar namespaces
kubectl get namespaces

# Verificar recursos por namespace
kubectl get all -n backstage-system
kubectl get all -n argocd
```

### Monitoreo de Recursos
```bash
# Verificar uso de recursos
kubectl top nodes
kubectl top pods -n backstage-system

# Verificar límites de recursos
kubectl describe pod -n backstage-system -l app.kubernetes.io/name=backstage
```

### Logs Centralizados
```bash
# Logs de ArgoCD
kubectl logs -n argocd deployment/argocd-application-controller --tail=100
kubectl logs -n argocd deployment/argocd-repo-server --tail=100

# Logs de Backstage
kubectl logs -n backstage-system deployment/backstage --tail=100 --follow

# Logs de todos los componentes
kubectl logs -n backstage-system -l app.kubernetes.io/name=backstage --tail=50
```

### Debugging de Red
```bash
# Verificar conectividad dentro del clúster
kubectl run test-pod --image=busybox --rm -it -- sh
# Dentro del pod: wget http://backstage.backstage-system.svc.cluster.local:4001/healthcheck

# Verificar DNS
kubectl run test-pod --image=busybox --rm -it -- nslookup backstage.backstage-system.svc.cluster.local

# Verificar network policies (si existen)
kubectl get networkpolicies -n backstage-system
```

## Procedimientos de Recuperación

### Recuperación Completa del Sistema
```bash
# 1. Limpiar todo
./cleanup.sh

# 2. Recrear clúster
./kind-setup.sh

# 3. Reinstalar todo
./bootstrap.sh

# 4. Verificar
./check-cluster.sh
```

### Recuperación de ArgoCD
```bash
# 1. Eliminar ArgoCD
kubectl delete namespace argocd --ignore-not-found=true

# 2. Reinstalar
kubectl apply -f infra/argocd/install.yaml

# 3. Recrear aplicación
kubectl apply -f infra/argocd/backstage-application.yaml
```

### Recuperación de Backstage
```bash
# 1. Eliminar despliegue actual
kubectl delete -f infra/argocd/backstage-application.yaml

# 2. Limpiar recursos
kubectl delete namespace backstage-system --ignore-not-found=true

# 3. Recrear
kubectl apply -f infra/argocd/backstage-application.yaml
```

## Scripts de Utilidad

### Script de Verificación de Salud
```bash
#!/bin/bash
# check-health.sh

echo "🔍 Health Check Report"
echo "======================"

# Check cluster
echo ""
echo "📊 Cluster Status:"
kubectl cluster-info 2>/dev/null || echo "❌ Cluster not accessible"

# Check ArgoCD
echo ""
echo "🎯 ArgoCD Status:"
if kubectl get namespace argocd >/dev/null 2>&1; then
    kubectl get applications -n argocd
else
    echo "❌ ArgoCD namespace not found"
fi

# Check Backstage
echo ""
echo "🎭 Backstage Status:"
if kubectl get namespace backstage-system >/dev/null 2>&1; then
    kubectl get pods -n backstage-system
    kubectl get services -n backstage-system
else
    echo "❌ Backstage namespace not found"
fi

# Check connectivity
echo ""
echo "🌐 Connectivity Check:"
if kubectl run test-conn --image=curlimages/curl --rm -i --restart=Never -- curl -f http://backstage.backstage-system.svc.cluster.local:4001/healthcheck 2>/dev/null; then
    echo "✅ Backstage health check passed"
else
    echo "❌ Backstage health check failed"
fi
```

### Script de Limpieza
```bash
#!/bin/bash
# cleanup.sh

echo "🧹 Cleaning up Backstage GitOps environment..."

# Delete ArgoCD application
kubectl delete -f infra/argocd/backstage-application.yaml --ignore-not-found=true

# Delete ArgoCD
kubectl delete -f infra/argocd/install.yaml --ignore-not-found=true

# Delete namespaces
kubectl delete namespace backstage-system --ignore-not-found=true
kubectl delete namespace argocd --ignore-not-found=true

# Delete kind cluster
kind delete cluster --name backstage-gitops

echo "✅ Cleanup completed!"
```

## Mejores Prácticas de Troubleshooting

1. **Siempre verificar logs primero**
2. **Usar `kubectl describe` para detalles**
3. **Verificar eventos con `kubectl get events`**
4. **Aislar componentes para testing**
5. **Documentar cambios y soluciones**
6. **Mantener backups de configuraciones**

## Contacto y Soporte

Para soporte adicional:
- Revisar issues en GitHub
- Consultar documentación de Backstage
- Revisar documentación de ArgoCD
- Contactar al equipo de DevOps

## Referencias

- [Documentación de Backstage](https://backstage.io/docs)
- [Documentación de ArgoCD](https://argo-cd.readthedocs.io/)
- [Documentación de kind](https://kind.sigs.k8s.io/)
- [Documentación de Kubernetes](https://kubernetes.io/docs/)