# Optional Features

## Support multiple environments

The default template includes CI/CD pipeline definitions for a single environment. The Azure Developer CLI supports multiple environments by using the `azd env new` command. This command can be used to create new environments however you will need to manually update the pipeline definitions to support the new environments.

This section will walk you through the steps of extending the pipeline to support multiple environments using GitHub Actions. In general, you will need to:

* Create (`azd env new`) and configure (`azd pipeline config`) new environments
* Add and configure new environments in GitHub
* Reconfigure the Azure federated credentials to use GitHub environments
* Update the GitHub pipeline definition (`./github/workflows/azure-dev.yml`)

### Create and configure new environments

Create and configure new environments for development, staging, and production using `azd`. 

Create and configure the development environment:

```bash
azd env new WebDev
azd pipeline config --auth-type federated --principal-name sp-WebDev
```

Repeat the above command for the staging and production environments. If you run `azd env list`, you should see the following output:

|NAME|DEFAULT|LOCAL|REMOTE|
|----|----|----|----|
|WebDev|false|true|False|
|WebStg|false|true|false|
|WebPrd|true|true|false|

You can see that the `WebPrd` environment is set as the default environment. This means that when you run `azd up`, the resources will be provisioned in the `WebPrd` environment. You can change the default environment by running `azd env set-default <environment-name>`.

### Add and configure new environments in GitHub

The following steps will walk you through the process of adding the new environments to GitHub.

1. Navigate to the GitHub repository and click on the **Settings** tab.
2. Click on **Environments** in the left navigation menu.
3. Click on **New environment**.
4. Enter the name of the environment (e.g. `WebDev`) and click **Configure environment**.

Repeat the above steps for the staging and production environments.

Next, you will need to configure the repository and environment variables. You can review the existing repository variables by clicking on **Secrets and variables**, **Actions**, and then the **Variables** tab. You should see the following variables:

|Name|Value|
|----|----|
|AZURE_CLIENT_ID|00000000-0000-0000-0000-000000000000|
|AZURE_ENV_NAME|WebPrd|
|AZURE_LOCATION|australiaeast|
|AZURE_SUBSCRIPTION_ID|00000000-0000-0000-0000-000000000000|
|AZURE_TENANT_ID|00000000-0000-0000-0000-000000000000|

Delete the `AZURE_CLIENT_ID` and `AZURE_ENV_NAME` variables as they are no longer needed. The `AZURE_CLIENT_ID` will be recreated as an environment variable and the specific environment will be managed using the CI/CD pipeline definition.

Next, you will need to retrieve the `AZURE_CLIENT_ID` for each environment. The `AZURE_CLIENT_ID` represents the service principal that will be used to authenticate with Azure. You can retrieve the service principal ids by running the following command:

```bash
az ad sp list --display-name "sp-Web" --output table
```

You can also retrieve the service principal ids using the Azure Portal:

1. Navigate to the Azure Portal and click on **Microsoft Entra ID**
2. Click on **App Registrations** in the left navigation menu.
3. Select **All Applications**
4. Specify `sp-Web` in the search box

The results listing includes the service principal ids for each environment. Returning to GitHub, you can add the `AZURE_CLIENT_ID` variable for each environment:

1. Navigate to the GitHub repository and click on the **Settings** tab.
2. Click on **Environments** in the left navigation menu.
3. Click on the environment (e.g. `WebDev`) and then click on **Add variable**.
4. Enter `AZURE_CLIENT_ID` for the name and the service principal id for the value.
5. Click **Add varible**.

Repeat the above steps for the staging and production environments.

### Reconfigure the Azure federated credentials to use GitHub environments

The Azure federated credentials are used to authenticate with Azure. The following steps will walk you through the process of reconfiguring the federated credentials to use GitHub environments.

1. Navigate to the Azure Portal and click on **Microsoft Entra ID**
2. Click on **App Registrations** in the left navigation menu.
3. Select **All Applications**
4. Specify `sp-Web` in the search box
5. Select the `sp-WebDev` service principal
6. Click on **Certificates & secrets**
7. Select the **Federated credentials** tab
8. You will see two credentials, one for the main branch and one for pull requests. Open the **main** credential, e.g. **jasontaylordev-todo-aspnetcore-csharp-sqlite-main**
9. Change **Entity type** to `Environment`
10. Set **GitHub environment name** to `WebDev`
11. Click **Update**

Repeat the above steps for the staging and production service principals.

