# Cara Salesforce Service Cloud

This Salesforce DX project contains only the Cara-specific Service Cloud metadata that is intentionally maintained in source control.

## Included scope

- Case fields, record types, layouts, list views, quick actions, and Lightning record pages
- Case numbering trigger
- Case finance approval process
- First-call-resolution flow
- Entitlement process and service milestones
- Omni-Channel queue, routing, presence statuses, and permission set
- Core Case, Knowledge, Omni-Channel, Entitlement, and Order settings
- Custom Product Request object, validation rules, Apex controller, tests, and Lightning Web Component

Bulk-retrieved standard Salesforce schema, default profiles, unused applications, Data Cloud internals, sample reports, sample email templates, and unrelated settings are intentionally excluded.

## Commands

```powershell
sf project generate manifest --source-dir force-app --name package --output-dir manifest
sf project convert source --root-dir force-app --output-dir <temporary-output-directory>
npm.cmd install
npm.cmd test
```

The deployment manifest is [manifest/package.xml](manifest/package.xml).
