/**
 * HTTP callouts to ExchangeRate-API's open access endpoint (https://www.exchangerate-api.com/docs/free).
 * No API key needed. Requires a Remote Site Setting for https://open.er-api.com.
 */
public with sharing class ExchangeRateService {
    private static final String BASE_URL = 'https://open.er-api.com/v6/latest/';
    /**
     * Returns all conversion rates for the given base currency (e.g. 'USD').
     */
    public static Map<String, Decimal> getLatestRates(String baseCurrency) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(BASE_URL + EncodingUtil.urlEncode(baseCurrency.trim().toUpperCase(), 'UTF-8'));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new ExchangeRateException(res);
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (body.get('result') != 'success') {
            throw new ExchangeRateException(res);
        }

        Map<String, Decimal> rates = new Map<String, Decimal>();
        Map<String, Object> rawRates = (Map<String, Object>) body.get('rates');
        for (String code : rawRates.keySet()) {
            rates.put(code, Decimal.valueOf(String.valueOf(rawRates.get(code))));
        }
        System.debug('Rate: ' + rates);
        return rates;
    }

    /**
     * Returns the rate from one currency to another.
     */
    public static Decimal getRate(String fromCurrency, String toCurrency) {
        Decimal rate = getLatestRates(fromCurrency).get(toCurrency.trim().toUpperCase());
        if (rate == null) {
            throw new ExchangeRateException('Unsupported currency: ' + toCurrency);
        }
        return rate;
    }

    /**
     * Converts an amount from one currency to another.
     */
    public static Decimal convert(Decimal amount, String fromCurrency, String toCurrency) {
        return amount * getRate(fromCurrency, toCurrency);
    }

    /**
     * Thrown when a callout fails or the API reports an error.
     * The built-in constructors (message, cause) still work for non-HTTP errors.
     */
    public class ExchangeRateException extends Exception {
        public Integer statusCode { get; private set; }
        public String errorType { get; private set; }
        public String responseBody { get; private set; }

        public ExchangeRateException(HttpResponse res) {
            this.statusCode = res.getStatusCode();
            this.responseBody = res.getBody();
            try {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(this.responseBody);
                this.errorType = (String) body.get('error-type');
            } catch (Exception e) {
                // Body isn't JSON (e.g. an HTML error page); leave errorType null.
            }
            this.setMessage(
                'ExchangeRate-API request failed (HTTP ' +
                this.statusCode +
                ')' +
                (this.errorType != null ? ': ' + this.errorType : '')
            );
        }
    }
}
