/**
 * One-off utility to seed the initial Customisation_Option__c catalog to match
 * the values the Customise wizard previously had hardcoded. Safe to run more
 * than once — skips insert if any Customisation_Option__c records already exist.
 * Not referenced by the wizard itself; can be deleted after initial setup.
 */
public without sharing class CustomisationOptionSeeder {

    public static void seedIfEmpty() {
        Integer existing = [SELECT COUNT() FROM Customisation_Option__c WITH SYSTEM_MODE];
        if (existing > 0) {
            System.debug('CustomisationOptionSeeder: catalog already has ' + existing + ' records, skipping.');
            return;
        }

        List<Customisation_Option__c> options = new List<Customisation_Option__c>{
            new Customisation_Option__c(Name = 'Ring', Option_Type__c = 'Category', Description__c = 'Cocktail, eternity and signature bands', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Engagement Ring', Option_Type__c = 'Category', Description__c = 'Solitaire, halo or a bespoke setting', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Necklace', Option_Type__c = 'Category', Description__c = 'Rivieres, pendants and chains', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Earrings', Option_Type__c = 'Category', Description__c = 'Studs, drops and hoops', Sort_Order__c = 4, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Bracelet', Option_Type__c = 'Category', Description__c = 'Tennis lines, bangles and cuffs', Sort_Order__c = 5, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Pendant', Option_Type__c = 'Category', Description__c = 'Personal charms and lockets', Sort_Order__c = 6, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Something Else', Option_Type__c = 'Category', Description__c = 'Tell us what you have in mind', Sort_Order__c = 7, Is_Active__c = true),

            new Customisation_Option__c(Name = 'Yellow Gold', Option_Type__c = 'Metal Type', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'White Gold', Option_Type__c = 'Metal Type', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Rose Gold', Option_Type__c = 'Metal Type', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Platinum', Option_Type__c = 'Metal Type', Sort_Order__c = 4, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Not sure yet', Option_Type__c = 'Metal Type', Sort_Order__c = 5, Is_Active__c = true),

            new Customisation_Option__c(Name = 'Diamond', Option_Type__c = 'Stone Type', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Emerald', Option_Type__c = 'Stone Type', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Sapphire', Option_Type__c = 'Stone Type', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Ruby', Option_Type__c = 'Stone Type', Sort_Order__c = 4, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Pearl', Option_Type__c = 'Stone Type', Sort_Order__c = 5, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Not sure yet', Option_Type__c = 'Stone Type', Sort_Order__c = 6, Is_Active__c = true),

            new Customisation_Option__c(Name = 'Clear / Colourless', Option_Type__c = 'Color', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Blue', Option_Type__c = 'Color', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Green', Option_Type__c = 'Color', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Red', Option_Type__c = 'Color', Sort_Order__c = 4, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Pink', Option_Type__c = 'Color', Sort_Order__c = 5, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Yellow', Option_Type__c = 'Color', Sort_Order__c = 6, Is_Active__c = true),

            new Customisation_Option__c(Name = 'Under AED 10,000', Option_Type__c = 'Budget Guide', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'AED 10,000 - 25,000', Option_Type__c = 'Budget Guide', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'AED 25,000 - 50,000', Option_Type__c = 'Budget Guide', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'AED 50,000 - 100,000', Option_Type__c = 'Budget Guide', Sort_Order__c = 4, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Above AED 100,000', Option_Type__c = 'Budget Guide', Sort_Order__c = 5, Is_Active__c = true),

            new Customisation_Option__c(Name = 'No particular rush', Option_Type__c = 'Timeline', Sort_Order__c = 1, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Within 1 month', Option_Type__c = 'Timeline', Sort_Order__c = 2, Is_Active__c = true),
            new Customisation_Option__c(Name = 'Within 3 months', Option_Type__c = 'Timeline', Sort_Order__c = 3, Is_Active__c = true),
            new Customisation_Option__c(Name = 'For a specific date', Option_Type__c = 'Timeline', Sort_Order__c = 4, Is_Active__c = true)
        };

        Database.insert(options, true, AccessLevel.SYSTEM_MODE);
    }
}