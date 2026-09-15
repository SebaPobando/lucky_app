-- =============================================================================
-- Lucky Point Coffee — Esquema de base de datos
-- MySQL 8.0.16 o superior  (las restricciones CHECK se ignoran en versiones
-- anteriores, y varias de ellas son lo que protege el saldo)
-- Versión 2 · septiembre 2026
--
-- Para verlo como diagrama en MySQL Workbench:
--   1. Ejecuta este archivo en tu servidor local
--   2. Database -> Reverse Engineer -> elige lucky_point_db
--   3. Workbench arma el EER solo, con las 20 tablas y sus relaciones
--   (Es mucho menos trabajo que dibujarlas a mano, y queda fiel al SQL real.)
--
-- Convenciones:
--   · Todo el dinero en CLP como INT. El peso chileno no tiene decimales.
--   · 1 LP = $10 CLP. El precio en LP se DERIVA del precio en CLP: no se guarda.
--   · Fechas en DATETIME, siempre en UTC. La app convierte a America/Santiago.
--     (No usamos TIMESTAMP: su rango se acaba en 2038.)
--   · Nada se borra: se marca con deleted_at o con un movimiento compensatorio.
-- =============================================================================

DROP DATABASE IF EXISTS lucky_point_db;
CREATE DATABASE lucky_point_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;   -- ai_ci = acentos y mayúsculas indiferentes
USE lucky_point_db;


-- =============================================================================
-- 1. MARCAS
-- Lucky Point (café) y Gladiatore (pizzas) comparten sitio, usuarios y saldo.
-- Separarlas permite repartir ingresos y cambiar la paleta por sección.
-- =============================================================================

CREATE TABLE marcas (
    id          SMALLINT      NOT NULL AUTO_INCREMENT,
    slug        VARCHAR(50)   NOT NULL,
    nombre      VARCHAR(100)  NOT NULL,
    tema_css    VARCHAR(50)   NOT NULL,
    activa      BOOLEAN       NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id),
    UNIQUE KEY uq_marcas_slug (slug)
) ENGINE=InnoDB;

INSERT INTO marcas (slug, nombre, tema_css) VALUES
    ('lucky-point', 'Lucky Point Coffee', 'lp'),
    ('gladiatore',  'Gladiatore',         'gladiatore');


-- =============================================================================
-- 2. USUARIOS
-- Una sola tabla para clientes, invitados y staff. El invitado que se inscribe
-- a una actividad sin cuenta queda con estado='invitado'; cuando después se
-- registra con el mismo correo, hereda todo su historial.
-- =============================================================================

CREATE TABLE usuarios (
    id                  BIGINT        NOT NULL AUTO_INCREMENT,
    -- La colación ai_ci ya hace la comparación insensible a mayúsculas.
    -- Igual: normaliza a minúsculas en la app antes de guardar.
    email               VARCHAR(255)  NOT NULL,
    email_verificado_at DATETIME      NULL COMMENT 'UTC. Requisito para girar la ruleta',
    nombre              VARCHAR(100)  NULL,
    apellido            VARCHAR(100)  NULL,
    nickname            VARCHAR(50)   NULL,
    telefono            VARCHAR(20)   NULL COMMENT 'Identificador en el mesón',
    -- RUT como '12345678-K'. El dígito verificador puede ser K y hay RUTs con
    -- ceros a la izquierda: por eso nunca INT. Pídelo SOLO si emitirás boleta;
    -- bajo la Ley 21.719 recolectarlo "por si acaso" te suma obligaciones gratis.
    rut                 VARCHAR(12)   NULL,
    fecha_nacimiento    DATE          NULL COMMENT 'Promo de cumpleaños',
    password_hash       VARCHAR(255)  NULL COMMENT 'argon2. NULL si solo usa magic link',
    rol                 ENUM('cliente','barista','admin')          NOT NULL DEFAULT 'cliente',
    estado              ENUM('invitado','activo','bloqueado')      NOT NULL DEFAULT 'invitado',
    created_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at          DATETIME      NULL COMMENT 'Borrado lógico: derecho del titular',
    PRIMARY KEY (id),
    UNIQUE KEY uq_usuarios_email (email),
    UNIQUE KEY uq_usuarios_rut (rut),      -- MySQL permite varios NULL en UNIQUE
    KEY idx_usuarios_telefono (telefono),
    KEY idx_usuarios_rol (rol)
) ENGINE=InnoDB;


