# Hariculture — passation technique API et intégration Raspberry

> Document destiné à la personne qui reprend l’API avec son propre assistant.
>
> État constaté le 28 juillet 2026. Ce document décrit l’existant, les contrats
> consommés par Flutter et les travaux restant à réaliser. Aucun changement de
> code API n’a été effectué pendant l’audit.

## 1. Objectif du projet

Hariculture est une application mobile de supervision et de pilotage d’une serre
connectée.

Le projet comporte actuellement deux parties :

- `Api/` : API Node.js/Express, MongoDB, authentification JWT, routines et
  abstraction du matériel ;
- `mobile/` : application Flutter Android/iOS, utilisable en mode démonstration
  sans API ou connectée à l’API réelle.

Le Raspberry Pi pilote le matériel de la serre :

- capteur de température ;
- humidité de l’air ;
- humidité du sol ;
- luminosité ;
- éclairage de croissance ;
- pompe d’irrigation ;
- ouverture ou ventilation de la serre ;
- caméra.

Le watchdog de sécurité de l’arrosage sera implémenté dans le code du Raspberry.
Le Raspberry doit donc rester l’autorité finale de sécurité : même si
l’application, l’API ou le réseau tombe, la pompe doit revenir automatiquement
dans un état sûr.

## 2. Architecture cible

```text
Application Flutter
        |
        | HTTPS + JWT
        v
API Node.js / Express
        |
        +------ MongoDB
        |
        +------ Couche matériel / service Raspberry
                        |
                        +-- Capteurs
                        +-- LED
                        +-- Pompe + watchdog
                        +-- Ventilation
                        +-- Caméra MJPEG
```

À court terme, l’API peut tourner directement sur le Raspberry ou communiquer
avec un service matériel local. Le choix doit rester caché derrière
`Api/src/services/hardware.js`.

## 3. Technologies et versions constatées

### API

- Node.js 20 minimum déclaré ;
- Node.js 24.18.0 utilisé pendant l’audit ;
- Express 5 ;
- MongoDB 7 ;
- Mongoose 8 ;
- Zod 4 ;
- JWT ;
- Vitest et Supertest ;
- `mongodb-memory-server` pour les tests.

### Mobile

- Flutter ;
- Forui pour le système visuel ;
- `http` pour les requêtes ;
- `shared_preferences` pour les données locales ;
- Android et iOS configurés.

## 4. Arborescence utile

```text
Api/
  src/
    app.js
    server.js
    config/
      env.js
      database.js
    middleware/
      auth.js
      errorHandler.js
      validate.js
    models/
      User.js
      Greenhouse.js
      SensorReading.js
      Routine.js
    routes/
      auth.routes.js
      greenhouse.routes.js
      sensor.routes.js
      routine.routes.js
      camera.routes.js
      health.routes.js
    services/
      greenhouseAccess.js
      hardware.js
      routineScheduler.js
    scripts/
      seed.js
  tests/
    api.test.js
  docker-compose.yml
  package.json

mobile/
  lib/
    main.dart
    api_client.dart
    mock_api_client.dart
    models.dart
    serial_number_input.dart
    greenhouse_list_screen.dart
    home_screen.dart
```

## 5. État actuel vérifié

### Tests API

La commande suivante passe :

```bash
cd Api
npm test
```

Résultat constaté :

- 1 fichier de tests ;
- 7 tests d’intégration réussis ;
- authentification, association, commandes, capteurs et routines couverts.

### Dépendances

L’audit des dépendances de production ne remonte aucune vulnérabilité :

```bash
npm audit --omit=dev
```

Deux alertes concernent actuellement Vite/esbuild dans l’outillage de
développement et de test. Elles peuvent être corrigées séparément en mettant à
jour la chaîne Vitest/Vite.

### Démarrage réel et problème MongoDB

Le serveur Node démarre et annonce :

```text
API Hariculture disponible sur http://localhost:3000
```

