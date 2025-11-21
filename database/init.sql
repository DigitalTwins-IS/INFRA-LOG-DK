-- Unified SQL schema + seed data (PostGIS) - CORREGIDO
-- Validado y ajustado para compatibilidad con modelos SQLAlchemy

-- 1) Extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2) Utility functions used by triggers (must exist before triggers)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_shopkeeper_location()
RETURNS TRIGGER AS $$
BEGIN
    -- Solo actualizar location si lat/lon están presentes
    IF NEW.longitude IS NOT NULL AND NEW.latitude IS NOT NULL THEN
        NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3) Tables
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'ADMIN' CHECK (role IN ('ADMIN', 'TENDERO', 'VENDEDOR')),
    is_active BOOLEAN DEFAULT TRUE,
    -- Campos para verificación adicional de restablecimiento de contraseña
    phone_number VARCHAR(20) NULL,
    security_question VARCHAR(255) NULL,
    security_answer_hash VARCHAR(255) NULL,
    -- Campos para restablecimiento de contraseña
    reset_token VARCHAR(255) NULL,
    reset_code VARCHAR(6) NULL,
    reset_token_expires TIMESTAMP WITH TIME ZONE NULL,
    reset_code_expires TIMESTAMP WITH TIME ZONE NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Alinear constraint de roles a mayúsculas por compatibilidad con frontend/backend
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE table_name='users' AND constraint_type='CHECK' AND constraint_name='users_role_check'
  ) THEN
    ALTER TABLE users DROP CONSTRAINT users_role_check;
  END IF;
EXCEPTION WHEN undefined_object THEN
  -- ignorar si no existe
  NULL;
END$$;

ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('ADMIN', 'TENDERO', 'VENDEDOR'));

CREATE TABLE IF NOT EXISTS cities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    country VARCHAR(100) DEFAULT 'Colombia',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS zones (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    city_id INTEGER NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
    color VARCHAR(7) DEFAULT '#3498db',
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(name, city_id)
);

