# ==========================================================================
# tienda_controller.py — el catálogo de la tienda online
#
# La tienda es café en grano y accesorios: lo que se despacha en caja. Vive en
# Shopify, no en MySQL (la regla de siempre: si se sirve en taza va en MySQL,
# si se despacha en caja es de Shopify).
#
# Hasta ahora el precio estaba escrito a mano en DOS lugares del código —el
# catálogo de `tienda-productos.js` y el texto de la tarjeta en la landing—
# más Shopify, que es el que de verdad cobra. Tres copias del mismo número.
# El modo de fallar era el peor posible: subes un precio en Shopify, olvidas
# el código, y la persona ve un número y paga otro.
#
# Ahora el precio y el stock salen de Shopify y nada más. Lo que queda escrito
# a mano es el RESPALDO, para cuando Shopify no contesta.
# ==========================================================================

from flask import jsonify

from flask_app import app
from flask_app.config import shopify


def catalogo_para_plantilla():
    """
    Lo que reciben la landing y la ficha.

    Devuelve None —no una lista vacía— cuando no hay catálogo de Shopify, y
    la diferencia importa: None significa «usa el respaldo escrito a mano»,
    mientras que una lista vacía significaría «la colección existe y no tiene
    nada», que es una tienda vacía de verdad.

    Nunca lanza: una caída de Shopify no puede llevarse la portada por
    delante.
    """
    try:
        return shopify.catalogo()
    except Exception as e:      # pragma: no cover  (shopify.catalogo ya atrapa)
        app.logger.error("No se pudo leer el catálogo de Shopify: %s", e)
        return None


@app.route("/api/v1/tienda")
def api_tienda():
    """
    El catálogo en JSON.

    Existe por lo mismo que /api/v1/menu y /api/v1/agenda: el día que la
    landing vuelva a GitHub Pages no va a haber servidor que pinte las
    tarjetas, y este endpoint pasa a ser de dónde las saca.

    Hoy las páginas servidas por Flask NO lo usan: reciben el catálogo
    inyectado en el HTML, que llega sin un segundo viaje y sin que las
    tarjetas parpadeen al cargar.

    503 si no hay catálogo: es más honesto que una lista vacía, que el front
    leería como «no hay productos».
    """
    datos = catalogo_para_plantilla()
    if datos is None:
        return jsonify({"error": "catálogo no disponible",
                        "detalle": shopify.estado()}), 503
    return jsonify(datos)


@app.route("/api/v1/tienda/estado")
def api_tienda_estado():
    """
    Diagnóstico. Dice si Shopify está configurado, cuántos productos trajo,
    de cuándo es la copia que se está sirviendo y, si algo falló, qué falló.

    Es lo primero que hay que mirar cuando la tienda muestre precios viejos:
    `error` distingue «el token está malo» de «la colección no existe» de
    «no hay internet», que desde afuera se ven todos igual.
    """
    return jsonify(shopify.estado())
