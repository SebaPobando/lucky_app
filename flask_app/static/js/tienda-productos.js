/* ===========================================================================
   Lucky Point Coffee — Catalogo de la tienda online (RESPALDO)
   ---------------------------------------------------------------------------
   OJO: esto YA NO ES la fuente de verdad. Los productos, precios y stock los
   trae el servidor desde Shopify (config/shopify.py) y los inyecta en el HTML
   llamando a LP_TIENDA.cargar(). Lo que hay escrito aca abajo es el RESPALDO:
   lo que se ve si Shopify no contesta y el servidor nunca alcanzo a traer el
   catalogo.

   Por que existe igual: una tienda que muestra precios de hace un mes es
   mala; una tienda en blanco es peor. Es el mismo trato que MENU_RESPALDO
   con la carta.

   REGLA DEL PROYECTO: esto NO se duplica en MySQL. `productos` en la base es
   solo la carta del local (lo que se sirve en taza o plato). Lo que se
   despacha en caja vive en Shopify.

   Para agregar un producto de verdad: se crea en Shopify y se mete en la
   coleccion que apunta SHOPIFY_COLECCION. Nada mas. Este archivo se actualiza
   solo cuando uno quiera que el respaldo se parezca a la realidad; que quede
   viejo no rompe nada mientras Shopify responda.

   El precio (clp) es SOLO para mostrar. Shopify cobra lo que dice Shopify.
   =========================================================================== */
