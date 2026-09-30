# La colección

Todo lo que ves en la app sale de esta carpeta. La app la descarga cada vez que
se abre y sube lo que agregues o muevas desde el teléfono.

```
collection/
  layout.json            ← posición, tamaño y rotación de cada carta + fondo del tablero
  idols/
    <id>/                ← el id es el nombre de la carpeta (ej: marie-curie)
      card.md            ← datos de la carta y el texto de por qué lo admirás
      image.jpg          ← la imagen (idealmente ≤ 1600 px de lado, JPEG)
```

## `card.md`

```markdown
---
name: "Marie Curie"                 # obligatorio
title: "La Dama del Radio"          # epíteto épico (opcional)
category: "Ciencia"                 # agrupa las cartas en constelaciones (opcional)
rarity: mythic                      # common | rare | epic | legendary | mythic
frame: esmeralda                    # ver tabla de marcos
font: CinzelDecorative              # ver tabla de fuentes
added: 2026-09-01                   # fecha de ingreso al salón (va en el matasellos)
number: 1                           # número de colección (opcional: si falta, se asigna por fecha)
quote: "Nada en la vida debe ser temido, solo comprendido."   # opcional
image: "image.jpg"                  # archivo de imagen dentro de la carpeta
focus: [0.00, -0.30]                # encuadre de la imagen, -1..1 en x e y (opcional)
---

Por qué lo admiro, en **markdown**: párrafos, _cursiva_, listas con `-`.
```

Las rarezas también se pueden escribir en español: `común`, `rara`, `épica`,
`legendaria`, `mítica`.

## `layout.json`

```json
{
  "version": 1,
  "board": { "theme": "nebulosa" },
  "cards": {
    "marie-curie": { "x": -420, "y": -160, "scale": 1.35, "rotation": -0.05, "z": 8 }
  }
}
```

- `x`, `y`: centro de la carta en el tablero (una carta mide 240 × 320 a escala 1).
- `scale`: tamaño (1 = normal). `rotation`: en radianes. `z`: la mayor queda arriba.
- Si una carta no figura acá, la app le busca un lugar libre y lo guarda.

## Marcos (12)

| `frame` | Nombre |
|---|---|
| `clasico` | Clásico |
| `oro` | Oro Imperial |
| `plata` | Plata Lunar |
| `obsidiana` | Obsidiana |
| `pergamino` | Pergamino Antiguo |
| `neon` | Neón |
| `holografico` | Holográfico |
| `carmesi` | Carmesí Real |
| `esmeralda` | Esmeralda |
| `cosmico` | Cósmico |
| `hielo` | Cristal de Hielo |
| `fuego` | Fuego Eterno |

## Fuentes (21)

| `font` | Nombre |
|---|---|
| `Cinzel` | Cinzel |
| `CinzelDecorative` | Cinzel Decorative |
| `UncialAntiqua` | Uncial Antiqua |
| `MedievalSharp` | Medieval Sharp |
| `PirataOne` | Pirata One |
| `UnifrakturMaguntia` | Fraktur |
| `GrenzeGotisch` | Grenze Gotisch |
| `Metamorphous` | Metamorphous |
| `AlmendraDisplay` | Almendra |
| `NewRocker` | New Rocker |
| `MetalMania` | Metal Mania |
| `Orbitron` | Orbitron |
| `Audiowide` | Audiowide |
| `Bungee` | Bungee |
| `BlackOpsOne` | Black Ops |
| `BebasNeue` | Bebas Neue |
| `Monoton` | Monoton |
| `PressStart2P` | Press Start 2P |
| `GreatVibes` | Great Vibes |
| `Rye` | Rye (western) |
| `MarcellusSC` | Marcellus |

## Fondos del tablero (20)

| `theme` | Nombre | Descripción |
|---|---|---|
| `nebulosa` | Nebulosa | Nubes de gas estelar y estrellas en tres capas de profundidad. |
| `galaxia` | Galaxia Espiral | Una galaxia girando lentamente detrás de tu colección. |
| `terciopelo` | Terciopelo Carmesí | Terciopelo rojo profundo, como un estuche de joyería. |
| `corcho` | Tablero de Corcho | Corcho cálido, como un tablero donde clavás tus tesoros. |
| `album` | Álbum Filatélico | Hojas de álbum antiguo con cuadrícula y bandas de sujeción. |
| `pergamino` | Mapa de Pergamino | Pergamino envejecido con rosa de los vientos y rutas. |
| `marmol` | Mármol Negro | Mármol negro con vetas de oro. |
| `aurora` | Aurora Boreal | Cortinas de luz verde y violeta sobre montañas nevadas. |
| `oceano` | Océano Profundo | Luz filtrándose en el fondo del mar, con burbujas. |
| `brasas` | Brasas | Chispas que suben desde un fuego invisible. |
| `synthwave` | Synthwave | Atardecer retro de los 80 con grilla de neón en movimiento. |
| `matrix` | Código | Lluvia de símbolos verdes, estilo terminal. |
| `olimpo` | Olimpo | Cielo dorado entre nubes: el hogar de los dioses. |
| `madera` | Madera Noble | Tablones de madera oscura con veta, como una vitrina. |
| `catedral` | Catedral | Haces de luz sagrada cayendo sobre la penumbra, con polvo flotando. |
| `plano` | Plano Técnico | Papel de plano azul con cuadrícula técnica. |
| `tormenta` | Tormenta | Nubes pesadas, lluvia y relámpagos repentinos. |
| `sakura` | Sakura Nocturno | Pétalos de cerezo cayendo en una noche índigo. |
| `glaciar` | Glaciar | Hielo azul y una nevada suave. |
| `salon` | Salón de la Fama | Focos que barren un salón oscuro con piso dorado. |
