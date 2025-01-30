# PROVIDER 
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.16.0"
    }
  }
}
provider "azurerm" {
    subscription_id = "c23a3174-f9e7-4414-9f75-966ddbb786fb"
  features {
  }
}

# ======================================
# VARIABLES

variable "location" {
  default = "eastus"
}

variable "rg_name" {
  default = "rg1-test"
}

variable "vm_password" {
  default = "Vanguard1234"
}


# ===============================================
# MAIN BODY

resource "azurerm_resource_group" "rg1" {
  name     = var.rg_name
  location = var.location
}




# -----------------------------------------------
# VMSS


resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet1"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_linux_virtual_machine_scale_set" "vmss1" {
  name                = "vmss1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  sku                 = "Standard_B1s"
  instances           = 1
  admin_username      = "adminuser"
  admin_password = var.vm_password
  disable_password_authentication = false


  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

    lifecycle {
    ignore_changes = [instances]   # Helps prevent Terraform from modifying instance counts manually.
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic1"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnet1.id
    }

    
  }
}

# --------------------------------------
# Autoscale settings

resource "azurerm_monitor_autoscale_setting" "autoscale-rule1" {
  name                = "autoscale-rule1"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.vmss1.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 3
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss1.id
        time_grain         = "PT5M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
        metric_namespace   = "microsoft.compute/virtualmachinescalesets"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.vmss1.id
        time_grain         = "PT5M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  predictive {
    scale_mode      = "Enabled"
    look_ahead_time = "PT5M"
  }

}

# -------------------------------------------------
# NSG

resource "azurerm_network_security_group" "nsg1" {
  name                = "acceptanceTestSecurityGroup1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
    security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

      security_rule {
    name                       = "allow-http"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_subnet_network_security_group_association" "nsg-association-1" {
  subnet_id                 = azurerm_subnet.subnet1.id
  network_security_group_id = azurerm_network_security_group.nsg1.id
}


# -------------------------------
# Load Balancer

resource "azurerm_public_ip" "pubip-lb" {
  name                = "pubip-lb"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  allocation_method   = "Static"
}

resource "azurerm_lb" "lbtest" {
  name                = "TestLoadBalancer"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.pubip-lb.id
  }
}

# ------
# LB Probe

resource "azurerm_lb_probe" "probe1" {
  loadbalancer_id = azurerm_lb.lbtest.id
  name            = "ssh-running-probe"
  port            = 22
  protocol = "Tcp"
}


resource "azurerm_lb_rule" "lbrule1" {
  loadbalancer_id                = azurerm_lb.lbtest.id
  name                           = "LBRule-SSH"
  protocol                       = "Tcp"
  frontend_port                  = 22
  backend_port                   = 22
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_rule" "lbrule2" {
  loadbalancer_id                = azurerm_lb.lbtest.id
  name                           = "LBRule-HTTPS"
  protocol                       = "Tcp"
  frontend_port                  = 443
  backend_port                   = 443
  frontend_ip_configuration_name = "PublicIPAddress"
}

resource "azurerm_lb_rule" "lbrule3" {
  loadbalancer_id                = azurerm_lb.lbtest.id
  name                           = "LBRule-HTTP"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
}

