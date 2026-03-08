enum LlmFailureType { network, unauthorized, protocol, emptyResponse, unknown }

class LlmException implements Exception {
  final LlmFailureType type;
  final String message;
  final Object? cause;

  const LlmException({required this.type, required this.message, this.cause});

  @override
  String toString() {
    return 'LlmException(type: $type, message: $message, cause: $cause)';
  }
}
