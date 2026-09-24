# Lucky Point Coffee — contexto para quien siga

Este archivo es el traspaso. Si eres un agente trabajando en este repo, léelo
entero antes de tocar nada: casi todas las decisiones de acá abajo tienen un
motivo que no se deduce mirando el código, y varias se tomaron **después** de
equivocarse una vez.

Escrito el 2026-09-11.

---

## 1. Qué es esto

Sitio web y sistema de gestión para **Lucky Point Coffee**, una cafetería de
especialidad en Osorno, Chile. Es un proyecto freelance: la cafetería es el
cliente, no el negocio del desarrollador. Trabaja una sola persona, ~6 h a la
semana.

Segunda marca en el mismo sitio: **Gladiatore** (pizzas). Es **otra sociedad,
con otro RUT**, y por eso la tabla `marcas` tiene `razon_social` y `rut`.

### Reglas del proyecto (no negociables)

- **Front: HTML5, CSS3 puro y JavaScript vanilla.** Sin frameworks de JS, sin
  SASS, sin librerías (ni para el carrusel, ni para el carrito, ni para nada).
- **Variables CSS** (custom properties) para colores y tipografías, y
  **metodología BEM** para las clases. El día que esto se migre a un framework,
  eso es lo que lo hace posible.
- **Mobile first y 100% responsivo.**
- **Precios duales siempre**: `$X CLP | Y Lucky Points`. 1 LP = $10 CLP.
- Back: **Flask + MySQL, con SQL crudo. Sin ORM.**

### Idioma

Todo el código, los comentarios, los nombres de variables y los mensajes están
**en español**. Mantenerlo así. Los comentarios explican el **por qué**, no el
qué; varios documentan errores que ya se cometieron, y borrarlos es invitar a
repetirlos.

---

## 2. Las dos carpetas

```
C:\Users\sebap\Documents\Workspace\
├── lucky-point\     ← NO SE TOCA. Repo publicado en GitHub Pages
│                       (rama main, carpeta /docs) sobre
│                       www.luckypointcoffee.cl. Ahí vive también el
│                       sistema de diseño (tokens, componentes, guías).
└── lucky_app\       ← ACÁ SE TRABAJA. Flask + MySQL.
```

**`lucky_app` NO está bajo control de versiones.** No hay carpeta `.git`. No
hay historial que consultar ni forma de deshacer. Es la primera cosa que
convendría arreglar.

### Durante el desarrollo, Flask sirve TODO en localhost:5000

Decisión explícita: nada apunta a producción todavía. La app sirve la landing
(`/`), la ficha de producto (`/producto?id=`), las APIs y el área de cuenta.

Cuando la landing vuelva a Pages, se cambia el cuerpo de `home()` por
`redirect(SITIO_PUBLICO)`. Las plantillas enlazan con `url_for('home')`, nunca
con `sitio_publico`.

**Deuda conocida:** la landing existe en dos lugares —
`lucky-point/docs/index.html` (publicada) y
`lucky_app/flask_app/templates/landing.html` (la que se edita). Solo se toca la
segunda. **Decidido posponer** hasta la Fase 3: la pregunta real (¿Render o
Pages?) se responde cuando haya que desplegar, y contestarla antes es adivinar.

---

## 3. Los Lucky Points son dinero, no fidelización

Esto cambia cómo hay que programar todo lo que los toque.

**1 LP = $10 CLP.** Tarjetas de recarga: 10k → 1.100 LP, 20k → 2.300 LP,
40k → 4.800 LP (bonos de 10 / 15 / 20%).

Con recarga pagada, el LP es una **gift card**: plata que el cliente ya pagó,
que no expira, es reembolsable y es **pasivo contable**. Un bug no regala
puntos: pierde plata.

### Reglas para cuando llegue el ledger (Fase 3)

- **El saldo NO es una columna.** Es `SUM(delta)` sobre `lp_movimientos`.
  Append-only.
- **Dos bolsillos:** `prepago` (pagado: no expira, reembolsable, es deuda) y
  `promo` (regalado por ruleta/bonos/campañas: expira, no se devuelve, es gasto
  de marketing). Al consumir se descuenta **primero promo**, empezando por lo
  que vence antes.
- El **bono de recarga entra como movimiento SEPARADO**, para poder medir el
  margen regalado por tramo.
- Todo consumo dentro de `transaccion()` con `FOR UPDATE` sobre la fila del
  usuario. Nunca `query_db()`.
- Todo movimiento que venga de un webhook lleva `idempotency_key`.
- **Precios en CLP como INTEGER.** El peso chileno no tiene decimales y un
  float para plata es pedir problemas. El precio en LP se **deriva** (÷10),
  nunca se guarda.

Pendiente de revisar: el bono de la tarjeta de 40k equivale a regalar 16,7% de
esas ventas (paga $40.000, consume $48.000), es permanente y no se modeló
contra margen. Decisión: dejarlo y monitorearlo con una métrica en el panel.

### Pasarelas

- **Shopify** para café en grano y actividades.
- **MercadoPago** directo para recargas de LP y la suscripción mensual.

Why: Shopify cobra ~2% extra por gateway externo justo en el producto de mayor
ticket, y su app de suscripciones solo funciona con pasarelas que no operan en
CLP. MercadoPago sí tiene Suscripciones (preapproval) en Chile.

