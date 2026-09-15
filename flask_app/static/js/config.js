/* ===========================================================================
   Lucky Point Coffee — Configuracion del front
   ---------------------------------------------------------------------------
   Lo poco que el JavaScript necesita saber del entorno. Va en un archivo y no
   repetido en cada plantilla: la URL de la tienda estaba escrita a mano en
   landing.html y producto.html, y al sumar base.html iban a ser tres copias
   que se separan el dia que cambie el dominio de Shopify.

   No es secreto: es la direccion publica de la tienda. Por eso puede vivir en
   un .js estatico y seguir funcionando cuando la landing vuelva a Pages.

   PENDIENTE: cuando la app se despliegue de verdad, esto deberia salir del
   .env y renderizarse desde Flask, para no tocar codigo al cambiar de tienda.
   =========================================================================== */
window.SHOPIFY_STORE_URL = "https://lucky-point-coffee.myshopify.com";
