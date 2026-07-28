export function notFound(req, _res, next) {
  const error = new Error(`Route introuvable: ${req.method} ${req.originalUrl}`);
  error.status = 404;
  next(error);
}

export function errorHandler(error, _req, res, _next) {
  let status = error.status || 500;
  let message = error.message || 'Erreur interne du serveur';

  if (error.name === 'CastError') {
    status = 400;
    message = 'Identifiant invalide';
  }
  if (error.code === 11000) {
    status = 409;
    message = 'Cette valeur existe déjà';
  }

  res.status(status).json({
    error: { message, ...(error.details && { details: error.details }) }
  });
}
