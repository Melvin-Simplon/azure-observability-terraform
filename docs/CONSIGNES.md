# Lab — Azure Observability Stack

> **Prerequisites**: Terraform lab completed (App Service, Function App, Storage Account deployed).
> **Format**: groups of 3-4 people, each group monitors its own infrastructure.
> **Duration**: 6h

| Step | Content | Duration |
|---|---|---|
| 0 | Deploy the code (App Service + Function App) | 30 min |
| 1 | `observability` module (Log Analytics + App Insights + Alerts) | 2h |
| 2 | Wire it into main.tf + apply | 30 min |
| 3 | Azure Monitor Workbooks dashboards | 1h |
| 4 | War Room, live incidents | 1h |
| 5 | Post-mortem + presentation | 30 min |

---

## Context

Your infrastructure is running in "production". But how do you know it is healthy?

Picture this: it is 3 a.m. and an alert wakes you up. The app is not responding. Is the App Service crashing? Is the Function App stuck in a loop? Is the Storage Account saturated? Without observability you are flying blind: you open the Azure portal, you hunt for logs scattered across 5 different resources, and meanwhile users keep hitting errors.

Observability means building, **before** the incident, the visibility you will need **during** the incident. It is a core SRE (Site Reliability Engineering) principle: you cannot make reliable what you do not measure.

You are going to instrument your infrastructure with a full stack, deployed entirely through Terraform. At the end of the day the instructor will trigger incidents. Your group must detect them, diagnose them, and write a post-mortem.

---

## Target architecture

```
App Service + Function App + Storage Account
        │
        ▼ Diagnostic Settings (logs + metrics)
┌───────────────────────────┐
│  Log Analytics Workspace  │ ◄── centralized source of truth
└───────────────────────────┘
        │
        ├──► Application Insights  (traces, exceptions, perf)
        ├──► Azure Monitor Alerts  → Action Group → email
        └──► Monitor Workbooks     (dashboards)
```

---

## Step 0 — Deploy the code *(30 min)*

The `app/` folder contains a Flask application with routes designed for monitoring:

| Route | Behavior | Purpose |
|---|---|---|
| `GET /` | 200 Hello World | nominal traffic |
| `GET /health` | 200 JSON | health check |
| `GET /error` | 500 error | trigger the Http5xx alerts |
| `GET /slow` | 200 after 3s | trigger the response time alert |
| `GET /crash` | Python exception | test Application Insights exceptions |

### Deploy to the App Service

```bash
cd tp-observability/app

# Create the zip (code only, leaves the Terraform infrastructure untouched)
zip -r ../app.zip .

# Deploy
az webapp deployment source config-zip \
  --name <your-app-service-name> \
  --resource-group <your-rg> \
  --src ../app.zip
```

> ⚠️ Azure runs `pip install -r requirements.txt` automatically when it receives the zip (via Oryx). The first deployment can take 5-10 min.

> ⚠️ If the app returns 404 after deployment, set the startup command:
> ```bash
> az webapp config set --name <app> --resource-group <rg> \
>   --startup-file "gunicorn --bind=0.0.0.0:8000 app:app"
> ```

Check that it runs:
```bash
curl https://<your-app>.azurewebsites.net/health
# → {"status": "ok"}
```

### Enable the Azure Health Check in the Terraform modules

> 💼 **In production**: an App Service instance can end up in a zombie state, answering TCP pings while the application no longer works. Without a health check, Azure keeps sending traffic to that broken instance, and one request out of N fails silently. With `health_check_path`, Azure detects the sick instance within 10 min and pulls it out of the load balancer automatically, no human intervention needed.

Wire the health check into your Terraform modules:

**`modules/app-service/main.tf`**, inside the `site_config` block of `azurerm_linux_web_app`:

```hcl
site_config {
  # ... existing config ...

  health_check_path                 = "/health"        # existing Flask route
  health_check_eviction_time_in_min = 10
}
```

**`modules/function-app/main.tf`**, inside the `site_config` block of `azurerm_linux_function_app`:

```hcl
site_config {
  # ... existing config ...

  health_check_path                 = "/api/http_trigger"   # the Function App has no /health
  health_check_eviction_time_in_min = 10
}
```

Also expose `default_hostname` as an output in each module (the observability module will use it):

In `modules/app-service/outputs.tf`:
```hcl
output "default_hostname" {
  value = azurerm_linux_web_app.app.default_hostname
}
```

In `modules/function-app/outputs.tf`:
```hcl
output "default_hostname" {
  value = azurerm_linux_function_app.func.default_hostname
}
```

Run `terraform apply` to update the resources.

### Deploy to the Function App