`GET /api/health` répondait `200`, mais une vraie requête MongoDB renvoyait :

```text
Command find requires authentication
```

Cause constatée sur la machine auditée :

- un autre conteneur MongoDB occupait déjà le port `27017` ;
- ce MongoDB exige une authentification ;
- `MONGODB_URI` pointait vers `127.0.0.1:27017/hariculture` sans identifiants ;
- le conteneur MongoDB du projet ne pouvait pas démarrer à cause du conflit de
  port.

Le code API est donc testable et ses tests passent, mais l’environnement local
réel doit être corrigé avant un parcours complet depuis Flutter.

### Faux positif du healthcheck

Le healthcheck teste uniquement `mongoose.connection.readyState`.

Une connexion TCP peut être ouverte alors que la base refuse toutes les
requêtes. Le healthcheck doit effectuer une vraie opération MongoDB, par
exemple :

```js
await mongoose.connection.db.admin().ping();
```

Il doit répondre `503` si le ping ou l’authentification échoue.

## 6. Configuration attendue

Le dépôt référence un fichier `.env.example`, mais celui-ci apparaît supprimé
dans l’état Git actuel. Il faut le restaurer sans y placer de secret réel.

Variables utilisées par `Api/src/config/env.js` :

```dotenv
NODE_ENV=development
PORT=3000
MONGODB_URI=mongodb://127.0.0.1:27017/hariculture
JWT_SECRET=change-me-with-at-least-32-characters
JWT_EXPIRES_IN=7d
CORS_ORIGIN=*
DEFAULT_GREENHOUSE_CODE=0000
CAMERA_STREAM_URL=http://127.0.0.1:8080/stream
HARDWARE_MODE=mock
```

En production :

- utiliser une URI MongoDB authentifiée ;
- utiliser un vrai secret JWT long et aléatoire ;
- limiter `CORS_ORIGIN` si une interface web est ajoutée ;
- ne pas conserver `0000` comme code générique ;
- utiliser HTTPS ;
- documenter les broches, niveaux actifs et limites du matériel.

## 7. Lancement local recommandé

### API

```bash
cd Api
npm ci
docker compose up -d mongodb
npm run seed
npm run dev
```

Avant de lancer Docker, vérifier que le port `27017` est disponible.

Autres solutions possibles :

- utiliser un port hôte différent, par exemple `27018:27017`, puis adapter
  `MONGODB_URI` ;
- utiliser le MongoDB déjà installé avec ses bons identifiants ;
- utiliser un nom d’hôte Docker interne si l’API est également conteneurisée.

### Flutter avec l’API réelle

Depuis un émulateur Android, `10.0.2.2` désigne le Mac hôte :

```bash
cd mobile
flutter run \
  --dart-define=USE_MOCK_DATA=false \
  --dart-define=API_URL=http://10.0.2.2:3000/api
```

Sans `USE_MOCK_DATA=false`, l’application utilise le client mock local.

## 8. Contrat d’erreur attendu par Flutter

Flutter sait maintenant lire le format actuel de l’API :

```json
{
  "error": {
    "message": "Authentification requise"
  }
}
```

Le statut HTTP est également conservé dans `ApiException.statusCode`.

Conserver ce contrat pour toutes les erreurs :

```json
{
  "error": {
    "message": "Message destiné à l’utilisateur",
    "details": {}
  }
}
```

Pour les erreurs `500`, ne pas renvoyer directement le message MongoDB ou la
stack au client en production. Journaliser le détail côté serveur et répondre
avec un message générique.

Codes recommandés :

- `400` : validation incorrecte ;
- `401` : jeton absent, invalide ou expiré ;
- `403` : action interdite ;
- `404` : ressource ou SN introuvable ;
- `409` : conflit ou ressource déjà associée ;
- `429` : trop de tentatives ;
- `502` : service Raspberry ou caméra indisponible ;
- `503` : matériel, caméra ou base temporairement indisponible.

## 9. Authentification et compte

