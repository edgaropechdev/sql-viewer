# SQL Viewer

Cliente MySQL nativo para macOS (Apple Silicon). Swift 6 + SwiftUI, con AppKit
para el grid (`NSTableView`) y el editor (`NSTextView`). Driver: `libmysqlclient`
enlazado estáticamente (junto con OpenSSL y zstd): la app no necesita MySQL ni
Homebrew para ejecutarse.

## Requisitos

- macOS 27+, Command Line Tools (no requiere Xcode)
- Solo para compilar: `brew install mysql-client` (solo librería cliente, sin
  servidor; se usan `libmysqlclient.a` y los headers, y trae `openssl@3` y
  `zstd` como dependencias)

## Uso

```sh
scripts/build-app.sh            # build/SQL Viewer.app
scripts/build-app.sh --install  # además copia a ~/Applications
scripts/test.sh                 # tests unitarios
scripts/test.sh --mysql         # + integración contra root@localhost
scripts/make-icon.sh            # regenera Support/AppIcon.icns (tras cambiar el ícono)
```

## Atajos

| | |
|---|---|
| ⌘↩ | Ejecutar selección o sentencia bajo el cursor |
| ⇧⌘↩ | Ejecutar todo |
| ⌘. | Cancelar consulta (`KILL QUERY`) |
| ⌘R | Recargar tabla |
| Doble clic | Editar celda (tablas con PK) · Esc cancela |
| ⌘C | Copiar filas como TSV |
| ⌘T | Nueva sesión (abre la lista de conexiones) |
| ⌘1…⌘9 · ⇧⌘] / ⇧⌘[ | Ir a la sesión N · siguiente / anterior |

## Notas

- Conexiones en `~/Library/Application Support/SQLViewer/connections.json`;
  contraseñas en el llavero. Ejecuta una vez `scripts/create-signing-identity.sh`:
  firma la app con un certificado local estable para que "Permitir siempre" del
  llavero sobreviva a cada recompilación (con firma ad-hoc vuelve a preguntar).
- Las librerías quedan dentro del binario: actualizar o desinstalar `mysql-client`
  con brew no afecta a una app ya compilada. Para tomar parches de seguridad de
  OpenSSL/libmysqlclient hay que recompilar.