Los cupos de actividades se manejan como stock de un producto Shopify (Shopify
controla el sobrecupo). El semestral y el anual de la suscripción **no**
necesitan cobro recurrente: son pago único con entregas programadas.

---

## 4. Estructura y responsabilidades

```
lucky_app/
├── server.py                    importa los controladores (registra rutas)
├── .env.example                 TODO lo configurable, muy comentado
├── schema/
│   ├── schema_mysql.sql         instalación nueva (⚠ BORRA la base)
│   ├── muro.sql                 migración incremental idempotente
│   ├── actividad_imagen.sql     migración incremental idempotente
│   ├── seed_carta.sql, seed_gladiatore.sql
│   └── _referencia_modelo_completo.sql   el modelo con ledger, de referencia
└── flask_app/
    ├── __init__.py              app, secret_key, cookie, DB, sort_keys
    ├── config/
    │   ├── mysqlconnection.py   query_db() y transaccion()
    │   ├── seguridad.py         bcrypt. NADIE MÁS importa bcrypt
    │   ├── correo.py            SMTP. NADIE MÁS importa smtplib
    │   ├── shopify.py           Storefront API. NADIE MÁS sabe de GraphQL
    │   ├── enlaces.py           tokens firmados (itsdangerous)
    │   ├── csrf.py              token anti-CSRF sin dependencias
    │   ├── tiempo.py            UTC en la base, hora de Chile en pantalla
    │   └── rut.py               validación de RUT chileno
    ├── models/                  SQL crudo: usuario, carta, actividad, muro
    ├── controllers/             main, admin (carta), actividad, muro,
    │                            usuarios, tienda
    ├── templates/
    └── static/css|js|img|fonts
```

**El patrón de los `config/`**: cada integración externa vive en UN archivo y
ningún otro la importa. Cambiar de proveedor de correo, de hash o de tienda es
tocar un archivo y nada más. Mantenerlo.

---

## 5. Base de datos

MySQL, SQL crudo, sin ORM. Esquema activo: `usuarios`, `marcas`, `categorias`,
`productos`, `actividades`, `usuarios_en_actividad`, `deseos`,
`muro_mensajes`.

**No hay billetera ni historial de compras todavía, y es a propósito:** una
columna `saldo` no es una versión simple del ledger, es una distinta que
después habría que migrar con plata de clientes adentro.

### `mysqlconnection.py` se reescribió, y por qué

El boilerplate original de Flask **no servía para dinero**:

- `autocommit=True` impide transacciones.
- La conexión se cerraba por consulta, así que dos consultas nunca podían
  compartir una transacción.
- `except: return False` se tragaba los errores: un INSERT fallido se veía
  igual que uno exitoso.

Ahora hay `query_db()` para consultas sueltas y `transaccion()` para todo lo
que toque saldo. **El `FOR UPDATE` solo sirve dentro de una transacción**: con
autocommit el bloqueo se suelta de inmediato y no protege de nada.

### `productos` es SOLO la carta del local

**La regla:** si se sirve en taza o plato, va en MySQL. Si se despacha en caja,
es de Shopify. El café en grano NO se duplica en MySQL — el que cobra es
Shopify, y tener stock y precios en dos sistemas que no se hablan es la receta
para cobrar un número distinto al que se muestra.

En `main_controller.producto()` había un TODO que decía lo contrario, de antes
de que se fijara esa regla. Se borró y en su lugar quedó la regla escrita.

---

## 6. Lo que está construido

### Fase 1 — carta administrable (HECHO)

`/admin/carta/<marca_slug>`: productos agrupados por categoría, editables ahí
mismo. La marca va **siempre en la URL**, y no es decoración: es lo que evita
que una pizza de Gladiatore termine colgada de la carta de la cafetería por un
POST mal dirigido. Son dos sociedades con RUT distinto.

`/api/v1/menu` devuelve la carta desde MySQL. La landing la pide por `fetch`:
una lista vacía muestra explícitamente que todavía no hay productos y una caída
de la API muestra «carta no disponible». **No hay respaldo con productos o
precios escritos a mano**: ocultaría errores del esquema y podría publicar
precios antiguos.

### Fase 2 — cuentas (HECHO)

Login, registro, perfil, bcrypt (cost 12), roles, RUT validado, recuperar
contraseña, verificar correo, CSRF en **todos** los POST, y `/admin/usuarios`
para bloquear y devolver el acceso.

**Lo único que falta no es código:** llenar el `.env` con las credenciales de
Gmail. Hasta entonces los correos caen en `buzon/`.

### Fase 6 — actividades (HECHO)

Agenda, cupos, inscripción con y sin cuenta, y afiche por URL.

### Fuera del roadmap (HECHO)

Tienda con carrito y checkout en Shopify; muro de deseos con moderación.

### Orden de fases acordado

`0 Fundaciones · 1 Backend + admin de cartas + Gladiatore · 2 Cuentas ·
3 Billetera/recarga MercadoPago · 4 Canje en mesón · 5 Ruleta · 6 Actividades ·
7 Suscripción y tarjetas físicas · 8 Operar y medir`

