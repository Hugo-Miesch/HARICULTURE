# Hariculture — contrat API de la galerie

L'application Flutter utilise une galerie globale, accessible depuis le menu
principal. Elle doit retourner les photos des serres appartenant à
l'utilisateur authentifié.

## 1. Lister les photos

```http
GET /api/gallery?limit=100
Authorization: Bearer <jwt>
```

Réponse `200` :

```json
{
  "photos": [
    {
      "id": "photo-123",
      "greenhouseId": "greenhouse-456",
      "greenhouseName": "Serre de test",
      "imageUrl": "/api/gallery/photo-123/file",
      "thumbnailUrl": "/api/gallery/photo-123/thumbnail",
      "capturedAt": "2026-07-29T15:30:00.000Z",
      "caption": "Capture automatique",
      "width": 1920,
      "height": 1080
    }
  ],
  "nextCursor": null
}
```

Champs obligatoires pour l'application :

- `id`
- `greenhouseId`
- `greenhouseName`
- `imageUrl`
- `capturedAt`

`thumbnailUrl` est optionnel : si absent, l'application utilise `imageUrl`.
Les URL peuvent être relatives ou absolues.

La route doit uniquement retourner les photos de serres dont le JWT courant
est propriétaire. `limit` doit être borné côté API, par exemple entre 1 et
200. Une pagination par `cursor` peut être ajoutée plus tard avec
`nextCursor`.

## 2. Servir une photo

```http
GET /api/gallery/:photoId/file
Authorization: Bearer <jwt>
```

Réponse :

- `200`
- `Content-Type: image/jpeg` ou `image/webp`
- contenu binaire de l'image
- `Cache-Control: private, max-age=300`

L'API doit vérifier que la photo appartient à une serre de l'utilisateur.

## 3. Servir une miniature

```http
GET /api/gallery/:photoId/thumbnail
Authorization: Bearer <jwt>
```

Même contrôle d'accès que pour l'image originale. Une largeur de 400 à
600 pixels est suffisante pour la grille mobile.

## 4. Stockage recommandé

Éviter de renvoyer les images en base64 dans `GET /api/gallery`. MongoDB peut
conserver les métadonnées et un identifiant GridFS, ou une clé vers un stockage
de fichiers. Les routes `file` et `thumbnail` se chargent ensuite de diffuser
le binaire.

## 5. Erreurs attendues

- `401` : JWT absent ou invalide
- `403` : photo hors du périmètre de l'utilisateur
- `404` : photo inconnue
- `500` : erreur de lecture du stockage

Tant que `GET /api/gallery` n'existe pas, l'application affiche un état
« Galerie indisponible » avec une action pour réessayer.
