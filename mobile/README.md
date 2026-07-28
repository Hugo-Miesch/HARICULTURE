# Hariculture mobile

Application Flutter de la serre connectée Hariculture. Elle démarre par défaut avec
des données de démonstration locales : aucune API n'est nécessaire.

## Démarrage

1. Installer Flutter 3.24 ou plus récent.
2. Depuis ce dossier, récupérer les dépendances :

   ```bash
   flutter pub get
   ```

3. Lancer la démo Android :

   ```bash
   flutter run
   ```

Le compte de démonstration est prérempli. Les commandes, mesures et routines sont
simulées dans l'application.

Pour reconnecter l'API plus tard :

```bash
flutter run \
  --dart-define=USE_MOCK_DATA=false \
  --dart-define=API_URL=http://10.0.2.2:3000/api
```

`10.0.2.2` cible la machine hôte depuis l'émulateur Android.

Les projets Android/iOS autorisent l'API HTTP locale pour le développement. En
production, utiliser HTTPS et retirer les exceptions de transport non sécurisé.

## Android Studio

1. Ouvrir le dossier `mobile/` dans Android Studio.
2. Vérifier que les extensions **Flutter** et **Dart** sont activées.
3. Ouvrir **Tools > Device Manager**.
4. Démarrer l'appareil **Medium Phone API 36**.
5. Sélectionner cet appareil dans la barre supérieure, puis lancer `lib/main.dart`
   avec le bouton **Run**.

Alternative en terminal :

```bash
flutter emulators --launch Medium_Phone_API_36
flutter run
```
