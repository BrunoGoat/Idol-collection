# Salón de Ídolos

Un tablero infinito de cartas-estampilla épicas con mis ídolos. App Android en
Flutter; los datos viven en este mismo repo, en `collection/`.

```
app/          ← código de la app (Flutter)
collection/   ← mis ídolos: imágenes + card.md + layout.json  (ver collection/README.md)
.github/      ← compila el APK automáticamente
```

## Qué hace

- **Tablero infinito**: arrastrá para moverte, pellizcá para hacer zoom. De lejos
  se ven cientos de cartas; al acercarte aparecen el nombre (con su fuente épica),
  el título, el número y el matasellos.
- **Tocar una carta**: la cámara vuela hasta ella y se abre en grande. Tocala
  para darla vuelta y leer por qué lo admirás. Deslizá el dedo o inclina el
  teléfono y brilla como una carta holográfica. Se puede compartir como imagen.
- **Mantener apretada**: la levantás y la movés. Mientras está seleccionada,
  pellizcá para agrandarla o rotarla. Las posiciones se guardan en el repo.
- **Botón +**: elegís una foto, nombre, título, categoría, rareza, uno de 12
  marcos, una de 21 fuentes, una frase y tu texto. Se sube sola al repo.
- **Rarezas** (Común → Mítica): cambian el color y la fuerza del brillo, el
  reflejo que cruza la carta y el holograma.
- **20 fondos** para el tablero (Ajustes → Fondo), con profundidad y animación.
- **Constelaciones**: las cartas de la misma categoría se unen con hilos de luz;
  de lejos se ve el nombre de cada zona.
- **Carta nueva**: si se agregó un ídolo al repo desde la última vez, al abrir
  la app se revela con animación de sobre de figuritas.
- **Ídolo del día**, **buscador** con filtros, **minimapa**, sonidos y vibración.
- **Funciona sin internet**: guarda una copia local y sube los cambios cuando
  vuelve la conexión.

## Instalar en Android

1. Cada vez que cambia el código en `main`, GitHub Actions compila el APK y lo
   publica en **Releases** (`/releases/latest` del repo). Desde el teléfono,
   con la sesión de GitHub iniciada, bajá `salon-de-idolos.apk` e instalalo
   (Android va a pedir permiso para instalar apps de origen desconocido).
2. **Opcional, recomendado — clave de firma fija.** Sin ella, cada APK sale
   firmado con una clave distinta y para actualizar hay que desinstalar la
   versión anterior (no perdés ídolos, que viven en el repo; solo tenés que
   volver a pegar el token). Para evitarlo, una sola vez, en una compu con Java:

   ```bash
   keytool -genkeypair -keystore idol-release.jks -alias idol -keyalg RSA -keysize 2048 -validity 36500
   base64 -w0 idol-release.jks   # en macOS: base64 -i idol-release.jks
   ```

   y en GitHub → Settings → Secrets and variables → Actions creá
   `ANDROID_KEYSTORE_BASE64` (la salida de base64) y
   `ANDROID_KEYSTORE_PASSWORD` (la contraseña que elegiste). Guardá el `.jks`
   en un lugar seguro y **no lo subas al repo**.

## Conectar la app al repo

En la app: **Ajustes → Repositorio de GitHub**.

- Dueño `BrunoGoat`, repo `Idol-collection`, rama `main`.
- Token: GitHub → Settings → Developer settings → Personal access tokens →
  **Fine-grained tokens** → acceso *solo* a este repo, permiso
  **Contents: Read and write**. Se guarda cifrado en el teléfono.

## Agregar ídolos pidiéndoselo a Claude

Pedile, por ejemplo: *"agregá a Lionel Messi, rareza mítica, marco oro, fuente
Cinzel Decorative, categoría Deporte, y este texto…"* junto con la imagen.
Claude crea `collection/idols/<id>/card.md` + `image.jpg`, y la próxima vez que
abras la app aparece con la animación de carta nueva.

## Desarrollo

```bash
cd app
flutter pub get
flutter analyze && flutter test
SCREENSHOTS=1 flutter test test/screenshots_test.dart   # capturas en build/screenshots/
flutter run
```

## Capturas

| Tablero | Zoom | Carta | Reverso |
|---|---|---|---|
| ![](docs/capturas/tablero.jpg) | ![](docs/capturas/zoom.jpg) | ![](docs/capturas/carta.jpg) | ![](docs/capturas/reverso.jpg) |

| Edición | Carta nueva | Marcos | Synthwave |
|---|---|---|---|
| ![](docs/capturas/edicion.jpg) | ![](docs/capturas/carta-nueva.jpg) | ![](docs/capturas/marcos.jpg) | ![](docs/capturas/synthwave.jpg) |

Los 20 fondos: ![](docs/capturas/fondos.jpg)

> Las capturas salen de `test/screenshots_test.dart`: los textos de botones se
> ven como barras grises porque el entorno de test no tiene la fuente del sistema.
