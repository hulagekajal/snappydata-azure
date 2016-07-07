# SnappyData on Azure
Automated SnappyData deployment on Microsoft Azure Cloud

# Example of using Azure CLI to deploy the template
```
azure group create --name avsnappydata1 --location westus
azure group deployment create --resource-group avsnappydata1 --name mainTemplate --template-file mainTemplate.json
```