-- =============================================================================
-- 3. LEDGER DE LUCKY POINTS  <- el corazón del sistema
--
-- APPEND-ONLY. Nunca UPDATE, nunca DELETE. ¿Te equivocaste? Insertas el
-- movimiento inverso. Esto es lo que permite auditar, revertir y responderle
-- a un cliente "¿por qué tengo este saldo?".
--
-- Dos bolsillos, porque no son lo mismo:
--   prepago : plata que el cliente pagó. No expira, es reembolsable,
--             es pasivo contable de la empresa.
--   promo   : LP regalados (bono de recarga, ruleta, campañas). Pueden expirar
--             y no se devuelven en dinero. Son gasto de marketing.
--
-- Regla de gasto (lógica de la app, no del esquema):
--   al consumir se descuenta PRIMERO de promo, y del más próximo a vencer.
-- =============================================================================

CREATE TABLE lp_movimientos (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    usuario_id      BIGINT       NOT NULL,
    bucket          ENUM('prepago','promo') NOT NULL,
    delta           INT          NOT NULL COMMENT '+ acumula, - descuenta',
    motivo          ENUM('recarga','bono_recarga','consumo','premio_ruleta',
                         'promocion','ajuste_manual','reembolso','expiracion') NOT NULL,
    marca_id        SMALLINT     NULL COMMENT 'Dónde se consumió',
    referencia_tipo VARCHAR(30)  NULL COMMENT 'recarga | orden | giro',
    referencia_id   BIGINT       NULL,
    -- Lo único que impide que un webhook reintentado sume dos veces.
    -- Formato sugerido: 'mp:payment:123456' / 'shopify:order:998877'
    idempotency_key VARCHAR(120) NULL,
    expira_at       DATETIME     NULL COMMENT 'UTC. Solo promo con delta > 0',
    creado_por      BIGINT       NULL COMMENT 'Qué staff lo hizo, si aplica',
    nota            TEXT         NULL COMMENT 'Obligatoria en ajuste_manual',
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_lpmov_idem (idempotency_key),
    KEY idx_lpmov_usuario (usuario_id, created_at DESC),
    KEY idx_lpmov_bucket (usuario_id, bucket),
    KEY idx_lpmov_vence (expira_at),
    CONSTRAINT fk_lpmov_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    CONSTRAINT fk_lpmov_marca   FOREIGN KEY (marca_id)   REFERENCES marcas(id),
    CONSTRAINT fk_lpmov_staff   FOREIGN KEY (creado_por) REFERENCES usuarios(id),
    CONSTRAINT chk_delta_no_cero  CHECK (delta <> 0),
    -- Los LP prepago son dinero: no pueden expirar.
    CONSTRAINT chk_expira_solo_promo
        CHECK (expira_at IS NULL OR bucket = 'promo'),
    -- Un ajuste manual sin explicación es un agujero de auditoría.
    CONSTRAINT chk_ajuste_con_nota
        CHECK (motivo <> 'ajuste_manual' OR nota IS NOT NULL)
) ENGINE=InnoDB;

-- El saldo se CALCULA. Si algún día pesa, se cachea en otra tabla,
-- pero el ledger sigue siendo la única fuente de verdad.
CREATE VIEW lp_saldos AS
SELECT
    usuario_id,
    COALESCE(SUM(CASE WHEN bucket = 'prepago' THEN delta ELSE 0 END), 0) AS saldo_prepago,
    COALESCE(SUM(CASE WHEN bucket = 'promo'   THEN delta ELSE 0 END), 0) AS saldo_promo,
    COALESCE(SUM(delta), 0)                                              AS saldo_total
FROM lp_movimientos
GROUP BY usuario_id;

-- Para el balance del negocio: cuánto le debes a tus clientes.
-- Los LP prepago no canjeados son deuda real, no ingreso.
CREATE VIEW lp_pasivo AS
SELECT
    COALESCE(SUM(CASE WHEN bucket = 'prepago' THEN delta ELSE 0 END), 0)      AS lp_prepago_circulando,
    COALESCE(SUM(CASE WHEN bucket = 'prepago' THEN delta ELSE 0 END), 0) * 10 AS deuda_clp,
    COALESCE(SUM(CASE WHEN bucket = 'promo'   THEN delta ELSE 0 END), 0)      AS lp_promo_circulando