**La ruleta va DESPUÉS del canje en mesón** porque reutiliza esa cañería; antes
sería construirla dos veces. Premio decidido server-side, topes semanales, un
giro diario por cuenta con email verificado, bases publicadas (SERNAC lo
exige).

---

## 7. Piezas, una por una

### 7.1 Cuentas y contraseñas

Todo el hashing en `config/seguridad.py`; ningún otro archivo importa bcrypt.
Si algún día se migra a Argon2id, se cambia ese archivo: los hashes viejos
siguen funcionando y se actualizan solos al iniciar sesión (`necesita_rehash`).

**El límite de bcrypt es de 72 BYTES, no de caracteres.** Cada tilde o ñ ocupa
dos. Validar el largo en bytes. Y nunca pre-hashear con SHA-256 para saltarse
el límite: OWASP lo marca como práctica peligrosa (*password shucking*).

**El nickname es obligatorio al registrarse** (desde 2026-09-11) y editable en
el perfil. Es con lo que se firma en el muro. No se exige único a propósito:
dos «Anita» no le hacen daño a nadie, la bandeja de moderación muestra el
correo de cada una, y rechazar un registro con «ese nombre ya está tomado» es
fricción en el peor momento.

`para_sesion()` es lo mínimo que va en la cookie. **Nunca meter el hash ahí**:
la cookie va firmada, no cifrada, y el cliente puede leer su contenido. Tampoco
el RUT ni el teléfono.

**Decisiones que son decisiones, no pendientes:**

- El registro responde 409 si el correo ya existe, y **se queda así**.
  Esconderlo obliga a dejar de iniciar sesión al registrarse y mandar a todos a
  confirmar por correo primero: fricción real, para todos, a cambio de esconder
  «esta persona tiene cuenta en una cafetería». El login sí da un mensaje único
  y recuperar contraseña responde lo mismo exista o no la cuenta — ahí el
  ataque es contra una cuenta concreta, acá es juntar una lista de correos.
- El perfil **no** deja cambiar el correo (es la llave de la sesión) ni el rol.

**Anotado, no hecho:** `/salir` es un GET sin token, así que alguien puede
cerrarte la sesión con un `<img src>`. Molesto, no peligroso; arreglarlo obliga
a convertir el link del menú en un formulario.

### 7.2 Bloquear cuentas — `/admin/usuarios`

Listar con búsqueda y filtros, bloquear y devolver el acceso. **Nada más**, y
cada omisión tiene motivo:

- **No crea cuentas de barista**: el rol existe, pero hasta la Fase 4 un
  barista no puede hacer nada que un cliente no pueda.
- **No borra**: `deleted_at` está lista y el listado ya la respeta, pero nadie
  la escribe. Borrar de verdad se lleva los mensajes del muro (ON DELETE
  CASCADE), lo impiden las inscripciones a actividades, y con el ledger encima
  borrar una cuenta con saldo prepago es destruir un pasivo contable.
- **No cambia roles**: sin eso, el panel no puede dejar el sistema sin
  administradores.

**Desbloquear recuerda el estado anterior sin columna nueva:**
`IF(password_hash IS NULL, 'invitado', 'activo')`. En este esquema los dos
estados se distinguen exactamente por tener contraseña.

**El bloqueo se comprueba AL ACTUAR, no en cada página.** Una sesión ya abierta
sobrevive al bloqueo: la cookie va firmada y no se consulta la base por
request. Poner un SELECT en `requiere_sesion` sería una consulta por página
para un caso rarísimo. En cambio `Muro.crear` lee el estado **dentro de la
transacción que ya bloquea la fila del usuario** — sale gratis. **Ese es el
patrón a repetir cuando lleguen el canje y la recarga.**

Protecciones: un admin no se bloquea (se rechaza en el controlador **y** en el
`WHERE rol <> 'admin'` del UPDATE); uno mismo tampoco. Y `bloquear()` lleva
`AND estado <> 'bloqueado'` en el WHERE aunque parezca redundante: MySQL cuenta
filas CAMBIADAS, pero eso depende de las banderas de la conexión
(`CLIENT_FOUND_ROWS` cuenta las que calzan). Dicho en el SQL, el 0 no depende
de la configuración.

**El buscador escapa con `!`, no con barra invertida:**
`LIKE %(patron)s ESCAPE '!'`. Con la barra habría que escribirla doble en el
SQL y cuádruple en Python, y basta con arrancar MySQL con
`NO_BACKSLASH_ESCAPES` para que deje de funcionar en silencio. Sin escapar,
escribir `%` en el buscador devuelve todo: no es un agujero, es un buscador que
miente.

### 7.3 Correo — `config/correo.py`

Dos modos según el entorno:

- **Sin `SMTP_HOST`**: buzón de desarrollo. Cada correo se escribe en `buzon/`
  (ignorada por git) y el enlace sale en el log. Se prueba el flujo completo
  sin credenciales de nadie.
- **Con `SMTP_HOST`**: envío real (STARTTLS, o SSL directo en el puerto 465).

**Regla no negociable: `enviar()` nunca lanza excepción.** Un correo que no sale
no puede tumbar un registro ni devolver un 500. Devuelve True/False y deja el
problema en el log.

