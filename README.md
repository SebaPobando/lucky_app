# Lucky Point App

Backend y área de cuenta de **Lucky Point Coffee** (y Gladiatore), en Flask + MySQL.

> **La carpeta `lucky-point` no se toca.** Ahí vive el repositorio que se
> despliega en GitHub Pages. Este proyecto es independiente: desde ahí solo se
> copiaron (en modo lectura) el sistema de diseño, las páginas del área de
> cuenta, la landing y la ficha de producto.

---

## Cómo se reparte el trabajo

Durante el desarrollo, **esta app sirve todo en un solo origen**
(`localhost:5000`): no hay que salir a producción para navegar el sitio.

| | Ruta | Qué es |
|---|---|---|
| **Landing** | `/` | Inicio, quiénes somos, carta, tienda, puntos. Copia de `lucky-point/docs/index.html`. |
| **Gladiatore** | `/gladiatore` | La carta de la pizzería, con su propia identidad (negro, rojo y dorado). Se llega desde el botón en la carta de Lucky Point. |
| **Ficha de producto** | `/producto?id=…` | El botón de compra sigue llevando a Shopify. |
| **Área de cuenta** | `/login`, `/dashboard`, `/perfil`, `/recarga`, `/credencial`… | Todo lo que necesita sesión. |
| **Cobro** | externo | Shopify: café en grano y actividades. MercadoPago: recargas de LP y suscripción mensual. |

> **Ojo con la doble fuente de verdad.** La landing existe ahora en dos lugares:
> `lucky-point/docs/index.html` (lo que está publicado en GitHub Pages) y
> `lucky_app/flask_app/templates/landing.html` (lo que sirve esta app). Mientras
> ambas vivan, un cambio hay que hacerlo dos veces o se desincronizan. Decidir
> cuál manda es una conversación pendiente.

**Cuando la landing vuelva a GitHub Pages**, el cambio es de una línea: en
`main_controller.py`, la ruta `/` pasa de `render_template("landing.html")` a
`redirect(SITIO_PUBLICO)`, y se define `SITIO_PUBLICO` en el `.env`.

---

## Levantarlo local

```powershell
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

copy .env.example .env    # y completa las credenciales

# Cargar el esquema. OJO: PowerShell no soporta `<` para redirigir entrada
# ("The '<' operator is reserved for future use"), así que se usa `source`,
# que además deja que mysql lea el archivo directo y no le toque los acentos.
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/schema_mysql.sql"
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/seed_carta.sql"
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/seed_gladiatore.sql"

python server.py          # http://localhost:5000
```

Si la base ya existía de antes, en vez de recargarla entera corre solo lo que
falte. Las migraciones incrementales no borran nada y se pueden correr dos
veces:

```powershell
mysql -u root -p --default-character-set=utf8mb4 -e "source schema/muro.sql"
```

### Crear la primera cuenta de administrador

Antes esto lo hacía `crear_admin.py`. Ese script ya no está, y el panel de
cuentas no cambia roles a propósito (así no puede dejar el sistema sin
administradores), así que hoy se hace a mano: regístrate normal en
`/registro`, genera el hash y ascendete.

```powershell
# El hash NUNCA se escribe a mano ni se guarda en texto plano
python -c "import bcrypt,getpass; print(bcrypt.hashpw(getpass.getpass().encode(), bcrypt.gensalt(12)).decode())"
```

```sql
UPDATE usuarios SET rol = 'admin', estado = 'activo'
WHERE email = 'tu@correo.cl';
```

(Si te registraste por la web ya tienes contraseña y el `UPDATE` del rol basta;
el comando de arriba es para ponerle contraseña a una cuenta que no la tenga.)

Si `mysql` no está en el PATH, abre el script en MySQL Workbench
(**File → Open SQL Script** y el botón del rayo). De paso,
**Database → Reverse Engineer** te arma el diagrama EER solo.

Si prefieres el cliente interactivo:

```powershell
mysql -u root -p --default-character-set=utf8mb4
```
```sql
source schema/schema_mysql.sql;
```

