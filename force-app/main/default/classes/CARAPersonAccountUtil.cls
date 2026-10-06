/*
 * Single source of truth for the Person Account RecordTypeId. Looked up by
 * DeveloperName via Schema (not hardcoded) because RecordType Ids differ
 * between orgs (sandbox vs. STG vs. prod).
 */
public class CARAPersonAccountUtil {

    public class PersonAccountNotConfiguredException extends Exception {}

    private static Id personAccountRecordTypeId;

    public static Id getRecordTypeId() {
        if (personAccountRecordTypeId == null) {
            Schema.RecordTypeInfo personRecordTypeInfo = Account.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get('PersonAccount');
            if (personRecordTypeInfo == null) {
                throw new PersonAccountNotConfiguredException(
                    'Person Account record type not found on Account - is Person Accounts enabled in this org?'
                );
            }
            personAccountRecordTypeId = personRecordTypeInfo.getRecordTypeId();
        }
        return personAccountRecordTypeId;
    }
}