```bash
cd tp-observability/function

# Install Azure Functions Core Tools if not already done
npm install -g azure-functions-core-tools@4

# Deploy
func azure functionapp publish <your-function-app-name>
```

Check:
```bash
curl "https://<your-function>.azurewebsites.net/api/http_trigger?name=Simplon"
# → Hello, Simplon! La Function App fonctionne.
```

---

## Step 1 — `observability` module *(2h)*

Create `terraform/modules/observability/` in your repo.

### variables.tf

```hcl
variable "owner"               { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "tags"                { type = map(string) }

variable "app_service_id"     { type = string }
variable "function_app_id"    { type = string }
variable "storage_account_id" { type = string }

variable "app_service_url"    { type = string }  # e.g. "https://app-xxx.azurewebsites.net"
variable "function_app_url"   { type = string }  # e.g. "https://func-xxx.azurewebsites.net"

variable "alert_email"        { type = string }
```

### main.tf — to complete

---

#### TODO (1/5) — Log Analytics Workspace

> 💼 **In production**: during an incident, logs are scattered across the App Service, the Function App, the Storage Account, and so on. Without centralization you spend 30 min searching and correlating by hand. The Log Analytics Workspace (LAW) is the single funnel: every resource sends its logs and metrics there, and you query all of it with one query language (KQL). It is the foundation of all Azure observability.

```hcl
# resource "azurerm_log_analytics_workspace" "law" {
#   name                = "law-${var.owner}-tf"
#   resource_group_name = ???
#   location            = ???
#   sku                 = "PerGB2018"
#   retention_in_days   = 30
#   tags                = ???
# }
```

Documentation: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace

---

#### TODO (2/5) — Application Insights

> 💼 **In production**: a user calls to say "your app has been slow since this morning". Without an APM (Application Performance Monitoring), you have no idea which route is slow, whether a Storage call is dragging, or whether an exception keeps repeating. Application Insights instruments your code and gives you: response time route by route, exceptions with the full stack trace, calls to dependencies (Storage, external APIs) and their latency. It is the difference between "something is broken" and "the /api/orders route calls the Storage Account and waits 8 seconds every time".

Create **two** Application Insights: one for the App Service, one for the Function App.

```hcl
# resource "azurerm_application_insights" "app" {
#   name                = "appi-app-${var.owner}-tf"
#   resource_group_name = ???
#   location            = ???
#   workspace_id        = ???   # ID of the Log Analytics Workspace
#   application_type    = "web"
#   tags                = ???
# }

# resource "azurerm_application_insights" "func" {
#   name                = "appi-func-${var.owner}-tf"
#   ...
# }
```

> 💡 The `workspace_id` field links Application Insights to the Log Analytics Workspace ("workspace-based" mode). Without it, the data stays isolated inside Application Insights and you cannot cross-reference it with the system logs in the LAW.

Documentation: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights

---

#### TODO (3/5) — Diagnostic Settings

> 💼 **In production**: the Storage Account returns 503 errors. Is it a quota, network, or configuration problem? Without Diagnostic Settings, each resource's metrics stay local to that resource. With them, everything lands in the LAW and you can write a KQL query that correlates Storage errors with App Service request spikes to see whether the app is saturating the storage.

Send logs and metrics to the Log Analytics Workspace for **every** resource.

```hcl
# resource "azurerm_monitor_diagnostic_setting" "app_service" {
#   name                       = "diag-app-${var.owner}"
#   target_resource_id         = var.app_service_id
#   log_analytics_workspace_id = ???
#
#   metric {
#     category = "AllMetrics"
#   }
# }

# Do the same for function_app_id
# and for "${var.storage_account_id}/blobServices/default" (storage blob)
```

> ⚠️ For the Storage Account, `target_resource_id` targets the blob sub-service:
> `"${var.storage_account_id}/blobServices/default"`

Documentation: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting

---

#### TODO (4/5) — Availability Tests

> 💼 **In production**: your team gets reports from users in Belgium saying "the app is not responding". From your desk in Paris, everything works. Without a multi-region availability test you never detect this kind of problem, you have to wait for a user to complain. The availability test pings `/health` from 3 different Azure regions every 5 minutes. If 2 regions fail, you get a Critical alert. You immediately know the problem is geographic (CDN, network routing) and not applicative.
>
> This is also the difference with the `health_check_path` from step 0: the health check watches the **internal instances** (is the instance responding inside the cluster?), the availability test watches **reachability from the internet** (is the app accessible to a real user?).

