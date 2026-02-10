class GenerateSOAException implements Exception {

  GenerateSOAException(this.message);
  final String message;

  @override
  String toString() {
    return message;
  }
}
