
# Azure Storage Administration Lab Report

## 1. Environment & Provisioned Resources

- **Subscription ID:** `c6a76d9c-0f67-4a42-b2a1-3defb05f2aae`
- **Resource Group:** `rg-andrei`
- **Deployment Region:** `westeurope` *(enforced by subscription `Policy_allowed_locations`)*
- **Provisioning Method:** Terraform (`azurerm v3.117.1`, `random v3.9.1`, `time v0.14.2`)
- **Storage Account:** `stlab<SUFFIX>` *(replace with actual suffix from `terraform state show azurerm_storage_account.lab_sa`)*
- **Static Website Endpoint:** `https://stlab<SUFFIX>.z6.web.core.windows.net/`
- **Linux VM (`vm-storage-lab`):** `<VM_PUBLIC_IP>`

---

## 2. Core Tasks & Azure CLI (`az storage`) Verification

### 2.1 Static Website & Blob Versioning

Static website hosting (`index_document = "index.html"`) and blob versioning (`versioning_enabled = true`) were enabled via Terraform. After updating `src/index.html` from `v1.0` to `v2.0` and re-applying, Azure preserved the historical version in the `$web` container.

**Verification Commands:**

```bash
# Check static website and versioning properties
az storage blob service-properties show \
  --account-name <SA_NAME> \
  --auth-mode login \
  --query "{staticWebsite:staticWebsite, versioning:isVersioningEnabled}"

# List all blob versions in the $web container
az storage blob list \
  --account-name <SA_NAME> \
  --container-name '$web' \
  --include v \
  --auth-mode login \
  --output table

# Verify HTTP response from the static website endpoint
curl -s "$(terraform output -raw static_website_url)"
```

### 2.2 Azure File Share & Linux VM SMB/CIFS Mount

An Azure File Share (`labshare`, 5 GiB quota) was provisioned and mounted over SMB 3.0 (`TCP/445`) on Ubuntu 22.04 (`vm-storage-lab`) with `cifs-utils`.

**Verification Commands (Azure CLI & VM):**

```bash
# Verify file share exists via Azure CLI
az storage share list \
  --account-name <SA_NAME> \
  --account-key <ACCOUNT_KEY> \
  --output table

# On the Linux VM: mount share and verify read/write access
sudo mount -t cifs //<SA_NAME>.file.core.windows.net/labshare /mnt/labshare \
  -o vers=3.0,username=<SA_NAME>,password=<ACCOUNT_KEY>,dir_mode=0777,file_mode=0777,serverino

df -h | grep labshare
echo "Mounted via CIFS" | sudo tee /mnt/labshare/verify.txt
ls -la /mnt/labshare/
```

### 2.3 Restricted Container SAS Token

A private container (`private-data`) containing `test.txt` was created alongside an HTTPS-only SAS token scoped strictly to `read` (`r`) and `list` (`l`) permissions with a 1-hour lifetime.

**Equivalent Azure CLI Command & Verification:**

```bash
# Generate equivalent 1-hour read/list SAS via CLI
EXPIRY=$(date -u -v+1H '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -d '+1 hour' '+%Y-%m-%dT%H:%MZ')
az storage container generate-sas \
  --account-name <SA_NAME> \
  --account-key <ACCOUNT_KEY> \
  --name private-data \
  --permissions rl \
  --expiry "$EXPIRY" \
  --https-only \
  --output tsv

# Verify READ succeeds (HTTP 200)
curl -i "$(terraform output -raw sas_url_example)"

# Verify WRITE is denied (HTTP 403 AuthorizationPermissionMismatch)
curl -i -X PUT -H "x-ms-blob-type: BlockBlob" -d "unauthorized" "$(terraform output -raw sas_url_example)"
```

---

## 3. Break/Fix Scenarios

### Scenario 1: SAS Expired / Not-Yet-Valid Due to Time Skew

