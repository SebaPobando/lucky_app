# ==========================================
# __init__.py — inicializa la aplicación Flask
# ==========================================
import os

from flask import Flask

# Carga el archivo .env antes de leer cualquier variable. Sin esto, todo lo que
# pongas en .env se ignora en silencio y la app usa los valores por defecto.
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:  # si aún no instalaste requirements.txt
    pass

app = Flask(__name__)

# La clave de sesión sale del entorno. Si queda escrita en el código, cualquiera
# con acceso al repo puede firmar cookies de sesión y entrar como quien quiera.
app.secret_key = os.environ.get("SECRET_KEY", "dev-solo-para-local-cambiar-en-produccion")

# --- Detrás del proxy de Railway (o de cualquier PaaS) ----------------------
# Railway termina el HTTPS en su borde y le habla a la app por HTTP interno.
# Sin esto Flask cree que la petición fue http, y `url_for(..., _external=True)`
# —el enlace del voucher que va al correo y al WhatsApp— sale con http://.
# Funciona igual porque Railway redirige, pero es un salto de más y se ve mal
# pegado en un mensaje.
#
# Va detrás de una variable y NO siempre encendido a propósito: ProxyFix le
# CREE a las cabeceras X-Forwarded-*, y eso solo es seguro cuando de verdad
# hay un proxy adelante que las reescribe. En un servidor expuesto sin proxy,
# cualquiera podría mandarlas y hacerse pasar por otra IP.
if os.environ.get("DETRAS_DE_PROXY") == "1":
    from werkzeug.middleware.proxy_fix import ProxyFix
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

# Cookie de sesión endurecida (ver Fase 2 del roadmap).
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.environ.get("FLASK_ENV") == "production",
)

# Flask ordena alfabéticamente las claves de todo lo que serializa a JSON, y
# eso NO es inocuo acá: el catálogo de la tienda llega de Shopify con los
# tamaños en el orden en que están definidos en el producto («250 g», «1 kg»,
# de más chico a más grande) y ordenarlos alfabéticamente los deja como
# «1 kg», «250 g». El sitio terminaba ofreciendo el kilo por defecto.
#
# Vale para todo lo demás igual: el orden que eligió quien escribió los datos
# suele querer decir algo, y ordenarlo solo lo borra.
app.json.sort_keys = False

# Y esto NO es lo mismo ni sobra: el filtro |tojson de las plantillas no usa
# la configuración de arriba, usa una política propia de Jinja que trae
# sort_keys=True y pisa la del proveedor. Sin esta línea, jsonify devuelve el
# orden bueno y el mismo dato inyectado en el HTML sale ordenado alfabético.
app.jinja_env.policies["json.dumps_kwargs"] = {"sort_keys": False}

# Base de datos que usan los modelos.
DB = os.environ.get("DB_NAME", "lucky_point_db")

# Hoy esta app sirve TODO en un solo origen (localhost:5000): la landing, la
# ficha de producto y el área de cuenta. Las plantillas enlazan con url_for.
#
# Cuando la landing vuelva a GitHub Pages, se cambia el cuerpo de la ruta "/"
# en main_controller.py por un redirect a esta variable. Mientras tanto queda
# apuntando a la raíz local.
SITIO_PUBLICO = os.environ.get("SITIO_PUBLICO", "/")


@app.context_processor
def inyectar_globales():
    """Disponibles en todas las plantillas sin pasarlas en cada render."""
    from flask import session
    from flask_app.config import csrf
    return {
        "sitio_publico": SITIO_PUBLICO,
        "usuario": session.get("usuario"),
        # Se pasa la FUNCIÓN, no el token. csrf.token() crea la sesión la
        # primera vez que se llama, y si lo evaluáramos acá le estaríamos
        # poniendo una cookie a todo el que abre la portada sin necesidad.
        # Así solo se crea en las plantillas que de verdad lo escriben.
        #
        # Nombre distinto a csrf_token a propósito: las vistas que ya pasan
        # csrf_token=csrf.token() como string siguen funcionando igual.
        "csrf_actual": csrf.token,
    }
