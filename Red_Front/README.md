# Red Drones móvil

Proyecto base Flutter para Android y iOS. Las carpetas nativas se generarán con Flutter cuando el SDK esté instalado:

```sh
flutter create --platforms=android,ios .
flutter pub get
flutter run
```

La app se conectará a la API de `Red_Back` mediante HTTPS. No incluyas la URI ni la contraseña de MongoDB en la app. La dirección de la API se configurará cuando se conozca dónde estará publicada.

