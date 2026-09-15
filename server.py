from flask_app import app
from flask_app.controllers import main_controller   # noqa: F401  (registra las rutas)
from flask_app.controllers import admin_controller  # noqa: F401
from flask_app.controllers import actividad_controller  # noqa: F401
from flask_app.controllers import muro_controller  # noqa: F401
from flask_app.controllers import usuarios_controller  # noqa: F401
from flask_app.controllers import tienda_controller  # noqa: F401

if __name__ == "__main__":
    # Esto corre SOLO cuando ejecutas `python server.py` en tu máquina. En
    # Railway arranca gunicorn (ver Procfile) y este bloque no se ejecuta.
    #
    # Aun así el debug se apaga con FLASK_ENV=production, por si algún día el
    # servidor lo levanta así: el depurador de Werkzeug deja ejecutar código
    # Python desde el navegador en cualquier página que reviente. En local es
    # comodísimo; abierto a internet es entregar el servidor.
    import os

    en_produccion = os.environ.get("FLASK_ENV") == "production"
    app.run(debug=not en_produccion,
            host=os.environ.get("HOST", "127.0.0.1"),
            port=int(os.environ.get("PORT", 5000)))
