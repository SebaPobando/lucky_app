# ==========================================================================
# admin_controller.py — administración de la carta
#
# Una sola pantalla por marca: todos los productos agrupados por categoría,
# editables ahí mismo. Crear, actualizar, eliminar, y apagar/prender de un
# click.
#
# La marca va SIEMPRE en la URL (/admin/carta/lucky-point). No es decoración:
# es lo que evita que una pizza de Gladiatore termine colgada de la carta de
# la cafetería por un POST mal dirigido. Son dos sociedades con RUT distinto;
# mezclarles los productos no es un bug cosmético.
#
# Todo va detrás de @requiere_admin. Ojo con el orden de los decoradores:
# @app.route va PRIMERO, y debajo el que protege. Al revés, Flask registra
# la vista sin protección.
# ==========================================================================

from flask import abort, flash, jsonify, redirect, render_template, request, url_for

from flask_app import app
from flask_app.config import csrf
from flask_app.controllers.main_controller import requiere_admin
from flask_app.models.carta_model import Carta

MARCA_POR_DEFECTO = "lucky-point"


# ------------------------------------------------------------------ ayudas

def _marca_o_404(slug):
    """
    Resuelve el slug de la URL a la marca. Si no existe o está desactivada,
    404: no tiene sentido administrar la carta de algo que no atiende.
    """
    marca = next((m for m in Carta.marcas_activas() if m["slug"] == slug), None)
    if not marca:
        abort(404)
    return marca


def _producto_de_la_marca(producto_id, marca):
    """
    Trae el producto y comprueba que sea de ESTA marca.

    Sin esta comprobación, /admin/carta/lucky-point/97 editaría la pizza 97
    de Gladiatore y le estamparía marca_id de la cafetería, moviéndola de
    empresa en silencio. Devuelve 404 y no 403 a propósito: desde la carta
    de una marca, los productos de la otra sencillamente no existen.
    """
    producto = Carta.obtener(producto_id)
    if not producto or producto["marca_id"] != marca["id"]:
        abort(404)
    return producto


def _protegido_csrf():
    """Corta la petición si el token no calza. 400, no 403: no damos pistas."""
    if not csrf.valido(request.form.get("csrf")):
        abort(400, "Token de seguridad inválido. Recarga la página.")


def _numero(valor, minimo=0, por_defecto=0):
    """Convierte texto de formulario a entero sin reventar con basura."""
    try:
        n = int(str(valor).strip().replace(".", "").replace("$", "") or por_defecto)
    except (TypeError, ValueError):
        return por_defecto
    return max(n, minimo)


def _texto(valor, maximo, obligatorio=False):
    v = (valor or "").strip()
    if obligatorio and not v:
        return None
    return v[:maximo] if v else None


def _numero_o_nada(valor):
    """
    Como _numero, pero el campo vacío devuelve None en vez de 0.

    Es la diferencia entre «esta pizza no tiene tamaño individual» y «el
    individual sale gratis». Un 0 en la carta pública se vería como $0.
    """
    if valor is None or not str(valor).strip():
        return None
    return _numero(valor)


def _datos_del_formulario(marca):
    nombre = _texto(request.form.get("nombre"), 150, obligatorio=True)
    if not nombre:
        return None, "El nombre no puede quedar vacío."

    # La categoría tiene que existir Y pertenecer a esta marca. Sin esta
    # comprobación, un POST a mano podría colgar un café de una categoría de
    # Gladiatore, o mandar un id inexistente y reventar la app con un 500.
    categoria_id = request.form.get("categoria_id") or None
    if categoria_id:
        validas = {str(c["id"]) for c in Carta.categorias_de(marca["slug"])}
        if str(categoria_id) not in validas:
            return None, "Esa categoría no existe en esta carta."

    return {
        "marca_id": marca["id"],
        "categoria_id": int(categoria_id) if categoria_id else None,
        "nombre": nombre,
        "descripcion": _texto(request.form.get("descripcion"), 2000),
        "etiqueta": _texto(request.form.get("etiqueta"), 30),
        "precio_clp": _numero(request.form.get("precio_clp")),
        "precio_individual_clp": _numero_o_nada(request.form.get("precio_individual_clp")),
        "imagen_url": _texto(request.form.get("imagen_url"), 255),
        "disponible": 1 if request.form.get("disponible") else 0,
        "orden": _numero(request.form.get("orden")),
    }, None


# --------------------------------------------------------------------- vistas