```hcl
# resource "azurerm_application_insights_standard_availability_test" "app_health" {
#   name                    = "avail-app-${var.owner}"
#   resource_group_name     = ???
#   location                = ???
#   application_insights_id = azurerm_application_insights.app.id
#   geo_locations           = ["emea-fr-pra-edge", "emea-nl-ams-azr", "emea-gb-db3-azr"]
#   frequency               = 300   # every 5 minutes
#   timeout                 = 30
#   tags                    = ???
#
#   request {
#     url = "${var.app_service_url}/health"
#   }
#
#   validation_rules {
#     expected_status_code = 200
#   }
# }

# Do the same for var.function_app_url (route /api/http_trigger)
```

Then add an alert on the availability test result:

```hcl
# resource "azurerm_monitor_metric_alert" "app_availability" {
#   name                = "alert-avail-app-${var.owner}"
#   resource_group_name = ???
#   scopes              = [
#     azurerm_application_insights_standard_availability_test.app_health.id,
#     azurerm_application_insights.app.id
#   ]
#   severity    = 0        # Critical
#   frequency   = "PT1M"
#   window_size = "PT5M"
#
#   application_insights_web_test_location_availability_criteria {
#     web_test_id           = azurerm_application_insights_standard_availability_test.app_health.id
#     component_id          = azurerm_application_insights.app.id
#     failed_location_count = 2   # alert if 2 regions out of 3 fail
#   }
#
#   action {
#     action_group_id = azurerm_monitor_action_group.team.id
#   }
# }
```

> ⚠️ An alert on an availability test uses `application_insights_web_test_location_availability_criteria` instead of `criteria`, a different syntax from classic metric alerts.

Documentation: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/application_insights_standard_availability_test

---

#### TODO (5/5) — Action Group + metric alerts

> 💼 **In production**: nobody watches dashboards permanently. Alerts are the automatic safety net between a silent incident and fast detection. Without an alert, you discover problems when users open support tickets, often 30 min to 1h after the incident started. The Action Group defines **who** is notified and **how** (email, SMS, PagerDuty webhook, and so on). Metric alerts define **when** to fire. Together they form the first line of incident response.

An Action Group defines who is notified when an alert fires.

```hcl
# resource "azurerm_monitor_action_group" "team" {
#   name                = "ag-${var.owner}-tf"
#   resource_group_name = ???
#   short_name          = "team"
#
#   email_receiver {
#     name          = "equipe"
#     email_address = var.alert_email
#   }
# }
```

Create **at least 2 metric alerts**. Pick from this list and **justify your thresholds**:

| Resource | Metric | Suggestion | Why this threshold? |
|---|---|---|---|
| App Service | `CpuPercentage` | > 80% over 5 min | Beyond that the app slows down and requests pile up |
| App Service | `Http5xx` | > 5 in 1 min | Occasional errors are normal, a burst is not |
| App Service | `AverageResponseTime` | > 2 seconds | Past 2s the UX degrades and users give up |
| Function App | `FunctionExecutionCount` | = 0 over 10 min | If the Function is never called, either it is down or the trigger is broken |
| Storage Account | `Availability` | < 99.9% | Below 99.9%, Microsoft's SLAs are at stake |

```hcl
# resource "azurerm_monitor_metric_alert" "http5xx" {
#   name                = "alert-http5xx-${var.owner}"
#   resource_group_name = ???
#   scopes              = [var.app_service_id]
#   severity            = 1        # 0=Critical 1=Error 2=Warning
#   frequency           = "PT1M"   # evaluated every 1 min
#   window_size         = "PT5M"   # observation window: 5 min
#
#   criteria {
#     metric_namespace = "Microsoft.Web/sites"
#     metric_name      = "Http5xx"
#     aggregation      = "Total"
#     operator         = "GreaterThan"
#     threshold        = ???
#   }
#
#   action {
#     action_group_id = azurerm_monitor_action_group.team.id
#   }
# }
```

Documentation: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert

---

### outputs.tf

```hcl
output "law_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "app_insights_connection_string" {
  value     = azurerm_application_insights.app.connection_string
  sensitive = true
}

output "func_insights_connection_string" {
  value     = azurerm_application_insights.func.connection_string
  sensitive = true
}
```

---

## Step 2 — Wire it into main.tf *(30 min)*

In `terraform/main.tf`:

```hcl
module "observability" {
  source = "./modules/observability"

  owner               = var.owner
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  tags                = local.tags

  app_service_id     = module.app_service.app_service_id
  function_app_id    = module.function_app.function_app_id
  storage_account_id = module.storage.storage_account_id

  app_service_url  = "https://${module.app_service.default_hostname}"
  function_app_url = "https://${module.function_app.default_hostname}"

  alert_email = "your.email@example.com"
}
```

Next, link Application Insights to the App Service and the Function App through their app settings.

**In `modules/app-service/variables.tf`**, add:
```hcl
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
```

