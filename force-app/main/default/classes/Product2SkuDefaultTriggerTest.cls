@isTest
private class Product2SkuDefaultTriggerTest {

    @isTest
    static void testCustomProductWithBlankSkuInheritsProductCode() {
        Product2 customProduct = new Product2(
            Name = 'Bespoke Ring',
            ProductCode = 'TEST-CODE-INHERIT-001',
            Is_Custom__c = true,
            IsActive = true
        );

        Test.startTest();
        insert customProduct;
        Test.stopTest();

        Product2 result = [SELECT StockKeepingUnit FROM Product2 WHERE Id = :customProduct.Id];
        System.assertEquals('TEST-CODE-INHERIT-001', result.StockKeepingUnit, 'Blank SKU should default to the Product Code.');
    }

    @isTest
    static void testCustomProductWithExistingSkuIsNotOverwritten() {
        Product2 customProduct = new Product2(
            Name = 'Bespoke Ring',
            ProductCode = 'TEST-CODE-KEEP-002',
            StockKeepingUnit = 'REAL-CATALOG-SKU',
            Is_Custom__c = true,
            IsActive = true
        );

        Test.startTest();
        insert customProduct;
        Test.stopTest();

        Product2 result = [SELECT StockKeepingUnit FROM Product2 WHERE Id = :customProduct.Id];
        System.assertEquals('REAL-CATALOG-SKU', result.StockKeepingUnit, 'An explicitly set SKU must never be overwritten.');
    }

    @isTest
    static void testNonCustomProductIsNeverDefaulted() {
        Product2 catalogProduct = new Product2(
            Name = 'Catalog Item',
            ProductCode = 'TEST-CODE-CATALOG-003',
            Is_Custom__c = false,
            IsActive = true
        );

        Test.startTest();
        insert catalogProduct;
        Test.stopTest();

        Product2 result = [SELECT StockKeepingUnit FROM Product2 WHERE Id = :catalogProduct.Id];
        System.assertEquals(null, result.StockKeepingUnit, 'Catalog products must not have a SKU inferred from Product Code.');
    }

    @isTest
    static void testProductCodeAddedLaterStillDefaultsSkuOnUpdate() {
        Product2 customProduct = new Product2(
            Name = 'Bespoke Necklace',
            Is_Custom__c = true,
            IsActive = true
        );
        insert customProduct;

        customProduct.ProductCode = 'TEST-CODE-LATER-004';

        Test.startTest();
        update customProduct;
        Test.stopTest();

        Product2 result = [SELECT StockKeepingUnit FROM Product2 WHERE Id = :customProduct.Id];
        System.assertEquals('TEST-CODE-LATER-004', result.StockKeepingUnit, 'SKU should default from Product Code added on a later update.');
    }
}