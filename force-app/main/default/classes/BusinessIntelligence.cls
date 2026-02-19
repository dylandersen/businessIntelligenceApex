public with sharing class BusinessIntelligence {

  // Standard objects with hardcoded detailed schemas in the prompt
  private static final Set<String> STANDARD_BI_OBJECTS = new Set<String>{
    'Account', 'Contact', 'Opportunity', 'Case', 'Lead', 'Task', 'Event',
    'OpportunityLineItem', 'Campaign', 'CampaignMember', 'Contract',
    'OpportunityContactRole', 'User'
  };

  private static final Integer MAX_QUERY_LIMIT = 200;

  @InvocableMethod(
    label='Business Intelligence Query'
    description='Answers business intelligence questions by translating natural language into SOQL queries, executing them as the running user, and providing AI-powered analysis of the results.'
  )
  public static List<BIResult> analyze(List<BIRequest> requests) {
    List<BIResult> results = new List<BIResult>();

    if (requests == null || requests.isEmpty()) {
      BIResult errorResult = new BIResult();
      errorResult.analysisResult = 'No query provided for analysis.';
      results.add(errorResult);
      return results;
    }

    BIRequest request = requests[0];

    if (String.isBlank(request.userQuery)) {
      BIResult errorResult = new BIResult();
      errorResult.analysisResult = 'A question is required for analysis.';
      results.add(errorResult);
      return results;
    }

    try {
      String userId = UserInfo.getUserId();
      String userName = UserInfo.getName();

      // --- Pass 1: NL to SOQL ---
      String schemaContext = buildSchemaContext();
      String nlToSoqlPrompt = buildNLtoSOQLPrompt(request.userQuery, userId, userName, schemaContext);
      String soqlResponse = callModelsAPI(nlToSoqlPrompt);
      List<QueryPlan> plans = parseAndValidateSOQL(soqlResponse);

      if (plans.isEmpty()) {
        BIResult errorResult = new BIResult();
        errorResult.analysisResult = 'Unable to generate a valid query for your question. Please try rephrasing.';
        results.add(errorResult);
        return results;
      }

      // Execute the validated queries
      List<QueryExecution> executions = executeQueries(plans);

      // --- Pass 2: Results to BI Analysis ---
      String analysisPrompt = buildAnalysisPrompt(request.userQuery, userName, executions);
      String htmlResponse = callModelsAPI(analysisPrompt);

      BIResult result = new BIResult();
      result.analysisResult = htmlResponse;
      results.add(result);
      return results;
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Error in BusinessIntelligence.analyze: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
      BIResult errorResult = new BIResult();
      errorResult.analysisResult = 'Error analyzing your question: ' + e.getMessage()
        + '\n\nPlease check debug logs for more details.';
      results.add(errorResult);
      return results;
    }
  }

  // ═══════════════════════════════════════════════
  // Pass 1: NL → SOQL
  // ═══════════════════════════════════════════════

  /**
   * Build schema context: hardcoded standard objects + dynamically discovered custom objects
   */
  private static String buildSchemaContext() {
    List<String> parts = new List<String>();
    parts.add('## SALESFORCE SCHEMA\n\n');

    // --- Hardcoded standard object schemas (detailed fields) ---
    parts.add('### Standard Objects\n\n');

    parts.add('**Account** — Company/organization record\n');
    parts.add('Key fields: Id, Name, Type, Industry, AnnualRevenue, NumberOfEmployees, OwnerId, BillingCity, BillingState, BillingCountry, Phone, Website, Description, CreatedDate, LastModifiedDate, ParentId\n\n');

    parts.add('**Contact** — Individual person record\n');
    parts.add('Key fields: Id, Name, FirstName, LastName, Email, Phone, MobilePhone, Title, Department, AccountId, OwnerId, MailingCity, MailingState, MailingCountry, LeadSource, CreatedDate, LastModifiedDate\n\n');

    parts.add('**Opportunity** — Sales deal record\n');
    parts.add('Key fields: Id, Name, Amount, StageName, Probability, CloseDate, Type, LeadSource, NextStep, Description, AccountId, OwnerId, IsClosed, IsWon, ForecastCategory, ForecastCategoryName, CreatedDate, LastModifiedDate, ExpectedRevenue, CampaignId, ContactId\n');
    parts.add('Common stages: Prospecting, Qualification, Needs Analysis, Value Proposition, Id. Decision Makers, Perception Analysis, Proposal/Price Quote, Negotiation/Review, Closed Won, Closed Lost\n\n');

    parts.add('**Case** — Customer service/support record\n');
    parts.add('Key fields: Id, CaseNumber, Subject, Description, Status, Priority, Type, Origin, AccountId, ContactId, OwnerId, IsClosed, ClosedDate, CreatedDate, LastModifiedDate\n');
    parts.add('Common statuses: New, Working, Escalated, Closed\n');
    parts.add('Common priorities: High, Medium, Low\n\n');

    parts.add('**Lead** — Prospective customer record\n');
    parts.add('Key fields: Id, Name, FirstName, LastName, Company, Title, Email, Phone, Status, LeadSource, Industry, AnnualRevenue, NumberOfEmployees, OwnerId, IsConverted, ConvertedAccountId, ConvertedContactId, ConvertedOpportunityId, CreatedDate, LastModifiedDate\n\n');

    parts.add('**Task** — Activity/to-do record\n');
    parts.add('Key fields: Id, Subject, Status, Priority, ActivityDate, Description, WhoId, WhatId, OwnerId, IsClosed, CreatedDate, CallType, CallDurationInSeconds, TaskSubtype\n\n');

    parts.add('**Event** — Calendar event/meeting record\n');
    parts.add('Key fields: Id, Subject, StartDateTime, EndDateTime, Description, WhoId, WhatId, OwnerId, DurationInMinutes, Location, IsAllDayEvent, CreatedDate\n\n');

    parts.add('**OpportunityLineItem** — Product line on an opportunity\n');
    parts.add('Key fields: Id, OpportunityId, Name, Quantity, UnitPrice, TotalPrice, Description\n\n');

    parts.add('**Campaign** — Marketing campaign record\n');
    parts.add('Key fields: Id, Name, Type, Status, StartDate, EndDate, BudgetedCost, ActualCost, ExpectedRevenue, NumberOfLeads, NumberOfContacts, NumberOfOpportunities, NumberOfWonOpportunities, AmountWonOpportunities, IsActive, OwnerId, CreatedDate\n\n');

    parts.add('**CampaignMember** — Campaign participation record\n');
    parts.add('Key fields: Id, CampaignId, LeadId, ContactId, Status, FirstRespondedDate, CreatedDate\n\n');

    parts.add('**Contract** — Contract/agreement record\n');
    parts.add('Key fields: Id, ContractNumber, AccountId, Status, StartDate, EndDate, ContractTerm, OwnerId, CreatedDate\n\n');

    parts.add('**OpportunityContactRole** — Contact role on an opportunity\n');
    parts.add('Key fields: Id, OpportunityId, ContactId, Role, IsPrimary\n\n');

    parts.add('**User** — Salesforce user record\n');
    parts.add('Key fields: Id, Name, FirstName, LastName, Email, Username, IsActive, UserRoleId, ProfileId, ManagerId, Department, Title, Phone, CreatedDate\n\n');


    // --- Dynamic discovery of custom objects ---
    parts.add('### Custom Objects\n\n');
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
    Integer customCount = 0;
    for (String objName : globalDescribe.keySet()) {
      if (objName.endsWith('__c') && customCount < 30) {
        Schema.DescribeSObjectResult describeResult = globalDescribe.get(objName).getDescribe();
        if (describeResult.isQueryable() && describeResult.isAccessible()) {
          parts.add('**' + objName + '** — ' + describeResult.getLabel() + '\n');
          customCount++;
        }
      }
    }
    if (customCount == 0) {
      parts.add('No custom objects found.\n');
    }

    return String.join(parts, '');
  }

  /**
   * Build the NL-to-SOQL prompt for Pass 1
   */
  private static String buildNLtoSOQLPrompt(String userQuery, String userId,
                                             String userName, String schemaContext) {
    List<String> parts = new List<String>();

    parts.add('You are a Salesforce SOQL expert. Your ONLY job is to convert a natural language question into one or more SOQL queries.\n\n');

    parts.add('## RULES\n');
    parts.add('1. Generate ONLY SELECT queries. Never generate INSERT, UPDATE, DELETE, or UPSERT.\n');
    parts.add('2. Every query MUST include a LIMIT clause. Maximum LIMIT is ' + MAX_QUERY_LIMIT + '.\n');
    parts.add('3. Only query objects from the schema provided below.\n');
    parts.add('4. Use the running user\'s ID for "my" queries (e.g., WHERE OwnerId = \'' + userId + '\').\n');
    parts.add('5. Today\'s date is ' + Date.today().format() + '. Use this for relative date calculations.\n');
    parts.add('6. For date ranges, prefer Salesforce date literals when possible: TODAY, YESTERDAY, THIS_WEEK, LAST_WEEK, THIS_MONTH, LAST_MONTH, THIS_QUARTER, LAST_QUARTER, THIS_YEAR, LAST_YEAR, NEXT_N_DAYS:n, LAST_N_DAYS:n, NEXT_N_MONTHS:n, LAST_N_MONTHS:n.\n');
    parts.add('7. Use aggregate functions (COUNT, SUM, AVG, MIN, MAX) with GROUP BY when the question asks for totals, averages, or grouped data.\n');
    parts.add('8. For questions requiring data from multiple objects, generate multiple queries.\n');
    parts.add('9. Always include relevant fields that help answer the question — don\'t just return IDs.\n');
    parts.add('10. Prefer ORDER BY on relevant fields (e.g., CloseDate, Amount, CreatedDate) to surface the most useful data.\n');
    parts.add('11. Do NOT use SOQL reserved words as aliases.\n');
    parts.add('12. For Opportunity stages use the exact stage names from the schema.\n');
    parts.add('13. IMPORTANT — ALWAYS PAIR detail queries with aggregate counts:\n');
    parts.add('    For EVERY detail SELECT query you generate, ALSO generate a matching COUNT() aggregate query with the same WHERE clause.\n');
    parts.add('    Example: if you write SELECT Name, Amount FROM Opportunity WHERE OwnerId = \'...\' AND IsClosed = false LIMIT 200,\n');
    parts.add('    also write SELECT COUNT() FROM Opportunity WHERE OwnerId = \'...\' AND IsClosed = false\n');
    parts.add('    The detail query is capped at 200 rows, but the COUNT gives the TRUE total across all records.\n');
    parts.add('    Put the COUNT query FIRST so the analyst sees the accurate total before the detail rows.\n');
    parts.add('    For grouped aggregates (SUM/AVG with GROUP BY), a separate COUNT is not needed.\n\n');

    parts.add('## RUNNING USER CONTEXT\n');
    parts.add('- User ID: ' + userId + '\n');
    parts.add('- User Name: ' + userName + '\n');
    parts.add('- When the user says "my", "mine", or "I", filter by OwnerId = \'' + userId + '\'\n\n');

    parts.add(schemaContext);

    parts.add('\n## USER QUESTION\n');
    parts.add(userQuery + '\n\n');

    parts.add('## OUTPUT FORMAT\n');
    parts.add('Return ONLY a JSON object with no additional text, no markdown code blocks, no explanation. Format:\n');
    parts.add('{"queries":[{"purpose":"Brief description of what this query answers","soql":"SELECT ... FROM ... WHERE ... LIMIT ..."}]}\n');

    return String.join(parts, '');
  }

  /**
   * Parse LLM response and validate each SOQL query
   */
  private static List<QueryPlan> parseAndValidateSOQL(String llmResponse) {
    List<QueryPlan> plans = new List<QueryPlan>();

    if (String.isBlank(llmResponse)) {
      return plans;
    }

    // Strip markdown code blocks if present
    String cleaned = llmResponse.trim();
    if (cleaned.startsWith('```')) {
      Integer firstNewline = cleaned.indexOf('\n');
      if (firstNewline > 0) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.lastIndexOf('```'));
      }
      cleaned = cleaned.trim();
    }

    // Parse JSON
    try {
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
      List<Object> queries = (List<Object>) parsed.get('queries');

      if (queries == null || queries.isEmpty()) {
        return plans;
      }

      // Build set of all allowed objects (standard + custom)
      Set<String> allowedObjects = new Set<String>();
      for (String obj : STANDARD_BI_OBJECTS) {
        allowedObjects.add(obj.toLowerCase());
      }
      Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
      for (String objName : globalDescribe.keySet()) {
        if (objName.endsWith('__c')) {
          allowedObjects.add(objName.toLowerCase());
        }
      }

      for (Object q : queries) {
        Map<String, Object> queryMap = (Map<String, Object>) q;
        String purpose = (String) queryMap.get('purpose');
        String soql = (String) queryMap.get('soql');

        if (String.isBlank(soql)) {
          continue;
        }

        soql = soql.trim();

        // Validate: must start with SELECT
        if (!soql.toUpperCase().startsWith('SELECT')) {
          System.debug(LoggingLevel.WARN, 'Rejected non-SELECT query: ' + soql);
          continue;
        }

        // Validate: extract FROM object and check allowlist
        String upperSoql = soql.toUpperCase();
        Integer fromIndex = upperSoql.indexOf(' FROM ');
        if (fromIndex < 0) {
          System.debug(LoggingLevel.WARN, 'Rejected query without FROM: ' + soql);
          continue;
        }

        String afterFrom = soql.substring(fromIndex + 6).trim();
        // Object name is the first token after FROM
        String objectName = afterFrom.split('\\s+')[0].trim();
        // Remove trailing comma or parenthesis if any
        objectName = objectName.replaceAll('[,\\(\\)]', '');

        if (!allowedObjects.contains(objectName.toLowerCase())) {
          System.debug(LoggingLevel.WARN, 'Rejected query for non-allowed object: ' + objectName);
          continue;
        }

        // Check if this is an aggregate query without GROUP BY
        // (e.g., SELECT COUNT(Id) FROM ... — these cannot have LIMIT)
        Boolean isNonGroupedAggregate = hasAggregateFunction(upperSoql)
          && !upperSoql.contains(' GROUP BY ');

        if (isNonGroupedAggregate) {
          // Remove LIMIT if present — SOQL forbids LIMIT on non-grouped aggregates
          Pattern limitPattern = Pattern.compile('(?i)\\s+LIMIT\\s+\\d+');
          soql = limitPattern.matcher(soql).replaceAll('');
        } else if (!upperSoql.contains(' LIMIT ')) {
          // Non-aggregate query: enforce LIMIT if missing
          soql = soql + ' LIMIT ' + MAX_QUERY_LIMIT;
        } else {
          // Non-aggregate query with LIMIT: ensure it doesn't exceed max
          Pattern limitPattern = Pattern.compile('(?i)LIMIT\\s+(\\d+)');
          Matcher limitMatcher = limitPattern.matcher(soql);
          if (limitMatcher.find()) {
            Integer existingLimit = Integer.valueOf(limitMatcher.group(1));
            if (existingLimit > MAX_QUERY_LIMIT) {
              soql = soql.substring(0, limitMatcher.start()) + 'LIMIT ' + MAX_QUERY_LIMIT
                + soql.substring(limitMatcher.end());
            }
          }
        }

        QueryPlan plan = new QueryPlan();
        plan.purpose = String.isNotBlank(purpose) ? purpose : 'Query';
        plan.soql = soql;
        plans.add(plan);
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Error parsing SOQL JSON: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Raw LLM response: ' + llmResponse);
    }

    return plans;
  }

  /**
   * Check if a SOQL query (uppercased) uses aggregate functions
   */
  private static Boolean hasAggregateFunction(String upperSoql) {
    // Match aggregate functions: COUNT(...), COUNT(), SUM(...), AVG(...), MIN(...), MAX(...)
    return Pattern.compile('\\b(COUNT|SUM|AVG|MIN|MAX)\\s*\\(').matcher(upperSoql).find();
  }

  /**
   * Execute validated SOQL queries as the running user
   */
  private static List<QueryExecution> executeQueries(List<QueryPlan> plans) {
    List<QueryExecution> executions = new List<QueryExecution>();

    for (QueryPlan plan : plans) {
      QueryExecution exec = new QueryExecution();
      exec.purpose = plan.purpose;
      exec.soql = plan.soql;

      try {
        // SELECT COUNT() FROM ... requires Database.countQuery(), not Database.query()
        String upperSoql = plan.soql.trim().toUpperCase();
        if (upperSoql.startsWith('SELECT COUNT()')) {
          Integer countResult = Database.countQuery(plan.soql, AccessLevel.USER_MODE);
          exec.results = new List<SObject>();
          exec.countResult = countResult;
          exec.error = null;
          exec.limitReached = false;
        } else {
          exec.results = Database.query(plan.soql, AccessLevel.USER_MODE);
          exec.countResult = null;
          exec.error = null;
          // Detect if we hit the LIMIT cap — actual total may be higher
          exec.limitReached = (exec.results.size() == MAX_QUERY_LIMIT);
        }
      } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Query execution error: ' + e.getMessage() + ' | SOQL: ' + plan.soql);
        exec.results = new List<SObject>();
        exec.countResult = null;
        exec.error = e.getMessage();
        exec.limitReached = false;
      }

      executions.add(exec);
    }

    return executions;
  }

  // ═══════════════════════════════════════════════
  // Pass 2: Results → BI Analysis
  // ═══════════════════════════════════════════════

  /**
   * Build the analysis prompt for Pass 2
   */
  private static String buildAnalysisPrompt(String userQuery, String userName,
                                             List<QueryExecution> executions) {
    List<String> parts = new List<String>();

    parts.add('You are a senior business analyst working inside a Salesforce CRM. '
      + 'A sales or service professional named ' + userName + ' asked a business intelligence question. '
      + 'You have access to the query results below. Provide a rich, insightful analysis.\n\n');

    parts.add('**Today\'s date:** ' + Datetime.now().format('MMMM d, yyyy') + '\n\n');

    parts.add('## ORIGINAL QUESTION\n');
    parts.add(userQuery + '\n\n');

    parts.add('## QUERY RESULTS\n\n');

    Boolean hasAnyResults = false;
    for (QueryExecution exec : executions) {
      parts.add('### ' + exec.purpose + '\n');
      parts.add('**Query:** `' + exec.soql + '`\n');

      if (String.isNotBlank(exec.error)) {
        parts.add('**Error:** ' + exec.error + '\n\n');
        continue;
      }

      // Handle COUNT() queries — they return a single integer, not rows
      if (exec.countResult != null) {
        hasAnyResults = true;
        parts.add('**Total Count:** ' + exec.countResult + '\n\n');
        continue;
      }

      if (exec.results == null || exec.results.isEmpty()) {
        parts.add('**Results:** No records found.\n\n');
        continue;
      }

      hasAnyResults = true;
      if (exec.limitReached) {
        parts.add('**Results:** ' + exec.results.size() + ' record(s) shown (display cap reached — use the COUNT query above for the accurate total)\n');
      } else {
        parts.add('**Results:** ' + exec.results.size() + ' record(s)\n');
      }

      // Serialize results to a readable format
      for (Integer i = 0; i < Math.min(exec.results.size(), MAX_QUERY_LIMIT); i++) {
        Map<String, Object> fields = exec.results[i].getPopulatedFieldsAsMap();
        List<String> fieldParts = new List<String>();
        for (String fieldName : fields.keySet()) {
          Object val = fields.get(fieldName);
          if (val instanceof SObject) {
            // Handle relationship fields (e.g., Account.Name)
            Map<String, Object> relFields = ((SObject) val).getPopulatedFieldsAsMap();
            for (String relField : relFields.keySet()) {
              fieldParts.add(fieldName + '.' + relField + ': ' + String.valueOf(relFields.get(relField)));
            }
          } else {
            fieldParts.add(fieldName + ': ' + String.valueOf(val));
          }
        }
        parts.add((i + 1) + '. ' + String.join(fieldParts, ' | ') + '\n');
      }
      parts.add('\n');
    }

    // Output format instructions
    parts.add('## OUTPUT FORMAT\n\n');
    parts.add('**CRITICAL:** Return clean, compact HTML. No markdown. No code blocks. No extra blank lines between tags.\n\n');

    parts.add('**VOICE & TONE:**\n');
    parts.add('- You are a helpful business analyst talking to a colleague. Be warm, direct, and insightful.\n');
    parts.add('- Address the user by first name (' + userName.split(' ')[0] + ').\n');
    parts.add('- Write in plain business English. Sound like a smart coworker, not a database.\n');
    parts.add('- Focus on WHAT the data means and WHY it matters, not HOW you got the data.\n\n');

    parts.add('**ABSOLUTELY DO NOT INCLUDE:**\n');
    parts.add('- Salesforce record IDs (e.g., 005Hu00000...) — never show IDs to the user\n');
    parts.add('- Field API names (e.g., TaskSubtype, OwnerId, StageName) — use plain English equivalents\n');
    parts.add('- SOQL date literals (e.g., LAST_MONTH, NEXT_N_DAYS) — use real dates and natural language\n');
    parts.add('- Query methodology explanations (e.g., "records were filtered by...", "verified under User ID...")\n');
    parts.add('- Any mention of SOQL, queries, the Task object, record types, or filtering logic\n');
    parts.add('- Self-referential commentary about how the analysis was performed\n');
    parts.add('- The word "record" when referring to deals, cases, calls, etc. — say "deal", "case", "call" instead\n\n');

    parts.add('**FORMATTING RULES:**\n');
    parts.add('- Use <b>bold</b> for important numbers, dollar amounts, dates, names, and statuses\n');
    parts.add('- Keep HTML tight — no newlines between tags. Write tags inline: <h2>Title</h2><ul><li>Item</li></ul>\n');
    parts.add('- Use <hr/> sparingly — only between major sections\n');
    parts.add('- Keep bullet points concise — 1 line each, no paragraphs inside list items\n\n');

    parts.add('**REQUIRED STRUCTURE:**\n\n');

    if (!hasAnyResults) {
      parts.add('<h1>Title</h1>');
      parts.add('<p>[Explain that no matching data was found. Suggest alternative questions the user could try.]</p>');
    } else {
      parts.add('<h1>[Short title summarizing the answer]</h1>');
      parts.add('<p>[1-2 sentence summary directly answering the question with key numbers bolded]</p>');
      parts.add('<hr/>');
      parts.add('<h2>Key Findings</h2>');
      parts.add('<ul>');
      parts.add('<li>[Insight about the data — what stands out, what matters]</li>');
      parts.add('<li>[Another insight with specific numbers bolded]</li>');
      parts.add('<li>[Third insight if applicable]</li>');
      parts.add('</ul>');
      parts.add('<hr/>');
      parts.add('<h2>Detailed Breakdown</h2>');
      parts.add('[Present the actual data the user asked about. Use the most natural format:');
      parts.add(' - Lists of items: <ul> with each as a <li>');
      parts.add(' - Comparisons: side-by-side');
      parts.add(' - Prioritization: ranked with rationale');
      parts.add('Include names, amounts, dates, stages — the details that help the user take action.]');
      parts.add('<hr/>');
      parts.add('<h2>Recommendations</h2>');
      parts.add('<ul>');
      parts.add('<li>[Specific action the user should take based on the data]</li>');
      parts.add('<li>[Another action — omit if not applicable]</li>');
      parts.add('</ul>');
    }

    parts.add('\nFINAL REMINDERS:\n');
    parts.add('- HTML only. No markdown. No code blocks.\n');
    parts.add('- No inline CSS, no <div> tags, no class attributes.\n');
    parts.add('- No fabricated data — only reference what is in the query results.\n');
    parts.add('- Replace ALL [placeholder] text with real analysis.\n');
    parts.add('- NEVER expose technical details (IDs, field names, query logic) to the user.\n');
    parts.add('- Be specific with real numbers, names, and dates from the data.\n');

    return String.join(parts, '');
  }

  // ═══════════════════════════════════════════════
  // Models API
  // ═══════════════════════════════════════════════

  /**
   * Calls the Salesforce Models API (Gemini 3.0 Flash)
   */
  private static String callModelsAPI(String promptText) {
    try {
      String modelName = 'sfdc_ai__DefaultVertexAIGemini30Flash';

      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = modelName;

      aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
      request.body = requestBody;
      requestBody.prompt = promptText;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request);

      if (response.Code200 != null && response.Code200.generation != null) {
        return response.Code200.generation.generatedText;
      } else {
        return 'No response received from AI. Please verify Agentforce Generative AI is enabled in your org.';
      }
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      System.debug(LoggingLevel.ERROR, 'Models API Response Exception: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Response code: ' + e.responseCode);
      return 'Error during AI analysis: ' + e.getMessage()
        + '\n\nPlease ensure Agentforce AI Models are enabled in Setup.';
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Models API Error: ' + e.getMessage());
      System.debug(LoggingLevel.ERROR, 'Stack Trace: ' + e.getStackTraceString());
      return 'Unexpected error during AI analysis: ' + e.getMessage()
        + '\n\nPlease check debug logs for more details.';
    }
  }

  // ═══════════════════════════════════════════════
  // Inner Classes
  // ═══════════════════════════════════════════════

  public class BIRequest {
    @InvocableVariable(required=true label='User Query')
    public String userQuery;
  }

  public class BIResult {
    @InvocableVariable(label='Analysis Result')
    public String analysisResult;
  }

  private class QueryPlan {
    public String purpose;
    public String soql;
  }

  private class QueryExecution {
    public String purpose;
    public String soql;
    public List<SObject> results;
    public Integer countResult;  // For SELECT COUNT() queries
    public String error;
    public Boolean limitReached;
  }
}
