# Subir lucky_app a Railway

Escrito el 2026-09-15. Es la primera puesta en línea: acá está lo que hay que
hacer **una vez**, en orden, y lo que conviene mirar después.

Supuestos: los correos automáticos siguen apagados (decisión tomada; sin
`SMTP_HOST` la app no manda nada) y el pago del evento se sigue cobrando por
transferencia con el Google Form.

---

## 1. Antes de tocar Railway

**Esta carpeta todavía no es un repositorio git.** Railway despliega desde
GitHub o desde su CLI (`railway up`, que sube la carpeta tal cual). Con git es
mejor: cada push vuelve a desplegar y queda historial.

    git init
    git add .
    git commit -m "Primera versión para producción"

`.gitignore` ya deja fuera `.env`, `venv/`, `__pycache__/` y `buzon/`.
**Revisa que `.env` no aparezca** en `git status` antes del primer push: ahí
está el token de Shopify.

## 2. El servicio de base de datos

En Railway: **New → Database → MySQL**. No hay que configurar nada más; el
servicio entrega sus propias credenciales.

Después, en el servicio de la app, en **Variables**, se enlazan con referencias
(así no quedan copiadas a mano y sobreviven a un cambio de contraseña):

    DB_HOST=${{MySQL.MYSQLHOST}}
    DB_PORT=${{MySQL.MYSQLPORT}}
    DB_USER=${{MySQL.MYSQLUSER}}
    DB_PASSWORD=${{MySQL.MYSQLPASSWORD}}
    DB_NAME=${{MySQL.MYSQLDATABASE}}

## 3. Cargar el esquema

Con la conexión pública que muestra Railway (host, puerto, usuario, clave):

    mysql -h <host> -P <puerto> -u <usuario> -p<clave> <base> --default-character-set=utf8mb4 -e "source schema/schema_mysql.sql"
    mysql -h ... -e "source schema/evento_voucher.sql"
    mysql -h ... -e "source schema/seed_carta.sql"
    mysql -h ... -e "source schema/seed_gladiatore.sql"

Ese es el orden y son los únicos cuatro que hacen falta en una base nueva:
`schema_mysql.sql` ya trae el muro y el afiche de las actividades, y
`evento_voucher.sql` agrega lo del voucher. `actividad_imagen.sql` y `muro.sql`
ya están dentro del esquema; `_referencia_modelo_completo.sql` es
documentación, no se corre.

También sirve MySQL Workbench como cliente: *File → Open SQL Script*, con la
conexión apuntando al host y puerto públicos que muestra Railway. Es la misma
cosa, con botones.

**Dos trampas de esta parte:**

1. `schema_mysql.sql` **empieza con `DROP DATABASE IF EXISTS lucky_point_db`.**
   Es lo correcto el primer día y una catástrofe cualquier otro día: borra la
   base entera, con los inscritos adentro. Después de esta carga inicial ese
   archivo no se vuelve a correr nunca; todo cambio posterior va como
   migración incremental aparte, al estilo de `evento_voucher.sql`.

2. Todos los `.sql` traen `USE lucky_point_db;` escrito. El script crea esa
   base, así que hay que dejar **`DB_NAME=lucky_point_db`** en las variables y
   NO usar la base `railway` que el servicio trae por defecto — si no, habría
   que editar el `USE` de todos los archivos.

**Si editaste la carta desde `/admin/carta`,** el `seed_carta.sql` quedó viejo:
esos cambios están en tu MySQL local y no en el archivo. En ese caso, en vez
de correr el seed, exporta desde Workbench **solo `categorias` y `productos`**
(Data Export → Dump Data Only) y carga ese dump después del esquema.

**Lo que NO conviene** es traspasar tu base local completa con el asistente de
migración: arrastra tus pruebas —usuarios de prueba, inscripciones, deseos,
actividades de mentira— y después hay que borrarlas respetando el orden de las
llaves foráneas. Partir del esquema deja la base limpia de entrada.

Para comprobar que quedó bien:

    SELECT COUNT(*) FROM productos;                 -- la carta
    SHOW COLUMNS FROM usuarios_en_actividad LIKE 'voucher_codigo';

## 4. Las variables de la app

| Variable | Valor | Por qué |
|---|---|---|
| `SECRET_KEY` | uno nuevo y aleatorio | Firma la cookie de sesión **y** los tokens de los enlaces de correo. Con el de ejemplo, cualquiera que lo sepa se fabrica una sesión de admin. `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `FLASK_ENV` | `production` | Apaga el debug y hace que la cookie sea `Secure`. |
| `DETRAS_DE_PROXY` | `1` | Railway corta el https en su borde. Sin esto, el enlace del voucher sale con `http://`. |
| `SITIO_PUBLICO` | la URL pública | Se usa en los enlaces «volver al sitio». |
| `SHOPIFY_DOMINIO`, `SHOPIFY_STOREFRONT_TOKEN`, `SHOPIFY_COLECCION` | los del `.env` local | Sin esto la tienda cae al respaldo escrito a mano, **con precios que pueden estar viejos**. |
| `CORREO_DESDE`, `CORREO_NOMBRE` | como en local | Solo cosmético mientras no haya SMTP. |
| `SMTP_*` | **vacías** | Vacías = no se manda ningún correo. Es lo acordado. |

## 5. Cómo arranca

