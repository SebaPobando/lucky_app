-- =============================================================================
-- Lucky Point Coffee — Carta real
-- 60 productos en 9 categorías, extraídos de la carta que ya estaba en el sitio.
--
-- Corre esto DESPUÉS de schema_mysql.sql. Es idempotente: puedes volver a
-- correrlo y no duplica nada (borra la carta de Lucky Point y la reinserta).
-- =============================================================================

-- Fija la codificación de la conexión. Sin esto, según cómo cargues el archivo
-- (consola, pipe de PowerShell, otro cliente) los acentos pueden quedar
-- doble-codificados: 'Café' se guarda como 'CafÃ©' y ya no hay vuelta atrás
-- salvo recargando. Con esta línea da igual desde dónde lo corras.
SET NAMES utf8mb4;

USE lucky_point_db;

-- Los productos de la carta pueden llevar una etiqueta corta ("Favorito").
-- Se agrega solo si todavía no existe.
SET @existe := (SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema='lucky_point_db' AND table_name='productos'
                  AND column_name='etiqueta');
SET @sql := IF(@existe = 0,
    'ALTER TABLE productos ADD COLUMN etiqueta VARCHAR(30) NULL COMMENT ''Favorito, Nuevo, Verano...'' AFTER descripcion',
    'SELECT ''la columna etiqueta ya existe'' AS nota');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;


SET @marca := (SELECT id FROM marcas WHERE slug = 'lucky-point');

-- Limpieza previa, para que correrlo dos veces no duplique
DELETE FROM productos  WHERE marca_id = @marca;
DELETE FROM categorias WHERE marca_id = @marca;


-- Categorías -------------------------------------------------------------
INSERT INTO categorias (marca_id, slug, nombre, orden) VALUES
    (@marca, 'cafe', 'Café', 1),
    (@marca, 'dulces', 'Café dulces', 2),
    (@marca, 'choco', 'Chocolatozos', 3),
    (@marca, 'te', 'Té e infusiones', 4),
    (@marca, 'jugos', 'Jugos', 5),
    (@marca, 'verano', 'Carta verano', 6),
    (@marca, 'sandwich', 'Sándwich', 7),
    (@marca, 'pasteleria', 'Pastelería', 8),
    (@marca, 'bolleria', 'Bollería', 9);

-- Productos ---------------------------------------------------------------

-- Café (7 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='cafe');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'long-black', 'Long Black', 'Espresso doble vertido sobre agua caliente.', NULL, 3200, 1),
    (@marca, @cat, 'espresso-doble', 'Espresso Doble', '36 g extraídos a 9 bar, alta concentración de sabores.', NULL, 3000, 2),
    (@marca, @cat, 'short-black', 'Short Black', 'Espresso simple vertido sobre agua caliente.', NULL, 3200, 3),
    (@marca, @cat, 'filtrado', 'Filtrado', 'Vertido de agua sobre cama de café en filtro de papel.', NULL, 3800, 4),
    (@marca, @cat, 'latte', 'Latte', 'Espresso simple con leche texturizada y una sutil espuma.', NULL, 3800, 5),
    (@marca, @cat, 'capuccino', 'Capuccino', 'Espresso doble con leche y espuma en partes iguales.', NULL, 3800, 6),
    (@marca, @cat, 'flat-white', 'Flat White', 'Espresso doble con leche y espuma en partes iguales.', NULL, 3800, 7);

-- Café dulces (5 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='dulces');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'mokka', 'Mokka', 'Espresso doble emulsionado con chocolate, leche y espuma.', NULL, 4200, 1),
    (@marca, @cat, 'bombom', 'Bombom', 'Espresso doble con leche condensada, leche y espuma.', NULL, 4200, 2),
    (@marca, @cat, 'vaniglia', 'Vaniglia', 'Espresso doble con sirup de vainilla macerada y leche.', NULL, 4200, 3),
    (@marca, @cat, 'mokka-blanco', 'Mokka Blanco', 'Espresso doble emulsionado con chocolate blanco y leche.', NULL, 4200, 4),
    (@marca, @cat, 'mokka-nutella', 'Mokka Nutella', 'Espresso doble emulsionado con nutella y leche.', 'Favorito', 5500, 5);