FROM lp_movimientos;


-- =============================================================================
-- 4. RECARGAS
-- Tramos: 10k -> 1100 LP · 20k -> 2300 LP · 40k -> 4800 LP
-- Es decir: base = monto/10, más un bono de 10% / 15% / 20%.
-- El bono entra al ledger como bucket 'promo' en un movimiento SEPARADO, para
-- poder medir después cuánto margen estás regalando por tramo.
-- =============================================================================

CREATE TABLE recargas (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    usuario_id    BIGINT       NOT NULL,
    tramo         VARCHAR(10)  NOT NULL COMMENT '10k | 20k | 40k',
    monto_clp     INT          NOT NULL,
    lp_base       INT          NOT NULL,
    lp_bono       INT          NOT NULL DEFAULT 0,
    estado        ENUM('pendiente','pagada','rechazada','reembolsada') NOT NULL DEFAULT 'pendiente',
    pasarela      VARCHAR(30)  NOT NULL DEFAULT 'mercadopago',
    pasarela_ref  VARCHAR(100) NULL COMMENT 'payment_id de MercadoPago',
    tarjeta_id    BIGINT       NULL COMMENT 'FK se agrega al final (fase posterior)',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_recargas_pasarela (pasarela, pasarela_ref),
    KEY idx_recargas_usuario (usuario_id, created_at DESC),
    CONSTRAINT fk_recargas_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    CONSTRAINT chk_recarga_monto CHECK (monto_clp > 0),
    CONSTRAINT chk_recarga_base  CHECK (lp_base > 0),
    CONSTRAINT chk_recarga_bono  CHECK (lp_bono >= 0)
) ENGINE=InnoDB;


-- =============================================================================
-- 5. CARTA: CATEGORÍAS Y PRODUCTOS
-- Lo que el admin edita sin hacer deploy. Incluye la carta de pizzas.
-- =============================================================================

CREATE TABLE categorias (
    id        INT          NOT NULL AUTO_INCREMENT,
    marca_id  SMALLINT     NOT NULL,
    slug      VARCHAR(50)  NOT NULL,
    nombre    VARCHAR(100) NOT NULL,
    orden     INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_categorias_marca_slug (marca_id, slug),
    CONSTRAINT fk_categorias_marca FOREIGN KEY (marca_id) REFERENCES marcas(id)
) ENGINE=InnoDB;

CREATE TABLE productos (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    marca_id      SMALLINT     NOT NULL,
    categoria_id  INT          NULL,
    slug          VARCHAR(80)  NOT NULL,
    nombre        VARCHAR(150) NOT NULL,
    descripcion   TEXT         NULL,
    -- El precio en LP NO se guarda: es precio_clp / 10.
    -- Guardar los dos garantiza que algún día se desincronicen.
    precio_clp    INT          NOT NULL,
    imagen_url    VARCHAR(255) NULL,
    disponible    BOOLEAN      NOT NULL DEFAULT TRUE,
    orden         INT          NOT NULL DEFAULT 0,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_productos_marca_slug (marca_id, slug),
    KEY idx_productos_carta (marca_id, categoria_id, disponible, orden),
    CONSTRAINT fk_productos_marca     FOREIGN KEY (marca_id)     REFERENCES marcas(id),
    CONSTRAINT fk_productos_categoria FOREIGN KEY (categoria_id) REFERENCES categorias(id),
    CONSTRAINT chk_producto_precio CHECK (precio_clp >= 0)
) ENGINE=InnoDB;


-- =============================================================================
-- 6. ÓRDENES
-- Reemplazan al `movimientos.detalle TEXT` del modelo original. Con líneas
-- reales puedes responder "cuántos flat white vendimos en julio";
-- con un TEXT, nunca.
-- =============================================================================