El `Procfile` tiene UNA sola línea, y así se queda:

    web: gunicorn server:app --workers 1 --threads 4 --bind 0.0.0.0:$PORT --timeout 60 --access-logfile - --error-logfile -

**El Procfile de Railway NO admite comentarios.** Lee cada línea que tenga dos
puntos como la definición de un servicio, así que un `# comentario con: algo`
revienta el deploy con *Invalid service name*. (Pasó: la primera versión de
este archivo venía comentada y Railway intentó crear un servicio llamado
«# seis controladores, y ESO es lo que registra las rutas».) Toda la
explicación vive acá, que para eso está este documento.

Qué significa cada parte:

- **`server:app`, no `flask_app:app`.** Es `server.py` el que importa los seis
  controladores, y eso es lo que registra las rutas. Con `flask_app:app` la
  app levanta sin ninguna ruta y todo responde 404.
- **`--workers 1 --threads 4`.** Un worker es un proceso Python entero y la
  RAM es lo que cobra Railway; los hilos casi no pesan. Esta app se pasa el
  tiempo esperando a MySQL y a Shopify, no calculando, que es justo para lo
  que sirven los hilos. Y además el freno anti-spam del registro cuenta en
  memoria: con un solo proceso, el límite que dice el código es el que se
  aplica. Si algún día se siente lento con gente de verdad, subir a
  `--workers 2 --threads 4` cuesta el doble de RAM.
- **`$PORT` lo pone Railway.** Fijarlo a 5000 es la forma más común de que el
  deploy quede «corriendo» pero sin responder.

Si prefieres no tener Procfile, lo mismo se puede escribir en el panel:
*Settings → Deploy → Custom Start Command*. Con una de las dos basta.

## 6. Entrar como admin la primera vez

El esquema crea el usuario admin `contacto@luckypoint.cl` **sin contraseña**:
no se puede iniciar sesión con él tal cual, y el correo de recuperación no va a
salir a ninguna parte.

Dos caminos:

1. **Por el log.** Pide recuperar la contraseña con ese correo. Sin SMTP, la
   app escribe el mensaje en `buzon/` y **deja el enlace en el log** — los
   logs de Railway lo muestran. Se abre el enlace y se crea la contraseña.
2. **Por SQL**, generando el hash a mano:

       python -c "import bcrypt; print(bcrypt.hashpw(b'tu-clave', bcrypt.gensalt(12)).decode())"
       -- luego:
       UPDATE usuarios SET password_hash='<el hash>', estado='activo'
        WHERE email='contacto@luckypoint.cl';

Y cambia ese correo por el tuyo de verdad si quieres recibir algo el día que se
encienda el SMTP.

## 7. Qué mirar apenas esté arriba

- La portada: que la **carta** salga (viene de MySQL) y que la **tienda**
  muestre los precios de Shopify y no el respaldo.
- `/api/v1/tienda/estado` — dice si el token de Shopify está funcionando.
- Crear una actividad de prueba en `/admin/actividades`, inscribirse como
  invitado, apretar «ya envié el formulario», confirmarla y abrir el voucher:
  el QR tiene que apuntar a la URL pública con **https**.
- Que el header no se rompa en un teléfono de verdad.

## 8. Lo que va a costar

Railway cobra por uso: **$20 por vCPU al mes, $10 por GB de RAM, $0,05 por GB
de salida** y centavos por el volumen. El plan Hobby son $5 al mes que ya
incluyen $5 de consumo; lo que pase de ahí se suma.

Con dos servicios prendidos todo el día, la cuenta se reparte más o menos así:

| | RAM típica | Al mes |
|---|---|---|
| La app (1 worker + 4 hilos) | ~0,15 GB | $1,5 – 2,5 |
| MySQL | ~0,4 GB | $4 – 5 |
| Salida de red | — | centavos |

O sea **entre $6 y $8**, con los $5 incluidos descontados: pagarías los $5 más
uno o tres dólares. Los límites del plan (48 vCPU, 48 GB, 5 réplicas) no tienen
nada que ver con eso: son techos gigantes, no lo que se cobra.

Dos formas de bajarlo, si molesta:

- **La nube naranja de Cloudflare**, una vez que Railway emita el certificado
  (y con el SSL en *Full (strict)*). Cachea las imágenes y el CSS, así que esos
  bytes dejan de salir de Railway.
- **Dormir el servicio web** cuando no hay nadie. Ahorra, pero la primera
  visita después de un rato espera el arranque. Para un sitio que se comparte
  por Instagram, no lo haría.

MySQL es la mitad cara y no hay mucho que apretar ahí: es el precio de tener
la base encendida.

## 9. Lo que queda sabido y aceptado

- **El disco es efímero**: en cada deploy se borra lo que la app haya escrito.
  Lo único que escribe es `buzon/`, y con los correos apagados no se pierde
  nada que importe — el enlace de cada inscripción se puede copiar desde el
  admin.
- **Sin pool de conexiones**: cada consulta abre y cierra su conexión a MySQL.
  Para el tráfico de una cafetería sobra; si alguna vez aparecen errores de
  «too many connections», eso es lo que hay que mirar.
- **El freno anti-spam cuenta en memoria**, así que vale por proceso. El
  `Procfile` arranca UN worker con cuatro hilos justamente para que el número
  que dice el código sea el que se aplica (y para gastar la mitad de RAM).
- **No hay respaldo automático de la base.** Vale la pena exportarla de vez en
  cuando, sobre todo después de cada evento con inscritos.