Evita `Get-Content schema/schema_mysql.sql | mysql -u root -p`: PowerShell 5.1
reencodea al pasar por el pipe y te puede romper los acentos de los comentarios.

Abre `http://localhost:5000` y verás la landing. El login ya es real: valida
contra la tabla `usuarios` con bcrypt.

---

## Estructura

```
lucky_app/
├── server.py                  punto de entrada
├── requirements.txt
├── .env.example               copiar a .env (NO se sube al repo)
├── schema/
│   ├── schema_mysql.sql       las 7 tablas, validado en MySQL 8.0.46
│   ├── seed_carta.sql         Lucky Point: 60 productos en 9 categorías
│   └── seed_gladiatore.sql    Gladiatore: 17 productos en 4 categorías
└── flask_app/
    ├── __init__.py            app, secret key, cookie de sesión, globales
    ├── config/
    │   ├── mysqlconnection.py conexión + transacciones
    │   ├── seguridad.py       hashing de contraseñas (bcrypt cost 12)
    │   ├── csrf.py            token anti-CSRF
    │   ├── rut.py             RUT chileno: módulo 11, normalizar, formatear
    │   └── tiempo.py          UTC en la base, hora de Chile en pantalla
    ├── controllers/
    │   ├── main_controller.py rutas del área de cuenta
    │   ├── admin_controller.py administración de la carta
    │   └── actividad_controller.py talleres, catas e inscripciones
    ├── models/
    │   ├── carta_model.py     lee la carta desde MySQL
    │   ├── usuario_model.py   cuentas y sesión
    │   └── actividad_model.py actividades, cupos e inscripciones
    ├── templates/
    │   ├── landing.html       la portada
    │   ├── producto.html      ficha de producto
    │   ├── base.html          header, footer, flashes (área de cuenta)
    │   ├── admin_inicio.html  el panel de administración
    │   ├── admin_carta.html   el CRUD de la carta
    │   ├── admin_actividades.html  talleres y catas
    │   ├── admin_inscritos.html    quién se inscribió
    │   ├── actividades.html   la agenda pública
    │   ├── actividad.html     ficha e inscripción
    │   ├── gladiatore.html    la carta pública de la pizzería
    │   ├── registro.html      crear cuenta
    │   ├── perfil.html        datos y contraseña
    │   └── *.html             el resto de las páginas de cuenta
    └── static/
        ├── css/               styles.css + account.css + tokens/
        ├── js/account.js      formateo y RUT chileno
        ├── fonts/               Handgoal.ttf + Anton (Gladiatore)
        └── img/               logo y mascotas
```

---

## Talleres y catas

| | Ruta |
|---|---|
| Agenda pública | `/actividades` |
| Ficha e inscripción | `/actividades/<slug>` |
| Administración | `/admin/actividades` |
| Lista de inscritos | `/admin/actividades/<id>/inscritos` |

### Los cupos se cuentan, no se guardan

No existe una columna `cupos_tomados` que se sume y se reste. Existe `COUNT()`
sobre las inscripciones vivas. Es el mismo criterio que el saldo del ledger: un
contador que se actualiza solo se desincroniza al primer error, y ahí tienes una
cata con 13 personas y 12 sillas.

Una inscripción **cancelada** libera el cupo. Los demás estados lo ocupan.

### Inscribirse va en una transacción con FOR UPDATE

Dos personas que tocan «Inscribirme» en el mismo segundo para el último cupo
leerían **las dos** que queda uno, y entrarían **las dos**. El bloqueo de la fila
de la actividad hace que la segunda espere a que la primera confirme, y entonces
ya lee cero.

Probado con seis hilos simultáneos peleando un cupo: entra exactamente uno, los
otros cinco reciben `CupoAgotado`, y en la base quedan 2 de 2. Sin sobreventa.

**Si algún día tocas `Actividad.inscribir()`, no saques el `FOR UPDATE`.** Sin
transacción no protege de nada: con autocommit el bloqueo se suelta de inmediato.

### Inscribirse no exige tener cuenta