**Tokens firmados sin tabla.** `config/enlaces.py` los firma con `SECRET_KEY`
vía itsdangerous. Sin tabla no hay migración, ni filas basura, ni estado que se
desincronice. El precio es que un token no se puede «marcar como usado», y se
resuelve con una **huella**: el token guarda un resumen del estado que va a
cambiar al usarse.

- **Reset**: la huella es el hash actual de la contraseña. Al cambiarla, todos
  los enlaces pendientes mueren solos.
- **Verificación**: la huella es el correo. Reusar el enlace es inofensivo, y
  `marcar_email_verificado` usa COALESCE para no mover la fecha original.

Sales distintas por propósito: un token de verificación **no** sirve para
resetear. Ventanas: verificación 48 h, reset 30 min.

**Producción: Gmail.** Tres cosas que hacen perder una tarde:

1. La contraseña normal de Gmail **no funciona**. Hay que activar la
   verificación en dos pasos y generar una *contraseña de aplicación* de 16
   caracteres. Desde 2025 Google no acepta otra cosa por SMTP.
2. **`CORREO_DESDE` tiene que ser la misma dirección que `SMTP_USER`**, o un
   alias ya verificado en «Enviar como». Si no, el correo **rebota**. Ojo: el
   `.env.example` trae `contacto@luckypointcoffee.cl` de fábrica, que solo
   sirve si esa es la cuenta que se autentica.
3. Tope diario: ~500 destinatarios en Gmail normal, 2.000 en Workspace. Al
   pasarse, el envío falla y queda en el log, sin aviso en la app.

Migrar a Resend o Brevo después es tocar **solo el `.env`**.

**Decisiones de producto:** un correo sin verificar NO bloquea el login (se
entra igual y se ve un aviso con botón de reenviar); la respuesta de «recuperar
contraseña» es siempre la misma exista o no la cuenta; una cuenta bloqueada no
recibe enlace; y un invitado que pide recuperar contraseña **reclama** su
cuenta (queda con clave, asciende a `activo` y su correo queda verificado).

### 7.4 Actividades

**Los cupos se cuentan, no se guardan.** No existe `cupos_tomados`: existe
`COUNT()` sobre las inscripciones vivas. Mismo criterio que el saldo — un
contador que se actualiza solo se desincroniza al primer error, y ahí tienes
una cata con 13 personas y 12 sillas.

**Inscribirse va en una transacción con FOR UPDATE.** Dos personas que tocan
«Inscribirme» a la vez para el último cupo leerían las dos que queda uno.

**Inscribirse NO exige tener cuenta.** Quien llega desde Instagram no quiere
inventar una contraseña primero: deja su nombre y su correo y queda como
`invitado`. Esa es toda la razón de que ese estado exista.

**No se borra una inscripción cancelada**: se marca `cancelada`. Queda registro
y el UNIQUE no estorba si la persona vuelve.

**El afiche** (`imagen_url VARCHAR(500)`) es una URL, no una subida: el afiche
ya vive donde se diseñó. Se acepta `http://`, `https://` o una ruta del propio
sitio (`/static/img/...`). Se valida el esquema porque un `javascript:` pegado
ahí terminaría dentro de un atributo del HTML. **No** se comprueba que la
imagen exista: eso solo se sabe pidiéndola.

Dos tratamientos distintos, y es lo importante: **en la ficha va ENTERO**
(proporción natural, máx. 420px) porque estos afiches traen la fecha y la hora
dibujadas dentro y recortarlos se come justo eso; **en la tarjeta va recortado
y chico** (72px, al borde derecho), donde es decoración.

### 7.5 La agenda en la landing

La sección `#talleres` se pinta **dos veces, a propósito**: `home()` la
renderiza en el servidor (existe en el primer pintado y en el HTML que ve
Google) y `agenda.js` la refresca contra `/api/v1/agenda`. Los cupos cambian
solos y la landing puede quedar cacheada; mostrar «quedan 2 cupos» cuando ya no
hay ninguno es peor que no mostrar el número. Y el día que la landing vuelva a
Pages, el fetch pasa a ser la única fuente.

Si la API falla, `agenda.js` **no toca nada**. Si MySQL no responde, `home()`
pasa `agenda=[]` y la página igual se sirve.

**Costo asumido:** la tarjeta `.evento` está escrita **dos veces** (el bloque
Jinja y `tarjeta()` de `agenda.js`). Si se toca una, hay que tocar la otra,
igual que en el muro.

### 7.6 La tienda — catálogo desde Shopify

Antes el precio estaba escrito en **tres lugares**: `tienda-productos.js`, el
texto de la tarjeta en `landing.html`, y Shopify. El modo de fallar era el
peor: subes un precio en Shopify, olvidas el código, y la persona ve un número
y paga otro.

Ahora: **la colección manda.** Lo que esté en la colección de Shopify que
apunta `SHOPIFY_COLECCION`, en ese orden, es lo que muestra el sitio. Agregar o
sacar un producto es cosa de Shopify.

**Storefront API, no Admin API**, y no es un detalle: el token de Storefront
solo da acceso a lo que ya es público. Si se filtra, se filtró el catálogo que
cualquiera ve. Un token de Admin lee clientes y pedidos.