### Routes existantes

```text
POST /api/auth/register
POST /api/auth/login
GET  /api/auth/me
```

Inscription :

```json
{
  "name": "Alice Martin",
  "email": "alice@example.com",
  "password": "motdepasse123"
}
```

Réponse attendue :

```json
{
  "token": "jwt",
  "user": {
    "_id": "id",
    "name": "Alice Martin",
    "email": "alice@example.com"
  }
}
```

Flutter :

- enregistre le JWT localement sous la clé `auth_token` ;
- l’envoie avec `Authorization: Bearer <token>` ;
- appelle `/auth/me` pour la page Compte ;
- supprime la session locale sur un `401`.

### Travaux restant côté API

- ajouter un rate limiting sur inscription et connexion ;
- décider s’il faut un système de refresh token ;
- prévoir la révocation de sessions si nécessaire ;
- ajouter la modification ou suppression du compte uniquement si elle devient
  une fonctionnalité produit ;
- ajouter des tests explicites sur `/auth/me`, les JWT expirés et les erreurs.

## 10. Association d’une serre par SN

### Comportement produit

- le SN contient exactement quatre caractères ;
- caractères autorisés dans Flutter : `A-Z` et `0-9` ;
- Flutter convertit automatiquement les lettres en majuscules ;
- exemples de formats : `0000`, `A12B`, `7K2P` ;
- en démonstration, seul `0000` existe ;
- tout autre SN doit renvoyer une erreur de création « SN inexistant ».

### Route existante

```text
POST /api/greenhouses/pair
```

Corps :

```json
{
  "code": "A12B",
  "name": "Ma serre"
}
```

Réponse :

```json
{
  "greenhouse": {
    "_id": "id",
    "name": "Ma serre",
    "online": true,
    "location": null,
    "actuators": {
      "light": { "state": false, "value": 0 },
      "irrigation": { "state": false, "value": 0 },
      "ventilation": { "state": false, "value": 0 }
    }
  }
}
```

### Adaptation API à faire

L’API valide actuellement seulement une longueur de quatre caractères. Elle
doit aussi normaliser et valider le format :

```js
z.string()
  .trim()
  .transform((value) => value.toUpperCase())
  .pipe(z.string().regex(/^[A-Z0-9]{4}$/))
```

Points à décider :

- comment les vrais SN sont provisionnés dans MongoDB ;
- si un SN est un code permanent ou un code d’association temporaire ;
- si une serre peut avoir plusieurs propriétaires ;
- comment transférer ou révoquer l’accès ;
- comment empêcher le brute force d’un espace de codes court.

Minimum sécurité :

- rate limiting par IP et par utilisateur ;
- délai progressif après plusieurs échecs ;
- journalisation des associations ;
- ne jamais exposer `pairingCode` dans une réponse JSON ;
- index unique conservé en base.

## 11. Modèle de serre consommé par Flutter

Flutter attend au minimum :

```json
{
  "_id": "greenhouse-id",
  "name": "Serre principale",
  "location": "Jardin nord",
  "online": true,
  "actuators": {
    "light": {
      "state": true,
      "value": 72,
      "updatedAt": "2026-07-28T10:00:00.000Z"
    },
    "irrigation": {
      "state": false,
      "value": 0,
      "updatedAt": "2026-07-28T10:00:00.000Z"
    },
    "ventilation": {
      "state": true,
      "value": 40,
      "updatedAt": "2026-07-28T10:00:00.000Z"
    }
  }
}
```

Routes existantes :

```text
GET /api/greenhouses
GET /api/greenhouses/:id
```

Flutter recharge maintenant le détail complet de la serre lors d’un refresh,
et pas uniquement les mesures.

## 12. Nom, pictogramme et thème

Ces éléments sont volontairement locaux dans l’application :

- nom d’affichage personnalisé ;
- pictogramme de plante ;
- thème clair ou sombre ;
- délai d’alerte d’arrosage.