Quien llega desde Instagram a anotarse en una cata no quiere inventar una
contraseña primero. Deja su nombre y su correo y queda con `estado='invitado'`,
sin contraseña. Si después se registra con ese mismo correo, `Usuario.reclamar()`
convierte esa fila en su cuenta y hereda la inscripción. **Esa es toda la razón
de que el estado 'invitado' exista en el esquema.**

En la lista de inscritos, quien no tiene cuenta sale marcado **Sin cuenta**: son
a quienes hay que escribirles a mano.

Un correo que **ya tiene cuenta con contraseña** no se inscribe a ciegas: se pide
iniciar sesión. Si no, cualquiera podría anotar a otra persona escribiendo su
correo, y de paso ver su nombre confirmado en la respuesta.

### En Windows hay que instalar `tzdata`

`zoneinfo` (de la biblioteca estándar) **no trae las zonas horarias: las lee del
sistema operativo.** Linux y macOS las traen; **Windows no trae ninguna**, así
que `ZoneInfo("America/Santiago")` revienta con `ZoneInfoNotFoundError`.

Por eso `tzdata` está en `requirements.txt`. Si te aparece ese error:

```powershell
pip install -r requirements.txt
```

**Esa dependencia no es una librería, es la tabla de husos horarios del mundo.**
Una versión vieja significa reglas de horario de verano viejas, y Chile cambia
sus fechas por decreto de vez en cuando. Conviene subirla una vez al año.

Y **no** hay un respaldo que use un desfase fijo de −3 o −4 horas: eso es
exactamente el error que guardar en UTC viene a evitar. Un desfase fijo acierta
media parte del año y se equivoca la otra media, en silencio. Mejor que falle
al arrancar y con un mensaje que diga qué hacer.

### UTC en la base, hora de Chile en pantalla

`config/tiempo.py`. Chile cambia de huso dos veces al año: UTC-4 en invierno,
UTC-3 en verano. **Si guardaras hora local, la noche en que se atrasa el reloj
existen dos veces las 23:30 y no hay forma de saber a cuál se refiere una fila.**

El admin escribe en hora de Chile, se guarda en UTC, y vuelve a pantalla
convertido. Verificado en los dos husos:

```
19:00 de junio     (invierno) -> 23:00 UTC
19:00 de diciembre (verano)   -> 22:00 UTC
```

Las mismas «19:00» son dos instantes distintos, y con UTC no hay ambigüedad.

### Estados

`borrador` no lo ve nadie — 404 para el público, no 403. `publicada` sale en la
agenda. `cancelada` y `realizada` se muestran con su explicación a quien tenga el
enlace.

**Una actividad con inscritos no se puede eliminar.** La llave foránea lo impide,
y está bien que lo impida: hay personas que contaban con eso. Para suspenderla
existe `cancelada`, que deja el registro y ellos lo ven al entrar.

**Tampoco puedes bajar los cupos por debajo de la gente ya inscrita**, porque
dejaría a alguien fuera sin avisarle.

---

## La barra de navegación

**El menú pasa a hamburguesa en 1200px, no en 760px.** Medido: el menú necesita
723px y la marca 357px, o sea 1120px contando el espacio entre ambos. Por debajo
de eso la marca se partía en dos líneas y «Quiénes somos» y «Mi cuenta» se
doblaban. Colapsar antes es mejor que apretar.

**Si agregas otro enlace, vuelve a medir.** El valor no es mágico: sale de sumar
lo que ocupan la marca y los enlaces. Se desarmó dos veces: al agregar
«Gladiatore» y al agregar «Talleres» + «Actividades».

**Por eso la administración cuelga de un solo enlace.** La barra lleva «Admin» y
de ahí sale el panel (`/admin`) con la carta y las actividades. Cada sección
nueva de administración habría sido otro enlace en la barra; así la barra queda
fija y el panel crece lo que haga falta.

Bajo 430px se esconde el «COFFEE» de la marca: en un teléfono angosto, logo +
nombre + tag + hamburguesa no caben, y el logo con el nombre ya identifican la
marca.

**Entrar y registrarse son botones, no enlaces.** «Entrar» era un enlace más
perdido entre otros seis; como botón se lee que es la acción y no una sección
del sitio.

### Cómo llegar a Gladiatore

