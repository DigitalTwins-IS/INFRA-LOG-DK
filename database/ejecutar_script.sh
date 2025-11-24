set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detectar qué versión de Docker Compose está disponible
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "❌ Error: Docker Compose no está instalado"
    echo "   Instala Docker Compose o asegúrate de que Docker esté en el PATH"
    exit 1
fi

echo "🔧 Usando: $DOCKER_COMPOSE"

echo "=========================================="
echo "  Script de Ejecución SQL - Digital Twins"
echo "=========================================="
echo ""

# Función para verificar si la BD tiene datos
check_db_has_data() {
    echo "Verificando si la base de datos tiene datos..."
    DATA_COUNT=$(docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
    
    if [ "$DATA_COUNT" -gt "0" ]; then
        return 0  # Tiene datos
    else
        return 1  # No tiene datos
    fi
}

# Función para hacer backup
make_backup() {
    echo "📦 Creando backup de la base de datos..."
    BACKUP_FILE="backup_$(date +%Y%m%d_%H%M%S).sql"
    docker exec postgres-db pg_dump -U dgt_user digital_twins_db > "$BACKUP_FILE"
    echo "✅ Backup creado: $BACKUP_FILE"
}

# Función para verificar visitas
verify_visits() {
    echo ""
    echo "📊 Verificando visitas insertadas..."
    VISITAS_COUNT=$(docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM visits;" 2>/dev/null | tr -d ' ' || echo "0")
    
    if [ "$VISITAS_COUNT" -gt "0" ]; then
        echo "✅ $VISITAS_COUNT visitas encontradas"
        echo ""
        echo "   Distribución por estado:"
        docker exec postgres-db psql -U dgt_user -d digital_twins_db -c "SELECT status, COUNT(*) as cantidad FROM visits GROUP BY status ORDER BY status;" 2>/dev/null
        echo ""
        echo "   Visitas por vendedor (top 5):"
        docker exec postgres-db psql -U dgt_user -d digital_twins_db -c "SELECT s.name, COUNT(v.id) as visitas FROM visits v JOIN sellers s ON v.seller_id = s.id GROUP BY s.id, s.name ORDER BY visitas DESC LIMIT 5;" 2>/dev/null
        return 0
    else
        echo "⚠️  No se encontraron visitas"
        echo ""
        echo "   Verificando dependencias..."
        echo "   Sellers disponibles:"
        docker exec postgres-db psql -U dgt_user -d digital_twins_db -c "SELECT id, email, name FROM sellers LIMIT 10;" 2>/dev/null
        echo ""
        echo "   Shopkeepers disponibles:"
        docker exec postgres-db psql -U dgt_user -d digital_twins_db -c "SELECT id, email, name FROM shopkeepers LIMIT 10;" 2>/dev/null
        return 1
    fi
}

# Función para ejecutar script corregido (BD nueva)
execute_new_db() {
    echo ""
    echo "🔄 Opción: Base de Datos NUEVA"
    echo "=========================================="
    echo ""
    echo "⚠️  ADVERTENCIA: Esto eliminará todos los datos existentes"
    echo ""
    read -p "¿Estás seguro? (s/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "❌ Operación cancelada"
        exit 1
    fi
    
    echo ""
    echo "1️⃣  Haciendo backup del script original..."
    cp init.sql init.sql.backup 2>/dev/null || true
    
    echo "2️⃣  Reemplazando init.sql con init_corrected.sql..."
    cp init_corrected.sql init.sql
    
    echo "3️⃣  Deteniendo contenedores..."
    cd ../compose
    $DOCKER_COMPOSE down
    
    echo "4️⃣  Eliminando volumen de PostgreSQL..."
    # Intentar diferentes nombres de volumen comunes
    docker volume rm digital-twins-db-data 2>/dev/null || true
    docker volume rm compose_postgres_data 2>/dev/null || true
    docker volume rm infra-log-dk_postgres_data 2>/dev/null || true
    # Buscar y eliminar cualquier volumen relacionado
    docker volume ls | grep -i postgres | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
    
    echo "5️⃣  Recreando base de datos..."
    $DOCKER_COMPOSE up -d postgres-db
    
    echo "6️⃣  Esperando a que PostgreSQL esté listo y termine de ejecutar init.sql..."
    for i in {1..30}; do
        if docker exec postgres-db pg_isready -U dgt_user -d digital_twins_db > /dev/null 2>&1; then
            echo "✅ PostgreSQL está listo"
            # Esperar adicional para que termine de ejecutar init.sql
            echo "   Esperando a que termine la ejecución del script SQL..."
            sleep 10
            break
        fi
        echo "   Esperando... ($i/30)"
        sleep 2
    done
    
    # Verificar que el script terminó de ejecutarse
    echo "   Verificando que el script SQL terminó..."
    for i in {1..20}; do
        VISITAS_COUNT=$(docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM visits;" 2>/dev/null | tr -d ' ' || echo "0")
        if [ "$VISITAS_COUNT" -gt "0" ]; then
            echo "✅ Script SQL completado (encontradas $VISITAS_COUNT visitas)"
            break
        fi
        if [ "$i" -eq "20" ]; then
            echo "⚠️  El script puede estar aún ejecutándose. Las visitas se insertarán en segundo plano."
        else
            echo "   Esperando inserción de datos... ($i/20)"
            sleep 3
        fi
    done
    
    echo ""
    echo "7️⃣  Verificando ejecución del script..."
    docker logs postgres-db | tail -30
    
    echo ""
    echo "8️⃣  Verificando datos insertados..."
    echo "   - Usuarios:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | xargs
    echo "   - Vendedores:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM sellers;" 2>/dev/null | xargs
    echo "   - Tenderos:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM shopkeepers;" 2>/dev/null | xargs
    echo "   - Productos:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM products;" 2>/dev/null | xargs
    echo "   - Inventarios:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM inventories;" 2>/dev/null | xargs
    
    # Verificar visitas con función dedicada
    verify_visits
    
    echo ""
    echo "✅ Proceso completado!"
    echo ""
    echo "Verifica con:"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c 'SELECT COUNT(*) FROM visits;'"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c 'SELECT status, COUNT(*) FROM visits GROUP BY status;'"
}

# Función para ejecutar migración (BD existente)
execute_migration() {
    echo ""
    echo "🔄 Opción: Migración de Base de Datos EXISTENTE"
    echo "=========================================="
    echo ""
    
    make_backup
    
    echo ""
    echo "📝 Ejecutando script de migración..."
    docker exec -i postgres-db psql -U dgt_user -d digital_twins_db < migration_fix_schema.sql
    
    echo ""
    echo "✅ Migración completada!"
    echo ""
    echo "Verifica con:"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c '\\d inventories'"
}

# Función para ejecutar script manualmente
execute_manual() {
    echo ""
    echo "🔄 Opción: Ejecutar Script Manualmente"
    echo "=========================================="
    echo ""
    
    if check_db_has_data; then
        echo "⚠️  La base de datos tiene datos. ¿Quieres hacer backup primero?"
        read -p "¿Hacer backup? (S/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            make_backup
        fi
    fi
    
    echo ""
    echo "📝 Ejecutando init_corrected.sql..."
    
    # Verificar que el contenedor esté corriendo
    if ! docker ps | grep -q postgres-db; then
        echo "❌ Error: El contenedor postgres-db no está corriendo"
        echo "   Ejecuta primero: cd ../compose && docker-compose up -d postgres-db"
        exit 1
    fi
    
    # Ejecutar el script
    docker exec -i postgres-db psql -U dgt_user -d digital_twins_db < init_corrected.sql
    
    echo ""
    echo "✅ Script ejecutado!"
    echo ""
    echo "📊 Verificando datos insertados..."
    echo "   - Usuarios:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | xargs
    echo "   - Vendedores:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM sellers;" 2>/dev/null | xargs
    echo "   - Tenderos:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM shopkeepers;" 2>/dev/null | xargs
    echo "   - Productos:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM products;" 2>/dev/null | xargs
    echo "   - Inventarios:"
    docker exec postgres-db psql -U dgt_user -d digital_twins_db -t -c "SELECT COUNT(*) FROM inventories;" 2>/dev/null | xargs
    
    # Verificar visitas con función dedicada
    verify_visits
    
    echo ""
    echo "Verifica con:"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c 'SELECT COUNT(*) FROM visits;'"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c 'SELECT status, COUNT(*) FROM visits GROUP BY status;'"
}

# Menú principal
if [ "$1" == "nueva" ] || [ "$1" == "new" ]; then
    execute_new_db
elif [ "$1" == "migracion" ] || [ "$1" == "migration" ]; then
    execute_migration
elif [ "$1" == "manual" ]; then
    execute_manual
else
    echo "Selecciona una opción:"
    echo ""
    echo "1) Base de datos NUEVA (reemplaza init.sql y recrea BD)"
    echo "2) Migración de BD EXISTENTE (preserva datos)"
    echo "3) Ejecutar script MANUALMENTE (sin recrear BD)"
    echo ""
    read -p "Opción (1/2/3): " -n 1 -r
    echo ""
    echo ""
    
    case $REPLY in
        1)
            execute_new_db
            ;;
        2)
            execute_migration
            ;;
        3)
            execute_manual
            ;;
        *)
            echo "❌ Opción inválida"
            exit 1
            ;;
    esac
fi

echo ""
echo "=========================================="
echo "  Proceso finalizado"
echo "=========================================="