CREATE TABLE ordenes (
    id            BIGINT   NOT NULL AUTO_INCREMENT,
    usuario_id    BIGINT   NULL COMMENT 'NULL = venta sin cuenta',
    marca_id      SMALLINT NOT NULL,
    canal         ENUM('meson','web','shopify') NOT NULL,
    estado        ENUM('borrador','confirmada','preparando','lista','entregada','anulada')
                  NOT NULL DEFAULT 'confirmada',
    total_clp     INT      NOT NULL DEFAULT 0,
    pagado_lp     INT      NOT NULL DEFAULT 0,
    pagado_clp    INT      NOT NULL DEFAULT 0,
    atendido_por  BIGINT   NULL COMMENT 'Staff',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_ordenes_usuario (usuario_id, created_at DESC),
    KEY idx_ordenes_fecha (created_at DESC),
    CONSTRAINT fk_ordenes_usuario FOREIGN KEY (usuario_id)   REFERENCES usuarios(id),
    CONSTRAINT fk_ordenes_marca   FOREIGN KEY (marca_id)     REFERENCES marcas(id),
    CONSTRAINT fk_ordenes_staff   FOREIGN KEY (atendido_por) REFERENCES usuarios(id),
    CONSTRAINT chk_orden_total  CHECK (total_clp  >= 0),
    CONSTRAINT chk_orden_lp     CHECK (pagado_lp  >= 0),
    CONSTRAINT chk_orden_clp    CHECK (pagado_clp >= 0)
) ENGINE=InnoDB;

CREATE TABLE orden_items (
    id                  BIGINT       NOT NULL AUTO_INCREMENT,
    orden_id            BIGINT       NOT NULL,
    producto_id         BIGINT       NULL,
    -- Snapshot obligatorio: si mañana subes el precio, las órdenes históricas
    -- no pueden cambiar de monto. Nunca dependas solo del FK.
    nombre_snapshot     VARCHAR(150) NOT NULL,
    precio_clp_snapshot INT          NOT NULL,
    cantidad            SMALLINT     NOT NULL,
    PRIMARY KEY (id),
    KEY idx_items_orden (orden_id),
    KEY idx_items_producto (producto_id),
    CONSTRAINT fk_items_orden    FOREIGN KEY (orden_id)    REFERENCES ordenes(id) ON DELETE CASCADE,
    CONSTRAINT fk_items_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    CONSTRAINT chk_item_precio   CHECK (precio_clp_snapshot >= 0),
    CONSTRAINT chk_item_cantidad CHECK (cantidad > 0)
) ENGINE=InnoDB;


-- =============================================================================
-- 7. BENEFICIOS  <- el "objeto Lucky Point" que faltaba en el modelo original
--
-- `beneficios` es el CATÁLOGO: qué se puede obtener.
-- `beneficios_usuario` es la INSTANCIA: el cupón que una persona posee.
--
-- Una sola cañería sirve para los tres casos: premio de ruleta, canje con LP
-- y promoción manual. El flujo de canje en el mesón se construye una vez.
-- =============================================================================

CREATE TABLE beneficios (
    id          INT          NOT NULL AUTO_INCREMENT,
    slug        VARCHAR(60)  NOT NULL,
    nombre      VARCHAR(100) NOT NULL COMMENT 'Café gratis',
    descripcion TEXT         NULL,
    tipo        ENUM('producto_gratis','descuento_pct','descuento_clp','lp_extra') NOT NULL,
    valor       INT          NULL COMMENT '% o CLP o LP, según tipo',
    producto_id BIGINT       NULL,
    costo_lp    INT          NULL COMMENT 'NULL = no se compra, solo se gana',
    marca_id    SMALLINT     NULL COMMENT 'NULL = vale en ambas marcas',
    activo      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_beneficios_slug (slug),
    CONSTRAINT fk_beneficios_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    CONSTRAINT fk_beneficios_marca    FOREIGN KEY (marca_id)    REFERENCES marcas(id)
) ENGINE=InnoDB;

CREATE TABLE beneficios_usuario (
    id             BIGINT      NOT NULL AUTO_INCREMENT,
    usuario_id     BIGINT      NOT NULL,
    beneficio_id   INT         NOT NULL,
    origen         VARCHAR(30) NOT NULL COMMENT 'ruleta | canje_lp | promocion | manual',
    origen_ref     BIGINT      NULL,
    codigo         VARCHAR(12) NOT NULL COMMENT '6 dígitos, se dicta al barista',
    estado         ENUM('disponible','usado','vencido','anulado') NOT NULL DEFAULT 'disponible',
    vence_at       DATETIME    NULL COMMENT 'Corto (7-14 días) para que la persona vuelva',
    usado_at       DATETIME    NULL,
    usado_en_orden BIGINT      NULL,
    canjeado_por   BIGINT      NULL COMMENT 'Qué barista',
    created_at     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_benuser_codigo (codigo),
    KEY idx_benuser_usuario (usuario_id, estado),
    KEY idx_benuser_vence (estado, vence_at),
    CONSTRAINT fk_benuser_usuario   FOREIGN KEY (usuario_id)     REFERENCES usuarios(id),
    CONSTRAINT fk_benuser_beneficio FOREIGN KEY (beneficio_id)   REFERENCES beneficios(id),
    CONSTRAINT fk_benuser_orden     FOREIGN KEY (usado_en_orden) REFERENCES ordenes(id),
    CONSTRAINT fk_benuser_staff     FOREIGN KEY (canjeado_por)   REFERENCES usuarios(id)
) ENGINE=InnoDB;