Sin dependencias nuevas: `urllib` de la stdlib.

**Dos reglas que impiden que esto tumbe el sitio:**

1. `catalogo()` **nunca lanza si alguna vez funcionó**: con Shopify caído
   devuelve la última copia buena. Caché de 5 min; tras un error reintenta a
   los 30 s.
2. Si Shopify nunca contestó devuelve `None`, y la plantilla pinta las tarjetas
   escritas a mano que quedaron como respaldo en `landing.html` +
   `tienda-productos.js`.

`/api/v1/tienda` responde **503**, no una lista vacía: una lista vacía el front
la leería como «no hay productos». `/api/v1/tienda/estado` es el diagnóstico:
dice si el token sirve, cuántos productos trajo y qué falló.

El catálogo se **inyecta en el HTML** (`LP_TIENDA.cargar(...)` inline y
síncrono), no se pide por fetch: el modal de elección rápida se inicializa unas
líneas más abajo y con un fetch alcanzaría a abrirse con los precios del
respaldo.

**Lo agotado se muestra marcado, no se esconde.** Producto entero agotado →
tarjeta en gris sin botón. Una molienda o tamaño agotado → esa pastilla
desactivada. El modal y la ficha abren preseleccionando la **primera
combinación comprable**.

**⚠ Lo único sin verificar contra la tienda real:** cómo se llaman las opciones
en los productos. La clasificación mira los nombres (`NOMBRES_TAMANO` /
`NOMBRES_MOLIENDA` en `shopify.py`) y, si no calzan, cae al orden en que
Shopify las devuelve: la primera es tamaño, la segunda molienda. Mirar
`/api/v1/tienda` cuando haya token.

### 7.7 El carrito

Vive en el **navegador**, no en el backend. `carrito.js` guarda las líneas en
`localStorage` (`lp_carrito_v1`) y al pagar arma un **cart permalink** de
Shopify con todas las líneas en una sola URL:

    https://TIENDA.myshopify.com/cart/VARIANTE:CANTIDAD,VARIANTE:CANTIDAD

No requiere Storefront API, ni token, ni backend, ni CORS, y sobrevive tal cual
el día que la landing vuelva a Pages.

**La clave de cada línea es el ID de variante**: tamaño y molienda ya vienen
codificados dentro de la variante, así que nunca colisionan.

**El precio guardado es SOLO de vitrina.** La fuente de verdad del precio, del
stock y del despacho es Shopify. Nunca usar el total local para nada contable.

**Los LP no pagan compras online.** El drawer los muestra como referencia.

El drawer y el modal se **inyectan por JS**, no son partials de Jinja: así los
mismos archivos sirven en Flask y en Pages.

Z-index: header 50 · menú de cuenta 60 · modal `.quickpick` 85 · drawer
`.cart` 90.

**Pendiente:** probar una compra real — que el permalink con varias líneas
llegue bien al checkout es lo único no verificado.

### 7.8 El muro de deseos

Quien tiene sesión deja un mensaje corto; el admin lo aprueba; recién ahí sale
publicado. Sección `#muro` en la landing (carrusel, 12 últimos) y página
`/muro` con paginación de 24.

**Tabla `muro_mensajes`, NO `deseos`.** `deseos` ya existía y es otra cosa: la
lista de deseos de productos de la carta.

**Con qué nombre se firma: lo pone la BASE.** Dos reglas que se apoyan:

1. **El nickname no sale del formulario.** `Muro.crear(usuario_id, mensaje)` lo
   lee de la fila del usuario, dentro de la transacción que ya bloquea esa
   fila. Antes llegaba del formulario, o sea cualquiera podía firmar con el
   nombre de otra persona.
2. **El nickname se COPIA, no se joinea.** El admin aprueba un par
   nickname + mensaje. Si saliera por JOIN, alguien podría hacerse aprobar
   «rico el café» y después renombrarse con un insulto — publicado y ya
   aprobado.

**Los frenos:** un pendiente a la vez por cuenta, y 5 envíos en 24 h **móviles**
(no por día calendario: si fuera por día, 5 a las 23:59 y 5 a las 00:01). Los
dos se comprueban dentro de `transaccion()` con `FOR UPDATE`. Estado, nickname
y frenos salen de **una sola lectura** de la fila del usuario.

**El carrusel es CSS puro** (`overflow-x` + `scroll-snap`). Se arrastra con el
dedo y se recorre con el teclado sin JavaScript; las flechas son un extra.
**El orden de las cajas importa:**

    [data-muro-carrusel]   la caja entera; es la que se esconde si no hay nada
    [data-muro]            la pista; muro.js le REEMPLAZA el innerHTML
    [data-muro-controles]  las flechas, FUERA de la pista

Las flechas van fuera porque el primer refresco por fetch se las llevaría.

`muro.js` pinta con `textContent`, **nunca `innerHTML`**: un mensaje con
`<img onerror=...>` se ejecutaría en la portada, y en la bandeja de moderación
ese mensaje se ve como texto inofensivo.

El texto se guarda con los **saltos de línea colapsados a espacios**: evita el
truco de mandar 200 saltos para ocupar media portada.

