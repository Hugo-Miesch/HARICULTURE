# API Hariculture

API Node.js/MongoDB pour piloter une serre connectée depuis une application mobile et un
Raspberry Pi 5.

## Fonctionnalités

- création de compte et connexion avec JWT ;
- association d'une serre avec le code de test `0000` ;
- pilotage des LED, de la pompe d'arrosage et de l'ouverture de fenêtre ;
- stockage et consultation de la température, de l'humidité de l'air, de l'humidité du
  sol et de la luminosité ;
- routines hebdomadaires d'éclairage, d'arrosage et d'aération ;
- relais authentifié du flux MJPEG de la caméra ;
- séparation entre la logique métier et l'accès GPIO ;
- tests API exécutés sur une vraie instance MongoDB éphémère.

## Installation

Prérequis : Node.js 20 ou plus récent, puis MongoDB 7 (installé localement ou lancé avec
Docker).

```bash
cp .env.example .env
npm install
docker compose up -d mongodb
npm run seed
npm run dev
```

L'API répond sur `http://adresse-du-raspberry:3000`. Vérification :

```bash
curl http://localhost:3000/api/health
```

Pour la production, changez impérativement `JWT_SECRET` et le code d'association dans
`.env`. Le code `0000` est uniquement destiné au développement.

## Routes principales

Toutes les routes de serre nécessitent l'en-tête
`Authorization: Bearer <token>`.

| Méthode | Route | Usage |
|---|---|---|
| POST | `/api/auth/register` | Créer un compte |
| POST | `/api/auth/login` | Se connecter |
| GET | `/api/auth/me` | Profil connecté |
| POST | `/api/greenhouses/pair` | Associer la serre avec `{ "code": "0000" }` |
| GET | `/api/greenhouses` | Lister les serres |
| GET | `/api/greenhouses/:id` | État d'une serre |
| PATCH | `/api/greenhouses/:id/actuators/:actuator` | Piloter `light`, `irrigation` ou `ventilation` |
| POST | `/api/greenhouses/:id/sensors` | Enregistrer un relevé |
| POST | `/api/greenhouses/:id/sensors/collect` | Lire l'adaptateur matériel |
| GET | `/api/greenhouses/:id/sensors` | Historique des mesures |
| GET | `/api/greenhouses/:id/sensors/latest` | Dernière mesure |
| GET/POST | `/api/greenhouses/:id/routines` | Lister/créer les routines |
| PATCH/DELETE | `/api/greenhouses/:id/routines/:routineId` | Modifier/supprimer une routine |
| GET | `/api/greenhouses/:id/camera/status` | État et URL de caméra |
| GET | `/api/greenhouses/:id/camera/stream` | Flux vidéo MJPEG protégé |

### Exemples de corps JSON

Inscription :

```json
{
  "name": "Alice",
  "email": "alice@example.com",
  "password": "motdepasse123"
}
```

Commande de la pompe (`PATCH .../actuators/irrigation`) :

```json
{ "state": true, "value": 100 }
```

Relevé des capteurs :

```json
{
  "temperature": 23.4,
  "airHumidity": 63,
  "soilHumidity": 48,
  "lightLevel": 750
}
```

Routine (jours : `0` dimanche, `1` lundi, ..., `6` samedi) :

```json
{
  "name": "Arrosage du matin",
  "actuator": "irrigation",
  "time": "07:30",
  "days": [1, 2, 3, 4, 5],
  "durationSeconds": 120,
  "value": 100
}
```

## Raspberry Pi et composants

Par défaut, `HARDWARE_MODE=mock` simule les composants, ce qui permet de développer
l'application mobile immédiatement. Le fichier
`src/services/hardware.js` contient l'interface à relier ensuite aux broches GPIO.
Définissez précisément les broches, les relais actifs à l'état haut/bas et les
références des capteurs avant d'activer `HARDWARE_MODE=raspberry`.

Pour la caméra, installez un serveur MJPEG local (par exemple `ustreamer`) et placez son
URL interne dans `CAMERA_STREAM_URL`. L'application mobile consomme la route protégée
de l'API, pas directement le port de la caméra.

> Une pompe, un moteur ou des LED puissantes ne doivent jamais être alimentés
> directement par une broche GPIO. Utilisez relais/MOSFET, alimentation adaptée,
> diode de roue libre pour les charges inductives et fins de course pour la fenêtre.

## Tests

```bash
npm test
```

Les tests téléchargent puis démarrent une instance MongoDB temporaire. Ils vérifient la
connexion à la base, l'authentification, l'association, les trois actionneurs, les
capteurs, les validations et le cycle de vie des routines.

## Structure

```text
src/
  config/       configuration et connexion MongoDB
  middleware/   authentification, validation, erreurs
  models/       schémas Mongoose
  routes/       contrôleurs HTTP
  services/     matériel, droits d'accès, planificateur
  scripts/      initialisation de la serre de test
tests/          tests d'intégration API + MongoDB
```
