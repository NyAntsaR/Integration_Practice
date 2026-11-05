
GitHubApiService.CreateIssueRequest request =
    new GitHubApiService.CreateIssueRequest();

request.title =
    '[Salesforce Integration Test] Subscription activation failure';

request.body =
    'Synthetic test issue created from Salesforce Apex.\n\n' +
    'Scenario: Payment succeeded, but the subscription ' +
    'remains Pending Activation.\n\n' +
    'Expected: Subscription becomes Active.\n' +
    'Actual: Subscription remains Pending Activation.';

GitHubApiService.IssueResponse response =
    GitHubApiService.createIssue(
        'NyAntsaR',
        'salesforce-engineering-escalations',
        request
    );

System.debug('Issue Number: ' + response.issueNumber);
System.debug('Issue ID: ' + response.id);
System.debug('Issue URL: ' + response.htmlUrl);
System.debug('Issue State: ' + response.state);
