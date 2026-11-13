# Guía: firmar y generar el APK de release (Santa Ana — app de préstamos)

Guía paso a paso para firmar la app móvil del sistema de préstamos. Se hace **una sola vez**.

> Los comandos son para **PowerShell** (la terminal de VS Code). Los que empiezan con una ruta entre
> comillas llevan `&` adelante: sin él PowerShell da "Token inesperado". En `cmd` se quita el `&`.

---

## ¿Qué es esto y por qué es necesario?

Android **no instala** una app si no está "firmada" digitalmente. La firma es
como la **cédula de identidad de la app**: garantiza que todas las versiones
(la de hoy y las actualizaciones futuras) vienen del mismo autor.

- En **desarrollo**, Flutter usa una firma "debug" automática (por eso
  `flutter run` funciona sin hacer nada). Esa firma es genérica y **no sirve
  para distribuir** la app.
- Para **entregar/publicar** se necesita una firma **propia**: el **keystore**
  (archivo `.jks` protegido con contraseña). En este proyecto es
  **`android/app/santaana-release.jks`**.

### ⚠️ Lo más importante de todo
El **keystore y su contraseña son para siempre**. Cada actualización de la app
DEBE firmarse con el **mismo** keystore. Si se **pierde** el `.jks` (o la contraseña):
- No se pueden instalar **actualizaciones** sobre la app ya instalada en los
  celulares de Santa Ana (Android las rechaza por tener otra firma).
- Habría que desinstalar y volver a instalar en cada celular, o publicar una app nueva.

Por eso: **respalda `santaana-release.jks` y guarda la contraseña y el alias**
en un lugar seguro (gestor de contraseñas, USB, nube privada). No se sube al
repositorio (`*.jks` y `key.properties` ya están en `.gitignore`).

---

## ¿Qué es `key.properties`?

Es un archivo de texto que le dice a Gradle (el compilador de Android)
**dónde está el keystore y cuáles son las contraseñas**, para que firme el APK
automáticamente al compilar, sin poner contraseñas dentro del código.

- El proyecto **ya está configurado** para leerlo:
  `android/app/build.gradle.kts` busca `android/key.properties`. Si existe,
  firma con el keystore de Santa Ana; si no existe, usa la firma debug (para no
  romper `flutter run --release`).
- La plantilla es `android/key.properties.example`.

---

## Paso 1 — Crear el keystore (✅ ya hecho)

Ya existe `android/app/santaana-release.jks`. Solo como referencia, se crea así
(desde `android/app`; `keytool` viene con el JDK de Android Studio, que no está
en el PATH, por eso va con la ruta completa):
```
cd D:\repository\prestamos\prestamos_movil\android\app
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool" -genkeypair -v -keystore santaana-release.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias santaana
```
- En PKCS12 la clave usa **la misma contraseña** del keystore.
- **No lo vuelvas a crear**: un keystore nuevo es otra firma.

### ¿Qué alias usé?
El alias es el "nombre" de la clave dentro del keystore y debe coincidir con
`keyAlias` en `key.properties`. Si no recuerdas cuál pusiste, consúltalo (pide
la contraseña):
```
cd D:\repository\prestamos\prestamos_movil\android\app
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool" -list -keystore santaana-release.jks
```
El alias es la primera palabra de la línea que dice `PrivateKeyEntry`
(por ejemplo `santaana, 29/10/2026, PrivateKeyEntry,`).

---

## Paso 2 — Crear `android/key.properties`

1. Copia la plantilla `android/key.properties.example` a `android/key.properties`
   (en `android/`, **no** dentro de `android/app/`):
   ```
   cd D:\repository\prestamos\prestamos_movil\android
   Copy-Item key.properties.example key.properties
   ```

2. Ábrelo y completa con tus datos reales:
   ```
   storePassword=LA_CONTRASEÑA_DEL_KEYSTORE
   keyPassword=LA_CONTRASEÑA_DEL_KEYSTORE
   keyAlias=santaana
   storeFile=santaana-release.jks
   ```
   - En PKCS12, `keyPassword` y `storePassword` son **la misma**.
   - `keyAlias`: el alias que usaste al crear el keystore (ver arriba).
   - `storeFile=santaana-release.jks` funciona porque el `.jks` está en
     `android/app/`. Si lo mueves, pon la **ruta completa** con `/`, por ejemplo
     `storeFile=C:/Users/Eric/llaves/santaana-release.jks`.
   - Si la contraseña tiene `\` o `:`, antepón otra `\` (formato `.properties`).

3. Guarda. No hace falta volver a tocarlo.

---

## Paso 3 — Compilar el APK firmado

Desde la carpeta del proyecto móvil:
```
cd D:\repository\prestamos\prestamos_movil
flutter build apk --release
```
- El APK sale en `build\app\outputs\flutter-apk\app-release.apk`.
- Ese APK está **firmado con el keystore de Santa Ana** y apunta a **producción**
  (`https://santaana2.sczsoft.net/api/v1`, ver `lib/app/app_config.dart`).
  Es el que se instala en los celulares.
- **No** uses `flutter build apk --debug` para entregar: ese apunta al servidor
  local de tu PC y no lleva la firma de release.

Si en el celular ya estaba instalada una versión firmada con la clave debug
(instalada con `flutter run`), Android no dejará actualizarla con la firmada:
desinstálala primero (solo esa vez).

Para **Play Store** (si se publica más adelante) se usa un App Bundle:
```
flutter build appbundle --release
```
(sale en `build\app\outputs\bundle\release\app-release.aab`).

Antes de cada entrega con cambios, sube la versión en `pubspec.yaml`
(`version: 1.0.1+2` → el número después de `+` debe aumentar siempre).

---

## Cómo saber que quedó bien firmado

Desde la raíz del proyecto móvil (la ruta del APK es relativa a ella). Los APK
actuales usan la firma v2/v3, que `keytool` no lee; se usa `apksigner` del SDK:
```
cd D:\repository\prestamos\prestamos_movil
& "C:\Users\Eric\AppData\Local\Android\Sdk\build-tools\37.0.0\apksigner.bat" verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```
Debe mostrar `Signer #1 certificate DN: CN=<tu nombre>, O=<tu organización>…`
(los datos que pusiste al crear el keystore), **no** `CN=Android Debug`.
Si dice que el archivo no existe, primero compila (Paso 3).

Errores típicos al compilar:
- `Keystore was tampered with, or password was incorrect` → contraseña mal escrita en `key.properties`.
- `No key with alias '...' found` → `keyAlias` no coincide (ver "¿Qué alias usé?").
- `Keystore file ... not found` → `storeFile` mal; el `.jks` debe estar en `android/app/` o con ruta completa.

---

## Resumen de checklist

- [x] Crear `santaana-release.jks` (Paso 1).
- [ ] **Respaldar** `santaana-release.jks` y guardar contraseña y alias.
- [ ] Crear `android/key.properties` desde `key.properties.example` (Paso 2).
- [ ] `flutter build apk --release` (Paso 3) y verificar la firma con `apksigner`.
- [ ] Instalar `app-release.apk` en los celulares.