Ils sont stockés avec `shared_preferences`.

Il n’est pas nécessaire d’ajouter des routes API pour ces données dans la
version actuelle.

Une synchronisation serveur ne devient utile que si les réglages doivent être
partagés entre plusieurs téléphones. Dans ce cas, ajouter plus tard :

```text
PATCH /api/greenhouses/:id/preferences
```

ou étendre proprement le modèle de serre, sans casser les champs existants.

## 13. Capteurs

### Champs consommés

```json
{
  "temperature": 23.4,
  "airHumidity": 63,
  "soilHumidity": 48,
  "lightLevel": 750,
  "measuredAt": "2026-07-28T10:00:00.000Z"
}
```

Routes existantes :

```text
POST /api/greenhouses/:id/sensors
POST /api/greenhouses/:id/sensors/collect
GET  /api/greenhouses/:id/sensors
GET  /api/greenhouses/:id/sensors/latest
```

Flutter utilise :

- la dernière mesure pour les compteurs ;
- les 30 dernières mesures pour l’historique.

Plages affichées actuellement dans Flutter :

| Mesure | Plage totale | Zone idéale affichée |
|---|---:|---:|
| Température | 5 à 40 °C | 18 à 26 °C |
| Humidité air | 20 à 100 % | 55 à 75 % |
| Humidité sol | 0 à 100 % | 45 à 65 % |
| Luminosité | 0 à 1500 lx | 500 à 1000 lx |

Ces plages sont actuellement des constantes UI et ne nécessitent pas de route
API.

### Travaux restant

- brancher les vrais capteurs dans l’adaptateur Raspberry ;
- définir la fréquence de collecte ;
- gérer les mesures absentes ou invalides ;
- déterminer la stratégie de rétention MongoDB ;
- éventuellement créer un index TTL ou une agrégation pour les longues
  périodes ;
- ajouter un heartbeat permettant de calculer correctement `online` et
  `lastSeenAt`.

## 14. Commandes des actionneurs

Actionneurs connus :

```text
light
irrigation
ventilation
```

Route existante :

```text
PATCH /api/greenhouses/:id/actuators/:actuator
```

Corps :

```json
{
  "state": true,
  "value": 100
}
```

Réponse consommée par Flutter :

```json
{
  "actuator": {
    "state": true,
    "value": 100,
    "updatedAt": "2026-07-28T10:00:00.000Z"
  },
  "hardware": {}
}
```

### Couche matériel actuelle

`MockHardwareAdapter` fonctionne.

`RaspberryPiAdapter` n’est pas implémenté et lève actuellement une erreur en
mode `HARDWARE_MODE=raspberry`.

La personne qui reprend l’API doit définir avec la personne qui développe le
Raspberry :

- protocole d’appel local, GPIO direct, socket, HTTP ou message broker ;
- format de commande ;
- accusé de réception ;
- timeout ;
- remontée de l’état réellement appliqué ;
- comportement si le Raspberry est hors ligne ;
- idempotence des commandes ;
- réconciliation entre l’état MongoDB et l’état physique.

Ne pas enregistrer `state: true` dans MongoDB comme si la commande avait réussi
si le Raspberry a refusé ou n’a pas confirmé la commande.

## 15. Sécurité d’arrosage et watchdog Raspberry

### Comportement Flutter actuel

Quand l’utilisateur active l’arrosage :

1. Flutter envoie `irrigation = true` à l’API ;
2. Flutter attend un délai configurable ;
3. délais proposés : 10 s, 30 s, 1 min, 2 min, 5 min et 10 min ;
4. une fenêtre demande si l’utilisateur souhaite continuer ;
5. cette fenêtre possède un compte à rebours supplémentaire de 10 secondes ;
6. sans réponse, Flutter envoie `irrigation = false` ;
7. si l’utilisateur continue, un nouveau cycle est programmé.

Ce mécanisme est une protection UX, mais il ne doit pas être considéré comme
la sécurité physique.