CREATE TABLE IF NOT EXISTS sellers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20),
    address TEXT,
    zone_id INTEGER NOT NULL REFERENCES zones(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS shopkeepers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    business_name VARCHAR(255),
    address TEXT NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(255),
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    location GEOMETRY(POINT, 4326),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CORRECCIÓN: Constraint único parcial solo para asignaciones activas
-- Esto permite múltiples registros históricos (is_active=FALSE) pero solo uno activo
CREATE TABLE IF NOT EXISTS assignments (
    id SERIAL PRIMARY KEY,
    seller_id INTEGER NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    shopkeeper_id INTEGER NOT NULL REFERENCES shopkeepers(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    unassigned_at TIMESTAMP WITH TIME ZONE,
    assigned_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    unassigned_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índice parcial único: solo un registro activo por (seller_id, shopkeeper_id)
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_active_assignment 
ON assignments(seller_id, shopkeeper_id) 
WHERE is_active = TRUE;

CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    category VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- CORRECCIÓN: Tabla de inventario ajustada al modelo Python
-- El modelo Python usa __tablename__ = "inventories"
CREATE TABLE IF NOT EXISTS inventories (
    id SERIAL PRIMARY KEY,
    shopkeeper_id INTEGER NOT NULL REFERENCES shopkeepers(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL DEFAULT 0,
    min_stock NUMERIC(10, 2) DEFAULT 10,
    max_stock NUMERIC(10, 2) DEFAULT 100,
    current_stock NUMERIC(10, 2) NOT NULL DEFAULT 0 CHECK (current_stock >= 0),
    product_name VARCHAR(255),
    product_description VARCHAR(500),
    product_category VARCHAR(100),
    product_brand VARCHAR(100),
    is_validated BOOLEAN DEFAULT FALSE,
    validated_by INTEGER,
    validated_at TIMESTAMP WITH TIME ZONE,
    assigned_by INTEGER,
    assigned_at TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(shopkeeper_id, product_id)
);

-- HU21: Tabla de Visitas - Agendar visitas basadas en inventario
CREATE TABLE IF NOT EXISTS visits (
    id SERIAL PRIMARY KEY,
    seller_id INTEGER NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    shopkeeper_id INTEGER NOT NULL REFERENCES shopkeepers(id) ON DELETE CASCADE,
    scheduled_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
    reason VARCHAR(255) DEFAULT 'reabastecimiento',
    notes TEXT,
    completed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    cancelled_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- HU16: Tabla de Incidencias de la visita - registrar  durante visitas
CREATE TABLE IF NOT EXISTS seller_incidents (
    id SERIAL PRIMARY KEY,
    seller_id INTEGER NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    shopkeeper_id INTEGER REFERENCES shopkeepers(id) ON DELETE SET NULL,
    visit_id INTEGER REFERENCES visits(id) ON DELETE SET NULL,
    type VARCHAR(30) NOT NULL CHECK (type IN ('absence', 'delay', 'non_compliance')),
    description TEXT,
    incident_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4) Triggers that use update_updated_at_column or update_shopkeeper_location
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cities_updated_at BEFORE UPDATE ON cities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_zones_updated_at BEFORE UPDATE ON zones
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sellers_updated_at BEFORE UPDATE ON sellers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shopkeepers_updated_at BEFORE UPDATE ON shopkeepers
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assignments_updated_at BEFORE UPDATE ON assignments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_inventories_updated_at BEFORE UPDATE ON inventories
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_visits_updated_at BEFORE UPDATE ON visits
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_shopkeeper_location_trigger
    BEFORE INSERT OR UPDATE ON shopkeepers
    FOR EACH ROW EXECUTE FUNCTION update_shopkeeper_location();

CREATE TRIGGER update_seller_incidents_updated_at 
BEFORE UPDATE ON seller_incidents
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 5) Indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
-- Índices para restablecimiento de contraseña
CREATE INDEX IF NOT EXISTS idx_users_phone_number ON users(phone_number) WHERE phone_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_reset_token ON users(reset_token) WHERE reset_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_reset_code ON users(reset_code) WHERE reset_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_zones_city_id ON zones(city_id);
CREATE INDEX IF NOT EXISTS idx_zones_name ON zones(name);
CREATE INDEX IF NOT EXISTS idx_sellers_zone_id ON sellers(zone_id);
CREATE INDEX IF NOT EXISTS idx_sellers_email ON sellers(email);
CREATE INDEX IF NOT EXISTS idx_sellers_user_id ON sellers(user_id);
CREATE INDEX IF NOT EXISTS idx_shopkeepers_location ON shopkeepers USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_shopkeepers_coordinates ON shopkeepers(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_shopkeepers_email ON shopkeepers(email);
CREATE INDEX IF NOT EXISTS idx_assignments_seller_id ON assignments(seller_id);
CREATE INDEX IF NOT EXISTS idx_assignments_shopkeeper_id ON assignments(shopkeeper_id);
CREATE INDEX IF NOT EXISTS idx_assignments_assigned_by ON assignments(assigned_by);
CREATE INDEX IF NOT EXISTS idx_assignments_unassigned_by ON assignments(unassigned_by);
CREATE INDEX IF NOT EXISTS idx_assignments_is_active ON assignments(is_active);
CREATE INDEX IF NOT EXISTS idx_assignments_active_seller ON assignments(seller_id, is_active) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_inventories_shopkeeper ON inventories(shopkeeper_id);
CREATE INDEX IF NOT EXISTS idx_inventories_product ON inventories(product_id);
CREATE INDEX IF NOT EXISTS idx_visits_seller_id ON visits(seller_id);
CREATE INDEX IF NOT EXISTS idx_visits_shopkeeper_id ON visits(shopkeeper_id);
CREATE INDEX IF NOT EXISTS idx_visits_scheduled_date ON visits(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_visits_status ON visits(status);
CREATE INDEX IF NOT EXISTS idx_visits_seller_status ON visits(seller_id, status);
CREATE INDEX IF NOT EXISTS idx_seller_incidents_seller_id ON seller_incidents(seller_id);

-- 6) Views
CREATE OR REPLACE VIEW v_sellers_full AS
SELECT 
    s.id,
    s.name,
    s.email,
    s.phone,
    s.address,
    s.is_active,
    z.id as zone_id,
    z.name as zone_name,
    z.color as zone_color,
    c.id as city_id,
    c.name as city_name,
    c.country,
    u.id as user_id,
    u.name as user_name,
    s.created_at,
    s.updated_at
FROM sellers s
JOIN zones z ON s.zone_id = z.id
JOIN cities c ON z.city_id = c.id
LEFT JOIN users u ON s.user_id = u.id;

CREATE OR REPLACE VIEW v_shopkeepers_current AS
SELECT 
    sk.id,
    sk.name,
    sk.business_name,
    sk.address,
    sk.phone,
    sk.email,
    sk.latitude,
    sk.longitude,
    sk.location,
    sk.is_active,
    sk.created_at,
    sk.updated_at,
    s.id as seller_id,
    s.name as seller_name,
    s.email as seller_email,
    z.id as zone_id,
    z.name as zone_name,
    z.color as zone_color,
    c.id as city_id,
    c.name as city_name,
    a.assigned_at,
    a.assigned_by,
    u.name as assigned_by_name
FROM shopkeepers sk
LEFT JOIN assignments a ON sk.id = a.shopkeeper_id AND a.is_active = TRUE
LEFT JOIN sellers s ON a.seller_id = s.id
LEFT JOIN zones z ON s.zone_id = z.id
LEFT JOIN cities c ON z.city_id = c.id
LEFT JOIN users u ON a.assigned_by = u.id;

CREATE OR REPLACE VIEW v_seller_assignments_summary AS
SELECT 
    s.id as seller_id,
    s.name as seller_name,
    s.email,
    z.name as zone_name,
    c.name as city_name,
    COUNT(DISTINCT a.shopkeeper_id) FILTER (WHERE a.is_active = TRUE) as active_shopkeepers,
    COUNT(DISTINCT a.shopkeeper_id) as total_shopkeepers_ever,
    MAX(a.assigned_at) as last_assignment_date
FROM sellers s
JOIN zones z ON s.zone_id = z.id
JOIN cities c ON z.city_id = c.id
LEFT JOIN assignments a ON s.id = a.seller_id
GROUP BY s.id, s.name, s.email, z.name, c.name;

-- CORRECCIÓN: View actualizada para usar 'inventories' en lugar de 'shopkeeper_inventory'
CREATE OR REPLACE VIEW v_shopkeeper_inventory AS
SELECT 
    si.id,
    si.shopkeeper_id,
    sk.name as shopkeeper_name,
    sk.business_name,
    si.product_id,
    COALESCE(si.product_name, p.name) as product_name,
    COALESCE(si.product_category, p.category) as category,
    COALESCE(si.unit_price, p.price) as price,
    si.current_stock as stock,
    si.min_stock,
    si.max_stock,
    CASE 
        WHEN si.current_stock < si.min_stock THEN 'low'
        WHEN si.current_stock > si.max_stock THEN 'high'
        ELSE 'normal'
    END as stock_status,
    si.last_updated,
    si.created_at
FROM inventories si
JOIN shopkeepers sk ON si.shopkeeper_id = sk.id
LEFT JOIN products p ON si.product_id = p.id
WHERE sk.is_active = TRUE AND si.is_active = TRUE;

-- 7) Other functions (distance, reassign, within radius)
CREATE OR REPLACE FUNCTION get_distance_between_shopkeepers(
    shopkeeper1_id INTEGER,
    shopkeeper2_id INTEGER
)
RETURNS NUMERIC AS $$
DECLARE
    distance NUMERIC;
BEGIN
    SELECT 
        ST_Distance(
            sk1.location::geography,
            sk2.location::geography
        ) / 1000
    INTO distance
    FROM shopkeepers sk1, shopkeepers sk2
    WHERE sk1.id = shopkeeper1_id AND sk2.id = shopkeeper2_id;
    
    RETURN distance;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION reassign_shopkeeper(
    p_shopkeeper_id INTEGER,
    p_new_seller_id INTEGER,
    p_user_id INTEGER,
    p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE assignments
    SET 
        is_active = FALSE,
        unassigned_at = CURRENT_TIMESTAMP,
        unassigned_by = p_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE 
        shopkeeper_id = p_shopkeeper_id 
        AND is_active = TRUE;
    
    INSERT INTO assignments (
        seller_id,
        shopkeeper_id,
        assigned_by,
        notes,
        is_active
    ) VALUES (
        p_new_seller_id,
        p_shopkeeper_id,
        p_user_id,
        p_notes,
        TRUE
    );
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_shopkeepers_within_radius(
    p_latitude DECIMAL,
    p_longitude DECIMAL,
    p_radius_km DECIMAL
)
RETURNS TABLE (
    id INTEGER,
    name VARCHAR(255),
    business_name VARCHAR(255),
    address TEXT,
    distance_km NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sk.id,
        sk.name,
        sk.business_name,
        sk.address,
        (ST_Distance(
            sk.location::geography,
            ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography
        ) / 1000)::NUMERIC as distance_km
    FROM shopkeepers sk
    WHERE ST_DWithin(
        sk.location::geography,
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography,
        p_radius_km * 1000
    )
    ORDER BY distance_km;
END;
$$ LANGUAGE plpgsql;

-- 8) Seed data (INSERTs) - use ON CONFLICT to avoid duplicates

INSERT INTO cities (name, country) VALUES 
    ('Bogotá', 'Colombia'),
    ('Medellín', 'Colombia'),
    ('Cali', 'Colombia'),
    ('Barranquilla', 'Colombia'),
    ('Cartagena', 'Colombia')
ON CONFLICT (name) DO NOTHING;

INSERT INTO zones (name, city_id, color, description) VALUES 
    ('Norte', 1, '#e74c3c', 'Zona norte de Bogotá - Chapinero, Usaquén'),
    ('Centro', 1, '#f39c12', 'Zona centro de Bogotá - Candelaria, Teusaquillo'),
    ('Sur', 1, '#27ae60', 'Zona sur de Bogotá - Bosa, Ciudad Bolívar'),
    ('Norte', 2, '#e74c3c', 'Zona norte de Medellín - El Poblado, Laureles'),
    ('Centro', 2, '#f39c12', 'Zona centro de Medellín - La Candelaria, Villa Hermosa'),
    ('Sur', 2, '#27ae60', 'Zona sur de Medellín - San Antonio de Prado'),
    ('Norte', 3, '#e74c3c', 'Zona norte de Cali - Granada, El Peñón'),
    ('Centro', 3, '#f39c12', 'Zona centro de Cali - San Antonio, La Merced'),
    ('Sur', 3, '#27ae60', 'Zona sur de Cali - Pance, Ciudad Jardín')
ON CONFLICT (name, city_id) DO NOTHING;

-- Usuarios iniciales del sistema
-- Contraseña por defecto: Admin123!
INSERT INTO users (name, email, password_hash, role) VALUES 
    ('Administrador Principal', 'admin@digitaltwins.com', '$2b$12$GwXkoxF7JFaNKvPzHuuriOP.s492DNA5okoRoULFIbFhW0KlYnoje', 'ADMIN'),
    ('Admin Bogotá', 'admin.bogota@digitaltwins.com', '$2b$12$GwXkoxF7JFaNKvPzHuuriOP.s492DNA5okoRoULFIbFhW0KlYnoje', 'ADMIN'),
    ('Tendero Principal', 'tendero@digitaltwins.com', '$2b$12$GwXkoxF7JFaNKvPzHuuriOP.s492DNA5okoRoULFIbFhW0KlYnoje', 'TENDERO'),
    ('Vendedor Principal', 'vendedor@digitaltwins.com', '$2b$12$GwXkoxF7JFaNKvPzHuuriOP.s492DNA5okoRoULFIbFhW0KlYnoje', 'VENDEDOR')
ON CONFLICT (email) DO NOTHING;

INSERT INTO sellers (name, email, phone, address, zone_id, user_id) VALUES 
    ('Vendedor Principal', 'vendedor@digitaltwins.com', '3001234567', 'Calle 80 #12-34, Bogotá', 1, 4),
    ('Juan Pérez', 'juan.perez@vendedor.com', '3001234567', 'Calle 80 #12-34, Bogotá', 1, NULL),
    ('María García', 'maria.garcia@vendedor.com', '3007654321', 'Carrera 15 #93-47, Bogotá', 2, NULL),
    ('Carlos López', 'carlos.lopez@vendedor.com', '3009876543', 'Avenida 68 #25-30, Bogotá', 3, NULL),
    ('Ana Rodríguez', 'ana.rodriguez@vendedor.com', '3005555555', 'Calle 50 #40-20, Medellín', 4, NULL),
    ('Pedro Martínez', 'pedro.martinez@vendedor.com', '3006666666', 'Carrera 43 #20-15, Medellín', 5, NULL)
ON CONFLICT (email) DO NOTHING;

-- Products: prefer the more detailed prices from the first file (kept is_active = TRUE)
INSERT INTO products (name, description, price, category, is_active) VALUES
    ('Manzana Roja', 'Manzana fresca y crujiente de cultivo local.', 2500.00, 'FRUTAS Y VEGETALES', TRUE),
    ('Arroz Integral', 'Grano entero con alto contenido de fibra.', 3200.50, 'GRANOS', TRUE),
    ('Leche Entera', 'Leche pasteurizada entera de 1 litro.', 4200.00, 'LACTEOS', TRUE),
    ('Chocolate de Leche', 'Barra de chocolate con leche al 30% cacao.', 1500.75, 'DULCERIA', TRUE),
    ('Zanahoria', 'Zanahoria fresca ideal para ensaladas o jugos.', 1800.25, 'FRUTAS Y VEGETALES', TRUE)
ON CONFLICT (name) DO NOTHING;

-- CORRECCIÓN: Shopkeepers - insertar solo si no existen (verificar por email)
INSERT INTO shopkeepers (name, business_name, address, phone, email, latitude, longitude) 
SELECT * FROM (VALUES 
    ('Tienda La Esperanza', 'Supermercado La Esperanza', 'Calle 80 #12-34, Chapinero', '6012345678', 'laesperanza@tienda.com', 4.6097100, -74.0817500),
    ('Farmacia San José', 'Farmacia San José', 'Carrera 7 #80-20, Chapinero', '6018765432', 'sanjose@farmacia.com', 4.6711600, -74.0579100),
    ('Panadería El Buen Pan', 'Panadería El Buen Pan', 'Calle 85 #15-30, Usaquén', '6013456789', 'buenpan@panaderia.com', 4.6980800, -74.0335600),
    ('Supermercado El Ahorro', 'Supermercado El Ahorro', 'Carrera 15 #93-47, Teusaquillo', '6019876543', 'elahorro@super.com', 4.6372400, -74.0840800),
    ('Ferretería El Constructor', 'Ferretería El Constructor', 'Calle 26 #15-40, Candelaria', '6014567890', 'constructor@ferreteria.com', 4.5977600, -74.0751300),
    ('Miscelánea La Bendición', 'Miscelánea La Bendición', 'Avenida 68 #25-30, Bosa', '6015678901', 'labendicion@miscelanea.com', 4.6280700, -74.1862200),
    ('Veterinaria San Martín', 'Veterinaria San Martín', 'Calle 60 Sur #80-25, Ciudad Bolívar', '6016789012', 'sanmartin@veterinaria.com', 4.5654300, -74.1456700),
    ('Droguería La Salud', 'Droguería La Salud', 'Calle 50 #40-20, El Poblado', '6041234567', 'lasalud@drogueria.com', 6.2442000, -75.5812000),
    ('Carnicería El Buen Corte', 'Carnicería El Buen Corte', 'Carrera 43A #5-20, Laureles', '6042345678', 'buencorte@carniceria.com', 6.2489300, -75.5968600)
) AS v(name, business_name, address, phone, email, latitude, longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM shopkeepers WHERE shopkeepers.email = v.email AND shopkeepers.email IS NOT NULL
);

-- CORRECCIÓN: Assignments - insertar solo si no existe una asignación activa
-- Usar emails para encontrar los IDs correctos de sellers y shopkeepers
-- Asignar tenderos al "Vendedor Principal" (vendedor@digitaltwins.com)
INSERT INTO assignments (seller_id, shopkeeper_id, assigned_by) 
SELECT 
    s.id as seller_id,
    sk.id as shopkeeper_id,
    (SELECT id FROM users WHERE email = 'admin@digitaltwins.com' LIMIT 1) as assigned_by
FROM sellers s
CROSS JOIN shopkeepers sk
WHERE s.email = 'vendedor@digitaltwins.com'
  AND sk.email IN ('laesperanza@tienda.com', 'sanjose@farmacia.com', 'buenpan@panaderia.com', 'elahorro@super.com', 'constructor@ferreteria.com')
  AND NOT EXISTS (
    SELECT 1 FROM assignments 
    WHERE assignments.seller_id = s.id 
    AND assignments.shopkeeper_id = sk.id 
    AND assignments.is_active = TRUE
  );

-- Asignaciones para otros vendedores (usando emails)
INSERT INTO assignments (seller_id, shopkeeper_id, assigned_by) 
SELECT 
    s.id as seller_id,
    sk.id as shopkeeper_id,
    (SELECT id FROM users WHERE email = 'admin@digitaltwins.com' LIMIT 1) as assigned_by
FROM sellers s
CROSS JOIN shopkeepers sk
WHERE (s.email = 'juan.perez@vendedor.com' AND sk.email IN ('laesperanza@tienda.com', 'sanjose@farmacia.com', 'buenpan@panaderia.com'))
   OR (s.email = 'maria.garcia@vendedor.com' AND sk.email IN ('elahorro@super.com', 'constructor@ferreteria.com'))
   OR (s.email = 'carlos.lopez@vendedor.com' AND sk.email IN ('labendicion@miscelanea.com', 'sanmartin@veterinaria.com'))
   OR (s.email = 'ana.rodriguez@vendedor.com' AND sk.email IN ('lasalud@drogueria.com'))
   OR (s.email = 'pedro.martinez@vendedor.com' AND sk.email IN ('buencorte@carniceria.com'))
  AND NOT EXISTS (
    SELECT 1 FROM assignments 
    WHERE assignments.seller_id = s.id 
    AND assignments.shopkeeper_id = sk.id 
    AND assignments.is_active = TRUE
  );

UPDATE users 
SET password_hash = '$2b$12$GwXkoxF7JFaNKvPzHuuriOP.s492DNA5okoRoULFIbFhW0KlYnoje'
WHERE email = 'admin@digitaltwins.com';

-- CORRECCIÓN: Inventory seed - usar tabla 'inventories' y campo 'current_stock'
-- Productos para tenderos asignados al "Vendedor Principal" (vendedor@digitaltwins.com)
-- Tenderos asignados: 1 (La Esperanza), 2 (San José), 3 (Buen Pan), 4 (El Ahorro), 5 (Constructor)
-- IMPORTANTE: Agregar productos con bajo stock (current_stock < min_stock) para que aparezcan en visitas
INSERT INTO inventories (shopkeeper_id, product_id, current_stock, min_stock, max_stock, unit_price, product_name, product_category) VALUES
    -- Shopkeeper 1: La Esperanza (laesperanza@tienda.com)
    (1, 1, 50, 20, 100, 2500.00, 'Manzana Roja', 'FRUTAS Y VEGETALES'),
    (1, 2, 30, 10, 80, 3200.50, 'Arroz Integral', 'GRANOS'),
    (1, 3, 25, 15, 60, 4200.00, 'Leche Entera', 'LACTEOS'),
    -- Productos con BAJO STOCK para shopkeeper 1
    (1, 4, 5, 10, 50, 1500.75, 'Chocolate de Leche', 'DULCERIA'),  -- Bajo stock: 5 < 10
    (1, 5, 8, 15, 60, 1800.25, 'Zanahoria', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 8 < 15
    
    -- Shopkeeper 2: San José (sanjose@farmacia.com)
    (2, 3, 40, 20, 100, 4200.00, 'Leche Entera', 'LACTEOS'),
    -- Productos con BAJO STOCK para shopkeeper 2
    (2, 1, 12, 20, 100, 2500.00, 'Manzana Roja', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 12 < 20
    (2, 2, 7, 10, 80, 3200.50, 'Arroz Integral', 'GRANOS'),  -- Bajo stock: 7 < 10
    (2, 4, 3, 10, 50, 1500.75, 'Chocolate de Leche', 'DULCERIA'),  -- Bajo stock: 3 < 10
    
    -- Shopkeeper 3: Buen Pan (buenpan@panaderia.com)
    (3, 2, 20, 10, 50, 3200.50, 'Arroz Integral', 'GRANOS'),
    -- Productos con BAJO STOCK para shopkeeper 3
    (3, 1, 8, 20, 100, 2500.00, 'Manzana Roja', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 8 < 20
    (3, 3, 10, 15, 60, 4200.00, 'Leche Entera', 'LACTEOS'),  -- Bajo stock: 10 < 15
    (3, 5, 6, 15, 60, 1800.25, 'Zanahoria', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 6 < 15
    
    -- Shopkeeper 4: El Ahorro (elahorro@super.com)
    -- Productos con BAJO STOCK para shopkeeper 4
    (4, 1, 15, 20, 100, 2500.00, 'Manzana Roja', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 15 < 20
    (4, 2, 8, 10, 80, 3200.50, 'Arroz Integral', 'GRANOS'),  -- Bajo stock: 8 < 10
    (4, 3, 12, 15, 60, 4200.00, 'Leche Entera', 'LACTEOS'),  -- Bajo stock: 12 < 15
    (4, 4, 4, 10, 50, 1500.75, 'Chocolate de Leche', 'DULCERIA'),  -- Bajo stock: 4 < 10
    
    -- Shopkeeper 5: Constructor (constructor@ferreteria.com)
    -- Productos con BAJO STOCK para shopkeeper 5
    (5, 1, 10, 20, 100, 2500.00, 'Manzana Roja', 'FRUTAS Y VEGETALES'),  -- Bajo stock: 10 < 20
    (5, 2, 5, 10, 80, 3200.50, 'Arroz Integral', 'GRANOS'),  -- Bajo stock: 5 < 10
    (5, 3, 9, 15, 60, 4200.00, 'Leche Entera', 'LACTEOS'),  -- Bajo stock: 9 < 15
    (5, 5, 7, 15, 60, 1800.25, 'Zanahoria', 'FRUTAS Y VEGETALES')  -- Bajo stock: 7 < 15
ON CONFLICT (shopkeeper_id, product_id) DO UPDATE
SET 
    current_stock = EXCLUDED.current_stock,
    min_stock = EXCLUDED.min_stock,
    max_stock = EXCLUDED.max_stock,
    unit_price = EXCLUDED.unit_price,
    product_name = EXCLUDED.product_name,
    product_category = EXCLUDED.product_category;

-- Visitas de muestra para review
-- Visitas con diferentes estados y fechas para demostración
INSERT INTO visits (seller_id, shopkeeper_id, scheduled_date, status, reason, notes, completed_at, cancelled_at, cancelled_reason) 
SELECT 
    s.id as seller_id,
    sk.id as shopkeeper_id,
    scheduled_date,
    status,
    reason,
    notes,
    completed_at,
    cancelled_at,
    cancelled_reason
FROM (VALUES 
    -- Visitas completadas (pasadas)
    ('vendedor@digitaltwins.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '5 days', 'completed', 'reabastecimiento', 'Visita completada exitosamente. Stock actualizado.', CURRENT_TIMESTAMP - INTERVAL '5 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '3 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '1 hour', NULL, NULL),
    ('juan.perez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '7 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '7 days' + INTERVAL '3 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '10 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '10 days' + INTERVAL '2 hours', NULL, NULL),
    
    -- Visitas pendientes (futuras)
    ('vendedor@digitaltwins.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP + INTERVAL '2 days', 'pending', 'reabastecimiento', 'Visita programada para reabastecimiento de inventario.', NULL, NULL, NULL),
    ('juan.perez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '5 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending', 'reabastecimiento', 'Entrega programada de productos.', NULL, NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP + INTERVAL '7 days', 'pending', 'reabastecimiento', 'Visita de seguimiento programada.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP + INTERVAL '4 days', 'pending', 'reabastecimiento', 'Revisión de inventario pendiente.', NULL, NULL, NULL),
    
    -- Visitas canceladas
    ('vendedor@digitaltwins.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'cancelled', 'reabastecimiento', 'Visita cancelada por solicitud del tendero.', NULL, CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '30 minutes', 'Tendero no disponible en la fecha programada'),
    ('juan.perez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'cancelled', 'reabastecimiento', 'Cancelación por problemas de logística.', NULL, CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour', 'Problemas de transporte'),
    ('carlos.lopez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'cancelled', 'reabastecimiento', 'Visita cancelada por el vendedor.', NULL, CURRENT_TIMESTAMP - INTERVAL '2 days', 'Cambio de ruta del vendedor'),
    
    -- Más visitas completadas para tener mejor muestra
    ('vendedor@digitaltwins.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '8 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '8 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '12 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '12 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '15 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '15 days' + INTERVAL '3 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '20 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '20 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    
    -- Más visitas pendientes
    ('vendedor@digitaltwins.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '6 days', 'pending', 'reabastecimiento', 'Visita programada para próxima semana.', NULL, NULL, NULL),
    ('juan.perez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP + INTERVAL '8 days', 'pending', 'reabastecimiento', 'Revisión de stock programada.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP + INTERVAL '10 days', 'pending', 'reabastecimiento', 'Entrega de productos programada.', NULL, NULL, NULL),
    
    -- ===== VISITAS ADICIONALES PARA REPORTE DE CUMPLIMIENTO =====
    -- Vendedor Principal: ~95% cumplimiento (19 completadas, 1 pendiente)
    ('vendedor@digitaltwins.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('vendedor@digitaltwins.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '18 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '18 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '19 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '19 days' + INTERVAL '1 hour', NULL, NULL),
    ('vendedor@digitaltwins.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '21 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '21 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '22 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '22 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '23 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '23 days' + INTERVAL '2 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '24 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '24 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '25 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '25 days' + INTERVAL '3 hours', NULL, NULL),
    ('vendedor@digitaltwins.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '26 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '26 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '27 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '27 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('vendedor@digitaltwins.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    
    -- Juan Pérez: ~85% cumplimiento (17 completadas, 3 pendientes)
    ('juan.perez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('juan.perez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '18 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '18 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '19 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '19 days' + INTERVAL '1 hour', NULL, NULL),
    ('juan.perez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '21 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '21 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '22 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '22 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '23 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '23 days' + INTERVAL '2 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '24 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '24 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('juan.perez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '25 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '25 days' + INTERVAL '3 hours', NULL, NULL),
    ('juan.perez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    ('juan.perez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    ('juan.perez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '6 days', 'pending', 'reabastecimiento', 'Visita programada para próxima semana.', NULL, NULL, NULL),
    
    -- María García: ~75% cumplimiento (15 completadas, 5 pendientes)
    ('maria.garcia@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('maria.garcia@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '18 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '18 days' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '19 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '19 days' + INTERVAL '1 hour', NULL, NULL),
    ('maria.garcia@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '21 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '21 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('maria.garcia@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '22 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '22 days' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '23 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '23 days' + INTERVAL '2 hours', NULL, NULL),
    ('maria.garcia@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP + INTERVAL '2 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP + INTERVAL '4 days', 'pending', 'reabastecimiento', 'Entrega programada de productos.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '7 days', 'pending', 'reabastecimiento', 'Visita de seguimiento programada.', NULL, NULL, NULL),
    ('maria.garcia@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '9 days', 'pending', 'reabastecimiento', 'Revisión de inventario pendiente.', NULL, NULL, NULL),
    
    -- Carlos López: ~60% cumplimiento (12 completadas, 8 pendientes)
    ('carlos.lopez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '18 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '18 days' + INTERVAL '2 hours', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '19 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '19 days' + INTERVAL '1 hour', NULL, NULL),
    ('carlos.lopez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP + INTERVAL '2 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending', 'reabastecimiento', 'Entrega programada de productos.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP + INTERVAL '5 days', 'pending', 'reabastecimiento', 'Visita de seguimiento programada.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP + INTERVAL '6 days', 'pending', 'reabastecimiento', 'Revisión de inventario pendiente.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP + INTERVAL '7 days', 'pending', 'reabastecimiento', 'Visita programada para próxima semana.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '8 days', 'pending', 'reabastecimiento', 'Revisión de stock programada.', NULL, NULL, NULL),
    ('carlos.lopez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '10 days', 'pending', 'reabastecimiento', 'Entrega de productos programada.', NULL, NULL, NULL),
    
    -- Ana Rodríguez: ~90% cumplimiento (18 completadas, 2 pendientes)
    ('ana.rodriguez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '18 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '18 days' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '19 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '19 days' + INTERVAL '1 hour', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '21 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '21 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '22 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '22 days' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '23 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '23 days' + INTERVAL '2 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '24 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '24 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '25 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '25 days' + INTERVAL '3 hours', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '26 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '26 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    ('ana.rodriguez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    
    -- Pedro Martínez: ~50% cumplimiento (10 completadas, 10 pendientes)
    ('pedro.martinez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '1 day', 'completed', 'reabastecimiento', 'Visita completada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '1 day' + INTERVAL '2 hours', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '2 days', 'completed', 'reabastecimiento', 'Productos entregados correctamente.', CURRENT_TIMESTAMP - INTERVAL '2 days' + INTERVAL '1 hour', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '4 days', 'completed', 'reabastecimiento', 'Inventario verificado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '4 days' + INTERVAL '3 hours', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP - INTERVAL '6 days', 'completed', 'reabastecimiento', 'Visita realizada según lo programado.', CURRENT_TIMESTAMP - INTERVAL '6 days' + INTERVAL '1 hour 30 minutes', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '9 days', 'completed', 'reabastecimiento', 'Todos los productos fueron entregados.', CURRENT_TIMESTAMP - INTERVAL '9 days' + INTERVAL '2 hours', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '11 days', 'completed', 'reabastecimiento', 'Visita exitosa, inventario actualizado.', CURRENT_TIMESTAMP - INTERVAL '11 days' + INTERVAL '2 hours', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP - INTERVAL '13 days', 'completed', 'reabastecimiento', 'Productos entregados y verificados.', CURRENT_TIMESTAMP - INTERVAL '13 days' + INTERVAL '1 hour 45 minutes', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP - INTERVAL '14 days', 'completed', 'reabastecimiento', 'Visita completada según lo planificado.', CURRENT_TIMESTAMP - INTERVAL '14 days' + INTERVAL '3 hours', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP - INTERVAL '16 days', 'completed', 'reabastecimiento', 'Inventario revisado y actualizado.', CURRENT_TIMESTAMP - INTERVAL '16 days' + INTERVAL '2 hours 30 minutes', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP - INTERVAL '17 days', 'completed', 'reabastecimiento', 'Visita realizada exitosamente.', CURRENT_TIMESTAMP - INTERVAL '17 days' + INTERVAL '1 hour 15 minutes', NULL, NULL),
    ('pedro.martinez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '1 day', 'pending', 'reabastecimiento', 'Visita programada para mañana.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP + INTERVAL '2 days', 'pending', 'reabastecimiento', 'Revisión de stock pendiente.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'elahorro@super.com', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending', 'reabastecimiento', 'Entrega programada de productos.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP + INTERVAL '4 days', 'pending', 'reabastecimiento', 'Visita de seguimiento programada.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP + INTERVAL '5 days', 'pending', 'reabastecimiento', 'Revisión de inventario pendiente.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'sanmartin@veterinaria.com', CURRENT_TIMESTAMP + INTERVAL '6 days', 'pending', 'reabastecimiento', 'Visita programada para próxima semana.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'lasalud@drogueria.com', CURRENT_TIMESTAMP + INTERVAL '7 days', 'pending', 'reabastecimiento', 'Revisión de stock programada.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'buencorte@carniceria.com', CURRENT_TIMESTAMP + INTERVAL '8 days', 'pending', 'reabastecimiento', 'Entrega de productos programada.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'laesperanza@tienda.com', CURRENT_TIMESTAMP + INTERVAL '9 days', 'pending', 'reabastecimiento', 'Visita de seguimiento programada.', NULL, NULL, NULL),
    ('pedro.martinez@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP + INTERVAL '11 days', 'pending', 'reabastecimiento', 'Revisión de inventario pendiente.', NULL, NULL, NULL),
    
    -- Algunas visitas canceladas adicionales para diversidad
    ('juan.perez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '3 days', 'cancelled', 'reabastecimiento', 'Visita cancelada por solicitud del tendero.', NULL, CURRENT_TIMESTAMP - INTERVAL '3 days' + INTERVAL '30 minutes', 'Tendero no disponible en la fecha programada'),
    ('maria.garcia@vendedor.com', 'sanjose@farmacia.com', CURRENT_TIMESTAMP - INTERVAL '5 days', 'cancelled', 'reabastecimiento', 'Cancelación por problemas de logística.', NULL, CURRENT_TIMESTAMP - INTERVAL '5 days' + INTERVAL '1 hour', 'Problemas de transporte'),
    ('carlos.lopez@vendedor.com', 'buenpan@panaderia.com', CURRENT_TIMESTAMP - INTERVAL '7 days', 'cancelled', 'reabastecimiento', 'Visita cancelada por el vendedor.', NULL, CURRENT_TIMESTAMP - INTERVAL '7 days' + INTERVAL '2 hours', 'Cambio de ruta del vendedor'),
    ('ana.rodriguez@vendedor.com', 'constructor@ferreteria.com', CURRENT_TIMESTAMP - INTERVAL '8 days', 'cancelled', 'reabastecimiento', 'Visita cancelada por solicitud del tendero.', NULL, CURRENT_TIMESTAMP - INTERVAL '8 days' + INTERVAL '30 minutes', 'Tendero no disponible en la fecha programada'),
    ('pedro.martinez@vendedor.com', 'labendicion@miscelanea.com', CURRENT_TIMESTAMP - INTERVAL '10 days', 'cancelled', 'reabastecimiento', 'Cancelación por problemas de logística.', NULL, CURRENT_TIMESTAMP - INTERVAL '10 days' + INTERVAL '1 hour', 'Problemas de transporte')
) AS v(seller_email, shopkeeper_email, scheduled_date, status, reason, notes, completed_at, cancelled_at, cancelled_reason)
JOIN sellers s ON s.email = v.seller_email
JOIN shopkeepers sk ON sk.email = v.shopkeeper_email
WHERE NOT EXISTS (
    SELECT 1 FROM visits 
    WHERE visits.seller_id = s.id 
    AND visits.shopkeeper_id = sk.id 
    AND visits.scheduled_date = v.scheduled_date
);

-- Done

