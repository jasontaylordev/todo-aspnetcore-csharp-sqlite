param location string = resourceGroup().location
param tags object = {}
param logAnalyticsName string = ''
param applicationInsightsName string = ''
param applicationInsightsDashboardName string = ''
param appServicePlanName string
param appServiceName string

param serviceName string = 'web'

module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: logAnalyticsName
    applicationInsightsName: applicationInsightsName
    applicationInsightsDashboardName: applicationInsightsDashboardName
  }
}

module appServicePlan 'core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  params: {
    name: appServicePlanName
    location: location
    tags: tags
    reserved: true
    sku: {
      name: 'B1'
    }
    kind: 'linux'
  }
}

module web 'core/host/appservice.bicep' = {
  name: 'web'
  params: {
    name: appServiceName
    location: location
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'dotnetcore'
    runtimeVersion: '8.0'
    tags: union(tags, { 'azd-service-name': serviceName })
  }
}