### Responsabilité confirmée du Raspberry

Le watchdog sera dans le code du Raspberry.

Il doit :

- couper physiquement la pompe après une durée maximale ;
- rester fonctionnel sans Internet, API ou application ;
- démarrer avec la pompe coupée ;
- remettre la pompe à l’arrêt après crash ou redémarrage ;
- ignorer une commande trop ancienne ;
- disposer d’une limite maximale non contournable ;
- journaliser ou remonter la raison d’un arrêt watchdog.

### Contrat recommandé entre API et Raspberry

Le contrat actuel `state/value` est insuffisant pour réarmer proprement un
watchdog.

Proposition :

```json
{
  "actuator": "irrigation",
  "state": true,
  "value": 100,
  "commandId": "uuid",
  "issuedAt": "2026-07-28T10:00:00.000Z",
  "leaseSeconds": 40
}
```

Accusé de réception Raspberry :

```json
{
  "commandId": "uuid",
  "accepted": true,
  "state": true,
  "watchdogDeadline": "2026-07-28T10:00:40.000Z",
  "appliedAt": "2026-07-28T10:00:00.150Z"
}
```

Recommandations :

- l’API génère un `commandId` ;
- le Raspberry déduplique les commandes ;
- une prolongation d’arrosage renouvelle la lease ;
- un ordre `false` coupe immédiatement la pompe ;
- l’API expose l’état confirmé et la deadline à Flutter ;
- après reconnexion, l’API demande l’état réel au Raspberry ;
- MongoDB ne doit pas être la source de vérité de l’état électrique.

La valeur exacte de `leaseSeconds` doit être décidée avec l’équipe Raspberry.
Elle peut être plus longue que le délai d’alerte Flutter, mais elle doit rester
bornée par une limite matérielle stricte.

### Route API envisageable

Le contrat mobile actuel peut rester compatible en ajoutant un champ optionnel :

```json
{
  "state": true,
  "value": 100,
  "leaseSeconds": 40
}
```

Une route explicite de renouvellement est aussi possible :

```text
POST /api/greenhouses/:id/actuators/irrigation/renew
```

Ne pas implémenter cette décision sans valider le protocole avec le code
Raspberry.

## 16. Automatisations

Routes existantes :

```text
GET    /api/greenhouses/:id/routines
POST   /api/greenhouses/:id/routines
PATCH  /api/greenhouses/:id/routines/:routineId
DELETE /api/greenhouses/:id/routines/:routineId
```

Format :

```json
{
  "name": "Arrosage du matin",
  "actuator": "irrigation",
  "enabled": true,
  "time": "07:30",
  "days": [1, 2, 3, 4, 5],
  "durationSeconds": 120,
  "value": 100
}
```

Convention des jours :

- `0` : dimanche ;
- `1` : lundi ;
- ...
- `6` : samedi.

### Limites actuelles

Le scheduler :

- tourne dans le processus Node ;
- vérifie les routines toutes les 30 secondes ;
- utilise `setTimeout` pour arrêter les actionneurs ;
- perd les timers en mémoire lors d’un redémarrage ;
- utilise le fuseau horaire du serveur ;
- ne réconcilie pas systématiquement l’état matériel au redémarrage.

### Travaux restant

- ajouter un fuseau horaire IANA par serre, par exemple `Europe/Paris` ;
- rendre les exécutions idempotentes ;
- enregistrer les exécutions et arrêts planifiés ;
- restaurer ou réconcilier les commandes après redémarrage ;
- laisser le watchdog Raspberry imposer la limite physique ;
- éviter qu’une routine et une commande manuelle se contredisent ;
- tester les changements d’heure et les redémarrages.

## 17. Caméra

Routes existantes :

```text
GET /api/greenhouses/:id/camera/status
GET /api/greenhouses/:id/camera/stream
```

Réponse du statut :

```json
{
  "camera": {
    "enabled": true,
    "streamUrl": "/api/greenhouses/id/camera/stream"
  }
}
```