Desde la carta de Lucky Point hay dos puertas: el botón negro **Carta
Gladiatore** al lado de las pestañas de categorías, y el bloque oscuro más
abajo. Gladiatore **no** está en el menú de arriba a propósito: es lo que
desbordaba la barra, y en las categorías se encuentra mejor.

Ojo con la tira de pestañas: se desplaza en horizontal y no avisa que sigue.
Cuando el botón de Gladiatore estaba dentro, empujaba «Pastelería» y «Bollería»
fuera de la vista. Por eso el botón va fuera de la tira, y sobre 720px las
pestañas se acomodan en dos filas en vez de desplazarse.

---

## Administrar la carta

`http://localhost:5000/admin/carta` — o el enlace **Editar carta** en el menú,
que solo aparece si tu usuario tiene `rol = 'admin'` en la tabla `usuarios`.

### Las dos marcas

Hay una carta por marca, con pestañas arriba:

| Marca | URL |
|---|---|
| Lucky Point Coffee | `/admin/carta/lucky-point` |
| Gladiatore | `/admin/carta/gladiatore` |

**La marca va siempre en la URL, y eso no es decoración.** El servidor comprueba
que el producto pertenezca a la marca de la URL antes de tocarlo; si no, devuelve
404. Sin eso, un POST a `/admin/carta/lucky-point/<id de una pizza>` editaría la
pizza y le estamparía el `marca_id` de la cafetería, moviéndola de empresa en
silencio. **Son dos sociedades con RUT distinto**: mezclarles los productos no es
un problema cosmético, es un problema contable.

Lo mismo con las categorías: al crear o editar, la categoría tiene que existir
**y** ser de esa marca.

### Los dos precios de las pizzas

Las pizzas de Gladiatore vienen en familiar e individual, así que `productos`
tiene **dos columnas de precio**:

- `precio_clp` — el precio principal. En pizzas, el familiar.
- `precio_individual_clp` — el segundo. **NULL** en todo lo que tiene un solo
  precio: los 60 productos de la cafetería, las bebidas, las promos.

En el admin es el campo **2º precio**. Dejarlo **vacío** significa «este producto
tiene un solo precio»; poner **0** significaría que sale gratis, y así saldría
impreso en la carta. Por eso el vacío se guarda como NULL y no como cero.

Dos columnas y no una tabla de variantes porque hoy son exactamente dos tamaños
fijos. Si algún día aparece un tercero, migrar once filas es una tarde.

**Pastas es la excepción y por eso va distinto.** En la carta impresa muestra
$7.000 y $8.000, pero no son familiar e individual: el segundo incluye la
bebida. Van como dos productos separados, porque son dos cosas que se piden.

Es una sola pantalla con los 60 productos agrupados por categoría, editables ahí
mismo. Cuatro cosas se pueden hacer:

| Acción | Cómo | Qué pasa |
|---|---|---|
| **Crear** | «+ Agregar un producto», arriba | El slug se genera solo desde el nombre (y agrega `-2` si ya existe) |
| **Actualizar** | Editas los campos y **Guardar** | Los Lucky Points se recalculan mientras escribes el precio |
| **Apagar/prender** | El botón **Disponible** | Un click, sin recargar. Desaparece de la carta pública al instante |
| **Eliminar** | **Eliminar**, con confirmación | Borrado real. Si algo lo referencia, MySQL lo impide y te avisa |

### El buscador

La barra de arriba filtra mientras escribes y se queda pegada bajo el header,
para que puedas corregir la búsqueda sin volver a subir.

- **Ignora tildes y mayúsculas.** `cafe` encuentra `Café`, `nino` encuentra `Niño`.
  En español esto no es un lujo: sin eso, medio buscador no sirve.
- **Busca en nombre, descripción, etiqueta y categoría.** Escribir `vegano`
  encuentra los que lo dicen en la descripción aunque no lo digan en el nombre.
- **Varias palabras = todas tienen que estar.** `cafe frio` no trae los 14 cafés,
  trae 1.
- **Lee lo que está en el campo, no lo que mandó el servidor.** Si renombraste un
  producto y todavía no guardas, el buscador ya lo encuentra por el nombre nuevo.
