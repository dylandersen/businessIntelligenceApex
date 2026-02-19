# Business Intelligence Apex

Natural language business intelligence for Salesforce. Ask questions in plain English and get AI-powered analysis of your CRM data.

## What it does

This invocable Apex action translates natural language questions into SOQL queries, executes them as the running user, and returns rich HTML analysis powered by Salesforce's Models API (Gemini).

**Example questions:**
- "How many open opportunities do I have closing in the next 30 days?"
- "What is my total pipeline value this quarter?"
- "Show me my open cases by priority"
- "Compare my open opportunities to my open cases this quarter"

## Features

- **Natural language → SOQL** — Two-pass AI pipeline: first converts your question to validated SOQL, then analyzes the results
- **Schema-aware** — Supports standard objects (Account, Contact, Opportunity, Case, Lead, Task, Event, Campaign, etc.) and dynamically discovers custom objects
- **User context** — Queries run as the current user; "my" and "mine" filter by `OwnerId`
- **Safe by design** — Read-only SELECT queries only, object allowlist, LIMIT enforcement
- **Gen AI function** — Can be invoked from Einstein Copilot, Flows, or Apex

## Requirements

- Salesforce org with **Agentforce Generative AI** enabled
- **Models API** configured (Gemini 3.0 Flash default model)
- API version 62.0+

## Installation

1. Clone this repository
2. Deploy to your org via Salesforce CLI:

   ```bash
   sf project deploy start --source-dir force-app
   ```

3. Add the **Business Intelligence Query** action to a Flow, or invoke from Einstein Copilot

## Project structure

```
force-app/main/default/
├── classes/
│   ├── BusinessIntelligence.cls          # Main invocable class
│   ├── BusinessIntelligence.cls-meta.xml
│   ├── BusinessIntelligenceTest.cls      # Test coverage
│   └── BusinessIntelligenceTest.cls-meta.xml
└── genAiFunctions/
    └── Business_Intelligence_Query/      # Gen AI function metadata
```

## Usage

### From Flow

Add an **Action** element and search for "Business Intelligence Query". Pass the user's question as the `User Query` input.

### From Apex

```apex
BusinessIntelligence.BIRequest req = new BusinessIntelligence.BIRequest();
req.userQuery = 'What deals are closing this month?';

List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
  new List<BusinessIntelligence.BIRequest>{ req }
);

String analysis = results[0].analysisResult;  // HTML analysis
```

## License

MIT
