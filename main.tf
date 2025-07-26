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
  network_security_group_id = "/subscriptions/1075a6d5-9637-41be-9e7a-38ea01eb2d86/resourceGroups/east-us-adb-rg/providers/Microsoft.Network/networkSecurityGroups/databricksnsg4nvh5vcohqnei"
}

resource "azurerm_subnet_network_security_group_association" "private" {
  subnet_id                 = data.azurerm_subnet.private_subnet.id
  network_security_group_id = "/subscriptions/1075a6d5-9637-41be-9e7a-38ea01eb2d86/resourceGroups/east-us-adb-rg/providers/Microsoft.Network/networkSecurityGroups/databricksnsg4nvh5vcohqnei"
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
    # Environment = "Dev"      # <-- REMOVE THIS LINE!
    "purpose" = "dev-demo"    # <-- You can use a different key if needed
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
