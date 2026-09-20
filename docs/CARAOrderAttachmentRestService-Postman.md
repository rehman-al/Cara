# Order Attachments API — Postman Guide

Reference for testing the two Apex REST endpoints that let the Wingold OMS
post files to a Salesforce Order and retrieve them back, by
`OrderReferenceNumber`.

- `CARAOrderAttachmentRestService.cls` — the REST endpoint
- `CARAOrderAttachmentPayload.cls` — the upload payload wrapper

Both endpoints require a valid Salesforce session — there is no anonymous
access. Neither endpoint parses `multipart/form-data`; file bytes travel as
base64 text inside a JSON body, and downloads come back as raw binary from
the standard Salesforce Files API.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/services/apexrest/cara/orders/attachments` | Upload one or more files and link them to an Order. |
| `GET` | `/services/apexrest/cara/orders/attachments?orderReferenceNumber=...` | List every file already attached to an Order. |
| `GET` | `/services/data/v67.0/sobjects/ContentVersion/{id}/VersionData` | Download one file's raw bytes (returned by the list call as `downloadUrl`). |

## Quick reference — all three calls

Copy-paste versions of upload, list, and download in one place. Replace
`<Instance Url>` and `<Access Token>` with the values from
[section 1](#1-get-an-access-token--instance-url); `<FILE_B64>` is your
file's base64 content (see [section 2](#2-upload-an-attachment-post)).

**Upload (`POST`)**
```bash
curl --location '<Instance Url>/services/apexrest/cara/orders/attachments' \
--header 'Authorization: Bearer <Access Token>' \
--header 'Content-Type: application/json' \
--data '{
  "orderReferenceNumber": "01",
  "attachments": [
    { "fileName": "file.pdf", "fileContent": "<FILE_B64>", "contentType": "application/pdf" }
  ]
}'
```

**List (`GET`)**
```bash
curl --location '<Instance Url>/services/apexrest/cara/orders/attachments?orderReferenceNumber=01' \
--header 'Authorization: Bearer <Access Token>'
```
Returns each file's metadata plus a `downloadUrl` — see
[section 3](#3-list-attachments-get).

**Download (`GET`)**
```bash
curl --location '<Instance Url><downloadUrl from the list response>' \
--header 'Authorization: Bearer <Access Token>' \
--output downloaded-file.pdf
```

## 1. Get an access token + instance URL

For sandbox testing, reuse your already-authenticated CLI session rather
than standing up a connected app.

```powershell
sf org display --target-org <Org_Name> --verbose
```

Copy the `Access Token` and `Instance Url` values from the output. Treat
the access token like a password — don't commit it or share it outside your
own tools. It's a temporary session token, so you'll need to re-run this
command once it expires.

## 2. Upload an attachment (`POST`)

File bytes must be base64-encoded and embedded in the JSON body — Postman's
`form-data` (multipart) tab will **not** work against this endpoint.

### Encode the file first

**Important:** this must be run in an actual **PowerShell** window (prompt
reads `PS C:\...>`), not Command Prompt (`cmd.exe`, prompt reads `C:\...>`).
Running `[Convert]::...` syntax in cmd.exe fails with
`The filename, directory name, or volume label syntax is incorrect.`

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\your\file.pdf")) | Set-Clipboard
```

This copies the base64 string to your clipboard, ready to paste into the
Postman body.

### Request

- **Method:** `POST`
- **URL:** `<Instance Url>/services/apexrest/cara/orders/attachments`
- **Headers:**

  | Key | Value |
  |---|---|
  | `Authorization` | `Bearer <Access Token>` |
  | `Content-Type` | `application/json` |

- **Body → raw → JSON:**

```json
{
  "orderReferenceNumber": "01",
  "attachments": [
    {
      "fileName": "test_lorem_document.pdf",
      "fileContent": "<paste base64 string here>",
      "contentType": "application/pdf",
      "description": "optional description"
    }
  ]
}
```

Send multiple files in one call by adding more objects to the `attachments`
array:

```json
{
  "orderReferenceNumber": "01",
  "attachments": [
    { "fileName": "invoice.pdf", "fileContent": "..." },
    { "fileName": "packing-slip.pdf", "fileContent": "..." }
  ]
}
```

### Response

**Success (`200`):**
```json
{
  "success": true,
  "message": "Attachment(s) created successfully.",
  "orderId": "801XXXXXXXXXXXXXXX",
  "contentDocumentIds": ["069XXXXXXXXXXXXXXX"]
}
```

**Failure (`400`):**
```json
{
  "success": false,
  "message": "No Order found with OrderReferenceNumber 01.",
  "orderId": null,
  "contentDocumentIds": []
}
```

## 3. List attachments (`GET`)

