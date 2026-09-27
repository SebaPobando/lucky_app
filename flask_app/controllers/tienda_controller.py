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

import json
from datetime import datetime, timezone

from flask import jsonify, render_template, request

from flask_app import app
from flask_app.config import shopify, tiempo
from flask_app.controllers.main_controller import requiere_admin
from flask_app.models.pedido_shopify_model import Pedido
from flask_app.models.usuario_model import Usuario, normalizar_email


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


# ============================================================== el webhook
#
# Cuando alguien paga en el checkout de Shopify, Shopify avisa acá con el
# webhook «orders/paid». Esto es un REGISTRO de lo que se vendió, no una
# billetera: no suma ni descuenta saldo de puntos (ver el encabezado de
# pedido_shopify_model.py). Cómo darlo de alta en el admin de Shopify está
# en el .env.example — necesita el sitio ya desplegado, con URL pública.


def _pesos_shopify(monto):
    """'12990.00' -> 12990. Los pedidos también se guardan en CLP enteros."""
    try:
        return int(round(float(monto)))
    except (TypeError, ValueError):
        return 0


def _fecha_shopify(iso):
    """
    '2026-09-27T10:15:00-03:00' -> datetime UTC sin tzinfo, para que calce
    con el resto de la base (ver config/tiempo.py). None si no se pudo leer
    — un pedido con una fecha rara igual se guarda, solo que sin ese dato.
    """
    if not iso:
        return None
    try:
        con_zona = datetime.fromisoformat(str(iso).replace("Z", "+00:00"))
        return con_zona.astimezone(timezone.utc).replace(tzinfo=None)
    except ValueError:
        return None


@app.route("/webhooks/shopify/orders-paid", methods=["POST"])
def webhook_shopify_orden_pagada():
    """
    Contesta rápido y simple a propósito: Shopify espera 2xx en unos
    segundos: si no lo recibe, reintenta con backoff durante horas y termina
    desactivando el webhook. Nada de lo que pasa acá debería demorar ni
    depender de que algo más responda.
    """
    cuerpo = request.get_data()   # crudo, ANTES de parsear: la firma es sobre esto
    firma = request.headers.get("X-Shopify-Hmac-Sha256", "")

    if not shopify.verificar_firma_webhook(cuerpo, firma):
        app.logger.warning("Webhook de Shopify con firma inválida o sin configurar.")
        return jsonify({"error": "firma inválida"}), 401

    try:
        orden = json.loads(cuerpo)
    except ValueError:
        return jsonify({"error": "cuerpo ilegible"}), 400

    if not orden.get("id"):
        return jsonify({"error": "sin id de orden"}), 400

    correo = normalizar_email(orden.get("email") or orden.get("contact_email") or "")
    usuario = Usuario.por_email(correo) if correo else None

    items = [{
        "titulo": (li.get("title") or li.get("name") or "")[:200],
        "cantidad": li.get("quantity") or 0,
        "clp": _pesos_shopify(li.get("price")),
    } for li in (orden.get("line_items") or [])]

    guardado = Pedido.registrar({
        "shopify_order_id": orden["id"],
        "numero_orden": (orden.get("name") or orden.get("order_number") or None),
        "usuario_id": usuario["id"] if usuario else None,
        "correo_comprador": correo or "(sin correo)",
        "monto_clp": _pesos_shopify(orden.get("total_price")
                                    or orden.get("current_total_price")),
        "moneda": (orden.get("currency") or "CLP")[:3],
        "items": items,
        "creado_shopify_at": _fecha_shopify(orden.get("created_at")),
    })
    if not guardado:
        app.logger.info("Webhook de Shopify repetido, la orden %s ya estaba.",
                        orden["id"])

    return jsonify({"ok": True}), 200


# --------------------------------------------------------------- el panel

@app.route("/admin/pedidos")
@requiere_admin
def admin_pedidos():
    return render_template("admin_pedidos.html",
                           pedidos=Pedido.recientes(100),
                           resumen=Pedido.resumen(),
                           tiempo=tiempo)
