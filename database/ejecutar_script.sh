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
    docker volume rm digital-twins-db-data 2>/dev/null || true
    
    echo "5️⃣  Recreando base de datos..."
    $DOCKER_COMPOSE up -d postgres-db
    
    echo "6️⃣  Esperando a que PostgreSQL esté listo..."
    sleep 5
    
    echo "7️⃣  Verificando ejecución..."
    docker logs postgres-db | tail -20
    
    echo ""
    echo "✅ Proceso completado!"
    echo ""
    echo "Verifica con:"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c '\\d inventories'"
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
    docker exec -i postgres-db psql -U dgt_user -d digital_twins_db < init_corrected.sql
    
    echo ""
    echo "✅ Script ejecutado!"
    echo ""
    echo "Verifica con:"
    echo "  docker exec -it postgres-db psql -U dgt_user -d digital_twins_db -c '\\d inventories'"
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