- **Method:** `GET`
- **URL:** `<Instance Url>/services/apexrest/cara/orders/attachments?orderReferenceNumber=01`
- **Headers:** same `Authorization: Bearer <Access Token>` as above; no body needed.

**Response (`200`):**
```json
{
  "success": true,
  "orderId": "801FV00KkXNk5m8YUB",
  "message": "Attachments retrieved successfully.",
  "count": 1,
  "attachments": [
    {
      "fileType": "PDF",
      "fileName": "test_lorem_document.pdf",
      "fileExtension": "pdf",
      "downloadUrl": "/services/data/v67.0/sobjects/ContentVersion/068FV007JFetcRgYYI/VersionData",
      "description": null,
      "createdDate": "2026-09-20T08:13:20.000Z",
      "contentVersionId": "068FV007JFetcRgYYI",
      "contentSize": 2125,
      "contentDocumentId": "069FV007HnHKvymYID"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `fileName` | Original filename as uploaded (`ContentVersion.Title`). |
| `contentSize` | File size in bytes. |
| `contentVersionId` / `contentDocumentId` | Salesforce record ids for the file version and its parent document. |
| `downloadUrl` | Relative path — prepend the instance URL and call it directly to get the raw file bytes. See section 4. |

**Failure (`400`)** if `orderReferenceNumber` is missing or no Order matches, in the same `{ success, message, orderId, ... }` shape as the POST endpoint.

## 4. Download a file in Postman

`downloadUrl` is relative — prepend your instance URL, and call it with the
same bearer token. The response body is raw binary, not JSON.

- **Method:** `GET`
- **URL:** `<Instance Url>/services/data/v67.0/sobjects/ContentVersion/068FV007JFetcRgYYI/VersionData`
- **Headers:** `Authorization: Bearer <Access Token>`

Postman can't render binary as text, so the **Body** tab shows a **Base64**
view by default — that's expected, not an error. If the **Visualize** tab
recognizes the file type (e.g. shows PDF page count/metadata), the download
already succeeded and you just need to save it properly:

1. Send the request normally (plain **Send** is fine).
2. Open the response panel's overflow menu (the **•••** near the top of the
   response, close to the AI/visualize controls).
3. Choose **Download response** at the bottom of that menu.
4. In the Save dialog, the filename defaults to `response` with no
   extension — replace it with something like `test_lorem_document.pdf`,
   keep "Save as type" as **All Files (\*.\*)**, then **Save**.

Never copy the Base64 text out of the Body tab by hand — that's just
Postman's raw-bytes display, not something to decode yourself. Use
**Download response** instead.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `INVALID_SESSION_ID` / 401 response | Access token missing, wrong, or expired — re-run `sf org display` to get a fresh one |
| `No Order found with OrderReferenceNumber ...` | No `Order` record in the target org has that value in the `OrderReferenceNumber` field |
| `Multiple Orders use OrderReferenceNumber ...` | More than one `Order` record shares that reference number — must be unique |
| `Missing required field(s): ...` | `orderReferenceNumber` or an attachment's `fileName`/`fileContent` was blank |
| `... has invalid base64 fileContent` | The `fileContent` string isn't valid base64 (e.g. you sent raw file bytes, a data URI prefix like `data:application/pdf;base64,`, or truncated the copy/paste) |
| Upload request silently does nothing | Using Postman's `form-data` (multipart) tab instead of `raw` JSON — this endpoint only accepts JSON |
| PowerShell command errors with "filename, directory name, or volume label syntax is incorrect" | The command was run in `cmd.exe` instead of PowerShell |
| Downloaded file won't open / wrong type | The Save dialog's default filename (`response`) had no extension — re-save with `.pdf` (or the correct extension) added |

## Equivalent curl (Git Bash)

### Upload

```bash
FILE_B64=$(base64 -w0 "/c/path/to/your/file.pdf")

curl --location '<Instance Url>/services/apexrest/cara/orders/attachments' \
--header 'Authorization: Bearer <Access Token>' \
--header 'Content-Type: application/json' \
--data "{
  \"orderReferenceNumber\": \"01\",
  \"attachments\": [
    {
      \"fileName\": \"file.pdf\",
      \"fileContent\": \"$FILE_B64\",
      \"contentType\": \"application/pdf\"
    }
  ]
}"
```

### List

```bash
curl --location '<Instance Url>/services/apexrest/cara/orders/attachments?orderReferenceNumber=01' \
--header 'Authorization: Bearer <Access Token>'
```

### Download

```bash
curl --location '<Instance Url>/services/data/v67.0/sobjects/ContentVersion/068FV007JFetcRgYYI/VersionData' \
--header 'Authorization: Bearer <Access Token>' \
--output test_lorem_document.pdf
```
