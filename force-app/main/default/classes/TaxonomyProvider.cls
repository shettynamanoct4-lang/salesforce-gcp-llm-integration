/**
 * @description Reads the live controlling -> dependent picklist matrix via Schema describe, so the AI
 *              service is always grounded in the values that currently exist in the org.
 * @author      Naman G Shetty
 */
public with sharing class TaxonomyProvider {

    /**
     * @return Map of active Risk_Reason__c value -> set of valid Risk_Sub_Reason__c values.
     */
    public static Map<String, Set<String>> reasonToSubReasons() {
        Schema.DescribeFieldResult controlling = Account.Risk_Reason__c.getDescribe();
        Schema.DescribeFieldResult dependent = Account.Risk_Sub_Reason__c.getDescribe();

        List<Schema.PicklistEntry> controllingValues = controlling.getPicklistValues();
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        for (Schema.PicklistEntry entry : controllingValues) {
            if (entry.isActive()) {
                result.put(entry.getValue(), new Set<String>());
            }
        }

        for (Schema.PicklistEntry dep : dependent.getPicklistValues()) {
            if (!dep.isActive()) {
                continue;
            }
            List<Boolean> validFor = decodeValidFor(dep, controllingValues.size());
            for (Integer i = 0; i < controllingValues.size(); i++) {
                String parent = controllingValues[i].getValue();
                if (validFor[i] && result.containsKey(parent)) {
                    result.get(parent).add(dep.getValue());
                }
            }
        }
        return result;
    }

    /** Decodes the base64 `validFor` bitmap that Salesforce returns for dependent picklist entries. */
    private static List<Boolean> decodeValidFor(Schema.PicklistEntry entry, Integer controllingCount) {
        Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(entry));
        String validFor = (String) raw.get('validFor');
        List<Boolean> flags = new List<Boolean>();
        String bits = validFor == null ? '' : EncodingUtil.convertToHex(EncodingUtil.base64Decode(validFor));
        for (Integer i = 0; i < controllingCount; i++) {
            Integer byteIndex = i / 8;
            Integer bitIndex = 7 - Math.mod(i, 8);
            Boolean isSet = false;
            if (bits.length() >= (byteIndex + 1) * 2) {
                Integer b = hexToInt(bits.substring(byteIndex * 2, byteIndex * 2 + 2));
                isSet = ((b >> bitIndex) & 1) == 1;
            }
            flags.add(isSet);
        }
        return flags;
    }

    private static Integer hexToInt(String hex) {
        String digits = '0123456789abcdef';
        hex = hex.toLowerCase();
        return digits.indexOf(hex.substring(0, 1)) * 16 + digits.indexOf(hex.substring(1, 2));
    }
}
