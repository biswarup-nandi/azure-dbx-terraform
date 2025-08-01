---

# **Azure Databricks VNet Injection – Full Terraform Guide**

---

## **1. Prerequisites**

* Azure subscription (Contributor rights)
* Existing VNet + subnets for Databricks (with required address spaces, NSGs)
* Azure Service Principal (for Terraform authentication)
* Terraform CLI installed (`terraform -v`)
* Databricks NSG in the correct RG

---

## **2. Directory & File Structure**

```shell
your_project/
│
├── main.tf
├── provider.tf
├── variables.tf
├── terraform.tfvars  # (optional, recommended)
└── README.md         # (optional)
```

---

## **3. Terraform Code**

### **main.tf**

```hcl
########################
# Resource Group
########################
resource "azurerm_resource_group" "dbxResourceGroup" {
  name     = "azure-dbx-resource-group"
  location = "East US"
  tags = {
    Environment = "Development"
    Owner       = "Biswa"
  }
}

########################
# Existing VNet & Subnets
########################
data "azurerm_virtual_network" "adb_vnet" {
  name                = "adb-vnet"
  resource_group_name = "east-us-adb-rg"
}

data "azurerm_subnet" "public_subnet" {
  name                 = "public-subnet-alternate"
  virtual_network_name = data.azurerm_virtual_network.adb_vnet.name
  resource_group_name  = data.azurerm_virtual_network.adb_vnet.resource_group_name
}

data "azurerm_subnet" "private_subnet" {
  name                 = "private-subnet-alternative"
  virtual_network_name = data.azurerm_virtual_network.adb_vnet.name
  resource_group_name  = data.azurerm_virtual_network.adb_vnet.resource_group_name
}

########################
# Subnet-NSG Associations
########################
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id                 = data.azurerm_subnet.public_subnet.id
  network_security_group_id = "<your-nsg-resource-id>"  # Replace with your NSG resource ID
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = data.azurerm_subnet.private_subnet.id
  network_security_group_id = "<your-nsg-resource-id>"
}

########################
# Databricks Workspace (VNet Injection)
########################
resource "azurerm_databricks_workspace" "dbxWorkspace" {
  name                = "azure-dbx-workspace-dev"
  resource_group_name = azurerm_resource_group.dbxResourceGroup.name
  location            = azurerm_resource_group.dbxResourceGroup.location
  sku                 = "standard"

  custom_parameters {
    virtual_network_id                                   = data.azurerm_virtual_network.adb_vnet.id
    public_subnet_name                                   = data.azurerm_subnet.public_subnet.name
    private_subnet_name                                  = data.azurerm_subnet.private_subnet.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
  }

  tags = {
    Environment = "Dev"
  }
}

########################
# Databricks Resources
########################

# Node type (smallest with local disk)
data "databricks_node_type" "smallest" {
  depends_on = [azurerm_databricks_workspace.dbxWorkspace]
  local_disk = true
}

# Spark version (latest LTS)
data "databricks_spark_version" "latest_lts" {
  depends_on        = [azurerm_databricks_workspace.dbxWorkspace]
  long_term_support = true
}

# Instance Pool
resource "databricks_instance_pool" "dbxInstancePool" {
  instance_pool_name                    = "azure-dbx-instance-pool"
  min_idle_instances                    = 0
  max_capacity                          = 3
  node_type_id                          = data.databricks_node_type.smallest.id
  idle_instance_autotermination_minutes = 5
  custom_tags = {
    "purpose" = "dev-demo"
  }
}

# Cluster
resource "databricks_cluster" "shared_autoscaling" {
  depends_on              = [azurerm_databricks_workspace.dbxWorkspace]
  instance_pool_id        = databricks_instance_pool.dbxInstancePool.id
  cluster_name            = "azure-dbx-dbx-small-shared-cluster"
  spark_version           = data.databricks_spark_version.latest_lts.id
  autotermination_minutes = 10

  autoscale {
    min_workers = 1
    max_workers = 5
  }
  spark_conf = {
    "spark.databricks.io.cache.enabled" = true
  }
  custom_tags = {
    "created_by" = "BN"
  }
}
```

---

### **provider.tf**

```hcl
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
    }
    databricks = {
      source = "databricks/databricks"
    }
  }
}

provider "azurerm" {
  features {}
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
}

provider "databricks" {
  azure_workspace_resource_id = azurerm_databricks_workspace.dbxWorkspace.id
  azure_client_id             = var.client_id
  azure_client_secret         = var.client_secret
  azure_tenant_id             = var.tenant_id
}
```

