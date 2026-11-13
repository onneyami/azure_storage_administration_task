
# Azure Storage Administration Lab (Terraform IaC)

Infrastructure-as-Code (IaC) implementation of the Azure Storage Administration lab using Terraform (`azurerm ~> 3.116`). This project automates the provisioning of an Azure Storage Account configured with static website hosting, blob versioning, an Azure File Share, a private container with a scoped time-bound SAS token, and an Ubuntu Linux VM to test SMB/CIFS file share mounting.

## Repository Structure

```text
azure_storage_administration_task/
├── src/
│   └── index.html          # Static website source file
├── compute.tf              # VNet, Subnet (with Storage Service Endpoint), Public IP, NIC, Linux VM
├── main.tf                 # Data source referencing the existing Resource Group
├── outputs.tf              # Static website URL, VM IP, SAS URL, and CIFS mount command
├── providers.tf            # Terraform and provider version constraints (azurerm, random, time)
├── storage.tf              # Storage Account, Static Website, File Share, Private Container, SAS
├── variables.tf            # Input variables (target location and resource group name)
├── storage-lab.md          # Lab completion report and Break/Fix documentation
└── README.md               # Project documentation
```

## Prerequisites

- **Terraform** `>= 1.5.0`
- **Azure CLI** (`az`) authenticated via `az login`
- An existing target Resource Group (default: `rg-andrei`)
- **Azure Policy Note:** If your subscription enforces an `Allowed locations` policy, set `var.location` in `variables.tf` to an approved region (configured to `westeurope` by default).

## Deployment

1. **Initialize Terraform:**

   ```bash
   terraform init
   ```
2. **Validate and preview the execution plan:**

   ```bash
   terraform validate
   terraform plan
   ```
3. **Provision the infrastructure:**

   ```bash
   terraform apply -auto-approve
   ```

## Verification & Usage

### 1. Static Website & Blob Versioning

Retrieve the static website endpoint and verify it loads:

```bash
terraform output -raw static_website_url
curl -I "$(terraform output -raw static_website_url)"
```

To publish a new version of the page, update `src/index.html` and re-run `terraform apply -auto-approve`. Because `versioning_enabled = true` is configured on the storage account, Azure automatically retains previous versions of `index.html` inside the `$web` container.

### 2. Mount Azure File Share on the Linux VM

1. Retrieve the VM's public IP and the generated CIFS mount command:
   ```bash
   terraform output -raw vm_public_ip
   terraform output -raw mount_command_for_vm
   ```
2. Connect to the VM via SSH (`password: P@ssw0rd1234Lab!`):
   ```bash
   ssh azureuser@$(terraform output -raw vm_public_ip)
   ```
3. Run the `sudo mount -t cifs ...` command printed in Step 1, then verify the mount:
   ```bash
   df -h | grep labshare
   touch /mnt/labshare/hello-from-vm.txt
   ```

### 3. Scoped Read-Only SAS Token

Test access to `test.txt` inside the `private-data` container using the generated 1-hour read/list SAS URL:

```bash
curl -i "$(terraform output -raw sas_url_example)"
```

Attempting a `PUT` or `DELETE` request with the same SAS token will fail with `403 AuthorizationPermissionMismatch`.

## Simulating Break/Fix Scenarios

| Scenario                                 | How to Reproduce (`storage.tf`)                                            | How to Fix                                                                                 |
| :--------------------------------------- | :--------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------- |
| **SAS Expired / Not-Yet-Valid**    | Set `offset_hours = -1` in `time_offset.sas_expiry` and apply.           | Restore `offset_hours = 1` (ensuring `start` and `expiry` align with UTC).           |
| **Public Access on Private Blob**  | Set `container_access_type = "blob"` on `private_container` and apply.   | Set `container_access_type = "private"` and `allow_nested_items_to_be_public = false`. |
| **Storage Firewall Blocks Client** | Set `default_action = "Deny"` in `network_rules` without adding your IP. | Add your client public IP to `ip_rules = ["<YOUR_IP>"]` or keep allowed VNet subnets.    |

## Cleanup

Destroy all provisioned lab resources (leaves the pre-existing Resource Group `rg-andrei` intact):

```bash
terraform destroy -auto-approve
```
