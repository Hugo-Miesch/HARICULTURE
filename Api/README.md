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
- flux MJPEG authentifié produit directement par `rpicam-vid` ;
- galerie privée avec miniature et capture automatique chaque jour à minuit ;
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

Le MongoDB Docker du projet écoute sur le port hôte `27018` afin de ne pas entrer en
conflit avec une installation MongoDB existante sur `27017`.

Pour la production, changez impérativement `JWT_SECRET` et le code d'association dans
`.env`. Le code `0000` est uniquement destiné au développement.

Le healthcheck exécute un vrai `ping` MongoDB et renvoie `503` si la base est
inaccessible ou refuse l'authentification. Les variables `AUTH_RATE_LIMIT`,
`PAIRING_RATE_LIMIT` et `RATE_LIMIT_WINDOW_MS` protègent les routes sensibles.
`GREENHOUSE_OFFLINE_AFTER_MS` définit le délai après lequel une serre sans heartbeat
est affichée hors ligne.

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
| POST | `/api/greenhouses/:id/heartbeat` | Signaler que la serre est en ligne |
| PATCH | `/api/greenhouses/:id/actuators/:actuator` | Piloter `light`, `irrigation` ou `ventilation` |
| POST | `/api/greenhouses/:id/sensors` | Enregistrer un relevé |
| POST | `/api/greenhouses/:id/sensors/collect` | Lire l'adaptateur matériel |
| GET | `/api/greenhouses/:id/sensors` | Historique des mesures |
| GET | `/api/greenhouses/:id/sensors/latest` | Dernière mesure |
| GET/POST | `/api/greenhouses/:id/routines` | Lister/créer les routines |
| PATCH/DELETE | `/api/greenhouses/:id/routines/:routineId` | Modifier/supprimer une routine |
| GET | `/api/greenhouses/:id/camera/status` | État et URL de caméra |
| GET | `/api/greenhouses/:id/camera/stream` | Flux vidéo MJPEG protégé |
| GET | `/api/gallery?limit=100` | Photos des serres de l'utilisateur |
| GET | `/api/gallery/:photoId/file` | Fichier JPEG protégé |
| GET | `/api/gallery/:photoId/thumbnail` | Miniature JPEG protégée |

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

Le mode `HARDWARE_MODE=raspberry` utilise un pont Python persistant basé sur
`libgpiod` et SMBus. Il maintient les sorties, lit les capteurs et remet les trois
actionneurs à l'arrêt au démarrage et à l'arrêt.

| Composant | Interface |
|---|---|
| DHT11 | GPIO24 |
| BH1750 | I²C1 : GPIO2/SDA, GPIO3/SCL, adresse `0x23` |
| Capteur de sol numérique 3 broches | GPIO25 |
| Pompe | GPIO18 |
| Éclairage | GPIO23 |
| Servomoteur SG90 de fenêtre/aération | GPIO12, signal servo 50 Hz |

Le capteur de sol numérique ne mesure pas un pourcentage : son état sec/humide est
converti en `0` ou `100` pour rester compatible avec l'application actuelle. Ajustez
le potentiomètre du module pour définir son seuil.

Les sorties pompe et éclairage sont configurées actives à l'état haut par défaut. Si un relais s'active
quand son GPIO passe à `0`, réglez la variable correspondante à `true` :
`PUMP_ACTIVE_LOW` ou `LIGHT_ACTIVE_LOW`. Vérifiez cette
polarité avant de raccorder une pompe ou un moteur.

Le SG90 utilise `SERVO_CLOSED_PULSE_US=500` et `SERVO_OPEN_PULSE_US=2500`.
La commande d'aération convertit `value` de 0 à 100 entre ces deux positions.
Les impulsions sont coupées après `SERVO_HOLD_SECONDS` pour limiter les tremblements
et l'échauffement. Le SG90 doit être alimenté en 5 V par une alimentation externe
avec masse commune ; seul son fil de signal est relié à GPIO12.

I²C doit être actif :

```bash
sudo raspi-config nonint do_i2c 0
i2cdetect -y 1
```

Le BH1750 doit apparaître à l'adresse `23`.

La caméra Raspberry est lancée à la demande par l'API avec `rpicam-vid`. Pour
l'IMX708 Wide NoIR détectée comme caméra `0`, les valeurs par défaut produisent un flux
MJPEG 1280×720 à 15 images/s. Un seul processus caméra est partagé entre les mobiles et
il est arrêté automatiquement quand le dernier spectateur ferme le direct.

Vérifiez la caméra avant de démarrer l'API :

```bash
rpicam-hello --list-cameras
rpicam-vid --camera 0 --codec mjpeg --width 1280 --height 720 \
  --framerate 15 --timeout 3000 --nopreview --output /tmp/camera-test.mjpeg
```

Les réglages se trouvent dans `.env` : `CAMERA_INDEX`, `CAMERA_WIDTH`,
`CAMERA_HEIGHT`, `CAMERA_FRAMERATE`, `CAMERA_QUALITY`,
`CAMERA_START_TIMEOUT_MS` et `CAMERA_IDLE_STOP_MS`. L'utilisateur qui lance Node doit
avoir accès aux périphériques caméra (`video`/`render` selon le système).

L'application consomme `/api/greenhouses/:id/camera/stream` avec son JWT. Aucun port
caméra supplémentaire ne doit être exposé sur le réseau.

## Galerie et captures automatiques

Les métadonnées des photos sont conservées dans MongoDB et les fichiers JPEG dans
`GALLERY_DIRECTORY` (`./data/gallery` par défaut). Ce dossier doit être inclus dans
les sauvegardes du Raspberry ; il est volontairement ignoré par Git. Les miniatures
ont une largeur maximale de `GALLERY_THUMBNAIL_WIDTH` (500 px par défaut).

À chaque minuit selon le fuseau horaire du Raspberry, l'API prend automatiquement une
photo pour chaque serre associée dont la caméra est activée. Elle partage le même
processus caméra que le direct afin d'éviter deux accès concurrents à la caméra.

Exemple :

```bash
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/gallery?limit=100"
```

Les URL `imageUrl` et `thumbnailUrl` retournées sont relatives à l'API et nécessitent
le même JWT. La liste est bornée entre 1 et 200 éléments et ne renvoie jamais les
photos d'une serre appartenant à un autre utilisateur.

> Une pompe, un moteur ou des LED puissantes ne doivent jamais être alimentés
> directement par une broche GPIO. Utilisez relais/MOSFET, alimentation adaptée,
> diode de roue libre pour les charges inductives et fins de course pour la fenêtre.

## Tests

```bash
npm test
```

Les tests téléchargent puis démarrent une instance MongoDB temporaire. Ils vérifient la
connexion à la base, l'authentification, l'association, les trois actionneurs, les
capteurs, les validations, la galerie privée et le cycle de vie des routines.

## Démarrage automatique sur le Raspberry

```bash
sudo cp deploy/hariculture-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now hariculture-api
systemctl status hariculture-api
```

Les journaux sont disponibles avec :

```bash
journalctl -u hariculture-api -f
```

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
