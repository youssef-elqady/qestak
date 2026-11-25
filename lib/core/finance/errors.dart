enum PaymentErrorCode {
  nonPositiveAmount,
  foreignContract,
  installmentNotOpen,
  excessWithoutPolicy,
  manualOverAllocated,
  manualInvalidAmount,
  reasonRequired,
  alreadyReversed,
  creditAlreadyConsumed,
}

class PaymentValidationException implements Exception {
  final PaymentErrorCode code;
  final String message;
  PaymentValidationException(this.code, this.message);
  @override
  String toString() => 'PaymentValidationException($code): $message';
}

class PricingException implements Exception {
  final String message;
  PricingException(this.message);
  @override
  String toString() => 'PricingException: $message';
}