-- =============================================================================
-- 8. RULETA
-- El premio lo decide SIEMPRE el servidor: el giro en pantalla es animación,
-- el resultado ya venía en la respuesta. Si lo decide el cliente, alguien abre
-- la consola del navegador y se gana cafés infinitos.
-- =============================================================================

CREATE TABLE ruleta_premios (
    id                INT          NOT NULL AUTO_INCREMENT,
    beneficio_id      INT          NULL COMMENT 'NULL = "sigue participando"',
    etiqueta          VARCHAR(60)  NOT NULL COMMENT 'Lo que se lee en la ruleta',
    peso              INT          NOT NULL COMMENT 'Probabilidad relativa',
    -- Sin tope, un bug o un post viral te vacía la caja.
    tope_semanal      INT          NULL COMMENT 'NULL = sin límite',
    entregados_semana INT          NOT NULL DEFAULT 0,
    activo            BOOLEAN      NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id),
    CONSTRAINT fk_premios_beneficio FOREIGN KEY (beneficio_id) REFERENCES beneficios(id),
    CONSTRAINT chk_premio_peso CHECK (peso >= 0)
) ENGINE=InnoDB;

CREATE TABLE ruleta_giros (
    id                   BIGINT      NOT NULL AUTO_INCREMENT,
    usuario_id           BIGINT      NOT NULL,
    premio_id            INT         NULL,
    beneficio_usuario_id BIGINT      NULL,
    -- Columna explícita en vez de derivarla de created_at: CURRENT_DATE depende
    -- de la zona horaria de la sesión MySQL. Que la app la escriba con la fecha
    -- de America/Santiago, o configura time_zone='-04:00' en la conexión.
    dia                  DATE        NOT NULL DEFAULT (CURRENT_DATE),
    ip                   VARCHAR(45) NULL COMMENT 'Cabe IPv6',
    user_agent           VARCHAR(255) NULL,
    created_at           DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    -- Un giro por persona por día. Sin esto, correos infinitos = premios infinitos.
    UNIQUE KEY uq_giro_uno_por_dia (usuario_id, dia),
    CONSTRAINT fk_giros_usuario  FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    CONSTRAINT fk_giros_premio   FOREIGN KEY (premio_id)  REFERENCES ruleta_premios(id),
    CONSTRAINT fk_giros_beneficio FOREIGN KEY (beneficio_usuario_id) REFERENCES beneficios_usuario(id)
) ENGINE=InnoDB;


-- =============================================================================
-- 9. ACTIVIDADES E INSCRIPCIONES
-- El cupo se maneja como STOCK de un producto en Shopify: Shopify cobra y
-- controla el sobrecupo por ti, y el webhook crea la inscripción acá.
-- =============================================================================

CREATE TABLE actividades (
    id                       BIGINT       NOT NULL AUTO_INCREMENT,
    marca_id                 SMALLINT     NULL,
    slug                     VARCHAR(80)  NOT NULL,
    nombre                   VARCHAR(150) NOT NULL,
    descripcion              TEXT         NULL,
    -- Reemplazan a horario_actividad + fecha_actividad, que se pisaban.
    inicio_at                DATETIME     NOT NULL COMMENT 'UTC',
    fin_at                   DATETIME     NULL,
    lugar                    VARCHAR(200) NULL,
    cupos                    SMALLINT     NOT NULL,
    precio_clp               INT          NOT NULL DEFAULT 0,
    shopify_product_id       BIGINT       NULL COMMENT 'El stock = los cupos',
    google_calendar_event_id VARCHAR(120) NULL COMMENT 'Botón "agregar al calendario"',
    estado                   ENUM('borrador','publicada','cancelada','realizada') NOT NULL DEFAULT 'borrador',
    created_at               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_actividades_slug (slug),
    KEY idx_actividades_agenda (estado, inicio_at),
    CONSTRAINT fk_actividades_marca FOREIGN KEY (marca_id) REFERENCES marcas(id),
    CONSTRAINT chk_actividad_cupos CHECK (cupos > 0),
    CONSTRAINT chk_actividad_fin   CHECK (fin_at IS NULL OR fin_at > inicio_at)
) ENGINE=InnoDB;

