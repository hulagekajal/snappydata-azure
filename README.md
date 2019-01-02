# SnappyData on Azure
Automated SnappyData deployment on Microsoft Azure Cloud

# Deploy via the Azure portal UI
```
<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fsnappydatainc%2Fsnappy-cloud-tools%2Fmaster%2Fazure%2FmainTemplate.json">
<img src="https://camo.githubusercontent.com/9285dd3998997a0835869065bb15e5d500475034/687474703a2f2f617a7572656465706c6f792e6e65742f6465706c6f79627574746f6e2e706e67" data-canonical-src="http://azuredeploy.net/deploybutton.png" style="max-width:100%;">
</a>
```
```
Fill the ARM template
```
```
Click on Purchase
```
# Deployment Template
```
Artifacts Base Url : Base URL for artifacts such as nested templates and scripts
```
```
Location : Location for the deployment
```
```
Cluster Name : Cluster name consisting of 2-4 lowercase letter and numbers
```
```
DNS Name Prefix : Globally unique DNS name
```
```
Admin Username : Username for administrator
```
```
Authentication Type : Authentication type for the virtual machines(Password/ SSh Public Key)
```
```
Admin Password : Password for administrator
```
```
Ssh Public Key : SSH public key that will be included on all nodes in the cluster. The OpenSSH public key can be generated with tools like ssh-keygen on Linux or OS X.
```
```
Locator Vm Size : VM size for Locator
```
```
Locator Node Count : The number of virtual machines instances to provision for the locator nodes
```
```
Lead And Data Store Vm Size : VM size for Lead and DataStore
```
```
Data Store Node Count : The number of virtual machines instances to provision for the DataStore nodes
```
```
Lead Node Count : The number of virtual machines instances to provision for the Lead nodes
```
```
Launch Zeppelin : Want to launch Snappydata with Zeppelin(yes/no)
```
```
Allowed IP Address Prefix : The IP address range that can be used to access the instances
```
```
Conf For Lead : Configuration Parameters for Lead
```
```
Conf For Locator : Configuration Parameters for Locator
```
```
Conf For Data Store : Configuration Parameters for DataStore
```
```
Snappydata Download URL : URL of Snappydata distribution to use. Uses the latest release from GitHub, if not specified
```

# mainTemplate.json

It is Divided into 4 Sections :

1) Parameters : Code for Defining fields and their default and applicable values inside the template.

2) Variables : Necessary Variables declared inside this section.

3) Resources : This section defines various resources which will be deployed as Vms in deployment process.( E.g., Virtual machines, Network Interfaces, Virtual Machine Extensions, Network Security Groups,etc.)

4) Outputs : This section defines specific outputs for quick access to the Snappydata DashBoard, creating a client connection, Snappydata JDBC connection.

# init.sh

This file contains code for launching Snappydata Processes depending on the node type (Lead/Locator/DataStore) also it launches zeppelin if zepplin option is enabled. 


# Deploy using Azure CLI
```
azure account login
```
```
azure account set "My Subscription"
```
```
azure group list
```
```
azure group create --name avsnappydata1 --location westus
```
```
azure group deployment create --resource-group avsnappydata1 --name mainTemplate --template-file mainTemplate.json
```

# Copy data to Azure Storage using Azure CLI
azure storage blob copy start --source-uri "https://templocistorage.blob.core.windows.net/snappydata/scripts.tgz" --dest-account-name "sdtests" --dest-account-key "" --dest-container "testdata" --dest-blob "scripts.tgz"

azure storage blob copy start --source-uri "https://templocistorage.blob.core.windows.net/snappydata/TPCH-1GB.zip" --dest-account-name "sdtests" --dest-account-key "" --dest-container "testdata" --dest-blob "TPCH-1GB.zip"

azure storage blob copy start --source-uri "https://templocistorage.blob.core.windows.net/snappydata/snappy-cluster_2.10-0.5-tests.jar" --dest-account-name "sdtests" --dest-account-key "" --dest-container "testdata" --dest-blob "snappy-cluster_2.10-0.5-tests.jar"

azure storage blob copy start --source-uri "https://templocistorage.blob.core.windows.net/snappydata/zeppelin.tgz" --dest-account-name "sdtests" --dest-account-key "" --dest-container "testdata" --dest-blob "zeppelin.tgz"





