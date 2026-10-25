# tk-pdf per Android e iPhone

Lettore ed editor PDF sul telefono: apri, annota a dito, firma, scansiona, unisci, gestisci le pagine,
modifica il testo, comprimi e proteggi con password. Tutte le funzioni sono gratis, per tutti.

- **Piattaforme:** Android (APK) e iPhone. C'è anche per Windows e Mac: [tk-pdf per computer](https://pietrodefilippis.it/software/).
- **Licenza:** software libero sotto [GNU AGPL-3.0](COPYING), fornito così com'è, senza alcuna garanzia.
- **Permesso aggiuntivo per le librerie:** Syncfusion Flutter PDF e Google ML Kit, vedi
  [ECCEZIONE-LICENZA.md](ECCEZIONE-LICENZA.md) (AGPL sez. 7).
- **Privacy:** documenti e dati restano sul telefono. Le statistiche anonime (una volta al giorno: nome, versione,
  sistema e un codice casuale) partono solo se dici sì nel benvenuto o in Informazioni.

## Compilare dal sorgente

Serve [Flutter](https://flutter.dev) (versione indicata in `.github/workflows/android.yml`):

```
flutter pub get
flutter test
flutter build apk --release
```

Senza la variabile `ANDROID_KEYSTORE` l'APK si firma con la chiave di debug di Flutter.

Il nome «tk-pdf» e il logo non sono coperti dalla licenza (AGPL sez. 7): una versione modificata deve avere un
nome diverso.

© 2026 Pietro De Filippis (TecnikGeek) — [pietrodefilippis.it](https://pietrodefilippis.it)
