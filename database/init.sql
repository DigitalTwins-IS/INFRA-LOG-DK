CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(50) DEFAULT 'admin' CHECK (role IN ('admin', 'tendero', 'vendedor')),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

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
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_active_assignment UNIQUE(seller_id, shopkeeper_id, is_active)
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
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

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

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

CREATE OR REPLACE FUNCTION update_shopkeeper_location()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_shopkeeper_location_trigger
    BEFORE INSERT OR UPDATE ON shopkeepers
    FOR EACH ROW EXECUTE FUNCTION update_shopkeeper_location();

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
    ('Juan Pérez', 'juan.perez@vendedor.com', '3001234567', 'Calle 80 #12-34, Bogotá', 1, 1),
    ('María García', 'maria.garcia@vendedor.com', '3007654321', 'Carrera 15 #93-47, Bogotá', 2, 1),
    ('Carlos López', 'carlos.lopez@vendedor.com', '3009876543', 'Avenida 68 #25-30, Bogotá', 3, 1),
    ('Ana Rodríguez', 'ana.rodriguez@vendedor.com', '3005555555', 'Calle 50 #40-20, Medellín', 4, 2),
    ('Pedro Martínez', 'pedro.martinez@vendedor.com', '3006666666', 'Carrera 43 #20-15, Medellín', 5, 2)
ON CONFLICT (email) DO NOTHING;

INSERT INTO shopkeepers (name, business_name, address, phone, email, latitude, longitude) VALUES 
    ('Tienda La Esperanza', 'Supermercado La Esperanza', 'Calle 80 #12-34, Chapinero', '6012345678', 'laesperanza@tienda.com', 4.6097100, -74.0817500),
    ('Farmacia San José', 'Farmacia San José', 'Carrera 7 #80-20, Chapinero', '6018765432', 'sanjose@farmacia.com', 4.6711600, -74.0579100),
    ('Panadería El Buen Pan', 'Panadería El Buen Pan', 'Calle 85 #15-30, Usaquén', '6013456789', 'buenpan@panaderia.com', 4.6980800, -74.0335600),
    ('Supermercado El Ahorro', 'Supermercado El Ahorro', 'Carrera 15 #93-47, Teusaquillo', '6019876543', 'elahorro@super.com', 4.6372400, -74.0840800),
    ('Ferretería El Constructor', 'Ferretería El Constructor', 'Calle 26 #15-40, Candelaria', '6014567890', 'constructor@ferreteria.com', 4.5977600, -74.0751300),
    ('Miscelánea La Bendición', 'Miscelánea La Bendición', 'Avenida 68 #25-30, Bosa', '6015678901', 'labendicion@miscelanea.com', 4.6280700, -74.1862200),
    ('Veterinaria San Martín', 'Veterinaria San Martín', 'Calle 60 Sur #80-25, Ciudad Bolívar', '6016789012', 'sanmartin@veterinaria.com', 4.5654300, -74.1456700),
    ('Droguería La Salud', 'Droguería La Salud', 'Calle 50 #40-20, El Poblado', '6041234567', 'lasalud@drogueria.com', 6.2442000, -75.5812000),
    ('Carnicería El Buen Corte', 'Carnicería El Buen Corte', 'Carrera 43A #5-20, Laureles', '6042345678', 'buencorte@carniceria.com', 6.2489300, -75.5968600)
ON CONFLICT DO NOTHING;

INSERT INTO assignments (seller_id, shopkeeper_id, assigned_by) VALUES 
    (1, 1, 1), (1, 2, 1), (1, 3, 1),
    (2, 4, 1), (2, 5, 1),
    (3, 6, 1), (3, 7, 1),
    (4, 8, 2), (4, 9, 2)
ON CONFLICT ON CONSTRAINT unique_active_assignment DO NOTHING;