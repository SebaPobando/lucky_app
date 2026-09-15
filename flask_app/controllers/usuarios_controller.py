# ==========================================================================
# usuarios_controller.py — el lado ADMIN de las cuentas
#
# Acá vive solo /admin/usuarios. El login, el registro, la recuperación de
# contraseña y el perfil siguen en main_controller: eso es lo que hace cada
# persona con su propia cuenta, y esto es lo que hace el admin con las de
# los demás.
#
# Qué se puede hacer hoy: mirar quién hay y bloquear o desbloquear.
#
# Qué NO se puede, y es a propósito:
#
#   - Crear cuentas de barista. El rol existe en el esquema, pero mientras
#     no exista el canje en mesón (Fase 4) un barista no puede hacer nada
#     que un cliente no pueda. Se agrega cuando haya algo que hacer con él.
#
#   - Borrar. La columna `deleted_at` está lista para el borrado lógico,
#     pero borrar de verdad se lleva por delante los mensajes del muro (la
#     llave va con ON DELETE CASCADE), lo impiden las inscripciones a
#     actividades, y cuando exista el ledger, borrar una cuenta con saldo
#     prepago es destruir un pasivo contable: plata que esa persona pagó.
#     Bloquear cubre lo que hace falta hoy.
#
#   - Cambiar roles. Sin esto, el panel no puede dejar el sistema sin
#     administradores.
# ==========================================================================

from flask import (abort, flash, redirect, render_template, request, session,
                   url_for)

from flask_app import app
from flask_app.config import csrf, tiempo
from flask_app.controllers.main_controller import requiere_admin
from flask_app.models.usuario_model import Usuario

ROLES = ("cliente", "barista", "admin")
ESTADOS = ("invitado", "activo", "bloqueado")


# ------------------------------------------------------------------ ayudas

def _protegido_csrf():
    if not csrf.valido(request.form.get("csrf")):
        abort(400, "Token de seguridad inválido. Recarga la página.")


def _filtro(nombre, validos):
    """Un filtro de la URL solo si es uno de los valores que existen."""
    valor = request.args.get(nombre)
    return valor if valor in validos else None


def _vista(fila):
    d = dict(fila)
    d["desde"] = tiempo.fecha(d["created_at"])
    d["verificado"] = bool(d["email_verificado_at"])
    # Cómo llamarla en pantalla, con el mismo criterio que para_sesion.
    d["etiqueta"] = (d.get("nickname") or "").strip() \
        or " ".join(p for p in [d.get("nombre"), d.get("apellido")] if p).strip() \
        or d["email"].split("@")[0]
    # Un admin no se puede tocar desde acá, y uno mismo tampoco.
    d["intocable"] = d["rol"] == "admin"
    return d


def _objetivo(usuario_id):
    """
    Resuelve el id a una cuenta que este panel pueda tocar.

    404 si no existe. Si es un admin, 400 con un mensaje claro: no es un
    error del sistema, es una regla — y la más importante de este archivo,
    porque es la que impide quedarse afuera del propio panel un domingo.
    """
    fila = Usuario.por_id(usuario_id)
    if not fila:
        abort(404)
    if fila["rol"] == "admin":
        abort(400, "Las cuentas de administrador no se bloquean desde acá.")
    return fila


# ------------------------------------------------------------------ vistas

@app.route("/admin/usuarios")
@requiere_admin
def admin_usuarios():
    busca = (request.args.get("busca") or "").strip()
    rol = _filtro("rol", ROLES)
    estado = _filtro("estado", ESTADOS)

    filas = Usuario.listar_para_admin(busca=busca or None, rol=rol, estado=estado)

    return render_template(
        "admin_usuarios.html",
        usuarios=[_vista(u) for u in filas],
        busca=busca,
        rol=rol,
        estado=estado,
        # Si el listado llega justo al tope, puede haber más que no se ven.
        # Decirlo es mejor que mostrar un listado incompleto en silencio.
        topado=len(filas) >= Usuario.TOPE_LISTADO,
        tope=Usuario.TOPE_LISTADO,
        conteo=Usuario.resumen(),
        csrf_token=csrf.token(),
    )


@app.route("/admin/usuarios/<int:usuario_id>/bloquear", methods=["POST"])
@requiere_admin
def admin_usuarios_bloquear(usuario_id):
    _protegido_csrf()

    # Cinturón además del tirante: _objetivo ya rechaza a los admins, y el
    # UPDATE del modelo también. Esta comprobación existe para el día en que
    # alguien se pueda bloquear a sí mismo sin ser admin.
    if usuario_id == session["usuario"]["id"]:
        abort(400, "No puedes bloquear tu propia cuenta.")

    objetivo = _objetivo(usuario_id)
    if Usuario.bloquear(usuario_id):
        flash(f"{objetivo['email']} quedó bloqueada. No podrá entrar ni "
              "escribir en el muro.", "info")
    else:
        flash("Esa cuenta ya estaba bloqueada.", "info")
    return redirect(_volver())


@app.route("/admin/usuarios/<int:usuario_id>/desbloquear", methods=["POST"])
@requiere_admin
def admin_usuarios_desbloquear(usuario_id):
    _protegido_csrf()
    objetivo = _objetivo(usuario_id)
    if Usuario.desbloquear(usuario_id):
        flash(f"{objetivo['email']} vuelve a tener acceso.", "info")
    else:
        flash("Esa cuenta no estaba bloqueada.", "info")
    return redirect(_volver())


def _volver():
    """
    Vuelve al listado con la misma búsqueda y los mismos filtros.

    Se rearma desde campos ocultos del formulario y NUNCA desde una URL
    entera: aceptar una URL del formulario sería un redirect abierto.
    """
    return url_for("admin_usuarios",
                   busca=(request.form.get("busca") or "").strip() or None,
                   rol=request.form.get("rol") if request.form.get("rol") in ROLES else None,
                   estado=request.form.get("estado") if request.form.get("estado") in ESTADOS else None)
