@IsTest
private class QuoteServiceTest {
  private static final String SUCCESS_BODY =
    '[{"quote":"The road to success begins with knowing what you need to know and why",' +
    '"author":"Savania China","work":"","categories":["success","wisdom","inspirational"]}]';

  private class MockResponse implements HttpCalloutMock {
    private Integer statusCode;
    private String body;
    public HttpRequest lastRequest;

    MockResponse(Integer statusCode, String body) {
      this.statusCode = statusCode;
      this.body = body;
    }

    public HttpResponse respond(HttpRequest req) {
      lastRequest = req;
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(body);
      return res;
    }
  }

  @IsTest
  static void getQuotesWithNullFilterReturnsQuotes() {
    MockResponse mock = new MockResponse(200, SUCCESS_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<QuoteService.QuoteData> quotes = QuoteService.getQuotes(null);
    Test.stopTest();

    Assert.areEqual(
      'callout:ApiNinjas/v2/quotes',
      mock.lastRequest.getEndpoint()
    );
    Assert.areEqual('GET', mock.lastRequest.getMethod());
    Assert.areEqual(1, quotes.size());
    Assert.areEqual('Savania China', quotes[0].author);
    Assert.areEqual('', quotes[0].work);
    Assert.areEqual(
      new List<String>{ 'success', 'wisdom', 'inspirational' },
      quotes[0].categories
    );
    Assert.isTrue(quotes[0].quote.startsWith('The road to success'));
  }

  @IsTest
  static void getQuotesBuildsQueryStringFromFilter() {
    MockResponse mock = new MockResponse(200, SUCCESS_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    QuoteService.QuoteFilter filter = new QuoteService.QuoteFilter();
    filter.categories = new List<String>{ ' Wisdom ', 'success', '' };
    filter.excludeCategories = new List<String>{ 'love' };
    filter.author = 'Albert Einstein';
    filter.work = 'War';
    filter.resultLimit = 10;
    filter.resultOffset = 20;
    filter.safe = true;

    Test.startTest();
    QuoteService.getQuotes(filter);
    Test.stopTest();

    Assert.areEqual(
      'callout:ApiNinjas/v2/quotes?categories=wisdom%2Csuccess&exclude_categories=love' +
      '&author=Albert+Einstein&work=War&limit=10&offset=20&safe=true',
      mock.lastRequest.getEndpoint()
    );
  }

  @IsTest
  static void emptyFilterAddsNoQueryString() {
    Assert.areEqual('', new QuoteService.QuoteFilter().toQueryString());
  }

  @IsTest
  static void getQuotesByCategorySetsCategory() {
    MockResponse mock = new MockResponse(200, SUCCESS_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    List<QuoteService.QuoteData> quotes = QuoteService.getQuotesByCategory(
      'success'
    );
    Test.stopTest();

    Assert.areEqual(
      'callout:ApiNinjas/v2/quotes?categories=success',
      mock.lastRequest.getEndpoint()
    );
    Assert.areEqual(1, quotes.size());
  }

  @IsTest
  static void getQuotesByAuthorSetsAuthor() {
    MockResponse mock = new MockResponse(200, SUCCESS_BODY);
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    QuoteService.getQuotesByAuthor('Einstein');
    Test.stopTest();

    Assert.areEqual(
      'callout:ApiNinjas/v2/quotes?author=Einstein',
      mock.lastRequest.getEndpoint()
    );
  }

  @IsTest
  static void emptyResultReturnsEmptyList() {
    Test.setMock(HttpCalloutMock.class, new MockResponse(200, '[]'));

    Test.startTest();
    List<QuoteService.QuoteData> quotes = QuoteService.getQuotesByAuthor(
      'Nobody'
    );
    Test.stopTest();

    Assert.isTrue(quotes.isEmpty());
  }

  @IsTest
  static void httpErrorWithJsonBodyThrows() {
    String body = '{"error":"Invalid API Key."}';
    Test.setMock(HttpCalloutMock.class, new MockResponse(400, body));

    try {
      QuoteService.getQuotes(null);
      Assert.fail('Expected QuoteException');
    } catch (QuoteService.QuoteException e) {
      Assert.areEqual(400, e.statusCode);
      Assert.areEqual('Invalid API Key.', e.error);
      Assert.areEqual(body, e.responseBody);
      Assert.areEqual(
        'API Ninjas Quotes request failed (HTTP 400): Invalid API Key.',
        e.getMessage()
      );
    }
  }

  @IsTest
  static void httpErrorWithNonJsonBodyThrows() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockResponse(503, '<html>Service Unavailable</html>')
    );

    try {
      QuoteService.getQuotes(null);
      Assert.fail('Expected QuoteException');
    } catch (QuoteService.QuoteException e) {
      Assert.areEqual(503, e.statusCode);
      Assert.isNull(e.error);
      Assert.areEqual(
        'API Ninjas Quotes request failed (HTTP 503)',
        e.getMessage()
      );
    }
  }
}
