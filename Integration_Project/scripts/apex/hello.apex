
try {
    String response =
        GitHubApiService.getAuthenticatedUser();

    Map<String, Object> githubUser =
        (Map<String, Object>) JSON.deserializeUntyped(
            response
        );

    System.debug(
        'SUCCESS - GitHub Username: ' +
        githubUser.get('login')
    );

    System.debug(
        'GitHub User ID: ' +
        githubUser.get('id')
    );

} catch (Exception e) {
    System.debug(
        'ERROR: ' + e.getMessage()
    );
}