CREATE TABLE inscripciones (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    actividad_id  BIGINT       NOT NULL,
    -- El invitado sin cuenta también es un usuario (estado='invitado').
    -- Así el modelo no se bifurca y su historial lo espera si después se registra.
    usuario_id    BIGINT       NOT NULL,
    estado        ENUM('pendiente','pagada','cancelada','asistio','no_asistio') NOT NULL DEFAULT 'pendiente',
    monto_clp     INT          NOT NULL DEFAULT 0,
    pago_ref      VARCHAR(100) NULL COMMENT 'Id de orden Shopify',
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_inscripcion (actividad_id, usuario_id),
    KEY idx_inscripciones_estado (actividad_id, estado),
    CONSTRAINT fk_inscripciones_actividad FOREIGN KEY (actividad_id) REFERENCES actividades(id),
    CONSTRAINT fk_inscripciones_usuario   FOREIGN KEY (usuario_id)   REFERENCES usuarios(id)
) ENGINE=InnoDB;


-- =============================================================================
-- 10. WEBHOOKS
-- MercadoPago y Shopify REINTENTAN. Sin esta tabla, un reintento duplica los
-- puntos del cliente. Es la diferencia entre un sistema y un problema.
-- =============================================================================

CREATE TABLE webhook_events (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    origen       VARCHAR(30)  NOT NULL COMMENT 'shopify | mercadopago',
    evento_id    VARCHAR(120) NOT NULL COMMENT 'Id del evento en el origen',
    topico       VARCHAR(60)  NULL COMMENT 'orders/paid, payment.updated',
    payload      JSON         NOT NULL,
    procesado_at DATETIME     NULL,
    error        TEXT         NULL,
    intentos     SMALLINT     NOT NULL DEFAULT 0,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_webhook_evento (origen, evento_id),
    KEY idx_webhooks_pendientes (procesado_at, created_at)
) ENGINE=InnoDB;


-- =============================================================================
-- 11. LISTA DE DESEOS
-- Antes era texto libre. Apuntando a productos sí sirve para algo: saber qué
-- quiere la gente que aún no vendes o que se te acaba seguido.
-- =============================================================================

CREATE TABLE deseos (
    id          BIGINT   NOT NULL AUTO_INCREMENT,
    usuario_id  BIGINT   NOT NULL,
    producto_id BIGINT   NULL,
    nota        TEXT     NULL COMMENT 'Para lo que aún no está en la carta',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_deseo (usuario_id, producto_id),
    CONSTRAINT fk_deseos_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuarios(id) ON DELETE CASCADE,
    CONSTRAINT fk_deseos_producto FOREIGN KEY (producto_id) REFERENCES productos(id)
) ENGINE=InnoDB;


-- =============================================================================
-- 12. SUSCRIPCIÓN DE CAFÉ  (fase posterior)
-- Semestral y anual NO necesitan cobro recurrente: son un pago único con
-- entregas programadas. Solo la mensual requiere MercadoPago Suscripciones.
-- =============================================================================

CREATE TABLE suscripciones (
    id                  BIGINT       NOT NULL AUTO_INCREMENT,
    usuario_id          BIGINT       NOT NULL,
    periodo             ENUM('mensual','semestral','anual') NOT NULL,
    estado              ENUM('activa','pausada','cancelada','vencida') NOT NULL DEFAULT 'activa',
    entrega             ENUM('retiro_tienda','delivery') NOT NULL DEFAULT 'retiro_tienda',
    gramos_por_entrega  INT          NOT NULL DEFAULT 250,
    variedades          SMALLINT     NOT NULL DEFAULT 1,
    direccion_envio     VARCHAR(255) NULL,
    -- Bluexpress prepagado: se compra junto con la suscripción.
    envio_prepagado_clp INT          NOT NULL DEFAULT 0,
    inicio_at           DATE         NOT NULL,
    termino_at          DATE         NULL,
    mp_preapproval_id   VARCHAR(100) NULL COMMENT 'Solo mensual',
    created_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_suscripciones_usuario (usuario_id, estado),
    CONSTRAINT fk_suscripciones_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id),
    CONSTRAINT chk_direccion_si_delivery
        CHECK (entrega <> 'delivery' OR direccion_envio IS NOT NULL)
) ENGINE=InnoDB;

