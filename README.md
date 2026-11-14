# Coro

Prototipo personal de letras sincronizadas para Spotify, iPhone y la tarjeta de Actividades en vivo de CarPlay (iOS 26 o posterior). Preparado para compilar en un Mac de GitHub y firmarse desde Windows. No requiere un servidor permanente, una cuenta de pago de Apple ni una suscripción de letras.

**Estado: código preparado; pendiente de compilar con Xcode, instalar y probar en el iPhone. No es todavía una app verificada en un automóvil.**

## Qué hace

- Consulta únicamente la canción y el progreso de Spotify; Spotify sigue reproduciendo el audio.
- Obtiene letras con tiempos de LRCLIB. Nunca inventa tiempos para una letra sin sincronización.
- Publica la línea actual y la siguiente en una Actividad en vivo, con presentación pequeña para CarPlay.
- Permite corregir el desfase de -10 a +10 segundos.
- Respeta `Retry-After`, oculta letras cuando la reproducción deja de estar confirmada y mantiene una caché solo en memoria.
- Incluye una demostración marcada como tal, con texto original y sin música, que termina a los 45 segundos.
- Termina al desconectar una ruta de audio CarPlay, al cerrar la Actividad en vivo, tras dos minutos sin reproducción confirmada, por una interrupción de audio o cuando iOS informa estado térmico serio/crítico.

## Límites que requieren una prueba real

La tarjeta sigue dependiendo del iPhone. La app utiliza una pista PCM local completamente silenciosa y `mixWithOthers` para intentar conservar ejecución en segundo plano. Es un experimento para instalación personal: no debe interpretarse como una estrategia aprobada para distribución en App Store. No usa GPS ni micrófono. Hay que comprobar en el iPhone que Spotify conserva audio y controles, que la tarjeta se actualiza bloqueada y que el consumo es aceptable. No hay garantía de que reduzca el calentamiento.

Los cambios de canción, pausas y saltos se detectan normalmente en la siguiente consulta (5 segundos al reproducir, 8 en pausa), más la latencia de red. Las líneas intermedias siguen un reloj local monotónico. No ofrece sincronización por palabra. Requiere Internet para consultar Spotify y para letras que no estén ya en memoria. Canciones locales, anuncios y podcasts no se muestran como letras. La cobertura de LRCLIB no es completa.

La app no tiene un icono propio dentro de CarPlay ni ocupa toda la pantalla: usa una tarjeta del panel. Activa Actividades en vivo para Coro y para tu vehículo en Ajustes si no aparece. El sistema decide ubicación y visibilidad. Haz la instalación y las pruebas con el vehículo estacionado.

## Ruta sin pagos desde Windows

1. Usar el repositorio público https://github.com/nickozarate1234-lab/coro-carplay para **este código únicamente**, sin datos personales ni credenciales.
2. Ejecutar manualmente `Compilar Coro gratis` en GitHub Actions. El job se niega a arrancar en un repositorio privado y utiliza `macos-15`, un runner estándar. No usa runners de pago, caché de Actions, almacenamiento de artifacts de Actions ni certificados de Apple. Guarda el instalador como un borrador de release, con un límite de 25 MiB. El token efímero de GitHub solo se usa para guardar ese borrador en el mismo repositorio. No añadir un medio de pago ni habilitar gasto extra.
3. Abrir Releases con la cuenta propietaria y descargar del borrador `Coro-unsigned.ipa` y `SHA256.txt`. El instalador queda sin publicar; el código fuente del repositorio sí será público.
4. Instalar con Sideloadly desde su sitio oficial en Windows. Se necesitarán los componentes de Apple que indique su instalador. La cuenta Apple y sus códigos se introducen personalmente en la herramienta, nunca en el chat ni en GitHub.
5. Mantener la extensión `CoroLive` al firmar: sin ella no hay tarjeta de letras. Conectar el iPhone por USB, desbloquearlo y completar en el teléfono los avisos de confianza y modo desarrollador que solicite iOS.
6. La firma gratuita dura siete días. Renovarla desde el PC antes de vencer; la renovación automática requiere que el equipo y el teléfono puedan conectarse. Si vence, volver a firmar la app. No hay una instalación gratuita permanente garantizada.

El acceso a Spotify requiere una app personal en su panel de desarrolladores y que su propietario mantenga Premium. Coro no tiene clave de desarrollador compartida.

## Conectar Spotify una vez

En https://developer.spotify.com/dashboard, usar la cuenta Premium y crear una app personal con Web API. Registrar exactamente:

```text
http://127.0.0.1:43821/callback
```

El acceso se hace con Authorization Code + PKCE. La dirección de retorno escucha únicamente en el propio iPhone. Se usa una ventana de Safari dentro de la app; no una contraseña incrustada ni un navegador con acceso al contenido del inicio de sesión. El permiso solicitado es solo `user-read-currently-playing`.

Copiar el Client ID público a Ajustes de Coro y pulsar Conectar Spotify en la pantalla principal. No se utiliza el Client Secret. Si el panel exige autorizar usuarios, añadir la misma cuenta desde User Management. Los tokens se almacenan en Keychain con acceso solo en este dispositivo. Desconectar desde Coro los borra; para revocar además la autorización del servicio, usar https://www.spotify.com/account/apps/.

## Verificación de desarrollo

En Windows, con Node:

```powershell
node scripts/generate-resources.mjs
node scripts/validate.mjs
```

La validación local comprueba recursos, configuración y controles de empaquetado. **No compila Swift.**

En macOS, con Xcode 26.3 y XcodeGen, o dentro de Actions:

```sh
swift test
node scripts/generate-resources.mjs
node scripts/validate.mjs
xcodegen generate
```

`swift test` ejecuta pruebas del parser LRC, offsets, silencios instrumentales, saltos, pausas, reloj de reproducción, caducidad de datos, coincidencia de canciones y pausas exigidas por servicios. La compilación iOS y la revisión del bundle se definen en `.github/workflows/ios.yml`.

## Prueba pendiente en el automóvil

1. Ejecutar la demostración y comprobar que aparece la tarjeta, sin tratarla como reproducción de Spotify.
2. Conectar Spotify, reproducir una canción con letra conocida e iniciar letras.
3. Bloquear el teléfono durante al menos diez minutos; comprobar continuidad, audio, controles de Spotify y temperatura.
4. Pausar, reanudar, saltar de canción y avanzar/retroceder dentro de una pista. Ajustar el desfase si es necesario.
5. Cortar Internet: tras caducar la confirmación, la tarjeta debe mostrar espera y no continuar afirmando que una línea está sincronizada. Reconectar.
6. Desconectar CarPlay: comprobar que la sesión termina. Probar una llamada/Siri y volver a iniciar si la sesión fue interrumpida.
7. Revisar el uso de batería en Ajustes tras una sesión comparable. No considerar resuelto el calentamiento sin esta comparación.

## Fuentes técnicas

- https://developer.apple.com/carplay/
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.spotify.com/documentation/web-api/concepts/redirect_uri
- https://developer.spotify.com/documentation/web-api/concepts/quota-modes
- https://lrclib.net/docs.txt
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://sideloadly.io/

Código propio para este proyecto. Letras y música pertenecen a sus respectivos titulares. Coro no está afiliado a Spotify ni a Apple.