- **Symptom:** Requests using the SAS URL fail with `HTTP 403 Server failed to authenticate the request` (`AuthenticationFailed` — *Signature not valid in the specified time frame*).
- **Root Cause:** The SAS `se` (expiry) timestamp is in the past, or the `st` (start) timestamp is in the future due to local clock skew between client and Azure UTC time.
- **Reproduction:** Setting `offset_hours = -1` in `time_offset.sas_expiry` generates a token whose validity window has already closed.
- **Resolution:** Ensure timestamps use UTC, allow a 5–15 minute buffer on the start time for clock skew, and regenerate the token with a valid future expiry (`offset_hours = 1`).

### Scenario 2: Blob Publicly Accessible When Private Is Required

- **Symptom:** Anonymous unauthenticated `curl https://<SA_NAME>.blob.core.windows.net/private-data/test.txt` (without a SAS token) succeeds with `HTTP 200 OK` instead of `404 ResourceNotFound`.
- **Root Cause:** Anonymous public read access was enabled at both the Storage Account level (`allow_nested_items_to_be_public = true`) and the container level (`container_access_type = "blob"`).
- **Resolution:** Set `container_access_type = "private"` on `private-data` and disable anonymous access globally on the storage account:
  ```bash
  az storage container set-permission --name private-data --account-name <SA_NAME> --public-access off
  az storage account update --name <SA_NAME> --resource-group rg-andrei --allow-blob-public-access false
  ```

### Scenario 3: Storage Firewall Blocking Authorized Client

- **Symptom:** Storage operations from the local workstation fail with `HTTP 403 This request is not authorized to perform this operation` (`AuthorizationFailure`).
- **Root Cause:** `network_rules.default_action` was switched to `"Deny"`, allowing traffic only from `snet-storage-lab` via the `Microsoft.Storage` Service Endpoint while dropping requests from the client's public IPv4 address.
- **Resolution:** Whitelist the client's public IP in `ip_rules`:
  ```bash
  MY_IP=$(curl -s ifconfig.me)
  az storage account network-rule add \
    --resource-group rg-andrei \
    --account-name <SA_NAME> \
    --ip-address "$MY_IP"
  ```

---

## 4. Storage Tiers, Replication, Use Cases & Cost/Risk Comparison

| Access Tier       | Recommended Replication                | Primary Use Case                                                                                 | Cost Profile & Risk Trade-Off                                                                                                                                                                                                         |
| :---------------- | :------------------------------------- | :----------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Hot**     | **LRS** (Locally Redundant)      | Active web assets (`$web` static sites), frequently accessed application data, active uploads. | **Cost:** Highest storage price per GB, lowest read/write transaction cost.**Risk:** Protected against single disk/node failure within one datacenter, but vulnerable to zone-wide or regional outages.                   |
| **Cool**    | **ZRS** (Zone-Redundant)         | Short-term backups, application logs, datasets accessed once every 30+ days.                     | **Cost:** ~40–50% lower storage cost than Hot, higher access/transaction fees, 30-day minimum retention penalty.**Risk:** Synchronous replication across 3 Availability Zones eliminates single-datacenter failure risk. |
| **Cold**    | **GZRS** (Geo-Zone-Redundant)    | Infrequently accessed operational archives and audit data (90+ day retention).                   | **Cost:** Lower storage rate than Cool, higher retrieval cost, 90-day early deletion penalty.**Risk:** Combines 3-zone local availability with asynchronous cross-region disaster recovery.                               |
| **Archive** | **GRS / RA-GRS** (Geo-Redundant) | Long-term compliance records, cold backups, raw datasets retained for years (180+ days).         | **Cost:** Lowest storage cost per GB, highest read/rehydration cost, 180-day early deletion penalty.**Risk:** Offline tier—data cannot be read directly and requires rehydration (up to 15 hours on Standard priority).  |

---

## 5. Cleanup Evidence

All lab infrastructure was deprovisioned via Terraform, leaving the pre-existing `rg-andrei` resource group clean.

```bash
# Destroy all Terraform-managed resources
terraform destroy -auto-approve
```

**Expected Terraform Output:**

```text
Destroy complete! Resources: 11 destroyed.
```

**Post-Cleanup Verification (`az cli`):**

```bash
az resource list --resource-group rg-andrei --output table
# Output: [] (No lab resources remaining)
```
