@isTest
public class BusinessIntelligenceTest {
  @TestSetup
  static void setupTestData() {
    // Create test account
    Account testAccount = new Account(
      Name = 'BI Test Account',
      Industry = 'Technology',
      Type = 'Customer',
      AnnualRevenue = 500000,
      NumberOfEmployees = 100
    );
    insert testAccount;

    // Create test opportunities
    List<Opportunity> opps = new List<Opportunity>();
    opps.add(new Opportunity(
      Name = 'BI Test Opp - Closing Soon',
      AccountId = testAccount.Id,
      Amount = 75000,
      StageName = 'Negotiation/Review',
      CloseDate = Date.today().addDays(15),
      Probability = 80
    ));
    opps.add(new Opportunity(
      Name = 'BI Test Opp - Early Stage',
      AccountId = testAccount.Id,
      Amount = 30000,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(60),
      Probability = 20
    ));
    insert opps;

    // Create test cases
    List<Case> cases = new List<Case>();
    cases.add(new Case(
      Subject = 'BI Test Case - Open',
      Status = 'New',
      Priority = 'High',
      AccountId = testAccount.Id
    ));
    cases.add(new Case(
      Subject = 'BI Test Case - Working',
      Status = 'Working',
      Priority = 'Medium',
      AccountId = testAccount.Id
    ));
    insert cases;

    // Create test tasks
    Task testTask = new Task(
      Subject = 'Follow up with BI Test Account',
      WhatId = opps[0].Id,
      Status = 'Not Started',
      ActivityDate = Date.today().addDays(3),
      Priority = 'High'
    );
    insert testTask;
  }

  @isTest
  static void testAnalyze_ValidQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = 'How many open opportunities do I have closing in the next 30 days?';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(null, results[0].analysisResult, 'Analysis result should not be null');
    System.assert(results[0].analysisResult.length() > 0, 'Analysis result should not be empty');
  }

  @isTest
  static void testAnalyze_EmptyRequest() {
    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>()
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assert(
      results[0].analysisResult.contains('No query provided'),
      'Should return error message for empty request'
    );
  }

  @isTest
  static void testAnalyze_NullRequest() {
    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(null);
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assert(
      results[0].analysisResult.contains('No query provided'),
      'Should return error message for null request'
    );
  }

  @isTest
  static void testAnalyze_BlankQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = '';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assert(
      results[0].analysisResult.contains('question is required'),
      'Should return error message for blank query'
    );
  }

  @isTest
  static void testAnalyze_NullQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = null;

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assert(
      results[0].analysisResult.contains('question is required'),
      'Should return error message for null query'
    );
  }

  @isTest
  static void testAnalyze_PipelineQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = 'What is my total pipeline value this quarter?';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(null, results[0].analysisResult, 'Analysis result should not be null');
  }

  @isTest
  static void testAnalyze_CaseQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = 'Show me my open cases by priority';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(null, results[0].analysisResult, 'Analysis result should not be null');
  }

  @isTest
  static void testAnalyze_CrossObjectQuery() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = 'Compare my open opportunities to my open cases this quarter';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(null, results[0].analysisResult, 'Analysis result should not be null');
  }

  @isTest
  static void testAnalyze_Top15OpenCasesWithOpportunityCorrelation() {
    BusinessIntelligence.BIRequest request = new BusinessIntelligence.BIRequest();
    request.userQuery = 'show me my top 15 open cases and determine why you think these are still open and if there\'s any correlation to the opportunities open for those accounts';

    Test.startTest();
    List<BusinessIntelligence.BIResult> results = BusinessIntelligence.analyze(
      new List<BusinessIntelligence.BIRequest>{ request }
    );
    Test.stopTest();

    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(null, results[0].analysisResult, 'Analysis result should not be null');
    System.assert(results[0].analysisResult.length() > 0, 'Analysis result should not be empty');
  }
}
