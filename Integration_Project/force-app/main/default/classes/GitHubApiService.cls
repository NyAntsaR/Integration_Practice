public with sharing class GitHubApiService {
  private static final String BASE_ENDPOINT = 'callout:GithubAPI';
  private static final Integer TIMEOUT_MS = 10000;

  // GitHub owners: letters, digits, hyphens. Repositories: also dots and underscores.
  private static final Pattern OWNER_PATTERN = Pattern.compile(
    '^[A-Za-z0-9-]{1,39}$'
  );
  private static final Pattern REPOSITORY_PATTERN = Pattern.compile(
    '^[A-Za-z0-9._-]{1,100}$'
  );

  public static String getAuthenticatedUser() {
    HttpResponse res = send(newRequest('GET', '/user'));
    if (res.getStatusCode() != 200) {
      throw httpError(res);
    }
    return res.getBody();
  }

  // Custom exception for GitHub API failures. statusCode is null when no HTTP response was received.
  public class GitHubApiException extends Exception {
    public Integer statusCode;
  }

  // Request wrapper - Salesforce to GitHub
  public class CreateIssueRequest {
    public String title;
    public String body;
  }

  // Response wrapper - GitHub to Salesforce
  public class IssueResponse {
    public Long id;
    public Integer issueNumber; // GitHub "number" (reserved word in Apex)
    public String htmlUrl;
    public String state;
    public String title;
  }

  // Create an issue in a GitHub repository
  public static IssueResponse createIssue(
    String owner,
    String repository,
    CreateIssueRequest issue
  ) {
    // Validate required inputs. The owner and repository go into the URL path,
    // so they must be plain GitHub names (no slashes, spaces, or "..").
    if (String.isBlank(owner) || !OWNER_PATTERN.matcher(owner).matches()) {
      throw new GitHubApiException(
        'A valid GitHub repository owner is required.'
      );
    }
    if (
      String.isBlank(repository) ||
      !REPOSITORY_PATTERN.matcher(repository).matches() ||
      repository == '.' ||
      repository == '..'
    ) {
      throw new GitHubApiException(
        'A valid GitHub repository name is required.'
      );
    }
    if (issue == null || String.isBlank(issue.title)) {
      throw new GitHubApiException('An issue title is required.');
    }

    HttpRequest req = newRequest(
      'POST',
      '/repos/' + owner + '/' + repository + '/issues'
    );
    req.setHeader('Content-Type', 'application/json');
    req.setBody(JSON.serialize(issue, true));

    HttpResponse res = send(req);
    if (res.getStatusCode() != 201) {
      throw httpError(res);
    }

    IssueResponse result = parseIssue(res.getBody());
    if (result.id == null || String.isBlank(result.htmlUrl)) {
      throw new GitHubApiException('Invalid response from GitHub.');
    }
    return result;
  }

  private static HttpRequest newRequest(String method, String path) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(BASE_ENDPOINT + path);
    req.setMethod(method);
    req.setHeader('Accept', 'application/vnd.github+json');
    req.setHeader('X-GitHub-Api-Version', '2022-11-28');
    req.setTimeout(TIMEOUT_MS);
    return req;
  }

  private static HttpResponse send(HttpRequest req) {
    try {
      return new Http().send(req);
    } catch (CalloutException e) {
      // Timeouts, DNS failures, or a missing/unauthorized named credential.
      throw new GitHubApiException('Could not reach GitHub: ' + e.getMessage());
    }
  }

  // Maps GitHub's issue JSON explicitly, so "number" and "html_url" don't depend on field naming.
  @TestVisible
  private static IssueResponse parseIssue(String body) {
    Map<String, Object> fields;
    try {
      fields = (Map<String, Object>) JSON.deserializeUntyped(body);
    } catch (Exception e) {
      throw new GitHubApiException('Invalid response from GitHub.');
    }

    IssueResponse result = new IssueResponse();
    result.id = fields.get('id') == null
      ? null
      : Long.valueOf(String.valueOf(fields.get('id')));
    result.issueNumber = fields.get('number') == null
      ? null
      : Integer.valueOf(fields.get('number'));
    result.htmlUrl = (String) fields.get('html_url');
    result.state = (String) fields.get('state');
    result.title = (String) fields.get('title');
    return result;
  }

  // Builds a readable error from a non-success response. Only GitHub's own
  // "message" text is included, never headers or the full body.
  @TestVisible
  private static GitHubApiException httpError(HttpResponse res) {
    Integer statusCode = res.getStatusCode();
    String reason;
    switch on statusCode {
      when 401 {
        reason = 'Authentication failed. Check the GithubAPI named credential.';
      }
      when 403 {
        reason = 'Access denied, or the GitHub rate limit was exceeded.';
      }
      when 404 {
        reason = 'Repository not found, or the credential cannot access it.';
      }
      when 410 {
        reason = 'Issues are disabled for this repository.';
      }
      when 422 {
        reason = 'GitHub rejected the request as invalid.';
      }
      when 429 {
        reason = 'GitHub rate limit exceeded. Try again later.';
      }
      when else {
        reason = statusCode >= 500
          ? 'GitHub is temporarily unavailable. Try again later.'
          : 'Unexpected response from GitHub.';
      }
    }

    String message =
      'GitHub request failed (HTTP ' +
      statusCode +
      '): ' +
      reason;
    String githubMessage = githubMessage(res.getBody());
    if (String.isNotBlank(githubMessage)) {
      message += ' GitHub says: ' + githubMessage.abbreviate(255);
    }

    GitHubApiException error = new GitHubApiException(message);
    error.statusCode = statusCode;
    return error;
  }

  private static String githubMessage(String body) {
    try {
      Object message = ((Map<String, Object>) JSON.deserializeUntyped(body))
        .get('message');
      return message == null ? null : String.valueOf(message);
    } catch (Exception e) {
      return null;
    }
  }
}