Le flux est prévu en MJPEG protégé par JWT.

### Besoin produit

Le flux ne doit pas consommer de bande passante tant que l’utilisateur n’a pas
appuyé sur « Ouvrir le direct ».

### État Flutter

L’encart et l’interaction existent, mais l’image « direct » est encore une
simulation locale. Flutter n’utilise pas encore le flux MJPEG réel.

### Travaux restant côté API

- vérifier `CAMERA_STREAM_URL` avec la vraie caméra ;
- ne contacter le flux amont qu’à l’ouverture du direct ;
- interrompre le fetch et la lecture amont dès que le client mobile se
  déconnecte ;
- poser un timeout de connexion ;
- limiter le nombre de spectateurs si nécessaire ;
- retourner clairement `502` si le flux amont est indisponible ;
- retourner `503` si la caméra est désactivée ;
- ajouter des tests sur le statut, les droits d’accès et les erreurs du flux.

Ensuite seulement, Flutter pourra intégrer un lecteur MJPEG acceptant les
headers `Authorization`.

## 18. Notifications

L’icône de cloche de la page des serres est actuellement décorative.

La section Notifications a été retirée de la page Compte parce qu’aucune
fonctionnalité n’existait derrière.

Si des notifications sont ajoutées plus tard, il faudra décider :

- seuils de température ou d’humidité ;
- serre hors ligne ;
- watchdog déclenché ;
- caméra ou capteur indisponible ;
- échec d’une automatisation ;
- notifications locales ou push ;
- FCM pour Android et APNs pour iOS ;
- stockage et acquittement des alertes.

Ce n’est pas bloquant pour la version actuelle.

## 19. Fonctionnalités volontairement hors API

Ne pas développer ces éléments côté API pour l’instant :

- thème clair/sombre ;
- nom local personnalisé ;
- emoji ou pictogramme de plante ;
- délai d’alerte Flutter ;
- suppression des préférences locales ;
- images des cartes de serre ;
- plages graphiques des compteurs ;
- section Défis, actuellement masquée mais conservée dans le code Flutter.

## 20. Routes manquantes possibles, non prioritaires

À ajouter seulement si le produit les demande :

```text
PATCH  /api/users/me
DELETE /api/users/me
PATCH  /api/greenhouses/:id
DELETE /api/greenhouses/:id/owners/me
GET    /api/greenhouses/:id/events
GET    /api/greenhouses/:id/actuators/status
```

La désassociation d’une serre sera probablement utile avant une mise en
production.

## 21. Travaux API classés par priorité

### P0 — nécessaire pour une API réellement utilisable

- [ ] Restaurer `.env.example` sans secrets.
- [ ] Corriger la connexion MongoDB locale.
- [ ] Remplacer le healthcheck `readyState` par un vrai ping.
- [ ] Masquer les erreurs internes sur les réponses `500`.
- [ ] Normaliser et valider les SN avec `^[A-Z0-9]{4}$`.
- [ ] Ajouter un rate limiting sur auth et association.
- [ ] Définir le contrat API ↔ Raspberry.
- [ ] Implémenter ou brancher `RaspberryPiAdapter`.
- [ ] Ne sauvegarder que les états confirmés par le matériel.
- [ ] Définir le protocole de lease/renouvellement du watchdog.

### P1 — nécessaire avant des tests terrain sérieux

- [ ] Ajouter heartbeat, `lastSeenAt` et état `online` fiable.
- [ ] Réconcilier MongoDB avec l’état physique après reconnexion.
- [ ] Rendre le scheduler résistant aux redémarrages.
- [ ] Ajouter le fuseau horaire par serre.
- [ ] Valider le vrai flux caméra.
- [ ] Couper le flux amont à la déconnexion du client.
- [ ] Ajouter désassociation et gestion propre des propriétaires.
- [ ] Étendre les tests d’intégration.

### P2 — produit et exploitation

