# 🐳 INFRAESTRUCTURA DOCKER COMPOSE - SISTEMA DIGITAL TWINS

Orquestación completa del sistema con Docker Compose, incluyendo API Gateway Nginx y publicación automática a Docker Hub.

## 📋 **Contenido**

Este directorio contiene:
- `docker-compose.yml` - Orquestación completa del sistema
- `nginx.conf` - Configuración del API Gateway
- `build-and-push.sh` - Script para subir imágenes a Docker Hub
- `env.example` - Variables de entorno de ejemplo
- `README.md` - Este archivo

---

## 🏗️ **Arquitectura**

```
┌─────────────────┐
│   Frontend      │  Puerto 3000
│   React + Nginx│
└────────┬────────┘
         │
┌────────▼────────┐
│  API Gateway    │  Puerto 8080
│  Nginx          │
└────────┬────────┘
         │
    ┌────┴────┬────────┬────────┐
    │         │        │        │
┌───▼───┐ ┌──▼──┐ ┌───▼──┐ ┌───▼──┐
│MS-AUTH│ │MS-GEO│ │MS-USER│ │MS-REP│
│ :8001 │ │:8003 │ │ :8002 │ │:8004 │
└───┬───┘ └──┬──┘ └───┬──┘ └───┬──┘
    └────────┴────────┴────────┘
              │
         ┌────▼─────┐
         │PostgreSQL│  Puerto 5437
         │+ PostGIS │
         └──────────┘
```

---

## 🚀 **Inicio Rápido**

### **Opción 1: Usar Imágenes de Docker Hub (Más Rápido)**

```bash
# 1. Ir al directorio de compose
cd INFRA-LOG-DK/compose

# 2. Copiar archivo de configuración
cp env.example .env

# 3. (Opcional) Editar .env con tus valores
nano .env

# 4. Levantar todo el stack
docker-compose up -d

# 5. Ver logs
docker-compose logs -f

# 6. Verificar estado
docker-compose ps
```

**Acceso**:
- Frontend: http://localhost:3000
- API Gateway: http://localhost:8080
- Swagger Docs: http://localhost:8080/docs/auth (auth, geo, users, reports)

**Login**: admin@digitaltwins.com / admin123
```

---

## 🔧 **Comandos Útiles**

### **Gestión del Stack**

```bash
# Levantar todo
docker-compose up -d

# Levantar con rebuild
docker-compose up -d --build

# Ver logs de todos los servicios
docker-compose logs -f

# Ver logs de un servicio específico
docker-compose logs -f ms-auth-py

# Ver estado de los servicios
docker-compose ps

# Parar todo
docker-compose stop

# Parar y eliminar contenedores
docker-compose down

# Parar, eliminar contenedores y volúmenes
docker-compose down -v

# Reiniciar un servicio específico
docker-compose restart ms-user-py
```

### **Verificación de Health Checks**

```bash
# API Gateway
curl http://localhost:8080/health

# Microservicios individuales
curl http://localhost:8001/health  # MS-AUTH
curl http://localhost:8003/health  # MS-GEO
curl http://localhost:8002/health  # MS-USER
curl http://localhost:8004/health  # MS-REPORT

# Frontend
curl http://localhost:3000
```

### **Acceso a PostgreSQL**

```bash
# Conectarse a la base de datos
docker exec -it postgres-db psql -U dgt_user -d digital_twins_db

# Dentro de PostgreSQL
\dt               # Listar tablas
\d+ users        # Ver estructura de tabla
SELECT * FROM cities;
\q               # Salir
```

### **Inspeccionar Contenedores**

```bash
# Ver logs en tiempo real
docker-compose logs -f --tail=100

# Entrar a un contenedor
docker exec -it ms-auth-py sh

# Ver recursos utilizados
docker stats

# Ver redes
docker network ls
docker network inspect digital-twins-network
```

---

## 🌐 **API Gateway - Nginx**

El API Gateway enruta las peticiones a los microservicios correspondientes:

| Ruta | Microservicio | Ejemplo |
|------|---------------|---------|
| `/api/v1/auth/*` | MS-AUTH-PY | http://localhost:8080/api/v1/auth/login |
| `/api/v1/geo/*` | MS-GEO-PY | http://localhost:8080/api/v1/geo/cities |
| `/api/v1/users/*` | MS-USER-PY | http://localhost:8080/api/v1/users/sellers |
| `/api/v1/reports/*` | MS-REPORT-PY | http://localhost:8080/api/v1/reports/metrics |

### **CORS**

El API Gateway está configurado para permitir CORS desde cualquier origen. En producción, ajustar en `nginx.conf`.

---

## 📊 **Dependencias entre Servicios**

El `docker-compose.yml` maneja las dependencias automáticamente:

```
postgres-db (primero)
    ↓
ms-auth-py
    ↓
ms-geo-py
    ↓
ms-user-py
    ↓
ms-report-py
    ↓
api-gateway
    ↓
frontend (último)
```

Todos los servicios esperan a que sus dependencias estén "healthy" antes de iniciar.

---

## 🔐 **Configuración de Seguridad**

### **Variables de Entorno Importantes**

Editar `.env` antes de desplegar en producción:

```env
# Cambiar esta clave en producción
SECRET_KEY=generar-clave-aleatoria-de-minimo-32-caracteres

# Contraseña de base de datos
POSTGRES_PASSWORD=cambiar-en-produccion

# Token de acceso
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

### **Generar SECRET_KEY Segura**

```bash
# Linux/Mac
openssl rand -hex 32

# Python
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

---

## 📈 **Monitoreo**

### **Health Checks**

Todos los servicios tienen health checks configurados:

```bash
# Ver estado de health checks
docker-compose ps

# Estado detallado
docker inspect ms-auth-py | grep -A 10 Health
```

### **Logs Centralizados**

```bash
# Ver logs de todos los servicios
docker-compose logs -f

# Filtrar por servicio
docker-compose logs -f ms-user-py api-gateway

# Ver últimas 100 líneas
docker-compose logs --tail=100
```

---

## 🐛 **Troubleshooting**

### **Problema: Servicio no inicia**

```bash
# Ver logs del servicio
docker-compose logs ms-auth-py

# Verificar que las dependencias estén healthy
docker-compose ps

# Reiniciar servicio específico
docker-compose restart ms-auth-py
```

### **Problema: Puerto ya en uso**

```bash
# Linux/Mac - Ver qué usa el puerto
lsof -i :8080
kill -9 <PID>

# Cambiar puertos en .env
nano .env
```

### **Problema: Base de datos no conecta**

```bash
# Verificar que postgres-db esté healthy
docker-compose ps postgres-db

# Ver logs de postgres
docker-compose logs postgres-db

# Reiniciar base de datos
docker-compose restart postgres-db

# Recrear desde cero
docker-compose down -v
docker-compose up -d
```
## 🎯 **Siguiente Pasos**

1. **Ejecutar el sistema**:
   ```bash
   docker-compose up -d
   ```

2. **Acceder al frontend**: http://localhost:3000

3. **Login**: admin@digitaltwins.com / admin123

4. **Explorar**:
   - Dashboard
   - Mapa interactivo
   - Gestión de vendedores
   - Gestión de tenderos
   - Reportes y análisis

---

**Versión**: 1.0.0  
**Última actualización**: Octubre 2025  
**Mantenido por**: Equipo Digital Twins

