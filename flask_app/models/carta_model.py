# ==========================================================================
# carta_model.py — la carta que se consume en el local
#
# SOLO la carta: cafetería, pastelería, pizzas. El café en grano vive en
# Shopify con su stock y sus variantes, y no se duplica acá.
#
# SQL crudo, sin ORM, con consultas parametrizadas (%(nombre)s). Nunca pegues
# valores dentro del string de la consulta: así es como entra un SQL injection.
# ==========================================================================

import re
import unicodedata

import pymysql.err

from flask_app import DB
from flask_app.config.mysqlconnection import connectToMySQL

CLP_POR_PUNTO = 10  # 1 Lucky Point = $10 CLP


class Carta:
    """Lectura de la carta. La escritura llega con el admin."""

    @staticmethod
    def menu(marca_slug="lucky-point"):
        """
        Devuelve la carta agrupada por categoría, en la misma forma que
        usaba el array que estaba escrito a mano en el HTML:

            [{"id": "cafe", "label": "Café", "items": [
                {"name": "Long Black", "clp": 3200, "desc": "...",
                 "tag": null, "lp": 320}
             ]}]

        Mantener la forma idéntica es lo que permite que el front no cambie
        casi nada: solo pasa de leer una constante a leer la API.

        Las categorías sin productos disponibles no se devuelven, para que no
        aparezca una pestaña vacía cuando se acaba todo lo de una sección.
        """
        query = """
            SELECT  c.slug         AS categoria_slug,
                    c.nombre       AS categoria_nombre,
                    c.orden        AS categoria_orden,
                    p.nombre       AS producto_nombre,
                    p.descripcion  AS producto_desc,
                    p.etiqueta     AS producto_etiqueta,
                    p.precio_clp   AS producto_precio,
                    p.precio_individual_clp AS producto_precio_ind,
                    p.orden        AS producto_orden
            FROM categorias c
            JOIN marcas m      ON m.id = c.marca_id
            LEFT JOIN productos p ON p.categoria_id = c.id
                                 AND p.disponible = TRUE
            WHERE m.slug = %(marca)s
              AND m.activa = TRUE
            ORDER BY c.orden, p.orden, p.nombre
        """
        filas = connectToMySQL(DB).query_db(query, {"marca": marca_slug})

        categorias = []
        indice = {}
        for f in filas:
            slug = f["categoria_slug"]
            if slug not in indice:
                indice[slug] = {"id": slug, "label": f["categoria_nombre"], "items": []}
                categorias.append(indice[slug])
            if f["producto_nombre"] is None:
                continue  # categoría sin productos disponibles
            ind = f["producto_precio_ind"]
            indice[slug]["items"].append({
                "name": f["producto_nombre"],
                "clp":  f["producto_precio"],
                "lp":   f["producto_precio"] // CLP_POR_PUNTO,
                "desc": f["producto_desc"],
                "tag":  f["producto_etiqueta"],
                # Segundo precio (pizza individual). Va como None cuando el
                # producto tiene uno solo, que es el caso de toda la cafetería:
                # así el front pregunta por él y no rompe nada donde no existe.
                "clp_ind": ind,
                "lp_ind":  (ind // CLP_POR_PUNTO) if ind is not None else None,
            })

        return [c for c in categorias if c["items"]]

    @staticmethod
    def marcas_activas():
        return connectToMySQL(DB).query_db(
            "SELECT id, slug, nombre, tema_css FROM marcas WHERE activa = TRUE ORDER BY id"
        )

    # ======================================================================
    # Escritura — lo que usa el admin
    # ======================================================================

    @staticmethod
    def categorias_de(marca_slug="lucky-point"):
        return connectToMySQL(DB).query_db(
            """SELECT c.id, c.slug, c.nombre, c.orden
               FROM categorias c JOIN marcas m ON m.id = c.marca_id
               WHERE m.slug = %(marca)s ORDER BY c.orden, c.nombre""",
            {"marca": marca_slug})

    @staticmethod
    def listar_para_admin(marca_slug="lucky-point"):
        """
        Todos los productos, incluidos los no disponibles — al revés que menu(),
        que solo devuelve lo que el cliente puede pedir.
        """
        return connectToMySQL(DB).query_db(
            """SELECT p.*, c.nombre AS categoria_nombre, c.orden AS categoria_orden
               FROM productos p
               JOIN marcas m ON m.id = p.marca_id
               LEFT JOIN categorias c ON c.id = p.categoria_id
               WHERE m.slug = %(marca)s
               ORDER BY c.orden, p.orden, p.nombre""",
            {"marca": marca_slug})

    @staticmethod
    def obtener(producto_id):
        filas = connectToMySQL(DB).query_db(
            "SELECT * FROM productos WHERE id = %(id)s", {"id": producto_id})
        return filas[0] if filas else None

    @staticmethod
    def _slug_libre(marca_id, nombre, excluir_id=None):
        """
        Genera un slug a partir del nombre y le agrega -2, -3... si ya existe.
        El UNIQUE de la base es (marca_id, slug), así que dos marcas pueden
        tener 'margarita' sin chocar.
        """
        base = unicodedata.normalize("NFKD", nombre or "")
        base = base.encode("ascii", "ignore").decode()
        base = re.sub(r"[^a-zA-Z0-9]+", "-", base).strip("-").lower()[:70] or "producto"

        candidato, n = base, 1
        while True:
            filas = connectToMySQL(DB).query_db(
                """SELECT id FROM productos
                   WHERE marca_id = %(marca)s AND slug = %(slug)s
                     AND (%(excluir)s IS NULL OR id <> %(excluir)s) LIMIT 1""",
                {"marca": marca_id, "slug": candidato, "excluir": excluir_id})
            if not filas:
                return candidato
            n += 1
            candidato = f"{base}-{n}"

    @staticmethod
    def crear(datos):
        datos = dict(datos)
        datos["slug"] = Carta._slug_libre(datos["marca_id"], datos["nombre"])
        return connectToMySQL(DB).query_db(
            """INSERT INTO productos
               (marca_id, categoria_id, slug, nombre, descripcion, etiqueta,
                precio_clp, precio_individual_clp, imagen_url, disponible, orden)
               VALUES (%(marca_id)s, %(categoria_id)s, %(slug)s, %(nombre)s,
                       %(descripcion)s, %(etiqueta)s, %(precio_clp)s,
                       %(precio_individual_clp)s,
                       %(imagen_url)s, %(disponible)s, %(orden)s)""", datos)

    @staticmethod
    def actualizar(producto_id, datos):
        datos = dict(datos)
        datos["id"] = producto_id
        # El slug sigue al nombre, pero conserva el suyo si no cambió: así los
        # enlaces que alguien haya guardado no se rompen sin necesidad.
        actual = Carta.obtener(producto_id)
        if actual and actual["nombre"] != datos["nombre"]:
            datos["slug"] = Carta._slug_libre(actual["marca_id"], datos["nombre"], producto_id)
        else:
            datos["slug"] = actual["slug"] if actual else None
        return connectToMySQL(DB).query_db(
            """UPDATE productos SET
                 categoria_id = %(categoria_id)s, slug = %(slug)s, nombre = %(nombre)s,
                 descripcion = %(descripcion)s, etiqueta = %(etiqueta)s,
                 precio_clp = %(precio_clp)s,
                 precio_individual_clp = %(precio_individual_clp)s,
                 imagen_url = %(imagen_url)s,
                 disponible = %(disponible)s, orden = %(orden)s
               WHERE id = %(id)s""", datos)

    @staticmethod
    def cambiar_disponible(producto_id, disponible):
        """La acción del día a día: se acabó el croissant."""
        return connectToMySQL(DB).query_db(
            "UPDATE productos SET disponible = %(d)s WHERE id = %(id)s",
            {"d": 1 if disponible else 0, "id": producto_id})

    @staticmethod
    def eliminar(producto_id):
        """
        Borrado real, para lo que se creó por error.

        Si alguien lo tiene en su lista de deseos, MySQL lo impide por la llave
        foránea y devolvemos False. En ese caso lo correcto no es borrar sino
        marcarlo como no disponible: el producto existió y hay datos que lo
        referencian.
        """
        try:
            connectToMySQL(DB).query_db(
                "DELETE FROM productos WHERE id = %(id)s", {"id": producto_id})
            return True
        except pymysql.err.IntegrityError:
            return False
