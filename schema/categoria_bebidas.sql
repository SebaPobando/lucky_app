-- =============================================================================
-- Lucky Point Coffee — Categoría Bebidas
-- Migración incremental: se corre SOBRE la base que ya existe.
--
-- Agrega una categoría vacía solo a Lucky Point. Si existe "Jugos", Bebidas
-- queda inmediatamente después; si la carta todavía está casi vacía, queda al
-- final. No toca Gladiatore ni crea productos. Se puede correr más de una vez.
-- =============================================================================

SET NAMES utf8mb4;
USE lucky_point_db;

SET @marca := (
    SELECT id FROM marcas WHERE slug = 'lucky-point' LIMIT 1
);

SET @existe := (
    SELECT COUNT(*)
    FROM categorias
    WHERE marca_id = @marca AND slug = 'bebidas'
);

SET @orden := COALESCE(
    (SELECT orden + 1 FROM categorias
     WHERE marca_id = @marca AND slug = 'jugos' LIMIT 1),
    (SELECT COALESCE(MAX(orden), 0) + 1 FROM categorias
     WHERE marca_id = @marca)
);

-- Se desplazan una sola vez: únicamente cuando Bebidas todavía no existe.
UPDATE categorias
SET orden = orden + 1
WHERE marca_id = @marca
  AND orden >= @orden
  AND @existe = 0;

INSERT INTO categorias (marca_id, slug, nombre, orden)
SELECT @marca, 'bebidas', 'Bebidas', @orden
WHERE @marca IS NOT NULL AND @existe = 0;

