@IsTest
private class ExchangeRateServiceTest {
    private static final String SUCCESS_BODY =
        '{"result":"success","base_code":"USD","time_last_update_unix":1700000000,' +
        '"rates":{"USD":1,"EUR":0.892784,"JPY":156.839696}}';

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
    static void getLatestRatesReturnsRates() {
        MockResponse mock = new MockResponse(200, SUCCESS_BODY);
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Decimal> rates = ExchangeRateService.getLatestRates(' usd ');
        Test.stopTest();

        Assert.areEqual('https://open.er-api.com/v6/latest/USD', mock.lastRequest.getEndpoint());
        Assert.areEqual('GET', mock.lastRequest.getMethod());
        Assert.areEqual(3, rates.size());
        Assert.areEqual(0.892784, rates.get('EUR'));
        Assert.areEqual(1, rates.get('USD'));
    }

    @IsTest
    static void getRateReturnsSingleRate() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, SUCCESS_BODY));

        Test.startTest();
        Decimal rate = ExchangeRateService.getRate('USD', 'eur');
        Test.stopTest();

        Assert.areEqual(0.892784, rate);
    }

    @IsTest
    static void convertMultipliesAmountByRate() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, SUCCESS_BODY));

        Test.startTest();
        Decimal result = ExchangeRateService.convert(100, 'USD', 'JPY');
        Test.stopTest();

        Assert.areEqual(15683.9696, result);
    }

    @IsTest
    static void unsupportedTargetCurrencyThrows() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, SUCCESS_BODY));

        try {
            ExchangeRateService.getRate('USD', 'XYZ');
            Assert.fail('Expected ExchangeRateException');
        } catch (ExchangeRateService.ExchangeRateException e) {
            Assert.areEqual('Unsupported currency: XYZ', e.getMessage());
            Assert.isNull(e.statusCode);
        }
    }

    @IsTest
    static void apiErrorResultThrowsWithErrorType() {
        String body = '{"result":"error","error-type":"unsupported-code"}';
        Test.setMock(HttpCalloutMock.class, new MockResponse(200, body));

        try {
            ExchangeRateService.getLatestRates('XYZ');
            Assert.fail('Expected ExchangeRateException');
        } catch (ExchangeRateService.ExchangeRateException e) {
            Assert.areEqual(200, e.statusCode);
            Assert.areEqual('unsupported-code', e.errorType);
            Assert.areEqual(body, e.responseBody);
            Assert.areEqual('ExchangeRate-API request failed (HTTP 200): unsupported-code', e.getMessage());
        }
    }

    @IsTest
    static void httpErrorWithJsonBodyThrows() {
        Test.setMock(
            HttpCalloutMock.class,
            new MockResponse(404, '{"result":"error","error-type":"unsupported-code"}')
        );

        try {
            ExchangeRateService.getLatestRates('XYZ');
            Assert.fail('Expected ExchangeRateException');
        } catch (ExchangeRateService.ExchangeRateException e) {
            Assert.areEqual(404, e.statusCode);
            Assert.areEqual('unsupported-code', e.errorType);
        }
    }

    @IsTest
    static void httpErrorWithNonJsonBodyThrows() {
        Test.setMock(HttpCalloutMock.class, new MockResponse(503, '<html>Service Unavailable</html>'));

        try {
            ExchangeRateService.getLatestRates('USD');
            Assert.fail('Expected ExchangeRateException');
        } catch (ExchangeRateService.ExchangeRateException e) {
            Assert.areEqual(503, e.statusCode);
            Assert.isNull(e.errorType);
            Assert.areEqual('ExchangeRate-API request failed (HTTP 503)', e.getMessage());
        }
    }
}