- [ ] Refresh token ou stratégie de renouvellement JWT.
- [ ] Journal d’événements et d’actions.
- [ ] Notifications.
- [ ] Rétention et agrégation des mesures.
- [ ] Observabilité, logs structurés et métriques.
- [ ] HTTPS, reverse proxy et déploiement.
- [ ] Sauvegardes MongoDB.

## 22. Tests API à ajouter

- [ ] `/auth/me`.
- [ ] JWT expiré.
- [ ] SN avec lettres minuscules normalisées.
- [ ] SN contenant un caractère interdit.
- [ ] SN inexistant.
- [ ] trop de tentatives d’association.
- [ ] association déjà existante.
- [ ] accès d’un autre propriétaire.
- [ ] Raspberry indisponible.
- [ ] commande refusée ou expirée.
- [ ] état non sauvegardé si le matériel refuse.
- [ ] expiration watchdog et réconciliation.
- [ ] conflits routine/commande manuelle.
- [ ] redémarrage pendant une routine.
- [ ] timezone et changement d’heure.
- [ ] caméra désactivée.
- [ ] caméra amont indisponible.
- [ ] fermeture du flux par le client.
- [ ] healthcheck avec MongoDB non authentifié.

## 23. Critères de validation de bout en bout

### Parcours minimum

1. démarrer MongoDB et l’API sans erreur ;
2. obtenir un vrai `200` sur `/api/health` ;
3. créer un compte ;
4. se connecter ;
5. associer la serre avec `0000` en développement ;
6. refuser proprement `AB12` s’il n’existe pas ;
7. afficher le profil `/auth/me` ;
8. récupérer la liste des serres ;
9. afficher les quatre mesures ;
10. allumer et éteindre les trois actionneurs ;
11. confirmer que l’état vient du Raspberry ;
12. activer l’arrosage puis vérifier la coupure watchdog ;
13. créer, désactiver et supprimer une routine ;
14. ouvrir puis fermer le flux caméra ;
15. vérifier qu’aucun flux amont ne reste ouvert ;
16. lancer Flutter avec `USE_MOCK_DATA=false`.

### Validation sécurité arrosage

Tester obligatoirement :

- téléphone fermé pendant l’arrosage ;
- API arrêtée pendant l’arrosage ;
- réseau coupé ;
- Raspberry redémarré ;
- commande de renouvellement dupliquée ;
- commande ancienne rejouée ;
- arrêt manuel pendant une routine ;
- expiration de la lease ;
- état final physique et état API cohérents.

## 24. Commandes de contrôle

```bash
# API
cd Api
npm ci
npm test
npm audit --omit=dev

# MongoDB du projet
docker compose up -d mongodb
docker compose ps

# API en développement
npm run dev

# Healthcheck
curl http://localhost:3000/api/health

# Flutter
cd ../mobile
flutter analyze
flutter test
flutter run \
  --dart-define=USE_MOCK_DATA=false \
  --dart-define=API_URL=http://10.0.2.2:3000/api
```

## 25. Consignes pour la reprise avec un autre assistant

Mission proposée :

1. travailler uniquement dans `Api/` pour la première passe ;
2. ne pas modifier les contrats JSON consommés par Flutter sans coordination ;
3. traiter les tâches P0 dans l’ordre ;
4. ajouter un test pour chaque correction ;
5. ne pas inventer les broches ou le protocole Raspberry ;
6. valider le contrat watchdog avec la personne responsable du Raspberry ;
7. conserver le mode matériel mock pour le développement ;
8. tester aussi avec `USE_MOCK_DATA=false` côté Flutter ;
9. documenter toute nouvelle variable d’environnement ;
10. ne jamais committer de secret.

Le premier objectif concret doit être :

> Obtenir un démarrage reproductible de MongoDB + API, un healthcheck fiable,
> puis un parcours réel inscription → association → mesures → commandes, tout
> en conservant les 7 tests existants et en ajoutant les tests manquants.