`volver` en el formulario es la palabra `landing` o `muro`, **nunca una URL**:
aceptar una URL sería un redirect abierto.

---

### 7.9 Las promos de la portada

El admin carga una promo en `/admin/promos` y la landing muestra un banner con
el tiempo que le queda. Al cumplirse el plazo el banner se retira solo: nadie
tiene que acordarse de apagarlo.

**El plazo son DOS FECHAS, no una duración.** La alternativa era guardar «dura
48 horas» y contarlas desde la publicación; suena más simple hasta la primera
edición del texto, cuando nadie sabe si el plazo se reinicia. Los atajos del
formulario («24 horas», «hasta el domingo») rellenan `fin_at`; lo que se
guarda es siempre una fecha. UTC, como todo el resto.

**Los segundos que quedan los calcula MySQL**, no Python ni el navegador.
`Promo.vigente()` devuelve `segundos` ya restados contra `UTC_TIMESTAMP()`, y
el front cuenta hacia abajo desde ese número. Contra una fecha absoluta el
plazo dependería del reloj de cada visitante: quien lo tenga corrido ve otra
cosa, y quien lo atrase se extiende la promo solo.

En el navegador el contador se deriva de un **vencimiento local calculado una
vez al cargar**, no de un `restan -= 1`: en segundo plano el navegador frena
los timers y un contador que resta por tick se va quedando atrás.

**El interruptor (`activa`) está separado de las fechas** y manda sobre ellas.
Es para el caso real: el 2x1 se cae a las seis porque se acabó el café y hay
que sacar el banner en ese momento, sin editar fechas. Reponerlo devuelve la
promo con su plazo intacto.

**El estado se deriva, no se guarda.** Programada, activa, terminada y pausada
salen de comparar las fechas con el ahora en el mismo SELECT. Una columna
`estado` habría que mantenerla con un cron, y el primer día que ese cron no
corra la portada muestra una promo vencida. Mismo criterio que los cupos.

**Se muestra UNA SOLA** aunque haya varias cargadas: mayor `prioridad`
primero y, a igual prioridad, la que termina antes. Sin eso, el día que se
deje una programada y se olvide la anterior hay dos banners peleando.

**El destino del botón se valida**: tiene que empezar con `#` o `/`, y no con
`//`. Una URL cualquiera sería un redirect abierto y un `javascript:` pegado
ahí termina dentro de un atributo del HTML de la portada. Mismo cuidado que el
`volver` del muro y el afiche de las actividades. Texto y destino van juntos o
no va ninguno: medio botón no lleva a ninguna parte.

**El banner va EN FLUJO, antes del `<header>`**, y no fijo: en la landing el
header es `position: sticky`, así que la promo lo empuja hacia abajo sin
taparlo y se va sola con el scroll. Fijo habría que calcularle la altura y
sumársela al header en cada resize. La burbuja sí es fija, con `z-index: 80`
— sobre el header (50) y bajo el modal de la tienda (85) y el drawer (90),
para que nunca quede encima del botón de pagar.

**Los dos elementos nacen `hidden` y los abre un script inline** que va en el
propio partial, antes del primer pintado: quien ya cerró esta promo tiene que
ver la burbuja y no el banner, y esa decisión vive en `localStorage`. Pintando
el banner y escondiéndolo después se vería un salto del contenido en cada
carga. Lo recordado es **por id de promo**: una promo nueva vuelve a mostrarse
entera en vez de quedar silenciada por un clic de hace tres semanas.

**Bajar por la página no es una decisión sobre la promo.** Si el banner se
pierde de vista sin que nadie lo cierre, aparece la burbuja, pero eso no se
guarda. Y el banner NO se esconde en ese caso: un elemento con `display:none`
no vuelve a disparar el IntersectionObserver, así que esconderlo dejaría la
burbuja pegada aunque la persona subiera de nuevo.

El contador va `aria-hidden` porque cambia cada segundo; el plazo viaja en
palabras dentro de la bajada, que es lo que sí lee un lector de pantalla.

Archivos: `schema/promos.sql` · `models/promo_model.py` ·
`controllers/promo_controller.py` · `templates/admin_promos.html`,
`_promo.html` · `static/css/promo.css` · `static/js/promo.js`. La migración
es incremental e idempotente:

    mysql -u root -p --default-character-set=utf8mb4 -e "source schema/promos.sql"

---

## 8. El header nunca cupo (leer antes de tocar el nav)

El nav horizontal solo existe **sobre 1200px**, y ahí `.header__inner` es un
`.container` topado en **1180px** → caja de 1100px. La fila pedía ~1216px con
sesión iniciada. Nunca cupo, en ningún ancho.

El síntoma era «COFFEE» montándose sobre «Inicio»: flexbox encogía la marca, y
**el mínimo automático de un flex item es el ancho de su hijo más ancho, no la
suma de sus hijos**. El bug no estaba en el nav, estaba en que la marca podía
encogerse.

Las reglas del arreglo viven **al final de `static/css/carrito.css`**, porque el
CSS del header está duplicado en el `<style>` de `landing.html` y de
`producto.html` y `carrito.css` lo cargan las dos y va después.