### Update the GitHub pipeline definition

The final step is to update the GitHub pipeline definition to support the new environments. The following steps will walk you through the process of updating the pipeline definition.

Open the GitHub pipeline definition (`./github/workflows/azure-dev.yml`) and update as follows:

```yaml
on:
  workflow_dispatch:
  push:
    # Run when commits are pushed to mainline branch (main or master)
    # Set this to the mainline branch you are using
    branches:
      - main
      - master

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    env:
      AZURE_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Install .NET
        uses: actions/setup-dotnet@v3

      - name: Install azd
        uses: Azure/setup-azd@v0.1.0

      - name: Package Application
        run: azd package web --output-path ./dist/web.zip --environment NONE --no-prompt
        working-directory: ./

      - name: Upload Package
        uses: actions/upload-artifact@v3
        with:
          name: package
          path: ./dist/web.zip
          if-no-files-found: error
```

The above pipeline will use `azd` to package the application and upload the package to GitHub.

> Note: `azd package` requires that an environment is specified. The AZD dev team has advised that this is supplied in case you would like a custom package per environment. You can see I have set this to environment NONE, which of course is an environment that does not exist. I don’t want to create an environment specific package, I want to create one package and deploy it to many environments, each having a specific configuration set. Build once, deploy many.

Next, within the **.github/workflows/** folder create a new file named **deploy.yml** and add the following content:

```yaml
name: Deploy

on:
  workflow_call:
    inputs:
      AZURE_ENV_NAME:
        required: true
        type: string

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ inputs.AZURE_ENV_NAME }}
    env:
      AZURE_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
      AZURE_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
      AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      AZURE_ENV_NAME: ${{ inputs.AZURE_ENV_NAME }}
    steps:
      - name: Checkout
        uses: actions/checkout@v3

      - name: Install .NET
        uses: actions/setup-dotnet@v3

      - name: Install AZD
        uses: Azure/setup-azd@v0.1.0

      - name: Log into Azure
        run: |
          azd auth login `
            --client-id "$Env:AZURE_CLIENT_ID" `
            --federated-credential-provider "github" `
            --tenant-id "$Env:AZURE_TENANT_ID"
        shell: pwsh

      - name: Provision Infrastructure
        run: azd provision --no-prompt
        env:
          AZURE_ENV_NAME: ${{ inputs.AZURE_ENV_NAME }}
          AZURE_LOCATION: ${{ vars.AZURE_LOCATION }}
          AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Download Package
        uses: actions/download-artifact@v3

      - name: Deploy Application
        run: azd deploy web --from-package ./package/web.zip --no-prompt
        env:
          AZURE_ENV_NAME: ${{ inputs.AZURE_ENV_NAME }}
          AZURE_LOCATION: ${{ vars.AZURE_LOCATION }}
          AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

The above code will deploy the application to the specified environment. The `environment` property is used to specify the environment name. The `AZURE_ENV_NAME` environment variable is used to specify the environment name when running `azd provision` and `azd deploy`.

Finally, **azure-dev.yml** to call the **deploy.yml** workflow for each environment:

```yaml
  deploy-development:
    uses: ./.github/workflows/deploy.yml
    secrets: inherit
    needs: [build]
    with:
      AZURE_ENV_NAME: WebDev

  deploy-staging:
    uses: ./.github/workflows/deploy.yml
    secrets: inherit
    needs: [deploy-development]
    with:
      AZURE_ENV_NAME: WebStg

  deploy-production:
    uses: ./.github/workflows/deploy.yml
    secrets: inherit
    needs: [deploy-staging]
    with:
      AZURE_ENV_NAME: WebPrd
```

The CI/CD pipeline is now configured to support multiple environments. You can test the pipeline by pushing a commit to the main branch. In addition, you can still run commands such as `azd up` and `azd down` to provision and delete resources.

## Next steps

At this point, the CI/CD pipeline will deploy the application to the development, staging, and production environments. However, you might like to configure 
[deployment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#deployment-protection-rules) to ensure that deployments to production are only performed after approval.

## Additional resources

* [Azure Developer CLI](https://aka.ms/azure-dev/overview)
* [GitHub Actions](https://docs.github.com/en/actions)
* [GitHub Environments](https://docs.github.com/en/actions/reference/environments)

## Issues

If you run into any issues, please [file an issue](https://github.com/jasontaylordev/todo-aspnetcore-csharp-sqlite/issues).