(function (window) {
  "use strict";

  /* El orden importa: el primero es el que viene seleccionado por defecto. */
  var MOLIENDAS = [
    "Entero",
    "Fino (Espresso o Moka)",
    "Medio (Filtrado)",
    "Grueso - Francesa"
  ];

  var PRODUCTOS = {
    "brasil": {
      name: "Brasil Peaberry",
      vendor: "Café de especialidad · Brasil",
      type: "cafe",
      desc: "Hacienda Furnas · Peaberry natural. Notas dulces y achocolatadas, cuerpo sedoso y acidez suave.",
      sizes: {
        "250 g": { clp: 12990, grinds: {
          "Entero": 56000936771750,
          "Fino (Espresso o Moka)": 56000936804518,
          "Medio (Filtrado)": 56000936837286,
          "Grueso - Francesa": 56000936870054 } },
        "1 kg": { clp: 41990, grinds: {
          "Entero": 56000964591782,
          "Fino (Espresso o Moka)": 56000964624550,
          "Medio (Filtrado)": 56000964657318,
          "Grueso - Francesa": 56000964690086 } }
      }
    },

    "colombia": {
      name: "Colombia La Plata Huila",
      vendor: "Café de especialidad · Colombia",
      type: "cafe",
      desc: "Huila · proceso lavado. Cítrico y equilibrado, cuerpo sedoso y retrogusto a chocolate.",
      sizes: {
        "250 g": { clp: 12990, grinds: {
          "Entero": 55998346625190,
          "Fino (Espresso o Moka)": 55998346657958,
          "Medio (Filtrado)": 55998346690726,
          "Grueso - Francesa": 55998346723494 } },
        "1 kg": { clp: 41990, grinds: {
          "Entero": 55998692688038,
          "Fino (Espresso o Moka)": 55998692655270,
          "Medio (Filtrado)": 55998692622502,
          "Grueso - Francesa": 55998692720806 } }
      }
    },

    "filtros-01": {
      name: "Filtros V60 · Tamaño 01",
      vendor: "Accesorios",
      type: "acc",
      clp: 6990,
      desc: "100 filtros de papel para tu V60, tamaño 01. Empacados en bolsa y caja de cartón.",
      variant: 56006701580454
    },

    "filtros-02": {
      name: "Filtros V60 · Tamaño 02",
      vendor: "Accesorios",
      type: "acc",
      clp: 7990,
      desc: "100 filtros de papel para tu V60, tamaño 02. Empacados en bolsa y caja de cartón.",
      variant: 56006730940582
    }
  };

  /* ===================== Helpers compartidos ===================== */

  var api = {
    MOLIENDAS: MOLIENDAS,
    PRODUCTOS: PRODUCTOS,

    /* Reemplaza el respaldo por el catalogo de Shopify.
       Lo llama un <script> inline que escribe el servidor, justo despues de
       cargar este archivo y ANTES de que la ficha o el modal se inicialicen:
       asi nadie llega a ver el precio del respaldo. */
    cargar: function (lista) {
      if (!lista || !lista.length) { return false; }
      var nuevos = {};
      lista.forEach(function (p) { if (p && p.id) { nuevos[p.id] = p; } });
      if (!Object.keys(nuevos).length) { return false; }
      PRODUCTOS = nuevos;
      api.PRODUCTOS = nuevos;
      api.deShopify = true;
      return true;
    },

    /* Si vino de Shopify, cada producto trae SUS moliendas. El respaldo no,
       y por eso sigue existiendo la lista global. */
    moliendas: function (prod) {
      return (prod && prod.moliendas && prod.moliendas.length)
        ? prod.moliendas : MOLIENDAS;
    },

    /* Hay stock de esta combinacion? El respaldo no sabe de stock, asi que
       responde que si: es lo unico que puede hacer, y no inventar un agotado
       que no existe. */
    disponible: function (prod, tamano, molienda) {
      if (!prod) { return false; }
      if (prod.type === "acc") {
        return prod.disponible !== false;
      }
      var caja = prod.sizes && prod.sizes[tamano];
      if (!caja || !caja.sin_stock) { return true; }
      return caja.sin_stock.indexOf(molienda || "Único") === -1;
    },

    /* El precio mas bajo del producto, para el «Desde $X» de la tarjeta. */
    desde: function (prod) {
      if (!prod) { return 0; }
      if (prod.desde_clp) { return prod.desde_clp; }
      if (prod.type === "acc") { return prod.clp; }
      var precios = api.tamanos(prod).map(function (t) { return prod.sizes[t].clp; });
      return precios.length ? Math.min.apply(null, precios) : 0;
    },

    /* Devuelve el producto o null. Nunca revienta con un id inventado. */
    get: function (id) {
      return Object.prototype.hasOwnProperty.call(PRODUCTOS, id) ? PRODUCTOS[id] : null;
    },

    tamanos: function (prod) {
      if (!prod || !prod.sizes) { return []; }
      /* Si el catalogo trae el orden explicito, ese manda. Object.keys es el
         respaldo, y depende de que nadie haya reordenado las claves por el
         camino. */
      return (prod.tamanos && prod.tamanos.length)
        ? prod.tamanos : Object.keys(prod.sizes);
    },

    precio: function (prod, tamano) {
      if (!prod) { return 0; }
      return prod.sizes ? prod.sizes[tamano].clp : prod.clp;
    },

    variante: function (prod, tamano, molienda) {
      if (!prod) { return null; }
      if (prod.type === "acc") { return prod.variant; }
      var caja = prod.sizes && prod.sizes[tamano];
      if (!caja) { return null; }
      var variantes = caja.grinds || {};
      /* "Único" es la dimensión ausente. Además de cubrir productos con una
         sola opción, el último fallback evita romper la compra si Shopify
         vuelve a entregar una opción con un rótulo inesperado. */
      if (variantes[molienda]) { return variantes[molienda]; }
      if (variantes["Único"]) { return variantes["Único"]; }
      var ids = Object.keys(variantes);
      return ids.length === 1 ? variantes[ids[0]] : null;
    },

    /* Traduce una seleccion a la linea que espera LPCarrito.agregar(). */
    linea: function (prod, tamano, molienda, qty) {
      if (!prod) { return null; }
      return {
        variante: api.variante(prod, tamano, molienda),
        nombre: prod.name,
        opciones: [prod.sizes && tamano !== "Único" ? tamano : null,
                   prod.type === "cafe" ? molienda : null]
                    .filter(Boolean).join(" · "),
        clp: api.precio(prod, tamano),
        qty: qty
      };
    }
  };

  window.LP_TIENDA = api;

})(window);