**Con sesión cerrada el margen es de unos pocos px** (las dos CTA de
«¡Regístrate!» y «¡Entra!» son lo más ancho). **Sustituir cabe; agregar no.**
Por eso «Deseos» reemplazó a «Puntos» en vez de sumarse.

**Trampa:** `landing.html` define `window.__lpHeaderHandled = true` porque trae
su propio toggle de hamburguesa, y ese guard saltaba **todo** `lpInitHeader()`.
El menú de cuenta se separó a `lpInitCuenta()`, que corre siempre. Si algo del
header deja de funcionar **solo en la landing**, mirar ese flag primero.

El nav es UN archivo: `templates/_nav.html`. Antes estaba en tres plantillas y
las tres copias ya habían divergido.

---

## 9. Trampas que ya mordieron

Cada una de estas costó una sesión encontrarla.

**Windows / PowerShell**
- PowerShell **no soporta `<`** para redirigir entrada. Para cargar SQL:
  `mysql -u root -p --default-character-set=utf8mb4 -e "source schema/x.sql"`.
- Evitar `Get-Content | mysql`: reencodea y rompe los acentos.
- `mysql.exe` no está en el PATH; se usa MySQL Workbench (File → Open SQL
  Script).

**Codificación**
- Todos los `.sql` llevan `SET NAMES utf8mb4;` al inicio. Ya pasó que los
  acentos quedaran doble-codificados (`Café` → `CafÃ©`) y no hay vuelta atrás
  salvo recargando.

**MySQL**
- `information_schema` devuelve los nombres de columna **en MAYÚSCULAS**. Con
  PyMySQL hay que poner alias (`SELECT table_name AS nombre`) o la clave del
  dict es `TABLE_NAME`.
- MySQL 8 **no tiene `ADD COLUMN IF NOT EXISTS`** (eso es MariaDB). La
  idempotencia se hace mirando `information_schema` y armando el ALTER con
  `PREPARE`/`EXECUTE`. Ver `schema/actividad_imagen.sql`.
- MySQL 8 usa `caching_sha2_password` y PyMySQL necesita el paquete
  **`cryptography`**. El error engaña: MySQL cachea la contraseña tras el
  primer login, y mientras esa caché está tibia usa un camino rápido que no lo
  necesita. Al reiniciar MySQL la caché se vacía y ahí salta — parece un bug
  nuevo y es una dependencia que siempre faltó.

**Flask**
- Flask ordena **alfabéticamente** las claves de todo lo que serializa, y hay
  que apagarlo en **DOS lugares distintos**:

      app.json.sort_keys = False                                         # jsonify
      app.jinja_env.policies["json.dumps_kwargs"] = {"sort_keys": False}  # |tojson

  Sin lo segundo, `jsonify` devuelve el orden bueno y el mismo dato inyectado
  en el HTML sale ordenado. Esto hacía que los tamaños llegaran como
  «1 kg, 250 g» y el sitio ofreciera el kilo por defecto.
- Por lo mismo, el orden de los tamaños viaja como **lista aparte** (`tamanos`),
  no deducido de las claves de `sizes`.
- **Cuidado con los imports dentro de un `try`**: `EN_LA_LANDING` se importaba
  dentro del try de `home()`, y la plantilla lo necesita siempre. Una caída de
  MySQL lo habría dejado sin definir y la portada se caería con un `NameError`
  — justo lo que ese try existe para evitar.

**CSS**
- `.ficha__afiche` tiene que vivir en el `<style>` de `actividad.html`, no en
  `agenda.css`: **esa página no carga `agenda.css`** y la regla se ignoraba en
  silencio.
- El reset del design system tiene `img { display: block }`, así que
  `text-align: center` no centra una imagen: hace falta `margin: 0 auto`.
- Un `<button>` dentro de un `<a>` es HTML inválido. Las tarjetas de la tienda
  usan **enlace estirado**: `<article>`, el `<a>` en el título y
  `::after { position:absolute; inset:0 }`, con el pie en `z-index:2`.

**Correo**
- El cuerpo viaja en **quoted-printable**: en los bytes crudos el enlace se ve
  como `token=3DeyJ1aWQi...` partido en varias líneas. Hay que parsear con el
  módulo `email`, no pasarle un regex a los bytes.
- Los enlaces usan `url_for(..., _external=True)`. Un enlace relativo no sirve:
  se abre desde Gmail, no desde el sitio.

**CSRF**
- El context processor pasa **`csrf_actual` como FUNCIÓN**, no como token ya
  evaluado: `csrf.token()` crea la sesión al llamarse, y evaluarlo en el
  processor le pondría cookie a todo el que abre la portada. Se llama
  `csrf_actual` y no `csrf_token` para no chocar con las vistas que ya pasan
  `csrf_token=csrf.token()` como string.

**Zonas horarias**
- `zoneinfo` **no trae** las zonas horarias: las lee del sistema. Windows no
  trae ninguna, así que hace falta el paquete `tzdata` (está en
  `requirements.txt`). Conviene subirlo una vez al año: Chile cambia sus fechas
  de horario de verano por decreto.
- **UTC entra y sale de la base.** La hora de Chile solo existe en el
  formulario del admin y en lo que ve la gente. Guardar hora local significa
  que la noche en que se atrasa el reloj existen dos veces las 23:30.