CREATE TABLE suscripcion_entregas (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    suscripcion_id  BIGINT       NOT NULL,
    programada_para DATE         NOT NULL,
    entregada_at    DATETIME     NULL,
    producto_id     BIGINT       NULL COMMENT 'Variedad elegida',
    tracking        VARCHAR(100) NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_entregas_pendientes (entregada_at, programada_para),
    CONSTRAINT fk_entregas_suscripcion FOREIGN KEY (suscripcion_id) REFERENCES suscripciones(id) ON DELETE CASCADE,
    CONSTRAINT fk_entregas_producto    FOREIGN KEY (producto_id)    REFERENCES productos(id)
) ENGINE=InnoDB;


-- =============================================================================
-- 13. TARJETAS FÍSICAS DE RECARGA  (fase posterior)
-- Arrancamos con recarga digital. Cuando existan las tarjetas impresas:
--   · el código NUNCA se guarda en claro, solo su hash
--   · se ACTIVA al venderla, para que una tarjeta robada del mostrador no sirva
-- =============================================================================

CREATE TABLE tarjetas_recarga (
    id           BIGINT       NOT NULL AUTO_INCREMENT,
    codigo_hash  VARCHAR(255) NOT NULL,
    tramo        VARCHAR(10)  NOT NULL COMMENT '10k | 20k | 40k',
    lp_total     INT          NOT NULL,
    estado       ENUM('impresa','activada','canjeada','anulada') NOT NULL DEFAULT 'impresa',
    activada_at  DATETIME     NULL,
    activada_por BIGINT       NULL,
    canjeada_at  DATETIME     NULL,
    canjeada_por BIGINT       NULL,
    created_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_tarjeta_hash (codigo_hash),
    CONSTRAINT fk_tarjeta_activada FOREIGN KEY (activada_por) REFERENCES usuarios(id),
    CONSTRAINT fk_tarjeta_canjeada FOREIGN KEY (canjeada_por) REFERENCES usuarios(id),
    CONSTRAINT chk_tarjeta_lp CHECK (lp_total > 0)
) ENGINE=InnoDB;

ALTER TABLE recargas
    ADD CONSTRAINT fk_recargas_tarjeta
    FOREIGN KEY (tarjeta_id) REFERENCES tarjetas_recarga(id);


-- =============================================================================
-- NOTAS DE IMPLEMENTACIÓN
-- =============================================================================
--
-- CANJE ATÓMICO. Todo consumo de LP va dentro de una transacción que primero
-- bloquea al usuario, o dos baristas cobrando a la vez dejan el saldo negativo:
--
--     START TRANSACTION;
--       SELECT id FROM usuarios WHERE id = ? FOR UPDATE;
--       SELECT saldo_total FROM lp_saldos WHERE usuario_id = ?;
--       -- validar que alcanza
--       INSERT INTO lp_movimientos (...);   -- primero promo, luego prepago
--     COMMIT;
--
-- El FOR UPDATE solo funciona con autocommit apagado: ver mysqlconnection.py.
--
-- ORDEN DE GASTO. Al consumir, descontar en este orden:
--   1. promo, del que vence más pronto
--   2. prepago
-- Así el cliente nunca pierde plata que pagó por no haber usado un regalo.
--
-- EXPIRACIÓN. Un job diario inserta movimientos 'expiracion' (delta negativo,
-- bucket promo) por los LP promocionales vencidos. Nunca borra filas.
--
-- IDEMPOTENCIA. Todo movimiento originado en un webhook lleva idempotency_key.
-- Test obligatorio: reenviar el mismo webhook 10 veces y verificar que el
-- saldo no cambia.
--
-- LO QUE NO ESTÁ ACÁ. Sesiones y tokens de magic link: los maneja Flask, no
-- conviene modelarlos a mano.
-- =============================================================================
