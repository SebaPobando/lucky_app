-- =============================================================================
-- Gladiatore — Carta real
-- 17 productos en 4 categorías, transcritos de la carta impresa.
--
-- Corre esto DESPUÉS de schema_mysql.sql. Es idempotente: puedes volver a
-- correrlo y no duplica nada (borra la carta de Gladiatore y la reinserta).
--
-- OJO: Gladiatore es otra sociedad, con otro RUT. Este archivo NO toca nada de
-- Lucky Point: filtra por marca en cada borrado.
-- =============================================================================

-- Fija la codificación de la conexión. Sin esto, según cómo cargues el archivo
-- los acentos quedan doble-codificados y 'Rómulo' se guarda como 'RÃ³mulo'.
SET NAMES utf8mb4;

USE lucky_point_db;


-- -----------------------------------------------------------------------------
-- Segundo precio: las pizzas vienen en familiar e individual.
-- Se agrega solo si todavía no existe, para que correr esto sobre una base ya
-- creada no falle.
-- -----------------------------------------------------------------------------
SET @existe := (SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = 'lucky_point_db'
                  AND table_name   = 'productos'
                  AND column_name  = 'precio_individual_clp');
SET @sql := IF(@existe = 0,
    'ALTER TABLE productos ADD COLUMN precio_individual_clp INT NULL
       COMMENT ''NULL = el producto tiene un solo precio'' AFTER precio_clp',
    'SELECT ''la columna precio_individual_clp ya existe'' AS nota');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- La etiqueta puede no existir si nunca corriste el seed de Lucky Point.
SET @existe := (SELECT COUNT(*) FROM information_schema.columns
                WHERE table_schema = 'lucky_point_db'
                  AND table_name   = 'productos'
                  AND column_name  = 'etiqueta');
SET @sql := IF(@existe = 0,
    'ALTER TABLE productos ADD COLUMN etiqueta VARCHAR(30) NULL AFTER descripcion',
    'SELECT ''la columna etiqueta ya existe'' AS nota');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;


SET @marca := (SELECT id FROM marcas WHERE slug = 'gladiatore');


-- -----------------------------------------------------------------------------
-- Limpieza previa, para que correrlo dos veces no duplique.
-- Solo la carta de Gladiatore: los 60 productos de la cafetería no se tocan.
-- -----------------------------------------------------------------------------
DELETE FROM productos  WHERE marca_id = @marca;
DELETE FROM categorias WHERE marca_id = @marca;


-- -----------------------------------------------------------------------------
-- Categorías, en el orden de la carta impresa
-- -----------------------------------------------------------------------------
INSERT INTO categorias (marca_id, slug, nombre, orden) VALUES
    (@marca, 'pizzas',      'Pizzas',      1),
    (@marca, 'pastas',      'Pastas',      2),
    (@marca, 'bebestibles', 'Bebestibles', 3),
    (@marca, 'promos',      'Promos',      4);

SET @pizzas := (SELECT id FROM categorias WHERE marca_id = @marca AND slug = 'pizzas');
SET @pastas := (SELECT id FROM categorias WHERE marca_id = @marca AND slug = 'pastas');
SET @bebes  := (SELECT id FROM categorias WHERE marca_id = @marca AND slug = 'bebestibles');
SET @promos := (SELECT id FROM categorias WHERE marca_id = @marca AND slug = 'promos');


-- -----------------------------------------------------------------------------
-- PIZZAS
-- precio_clp = familiar · precio_individual_clp = individual
-- El orden es el de la carta impresa, no el de precio.
-- -----------------------------------------------------------------------------
INSERT INTO productos
    (marca_id, categoria_id, slug, nombre, descripcion, etiqueta,
     precio_clp, precio_individual_clp, disponible, orden)