---

## 10. Cómo levantarlo

```powershell
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

copy .env.example .env    # y completarlo

mysql -u root -p --default-character-set=utf8mb4 -e "source schema/schema_mysql.sql"
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/seed_carta.sql"
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/seed_gladiatore.sql"

python server.py          # http://localhost:5000
```

Si la base ya existía, correr solo las migraciones incrementales (no borran
nada y se pueden correr dos veces):

```powershell
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/muro.sql"
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/actividad_imagen.sql"
```

**Crear el primer admin** (ya no existe `crear_admin.py`, y el panel no cambia
roles a propósito): registrarse normal en `/registro` y después:

```sql
UPDATE usuarios SET rol = 'admin', estado = 'activo' WHERE email = 'tu@correo.cl';
```

### Cómo se prueba

**Los scripts de prueba NO se versionan ni se dejan sueltos en la raíz.** Se
escriben, se corren y se borran. Si alguna vez se quieren guardar, van en una
carpeta `pruebas/`, preguntando antes.

El patrón que funcionó bien: reemplazar MySQL por **SQLite en memoria con una
capa de traducción**, de modo que las consultas que se prueban son las mismas
que están en el modelo (traducir `UTC_TIMESTAMP`, `INTERVAL`, `FOR UPDATE`,
`IF()`, `CONCAT_WS`, `%(x)s` → `:x`). Y, para lo que eso no cubre, correrlo
contra MySQL real.

Para las integraciones externas: levantar un **servidor de mentira local con
TLS de verdad** (certificado autofirmado instalado en `SSL_CERT_FILE`), así se
prueba el camino completo sin bajarle la guardia al código.

---

## 11. Lo que sigue

Orden acordado con el cliente: **2 → 1**, y el 5 va pegado al 1.

### 2. Enlace de Instagram al muro — SIGUIENTE

Poner en la bio un enlace que lleve directo a publicar un deseo. La página ya
existe (`/muro`). **Bloqueado por el despliegue**: hoy todo corre en
`localhost`, así que no hay URL pública.

Lo que **sí** se puede hacer antes: hoy `requiere_sesion` manda al login y el
login siempre termina en el dashboard, así que quien llega de Instagram a dejar
un deseo aterriza en otra parte y se pierde. Hace falta un `?next=` validado
contra rutas propias (nunca una URL del formulario — mismo cuidado que el
`volver` del muro).

### 1. Voucher de acceso al evento — DESPUÉS, y con el 5 decidido

Al confirmarse el pago de la inscripción, generar un voucher para entrar. Base
que ya existe: `usuarios_en_actividad` con `pendiente/pagada/asistio/no_asistio`
y `pago_ref`.

Falta definir si el voucher es un código corto, un QR, un correo, o las tres
cosas; y si se valida en el mesón con la misma cañería del canje de puntos
(Fase 4), que es el patrón ya decidido para reutilizar.

### 5. Cómo se cobra la asistencia a los eventos

Decidir entre **formulario** (sin cobro en línea, se paga en el local — es lo
que hay hoy), **MercadoPago** (ya elegido para recargas y suscripción) o
**Shopify** (lo que dice el roadmap: los cupos como stock de un producto, y
Shopify controla el sobrecupo). Si se cambia esa última, hay que actualizar la
decisión del roadmap en vez de dejarla contradicha.

### Otros pendientes sueltos

- **Poner `lucky_app` bajo control de versiones.** Es lo más barato y lo que
  protege todo lo demás.
- Llenar el `.env` con las credenciales de Gmail y con el token de Shopify.
- Probar una compra real con varias líneas en el permalink de Shopify.
- Decidir la landing duplicada (pospuesto a la Fase 3).
- `static/js/config.js` tiene la URL de Shopify escrita a mano; cuando haya
  deploy debería salir del `.env` y renderizarse desde Flask.
- No hay aviso por correo cuando llega algo nuevo a la bandeja del muro.
- Restos del boilerplate que se pueden borrar: `models/example_model.py`,
  `templates/index.html`, `static/css/style.css`, `static/js/script.js`.
- El freno por intentos de login vive en memoria: se borra al reiniciar Flask y
  no se comparte entre procesos. Cuando haya más de un worker, pasa a
  Flask-Limiter con Redis. (El del muro **no**: ese vive en la base.)

---

## 12. Cómo se ha trabajado acá

Por si ayuda a mantener el tono:

- **Se decide, no se deja un TODO vago.** Cuando algo no se hace, el porqué
  queda escrito en el código como decisión, con la condición que haría
  reconsiderarla.
- **Se prefiere lo aburrido que no se puede romper** antes que lo elegante que
  hay que cuidar. Ejemplo: los cupos se cuentan, el saldo se suma.
- **Nada que toque plata se hace sin transacción.**
- **Cuando una pieza se duplica** (la tarjeta del muro, la de la agenda, la
  carta) queda escrito en ambos lados que existe la otra.
- **Los datos que decide una persona no se recalculan después**: el nickname
  aprobado, el `monto_clp` de una inscripción. Se copian.
- Las validaciones van **en el servidor**, y de nuevo en la base cuando es
  barato (CHECK, UNIQUE, FK). El front es comodidad, no defensa.
