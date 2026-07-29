# Hariculture mobile

Application Flutter de la serre connectée Hariculture. Elle utilise directement
l'API réelle configurée dans `lib/main.dart` ou avec `API_URL`.

## Démarrage

1. Installer Flutter 3.24 ou plus récent.
2. Depuis ce dossier, récupérer les dépendances :

   ```bash
   flutter pub get
   ```

3. Lancer l'application Android :

   ```bash
   flutter run
   ```

Pour utiliser une autre adresse d'API :

```bash
flutter run \
  --dart-define=API_URL=http://adresse-api:3000
```

Le client ajoute automatiquement le préfixe `/api` à l'adresse si nécessaire.

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
