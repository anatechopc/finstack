enum ErrorCodes {
  notFound(404),
  serverError(500),
  badRequest(401);

  const ErrorCodes(this.value);
  final num value;
}