---

### **variables.tf**

```hcl
variable "client_id" {
  description = "Azure Service Principal Client ID"
  type        = string
  sensitive   = true
}

variable "client_secret" {
  description = "Azure Service Principal Client Secret"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure Tenant ID"
  type        = string
  sensitive   = true
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}
```

---

### **terraform.tfvars** *(recommended, not required)*

```hcl
client_id       = "<your-client-id>"
client_secret   = "<your-client-secret>"
tenant_id       = "<your-tenant-id>"
subscription_id = "<your-subscription-id>"
```

---

## **4. Terraform Commands (Step-by-step)**

**Initialize**:

```sh
terraform init
```

**Plan** (always review before applying!):

```sh
terraform plan
```

**Apply**:

```sh
terraform apply --auto-approve
```

---

## **5. Importing Existing Resources**

### **A. Import Existing NSG Associations**

1. **Comment out the Databricks provider block** in `provider.tf` temporarily.
2. **Import association for public subnet:**

   ```sh
   terraform import azurerm_subnet_network_security_group_association.public "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<public-subnet-name>"
   ```
3. **Import association for private subnet:**

   ```sh
   terraform import azurerm_subnet_network_security_group_association.private "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<private-subnet-name>"
   ```
4. **Uncomment the Databricks provider block** after import.

---

### **B. Import Existing Databricks Workspace (if already created via Portal/ARM)**

```sh
terraform import azurerm_databricks_workspace.dbxWorkspace "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Databricks/workspaces/<workspace-name>"
```

---

## **6. Troubleshooting & Common Issues**

### **A. “Resource already managed by Terraform”**

* **Solution:**

  * Resource is already in state. Use `terraform state list` and `terraform state rm <resource>` if you need to re-import.

### **B. “SubnetInUseError”**

* **Solution:**

  * The subnet is already used by another workspace. You must use an unused subnet or destroy the previous workspace.

### **C. NSG Association Already Exists**

* **Solution:**

  * Import the NSG association as shown above.

### **D. Databricks Provider – “depends on values that cannot be determined until apply”**

* **Solution:**

  * Comment out the provider block during import, then restore it after importing.

### **E. Tag Conflicts**

* **Solution:**

  * Do **not** use `"Environment"` as a custom tag in Databricks resources. Use another key.

### **F. Delegation Errors**

* **Solution:**

  * Make sure your Databricks subnets have the Microsoft.Databricks/workspaces delegation set via Portal or CLI:

    ```sh
    az network vnet subnet update \
      --name <subnet-name> \
      --resource-group <rg> \
      --vnet-name <vnet-name> \
      --delegations Microsoft.Databricks/workspaces
    ```

### **G. Databricks Cluster Creation Hangs/Timeouts**

* **Solution:**

  * Check if your corporate firewall/proxy is blocking outbound access to Databricks.
  * Ensure NSG rules allow outbound to Databricks service endpoints.

---

## **7. Best Practices**

* Use **separate environments** (dev/stage/prod) with their own state files.
* Use **backend** (Azure Storage) for remote state in teams.
* Always use **service principal** for Terraform automation.
* Regularly use `terraform plan` to review changes before applying.

---

## **8. Reference: Azure Portal / CLI Checks**

* **Subnet Delegation**:
  Azure Portal → VNet → Subnets → Select Subnet → “Service Endpoints”/“Delegations”
* **NSG Assignment**:
  Azure Portal → NSGs → Subnets

---

## **9. Useful Terraform CLI Commands**

* List state resources:

  ```sh
  terraform state list
  ```
* Remove resource from state:

  ```sh
  terraform state rm <resource>
  ```
* Show resource details:

  ```sh
  terraform state show <resource>
  ```

---

## **10. Final Diagram (Text-based)**

```
[Resource Group]
     |
     +-- [VNet (adb-vnet)]
     |       +-- [public-subnet-alternate] --(NSG)--> [databricksnsg4nvh5vcohqnei]
     |       +-- [private-subnet-alternative] --(NSG)--> [databricksnsg4nvh5vcohqnei]
     |
     +-- [Databricks Workspace (VNet Injection)]
             +-- [Databricks Instance Pool]
             +-- [Databricks Cluster (autoscaling)]
```

---

**This is the complete step-by-step, code, command, and troubleshooting guide for Azure Databricks VNet Injection with Terraform.**

---