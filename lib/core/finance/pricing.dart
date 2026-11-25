import 'errors.dart';
import 'money.dart';

enum MarkupType { percentage, fixed, manualFinalPrice }

class PricingResult {
  final int cashPrice;
  final int markupAmount;
  final int finalPrice;
  final int downPayment;
  final int financedAmount;
  const PricingResult(this.cashPrice, this.markupAmount, this.finalPrice,
      this.downPayment, this.financedAmount);
}

class PricingCalculator {
  /// [markupValue] meaning depends on [type]:
  ///  - percentage: basis points (20% = 2000)
  ///  - fixed: piastres
  ///  - manualFinalPrice: the agreed final price in piastres
  static PricingResult calculate({
    required int cashPrice,
    required MarkupType type,
    required int markupValue,
    int downPayment = 0,
  }) {
    if (cashPrice <= 0) throw PricingException('Cash price must be > 0');
    if (markupValue < 0) throw PricingException('Markup must be >= 0');
    if (downPayment < 0) throw PricingException('Down payment must be >= 0');

    final int finalPrice;
    switch (type) {
      case MarkupType.percentage:
        finalPrice = cashPrice + Money.roundDiv(cashPrice * markupValue, 10000);
      case MarkupType.fixed:
        finalPrice = cashPrice + markupValue;
      case MarkupType.manualFinalPrice:
        finalPrice = markupValue;
        if (finalPrice < cashPrice) {
          throw PricingException('Final price cannot be below cash price');
        }
    }
    if (downPayment > finalPrice) {
      throw PricingException('Down payment exceeds final price');
    }
    return PricingResult(cashPrice, finalPrice - cashPrice, finalPrice,
        downPayment, finalPrice - downPayment);
  }
}