- Las categorías sin coincidencias se esconden completas, con su título.
- <kbd>/</kbd> para saltar al buscador, <kbd>Esc</kbd> para limpiarlo.

Filtra **en el navegador**, no en el servidor: los 60 productos ya vienen en la
página, así que buscar es instantáneo, no recarga y no pierdes lo que estabas
editando. Si algún día la carta pasa de unos cientos de productos, esto se
cambia por una consulta con `LIKE` y `LIMIT` — hoy sería sobreingeniería.

Lo que **no** hace: no adivina. `capuchino` no encuentra `Cappuccino` porque no
hay corrección de errores de tipeo, y para 60 productos no vale la pena.

**«Se acabó» no es «eliminar».** Si se terminó el croissant de hoy, usa el botón
de disponibilidad: el producto se mantiene con su historial y vuelve mañana con
un click. `Eliminar` es para lo que se creó por error.

Los precios en Lucky Points **no se guardan**: siempre son `precio_clp ÷ 10`.
Cambiar un precio en pesos cambia el precio en puntos automáticamente, y nunca
pueden quedar desincronizados.

Quien no tenga sesión va a `/login`. Quien tenga sesión pero no sea admin recibe
un **404, no un 403**: un 403 confirma que la página existe.

Lo que **no** tiene todavía, por decisión explícita: reordenar arrastrando, subir
imágenes (el campo de imagen es una URL por ahora), buscador, paginación, CRUD de
categorías, editor enriquecido, historial y deshacer.

---

## Cuentas: registro y perfil

**El registro es real.** `/registro` crea la cuenta, hashea con bcrypt e inicia
sesión de inmediato — pedir la contraseña otra vez recién creada no aporta
seguridad, solo fricción.

### Lo que se valida en el servidor

Hay una copia de todo esto en JavaScript. **Esa no cuenta**: es una cortesía
para quien escribe. Cualquiera desactiva JavaScript o manda el POST con `curl`.
Lo que decide está en `main_controller.py` y en `config/rut.py`.

| | Regla |
|---|---|
| **Contraseña** | Mínimo 10 caracteres y máximo **72 BYTES** |
| **RUT** | Opcional. Si viene, módulo 11 y único en la base |
| **Correo** | Normalizado a minúsculas, único |
| **Freno** | 5 registros por IP cada hora |

**El límite de bcrypt es de 72 bytes, no de caracteres**, y cada tilde o ñ ocupa
dos: `'contraseña' × 8` son 80 caracteres pero 88 bytes. Sin validarlo, `hashear()`
lanza y la persona ve un 500 sin explicación.

### El RUT nunca es un número

Se guarda como `VARCHAR`, en la forma `12345678-9`: sin puntos, con guion, con
el dígito verificador en mayúscula. El dígito puede ser **K** y hay RUTs con
ceros a la izquierda — `INT` rompe las dos cosas. Los ceros se quitan **antes**
de medir el largo: si no, `0011111111-1` se rechazaría siendo el mismo RUT que
`11111111-1`, y guardarlos crearía dos filas para una sola persona.

### Reclamar una cuenta de invitado

El esquema lo dice desde el principio: quien se inscribe a una actividad sin
crear cuenta queda con `estado='invitado'` y sin contraseña. Eso no es una
cuenta, es un marcador. Cuando después se registra con el mismo correo,
**`Usuario.reclamar()` convierte esa fila en cuenta de verdad** — mismo `id`,
mismo historial — en vez de dejar dos usuarios con el mismo correo.

Los campos que llegan vacíos conservan lo que ya había (`COALESCE`): si el
invitado tenía teléfono y ahora no lo escribe, no se borra.

### Lo que el perfil NO deja cambiar

**El correo.** Es la llave con la que inicias sesión. Sin verificación por
correo, alguien que te pille la sesión abierta pondría el suyo y se quedaría
con la cuenta. Llega cuando exista el envío de correos.

**El rol y el estado.** Si estuvieran en el formulario, un POST a mano te
convierte en admin.

