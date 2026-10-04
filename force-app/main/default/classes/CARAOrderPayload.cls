public class CARAOrderPayload {
    public Decimal adjustedMerchandizeTotalTax;
    public Decimal adjustedShippingTotalTax;
    public Address billingAddress;
    public String channelType;
    public String confirmationStatus;
    public String createdBy;
    public String creationDate;
    public String currencyCode;
    public CustomerInfo customerInfo;
    public String customerName;
    public Boolean c_isKycNeed;
    public String c_ngeniusOrderReference;
    public String c_ngeniusPaymentReference;
    public String c_ngeniusPaymentState;
    public String exportStatus;
    public Boolean guest;
    public String lastModified;
    public Decimal merchandizeTotalTax;
    public String notes;
    public String orderNo;
    public String orderToken;
    public Decimal orderTotal;
    public String orderViewCode;
    public List<PaymentInstrument> paymentInstruments;
    public String paymentStatus;
    public List<ProductItem> productItems;
    public Decimal productSubTotal;
    public Decimal productTotal;
    public List<ShipmentPayload> shipments;
    public List<ShippingItem> shippingItems;
    public String shippingStatus;
    public Decimal shippingTotal;
    public Decimal shippingTotalTax;
    public String siteId;
    public String status;
    public String taxation;
    public Boolean taxRoundedAtGroup;
    public Decimal taxTotal;

    public class Address {
        public String address1;
        public String city;
        public String countryCode;
        public String firstName;
        public String fullName;
        public String id;
        public String lastName;
        public String phone;
        public String postalCode;
        public String stateCode;
    }

    public class CustomerInfo {
        public String customerId;
        public String customerName;
        public String email;
    }

    public class PaymentCard {
        public String cardType;
        public Boolean creditCardExpired;
        public Integer expirationMonth;
        public Integer expirationYear;
        public String holder;
        public String maskedNumber;
        public String numberLastDigits;
    }

    public class PaymentInstrument {
        public Decimal amount;
        public PaymentCard paymentCard;
        public String paymentInstrumentId;
        public String paymentMethodId;
    }

    public class ProductItem {
        public Decimal adjustedTax;
        public Decimal basePrice;
        public Boolean bonusProductLineItem;
        public Boolean gift;
        public String itemId;
        public String itemText;
        public Decimal price;
        public Decimal priceAfterItemDiscount;
        public Decimal priceAfterOrderDiscount;
        public String productId;
        public String productName;
        public Decimal quantity;
        public String shipmentId;
        public Decimal tax;
        public Decimal taxBasis;
        public String taxClassId;
        public Decimal taxRate;
    }

    public class ShipmentPayload {
        public Decimal adjustedMerchandizeTotalTax;
        public Decimal adjustedShippingTotalTax;
        public Boolean gift;
        public Decimal merchandizeTotalTax;
        public Decimal productSubTotal;
        public Decimal productTotal;
        public String shipmentId;
        public Decimal shipmentTotal;
        public Address shippingAddress;
        public ShippingMethod shippingMethod;
        public String shippingStatus;
        public Decimal shippingTotal;
        public Decimal shippingTotalTax;
        public Decimal taxTotal;
    }

    public class ShippingItem {
        public Decimal adjustedTax;
        public Decimal basePrice;
        public String itemId;
        public String itemText;
        public Decimal price;
        public Decimal priceAfterItemDiscount;
        public String shipmentId;
        public Decimal tax;
        public Decimal taxBasis;
        public String taxClassId;
        public Decimal taxRate;
    }

    public class ShippingMethod {
        public String id;
        public String name;
        public Decimal price;
    }
}