-- Chocolatozos (3 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='choco');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'nutellatte', 'Nutellatte', 'Mezcla de nutella y leche texturizada.', NULL, 5500, 1),
    (@marca, @cat, 'chocolate-blanco', 'Chocolate Blanco', 'Chocolate blanco, crema, leche condensada y leche.', NULL, 5000, 2),
    (@marca, @cat, 'chocolate-caliente', 'Chocolate Caliente', 'Chocolate de leche, crema, cacao amargo y leche.', NULL, 5000, 3);

-- Té e infusiones (6 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='te');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'te-negro', 'Té Negro', 'Mezcla natural de té negro tradicional.', NULL, 3000, 1),
    (@marca, @cat, 'infusion-roibos', 'Infusión Roibos', 'Infusión de hojas de rooibos.', NULL, 3000, 2),
    (@marca, @cat, 'te-chai', 'Té Chai', 'Té con canela, cardamomo, jengibre y clavo. Leche +500.', NULL, 3000, 3),
    (@marca, @cat, 'te-cedron', 'Té Cedrón', 'Té de cedrón con cáscaras de naranja.', NULL, 3000, 4),
    (@marca, @cat, 'matcha-latte', 'Matcha Latte', 'Té matcha con leche texturizada.', NULL, 4500, 5),
    (@marca, @cat, 'matcha-latte-vainilla', 'Matcha Latte Vainilla', 'Matcha con leche y syrup casero de vainilla.', NULL, 5000, 6);

-- Jugos (6 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='jugos');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'jugo-de-pina', 'Jugo de Piña', 'Jugo natural de piña.', NULL, 4000, 1),
    (@marca, @cat, 'jugo-de-mango', 'Jugo de Mango', 'Jugo natural de mango.', NULL, 4000, 2),
    (@marca, @cat, 'jugo-de-frambuesa', 'Jugo de Frambuesa', 'Jugo natural de frambuesa.', NULL, 4000, 3),
    (@marca, @cat, 'limonada', 'Limonada', 'Limonada natural.', NULL, 4000, 4),
    (@marca, @cat, 'jugo-de-naranja', 'Jugo de Naranja', 'Jugo natural de naranja.', NULL, 3500, 5),
    (@marca, @cat, 'agua-natural', 'Agua Natural', 'Agua natural.', NULL, 2500, 6);

-- Carta verano (12 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='verano');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'aerocano', 'Aerocano', 'Espresso doble texturizado con agua y hielo.', 'Verano', 4500, 1),
    (@marca, @cat, 'filtrado-frio', 'Filtrado Frío', 'Filtrado recibido sobre cama de hielo.', NULL, 4200, 2),
    (@marca, @cat, 'espresso-frio', 'Espresso Frío', 'Doble shot de espresso sobre cama de hielo.', NULL, 3300, 3),
    (@marca, @cat, 'cold-brew', 'Cold Brew', 'Café infusionado en frío por 24 horas.', NULL, 4500, 4),
    (@marca, @cat, 'espresso-tonic', 'Espresso Tonic', 'Espresso y agua tónica.', NULL, 5500, 5),
    (@marca, @cat, 'iced-vaniglia', 'Iced Vaniglia', 'Doble shot, leche texturizada en frío y sirup de vainilla.', NULL, 5000, 6),
    (@marca, @cat, 'iced-capuccino', 'Iced Capuccino', 'Doble shot con leche texturizada en frío.', NULL, 4500, 7),
    (@marca, @cat, 'iced-latte', 'Iced Latte', 'Un shot de espresso y leche fría.', NULL, 4500, 8),
    (@marca, @cat, 'iced-moka', 'Iced Moka', 'Doble shot, leche en frío emulsionada con chocolate.', NULL, 5000, 9),
    (@marca, @cat, 'iced-bombon', 'Iced Bombón', 'Doble shot, leche en frío con leche condensada.', NULL, 5000, 10),
    (@marca, @cat, 'matcha-latte-frio', 'Matcha Latte Frío', 'Matcha suave mezclado con leche, cremoso y equilibrado.', NULL, 5000, 11),
    (@marca, @cat, 'matcha-vainilla-frio', 'Matcha Vainilla Frío', 'Matcha con leche fría y un toque de vainilla.', NULL, 6000, 12);