**In `modules/app-service/main.tf`**, inside the `azurerm_linux_web_app` block:
```hcl
app_settings = merge(var.app_settings, {
  "APPLICATIONINSIGHTS_CONNECTION_STRING"      = var.app_insights_connection_string
  "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
})
```

**In `modules/function-app/variables.tf`**, same addition, and in `azurerm_linux_function_app`:
```hcl
app_settings = merge(var.app_settings, {
  "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
})
```

**In `terraform/main.tf`**, pass the connection strings:
```hcl
module "app_service" {
  # ... existing config ...
  app_insights_connection_string = module.observability.app_insights_connection_string
}

module "function_app" {
  # ... existing config ...
  app_insights_connection_string = module.observability.func_insights_connection_string
}
```

> ⚠️ Terraform handles dependencies automatically thanks to the references between modules, no `depends_on` needed.

Run `terraform apply` and check in the portal that the Diagnostic Settings show up on every resource.

---

## Step 3 — Dashboards with Azure Monitor Workbooks *(1h)*

> 💼 **In production**: during an incident, stress and fatigue make you waste precious time writing KQL queries from scratch. A pre-built workbook gives you the critical information in 30 seconds. It is also a communication tool towards managers and clients: a clear dashboard shows the real-time state without them needing access to Azure.

**Workbooks** are native Azure dashboards, free, with no deployment.

In the portal: **Azure Monitor > Workbooks > + New**

Build a workbook with the following panels:

**Panel 1 — App Service CPU (time chart)**
```kusto
AzureMetrics
| where ResourceId contains "<your-app-service-name>"
| where MetricName == "CpuPercentage"
| summarize avg(Average) by bin(TimeGenerated, 5m)
| render timechart
```

**Panel 2 — HTTP 5xx errors**
```kusto
AzureMetrics
| where MetricName == "Http5xx"
| where Total > 0
| summarize sum(Total) by bin(TimeGenerated, 1m)
| render barchart
```

**Panel 3 — Function App executions**
```kusto
AzureMetrics
| where MetricName == "FunctionExecutionCount"
| summarize sum(Total) by bin(TimeGenerated, 5m)
| render timechart
```

**Panel 4 — free choice**
Your group picks a relevant metric and justifies the choice during the presentation.

> 💡 To discover the metrics available in your LAW:
> `AzureMetrics | distinct MetricName | sort by MetricName asc`

Save the workbook in your Resource Group.

---

## Step 4 — War Room 🚨 *(1h)*

The instructor will trigger **2 incidents** on the production infrastructures. For each incident:

**During the incident:**
1. Did your alert fire? How long did it take?
2. What do your dashboards show?
3. What is the probable cause?

**After the incident — Post-mortem (10 lines max):**

| Field | Content |
|---|---|
| What | Description of the incident |
| When | Start / detection / resolution time |
| Impact | What was affected |
| Cause | Root of the problem |
| Fix | What was done to correct it |
| Action | How to prevent it from happening again |

<details>
<summary>🔒 Possible incidents — instructor only</summary>

- **5xx errors**: `hey -n 500 -c 10 https://<app>/error` (or `for i in $(seq 1 100); do curl -s https://<app>/error > /dev/null; done`)
- **Slowness**: `hey -n 50 -c 5 https://<app>/slow` (or `for i in $(seq 1 10); do curl -s https://<app>/slow > /dev/null; done`)
- **Application crash**: `curl https://<app>/crash` repeated → exceptions in Application Insights
- **Dead health check**: set `health_check_path = "/health-dead"` via the portal (App Service > Configuration) → the availability test fails from all 3 regions → Critical alert
- **Function App silence**: turn off a group's Diagnostic Settings via the portal
- **App Service down**: suspend the App Service (scale to 0) via the portal → the availability test drops immediately

</details>

---

## Step 5 — Presentation *(30 min)*

Each group presents in 5 min:
- Architecture of its observability stack
- Justification of the chosen alert thresholds
- Dashboard and what it shows
- What was detected during the war room, and the post-mortem

---

## Deliverables

- Complete `observability` module, clean `terraform plan`, successful `terraform apply`
- At least 2 alerts with justified thresholds
- Azure Monitor workbook with 4 panels (3 mandatory + 1 free)
- Post-mortem of the detected incident

---

## Performance criteria

| Criterion | Expected |
|---|---|
| IaC | 100% of the observability resources in Terraform |
| Coverage | App Service + Function App + Storage instrumented |
| Alerts | Thresholds consistent with the real load, justified orally |
| Dashboard | Readable by someone who does not know the infrastructure |
| Responsiveness | Incident detected in under 10 minutes |
| Post-mortem | Root cause identified and corrective action proposed |
