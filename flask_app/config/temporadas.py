# ==========================================================================
# temporadas.py — las mascotas de temporada (Halloween, Navidad...)
#
# Durante una temporada, las mascotas del sitio se cambian solas por las de
# esa fecha y al terminar vuelven las de siempre, sin tocar nada. Las fechas
# son mes y día y se repiten todos los años: Halloween va del 1 al 31 de
# octubre, y el 1 de noviembre el sitio amanece con las mascotas normales.
#
# Las plantillas NO escriben la ruta de la imagen: piden
#     {{ mascota('lucky-sirviendo.png', 'hero') }}
# y esto devuelve la URL que toca hoy. Se busca primero por LUGAR (para que
# la portada no repita el mismo disfraz en tres secciones) y después por
# ARCHIVO (para el resto de las páginas). Lo que la temporada no reemplaza
# sale con la mascota normal.
#
# La fecha es la de Chile (config/tiempo.py), no la del servidor: Railway
# corre en UTC y el 31 a las 21:00 de acá allá ya es 1 de noviembre.
#
# Una temporada también puede cambiar COLORES: las variables CSS de
# `colores` se pisan en las páginas públicas (portada, tienda, cuenta...)
# mientras dure. El panel de admin no cambia: es una herramienta de
# trabajo, no una vitrina. Ver templates/_temporada.html.
#
# Para probar o apagarla sin esperar a la fecha, en el .env:
#     TEMPORADA=halloween   fuerza esa temporada
#     TEMPORADA=no          apaga todas
# ==========================================================================

import os

from flask import url_for

from flask_app.config import tiempo

CARPETA = "img/mascotas"

TEMPORADAS = [
    {
        "nombre": "halloween",
        "desde": (10, 1),     # (mes, día), los dos incluidos
        "hasta": (10, 31),
        "carpeta": "img/mascotas/halloween",
        # Morado noche en vez del verde, naranjo calabaza en vez del dorado
        # y una crema un poco más tostada. El texto y las tarjetas no
        # cambian: sigue viéndose Lucky Point, en versión Halloween.
        "colores": {
            "--lp-cream-50": "#FBF3E6",
            "--lp-cream-100": "#F4E7D2",
            "--lp-cream-200": "#EEDDC3",
            "--lp-cream-300": "#E2CBA8",
            "--lp-forest-900": "#1E1428",
            "--lp-forest": "#2E1F3B",
            "--lp-forest-600": "#45305A",
            "--lp-forest-300": "#9C88B0",
            "--lp-gold": "#D9651F",
            "--lp-gold-soft": "#F2A65A",
            "--lp-gold-bg": "#FBE0C6",
            # Los alias se repiten a propósito: así gana igual aunque una
            # página los haya fijado con un valor y no con var().
            "--surface-page": "#F4E7D2",
            "--surface-forest": "#2E1F3B",
            "--accent": "#2E1F3B",
            "--accent-hover": "#45305A",
            "--points": "#D9651F",
            "--points-bg": "#FBE0C6",
        },
        # Un disfraz distinto en cada sección de la portada.
        "por_lugar": {
            "hero": "calabaza.png",
            "about": "dracula.png",
            "carta": "frankenstein.png",
            "tienda": "tostadog.png",
            "talleres": "jason.png",
            "agenda": "momia.png",
            "muro": "fantasma.png",
            "puntos": "payaso.png",
            "promo": "hombre-lobo.png",
            "promo-burbuja": "fantasma.png",
        },
        # Para el resto de las páginas (login, registro, dashboard...).
        "por_archivo": {
            "lucky-sirviendo.png": "calabaza.png",
            "lucky-tomando.png": "frankenstein.png",
            "lucky.png": "jason.png",
            "point-mano.png": "fantasma.png",
            "point.png": "dracula.png",
            "cheers.png": "payaso.png",
            "estamos-en-eso.png": "momia.png",
            "full.png": "hombre-lobo.png",
        },
    },
]


def _en_rango(hoy, desde, hasta):
    md = (hoy.month, hoy.day)
    if desde <= hasta:
        return desde <= md <= hasta
    # Una temporada que cruza el año (15 de diciembre al 6 de enero).
    return md >= desde or md <= hasta


def actual(hoy=None):
    """La temporada vigente hoy en Chile, o None."""
    forzada = (os.environ.get("TEMPORADA") or "").strip().lower()
    if forzada in ("no", "ninguna", "0"):
        return None
    if forzada:
        return next((t for t in TEMPORADAS if t["nombre"] == forzada), None)
    if hoy is None:
        hoy = tiempo.utc_a_local(tiempo.ahora_utc()).date()
    return next((t for t in TEMPORADAS if _en_rango(hoy, t["desde"], t["hasta"])), None)


def mascota(archivo, lugar=None):
    """La URL de la mascota que toca mostrar hoy en ese lugar."""
    t = actual()
    if t:
        cambio = t["por_lugar"].get(lugar) if lugar else None
        cambio = cambio or t["por_archivo"].get(archivo)
        if cambio:
            return url_for("static", filename=t["carpeta"] + "/" + cambio)
    return url_for("static", filename=CARPETA + "/" + archivo)
