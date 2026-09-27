# ==========================================================================
# pedido_shopify_model.py — el registro de compras confirmadas en Shopify
#
# Qué es: cada vez que alguien paga en el checkout de Shopify, un webhook
# («orders/paid», ver controllers/tienda_controller.py) le avisa a esta app
# y el pedido queda guardado acá.
#
# ESTO ES UN REGISTRO, NO UNA BILLETERA. No suma ni descuenta saldo de
# puntos — eso vive en una tabla de movimientos aparte que todavía no
# existe (ver la nota de `transaccion()` en config/mysqlconnection.py). La
# columna `puntos_acreditados_at` de la tabla es el enganche para esa fase
# futura y hasta entonces nadie la toca.
#
# LA COMPRA SE LIGA A UN USUARIO POR CORREO, SIN EXIGIR CUENTA. Alguien
# puede comprar sin haberse registrado nunca en el sitio y el pedido igual
# queda guardado, con `usuario_id` en NULL. Si después esa persona se
# registra con el mismo correo, los pedidos anteriores NO se re-vinculan
# solos — vincular compras viejas por correo automáticamente es la misma
# clase de agujero que ya se cerró en el registro (la prueba C1 de la
# suite), aunque acá el premio sea mucho menor.
# ==========================================================================

import json

from flask_app import DB
from flask_app.config.mysqlconnection import connectToMySQL


class Pedido:

    # ------------------------------------------------------------ escribir

    @staticmethod
    def registrar(datos):
        """
        Guarda el pedido si no estaba. Idempotente a propósito: Shopify
        reintenta un webhook que no contestó 2xx a tiempo, y a veces entrega
        el mismo dos veces aunque sí se haya procesado bien — es su
        política, no un error. `INSERT IGNORE` sobre el UNIQUE de
        `shopify_order_id` hace que procesar el mismo pedido otra vez no
        invente un segundo registro.

        Devuelve True si quedó guardado, False si ya existía.
        """
        insertado = connectToMySQL(DB).query_db("""
            INSERT IGNORE INTO pedidos_shopify
                (shopify_order_id, numero_orden, usuario_id, correo_comprador,
                 monto_clp, moneda, items, creado_shopify_at)
            VALUES
                (%(shopify_order_id)s, %(numero_orden)s, %(usuario_id)s,
                 %(correo_comprador)s, %(monto_clp)s, %(moneda)s,
                 %(items)s, %(creado_shopify_at)s);
        """, dict(datos, items=json.dumps(datos.get("items") or [], ensure_ascii=False)))
        return bool(insertado)

    # -------------------------------------------------------------- panel

    @staticmethod
    def recientes(limite=50):
        """Para /admin/pedidos: lo último primero, con el nombre si hay cuenta."""
        filas = connectToMySQL(DB).query_db("""
            SELECT p.*, u.nombre AS usuario_nombre
            FROM pedidos_shopify p
            LEFT JOIN usuarios u ON u.id = p.usuario_id
            ORDER BY p.recibido_at DESC
            LIMIT %(limite)s;
        """, {"limite": int(limite)})
        for f in filas:
            try:
                f["items"] = json.loads(f["items"]) if f.get("items") else []
            except (TypeError, ValueError):
                f["items"] = []
        return filas

    @staticmethod
    def resumen():
        """Para la pastilla del panel: cuántos pedidos y cuánto han sumado."""
        filas = connectToMySQL(DB).query_db("""
            SELECT COUNT(*) AS total, COALESCE(SUM(monto_clp), 0) AS total_clp
            FROM pedidos_shopify;
        """)
        fila = filas[0] if filas else {}
        return {"total": int(fila.get("total") or 0),
                "total_clp": int(fila.get("total_clp") or 0)}
