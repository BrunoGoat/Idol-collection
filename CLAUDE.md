# Notas para Claude

- `app/` es la app Flutter (Android). `collection/` son los datos que la app
  descarga del repo. El formato completo está en `collection/README.md`.
- Para **agregar un ídolo**: crear `collection/idols/<slug>/card.md` y
  `image.jpg` (JPEG, lado mayor ≤ 1600 px, calidad ~88). El slug es el nombre en
  minúsculas sin acentos, con guiones. Usar solo ids de marco/fuente/rareza que
  existan en las tablas de `collection/README.md`. `number` = el máximo actual + 1.
  No hace falta tocar `layout.json`: la app ubica sola las cartas nuevas.
- Para **mover o agrandar cartas**, editar `collection/layout.json` (solo las
  entradas que cambian: la app fusiona por carta).
- Los cambios solo en `collection/` no disparan el build del APK.
- La app lee la rama configurada en sus ajustes (por defecto `main`): los
  cambios de datos tienen que llegar a esa rama para verse en el teléfono.
- Antes de subir código: `cd app && flutter analyze && flutter test`. Los tests usan
  la colección de ejemplo de `app/test/fixtures/`, no la real. Para
  revisar el diseño: `SCREENSHOTS=1 flutter test test/screenshots_test.dart`.