@app.route("/admin")
@requiere_admin
def admin_inicio():
    """
    El panel. Existe para que el menú de arriba no crezca: cada sección nueva
    de administración era un enlace más en la barra, y con dos ya se partía
    en dos líneas. Ahora la barra lleva un solo «Admin» y lo demás vive acá.
    """
    from flask_app.models.actividad_model import Actividad
    from flask_app.models.muro_model import Muro
    from flask_app.models.usuario_model import Usuario
    return render_template(
        "admin_inicio.html",
        productos=len(Carta.listar_para_admin("lucky-point"))
                  + len(Carta.listar_para_admin("gladiatore")),
        publicadas=sum(1 for a in Actividad.listar_para_admin()
                       if a["estado"] == "publicada"),
        muro=Muro.resumen(),
        usuarios=Usuario.resumen(),
    )


@app.route("/admin/carta")
@requiere_admin
def admin_carta_inicio():
    """El enlace del menú no conoce marcas: lo mandamos a la de siempre."""
    return redirect(url_for("admin_carta", marca_slug=MARCA_POR_DEFECTO))


@app.route("/admin/carta/<marca_slug>")
@requiere_admin
def admin_carta(marca_slug):
    marca = _marca_o_404(marca_slug)
    productos = Carta.listar_para_admin(marca_slug)
    categorias = Carta.categorias_de(marca_slug)

    # Agrupar en Python y no con otra consulta: son 60 filas, no vale la pena.
    grupos, indice = [], {}
    for p in productos:
        clave = p["categoria_id"]
        if clave not in indice:
            indice[clave] = {"nombre": p["categoria_nombre"] or "Sin categoría",
                             "id": clave, "items": []}
            grupos.append(indice[clave])
        indice[clave]["items"].append(p)

    return render_template("admin_carta.html",
                           grupos=grupos, categorias=categorias, marca=marca,
                           marcas=Carta.marcas_activas(),
                           total=len(productos),
                           apagados=sum(1 for p in productos if not p["disponible"]),
                           csrf_token=csrf.token())


@app.route("/admin/carta/<marca_slug>/crear", methods=["POST"])
@requiere_admin
def admin_carta_crear(marca_slug):
    _protegido_csrf()
    marca = _marca_o_404(marca_slug)
    datos, error = _datos_del_formulario(marca)
    if error:
        flash(error, "error")
    else:
        Carta.crear(datos)
        flash(f"«{datos['nombre']}» agregado a la carta.", "info")
    return redirect(url_for("admin_carta", marca_slug=marca_slug))


@app.route("/admin/carta/<marca_slug>/<int:producto_id>", methods=["POST"])
@requiere_admin
def admin_carta_actualizar(marca_slug, producto_id):
    _protegido_csrf()
    marca = _marca_o_404(marca_slug)
    _producto_de_la_marca(producto_id, marca)
    datos, error = _datos_del_formulario(marca)
    if error:
        flash(error, "error")
    else:
        Carta.actualizar(producto_id, datos)
        flash(f"«{datos['nombre']}» actualizado.", "info")
    return redirect(url_for("admin_carta", marca_slug=marca_slug))


@app.route("/admin/carta/<marca_slug>/<int:producto_id>/eliminar", methods=["POST"])
@requiere_admin
def admin_carta_eliminar(marca_slug, producto_id):
    _protegido_csrf()
    marca = _marca_o_404(marca_slug)
    producto = _producto_de_la_marca(producto_id, marca)
    if Carta.eliminar(producto_id):
        flash(f"«{producto['nombre']}» eliminado.", "info")
    else:
        # Lo bloqueó una llave foránea: alguien lo tiene en su lista de deseos.
        flash(f"No se puede eliminar «{producto['nombre']}» porque hay datos "
              "que lo referencian. Márcalo como no disponible.", "error")
    return redirect(url_for("admin_carta", marca_slug=marca_slug))


@app.route("/admin/carta/<marca_slug>/<int:producto_id>/disponible", methods=["POST"])
@requiere_admin
def admin_carta_disponible(marca_slug, producto_id):
    """
    El toggle de un click. Responde JSON porque lo llama fetch() desde la
    página, sin recargar: es la acción que más se va a usar en el día a día.
    """
    _protegido_csrf()
    marca = _marca_o_404(marca_slug)
    producto = _producto_de_la_marca(producto_id, marca)
    nuevo = not producto["disponible"]
    Carta.cambiar_disponible(producto_id, nuevo)
    return jsonify({"id": producto_id, "disponible": nuevo})