**Cambiar la contraseña pide la actual.** No es burocracia: sin eso, quien te
agarre la sesión abierta te cambia la clave y te deja fuera de tu propia cuenta.

### Dos cosas que saqué de las maquetas

**El banner de «3.000 Lucky Points de bienvenida»** en el registro. Venía de
cuando los puntos se pensaban como premio. **Los Lucky Points se compran**:
regalar 3.000 es regalar $30.000 por cada registro. Si quieres un bono de
bienvenida, se decide el monto y sale del bolsillo `promo` del ledger — no de
un texto en el HTML.

**Los tres interruptores de notificaciones** del perfil. No se guardaban en
ninguna parte: la tabla no tiene esas columnas y no existe el envío de correos.
Un interruptor que no hace nada es peor que no tenerlo — la persona cree que se
dio de baja y le sigue llegando todo.

---

## Contraseñas

Todo el hashing vive en `config/seguridad.py` y ningún otro archivo importa
bcrypt. Si algún día migramos a Argon2id, se cambia ese archivo: los hashes
viejos siguen funcionando y se actualizan solos cuando cada persona inicia
sesión (`necesita_rehash`). Nadie tiene que resetear su contraseña.

Cost 12 (~280 ms por hash). OWASP pide mínimo 10 y hoy prefiere Argon2id;
bcrypt bien configurado no es una vulnerabilidad, es una capa menos de
resistencia frente a GPU.

**El límite de bcrypt es de 72 BYTES, no de caracteres.** Cada tilde o ñ ocupa
dos: `'contraseña' × 8` son 80 caracteres pero 88 bytes. Valida el largo en
bytes en los formularios. Y nunca pre-hashees con SHA-256 para saltarte el
límite: OWASP lo marca como práctica peligrosa (*password shucking*).

---

## Correo

Todo el envío vive en `config/correo.py` y ningún otro archivo importa
`smtplib`. Misma idea que `seguridad.py` con bcrypt: cambiar de proveedor es
tocar un archivo.

**Regla no negociable: `enviar()` nunca lanza excepción.** Un correo que no
sale no puede tumbar un registro ni devolver un 500. Devuelve True/False y
deja el problema en el log.

### En desarrollo no hace falta configurar nada

Sin `SMTP_HOST`, cada correo se escribe en `buzon/` (ignorada por git) y el
enlace sale en el log. Abres el `.html` en el navegador y sigues el flujo
completo sin credenciales de nadie.

### En producción: Gmail

