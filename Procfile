# Cómo arranca la app en Railway (y en cualquier PaaS que lea Procfile).
#
# server:app = el objeto `app` del archivo server.py. Ese archivo importa los
# seis controladores, y ESO es lo que registra las rutas: apuntar a
# flask_app:app levantaría la app sin ninguna ruta y todo daría 404.
#
# 2 workers alcanzan de sobra para una cafetería y entran en el plan chico.
# Ojo con subirlos: el freno anti-spam del registro cuenta en memoria, así
# que cada worker lleva su propia cuenta.
#
# $PORT lo pone Railway. Fijarlo a 5000 es la forma más común de que el
# deploy quede "corriendo" pero sin responder.
web: gunicorn server:app --workers 2 --bind 0.0.0.0:$PORT --timeout 60 --access-logfile - --error-logfile -
