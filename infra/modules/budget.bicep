// Presupuesto mensual del resource group con alertas por correo.

param amount int
param startDate string
param alertEmail string

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'budget-conversations'
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
    }
    notifications: {
      actual80: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
      }
      actual100: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: [alertEmail]
      }
    }
  }
}