VALUES
    (@marca, @pizzas, 'margherita', 'Margherita',
     'Pomodoro, mozzarella, albahaca.', NULL, 10000, 6000, TRUE, 1),

    (@marca, @pizzas, 'quattro-formagio', 'Quattro Formagio',
     'Pomodoro, mozzarella, queso azul, mantecoso, parmigiano.', NULL, 12990, 7000, TRUE, 2),

    (@marca, @pizzas, 'pepperoni', 'Pepperoni',
     'Pomodoro, mozzarella, pepperoni.', NULL, 11990, 6000, TRUE, 3),

    (@marca, @pizzas, 'serrano-rucula', 'Serrano Rucula',
     'Pomodoro, mozzarella, rúcula, jamón serrano, parmesano.', NULL, 13990, 7500, TRUE, 4),

    (@marca, @pizzas, 'marinara', 'Marinara',
     'Pomodoro, aceite de ajo, ajo picado, albahaca.', NULL, 8500, 6000, TRUE, 5),

    (@marca, @pizzas, 'harrington', 'Harrington',
     'Pomodoro, mozzarella, parmigiano, rúcula, aceite de ajo.', NULL, 12990, 7000, TRUE, 6),

    (@marca, @pizzas, 'casa-bianca', 'Casa Bianca',
     'Crema, jamón, champiñón, cebolla blanca, parmesano, estragón.', NULL, 13990, 7500, TRUE, 7),

    (@marca, @pizzas, 'per-bambini', 'Per Bambini',
     'Base nutella, marshmellow, frutilla o plátano.', NULL, 13990, 7500, TRUE, 8),

    -- Rómulo y Remo van juntos en la carta impresa, con su propio relato.
    (@marca, @pizzas, 'romulo', 'Rómulo',
     'Pomodoro, mozzarella, pepperoni, aceituna negra, orégano.', 'La dupla', 12990, 7000, TRUE, 9),

    (@marca, @pizzas, 'remo', 'Remo',
     'Pomodoro, mozzarella, jamón, cebolla, aceituna, orégano.', 'La dupla', 12990, 7000, TRUE, 10),

    (@marca, @pizzas, 'porco-dio', 'Porco Dio',
     'Pomodoro, mozzarella, jamón, tocino, cebolla, huevo.', NULL, 14990, 8000, TRUE, 11);


-- -----------------------------------------------------------------------------
-- PASTAS
-- En la carta aparecen dos precios, $7.000 y $8.000, pero NO son familiar e
-- individual: el segundo incluye la bebida. Por eso van como dos productos
-- distintos y no como dos columnas del mismo: son dos cosas que se piden.
-- -----------------------------------------------------------------------------
INSERT INTO productos
    (marca_id, categoria_id, slug, nombre, descripcion, etiqueta,
     precio_clp, precio_individual_clp, disponible, orden)
VALUES
    (@marca, @pastas, 'pastas', 'Pastas',
     'Consulta por la variedad del día.', NULL, 7000, NULL, TRUE, 1),

    (@marca, @pastas, 'pastas-con-bebida', 'Pastas + bebida en lata',
     'Consulta por la variedad del día. Incluye bebida en lata.', NULL, 8000, NULL, TRUE, 2);


-- -----------------------------------------------------------------------------
-- BEBESTIBLES
-- -----------------------------------------------------------------------------
INSERT INTO productos
    (marca_id, categoria_id, slug, nombre, descripcion, etiqueta,
     precio_clp, precio_individual_clp, disponible, orden)
VALUES
    (@marca, @bebes, 'bebida-lata', 'Bebida en lata',
     'Coca Cola, Coca Cola Zero, Fanta o Sprite.', NULL, 2000, NULL, TRUE, 1),

    (@marca, @bebes, 'bebida-15-litros', 'Bebida 1,5 litros',
     'Coca Cola, Coca Cola Zero, Fanta o Sprite.', NULL, 2500, NULL, TRUE, 2);


-- -----------------------------------------------------------------------------
-- PROMOS
-- Los palitos de ajo van acá porque así están impresos, al lado de la promo.
-- Si prefieres que sean una entrada, se cambia con el desplegable del admin.
-- -----------------------------------------------------------------------------
INSERT INTO productos
    (marca_id, categoria_id, slug, nombre, descripcion, etiqueta,
     precio_clp, precio_individual_clp, disponible, orden)
VALUES
    (@marca, @promos, 'promo-2x', 'Promo 2x',
     'Dos pizzas familiares: Pepperoni y/o Margherita.', 'Promo', 18000, NULL, TRUE, 1),

    (@marca, @promos, 'palitos-de-ajo', 'Palitos de ajo',
     'Diez unidades.', NULL, 4500, NULL, TRUE, 2);


-- -----------------------------------------------------------------------------
-- Comprobación
-- -----------------------------------------------------------------------------
SELECT c.nombre                                 AS categoria,
       COUNT(p.id)                              AS productos,
       SUM(p.precio_individual_clp IS NOT NULL) AS con_dos_precios
FROM categorias c
LEFT JOIN productos p ON p.categoria_id = c.id
WHERE c.marca_id = @marca
GROUP BY c.id, c.nombre, c.orden
ORDER BY c.orden;