-- Sándwich (9 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='sandwich');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'ave-pimenton', 'Ave Pimentón', 'Ciabatta, pollo desmenuzado, lechuga y mayo de morrones.', NULL, 5500, 1),
    (@marca, @cat, 'croissant', 'Croissant', 'Hojaldre horneado, relleno con jamón y queso.', NULL, 5500, 2),
    (@marca, @cat, 'tostadas-palta-y-huevo', 'Tostadas Palta y Huevo', 'Masa madre, dos huevos, palta, sal, pimienta y oliva.', NULL, 7000, 3),
    (@marca, @cat, 'huevo-tocino-queso', 'Huevo Tocino Queso', 'Masa madre, huevo frito, tocino y queso mantecoso.', NULL, 7000, 4),
    (@marca, @cat, 'baba-ganoush', 'Baba Ganoush', 'Masa madre, salteado de morrón, berenjena y tomate.', NULL, 5500, 5),
    (@marca, @cat, 'mechada-con-queso', 'Mechada con Queso', 'Masa madre, carne mechada jugosa y queso derretido.', NULL, 6000, 6),
    (@marca, @cat, 'caprese', 'Caprese', 'Masa madre, cherry, queso cabra, albahaca y oliva.', NULL, 8000, 7),
    (@marca, @cat, 'el-serrano', 'El Serrano', 'Masa madre, jamón serrano, brie, rúcula y oliva.', NULL, 8000, 8),
    (@marca, @cat, 'tostadas-con-palta', 'Tostadas con Palta', 'Masa madre, palta laminada, sal, pimienta y oliva.', NULL, 5500, 9);

-- Pastelería (8 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='pasteleria');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'cheesecake-matcha', 'Cheesecake Matcha', 'Base cremosa de matcha con corazón de limón.', NULL, 5000, 1),
    (@marca, @cat, 'tiramisu', 'Tiramisú', 'Bizcocho al café, crema de mascarpone y cacao.', NULL, 6000, 2),
    (@marca, @cat, 'tartaleta-de-frambuesa', 'Tartaleta de Frambuesa', 'Base crujiente, crema suave y frambuesas frescas.', NULL, 4500, 3),
    (@marca, @cat, 'pie-de-limon', 'Pie de Limón', 'Base crujiente, crema de limón y merengue ligero.', NULL, 3500, 4),
    (@marca, @cat, 'galleton', 'Galletón', 'Oreo o limón, suave por dentro y crocante por fuera.', NULL, 3000, 5),
    (@marca, @cat, 'barra-proteina-chocolate', 'Barra Proteína Chocolate', 'Whey, creatina, chocolate bitter, frutos secos y coco.', NULL, 4000, 6),
    (@marca, @cat, 'barquillos', 'Barquillos', 'Crujientes y rellenos de manjar cremoso.', NULL, 2000, 7),
    (@marca, @cat, 'barra-proteina-semillas', 'Barra Proteína Semillas', 'Almendras, maní, semillas, cranberry y chocolate.', NULL, 3000, 8);

-- Bollería (4 ítems)
SET @cat := (SELECT id FROM categorias WHERE marca_id=@marca AND slug='bolleria');
INSERT INTO productos (marca_id, categoria_id, slug, nombre, descripcion, etiqueta, precio_clp, orden) VALUES
    (@marca, @cat, 'croissant-de-nutella', 'Croissant de Nutella', 'Hojaldre crujiente relleno de Nutella cremosa.', NULL, 5000, 1),
    (@marca, @cat, 'ny-roll-pistacho', 'NY Roll Pistacho', 'Masa hojaldrada rellena de crema de pistacho.', NULL, 5000, 2),
    (@marca, @cat, 'rollo-de-canela', 'Rollo de Canela', 'Masa suave con canela y glaseado dulce.', NULL, 4000, 3),
    (@marca, @cat, 'media-luna', 'Media Luna', 'Masa hojaldrada, suave por dentro y dorada por fuera.', NULL, 2000, 4);


-- Comprobación ------------------------------------------------------------
SELECT c.orden, c.nombre AS categoria, COUNT(p.id) AS items,
       CONCAT('$', FORMAT(MIN(p.precio_clp),0), ' - $', FORMAT(MAX(p.precio_clp),0)) AS rango,
       CONCAT(MIN(p.precio_clp)/10, ' - ', MAX(p.precio_clp)/10, ' LP') AS en_puntos
FROM categorias c
LEFT JOIN productos p ON p.categoria_id = c.id
WHERE c.marca_id = (SELECT id FROM marcas WHERE slug='lucky-point')
GROUP BY c.id ORDER BY c.orden;

SELECT COUNT(*) AS total_productos FROM productos;