Es lo acordado, y para el volumen de una cafetería sobra. En el `.env`:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=la-cuenta-completa@gmail.com
SMTP_PASSWORD=la-contraseña-de-aplicación
CORREO_DESDE=la-cuenta-completa@gmail.com
```

Tres cosas que hacen perder una tarde si no se saben:

**La contraseña normal de Gmail no funciona.** Hay que activar la verificación
en dos pasos y generar una *contraseña de aplicación* de 16 caracteres en la
seguridad de la cuenta de Google. Desde 2025 Google no acepta otra cosa por
SMTP.

**`CORREO_DESDE` tiene que ser la misma dirección que `SMTP_USER`**, o un alias
que ya hayas verificado en Gmail («Enviar como»). Si pones una dirección
cualquiera —por ejemplo `contacto@luckypointcoffee.cl` mientras te autenticas
con una cuenta `@gmail.com`— el correo **rebota**. Si el correo del negocio
está en Google Workspace sobre el dominio, esto se resuelve solo: autenticas
con esa dirección y el remitente calza.

**Hay tope diario:** unos 500 destinatarios al día en una cuenta Gmail normal,
2.000 en Google Workspace. Cuando se pasa, Gmail deja de mandar sin avisarte
en la app: el envío falla y queda en el log.

El día que el volumen crezca o los correos empiecen a caer en spam, el cambio
es a un servicio de envío (Resend, Brevo) y se toca **solo el `.env`**:
`correo.py` no distingue proveedores. Eso sí, esos servicios piden verificar
el dominio con registros DNS, que es el paso que toma tiempo.

### Cómo está probado

El flujo completo se probó contra **MySQL real** y contra un **servidor SMTP
real** en localhost —con STARTTLS, autenticación obligatoria y verificación de
certificado activada—: registro, correo, verificar, recuperar contraseña,
restablecer, reusar el enlace y el login. 28 comprobaciones, sin necesitar
credenciales de Gmail. El script vive fuera del repo (las pruebas no se
versionan acá); si se quiere guardar, va en una carpeta `pruebas/`, no suelto
en la raíz.

Ojo con una trampa si alguna vez escribes una prueba parecida: el cuerpo del
correo viaja en *quoted-printable*, así que en los bytes crudos el enlace se
ve como `token=3DeyJ1aWQi...` partido en varias líneas. Hay que parsear el
mensaje con el módulo `email`, no pasarle un regex a los bytes.

---

## Tres cosas que conviene no olvidar

**El saldo nunca es una columna.** No existe `billeteras.saldo`. Existen
movimientos en `lp_movimientos`, y el saldo es su suma (vista `lp_saldos`).
Es lo que permite auditar, revertir un error y explicarle a un cliente por qué
tiene lo que tiene.

**Todo lo que toca el saldo va en una transacción.** Usa `transaccion()` de
`mysqlconnection.py`, nunca `query_db()`. Sin `FOR UPDATE` dentro de una
transacción, dos baristas cobrando a la vez leen el mismo saldo y uno de los
dos descuentos se pierde.

**Dos bolsillos, no uno.** `prepago` es plata que el cliente pagó: no expira,
es reembolsable, es deuda tuya. `promo` es lo regalado (bono de recarga,
ruleta, campañas): puede expirar y no se devuelve en dinero. Al consumir se
descuenta primero de promo, empezando por lo que vence antes.

---

## Qué cambió respecto del ejemplo de Flask

`mysqlconnection.py` se reescribió por cuatro razones concretas:

1. `autocommit=True` → `False`. Con autocommit no existen las transacciones:
   cada consulta se confirma sola. Si el descuento de saldo funciona y el
   registro de la orden falla, el cliente pierde puntos sin rastro de qué compró.
2. La conexión ya no se cierra dentro de `query_db`, así dos consultas pueden
   compartir transacción.
3. Los errores se relanzan en vez de `return False`. Un INSERT fallido en
   silencio, en un ledger, es plata perdida.
4. Las credenciales salen del entorno, no del código.

En `account.js` se conservaron los formateadores y la validación de RUT chileno
(están correctos), y se eliminó la sesión falsa en `localStorage`: la sesión
ahora la maneja Flask con cookie y el saldo lo entrega el servidor.

Las imágenes venían en resolución de imprenta para mostrarse en miniatura. Las
mascotas eran 3541×5016 px para verse a 64–96 px, y el hero pesaba 13 MB a
3700×5550. La foto del equipo venía en PNG, formato equivocado para una
fotografía. Todo se redujo y reconvirtió: **de 28 MB a 1,9 MB**. Los originales
siguen intactos en `lucky-point`.

---

## Estado por fase

- [x] **Fase 0-1** — estructura, plantillas, sistema de diseño, esquema
- [x] **Fase 1** — carta administrable multi-marca, API del menú, Gladiatore
      con su carta y su página
- [x] **Fase 2** — login, registro y perfil reales, bcrypt, roles, RUT validado,
      recuperar contraseña, verificar correo, CSRF en todos los POST, y el
      panel de cuentas para bloquear y devolver el acceso
- [ ] **Fase 3** — billetera: recarga con MercadoPago, ledger, idempotencia
- [ ] **Fase 4** — canje en el mesón
- [ ] **Fase 5** — ruleta
- [x] **Fase 6** — actividades: agenda, cupos, inscripción con y sin cuenta
- [ ] **Fase 7** — suscripción y tarjetas físicas

Fuera del roadmap, ya hechos: la tienda con carrito y checkout en Shopify, y
el muro de deseos con moderación.

Lo único que le falta a la Fase 2 no es código: llenar el `.env` con las
credenciales de Gmail (ver arriba). Hasta entonces los correos quedan en
`buzon/`.

El detalle está en el tablero del roadmap.
