/**
 * HTTP callouts to API Ninjas' Quotes API v2 (https://api-ninjas.com/api/quotes#v2-quotes).
 * Uses the ApiNinjas Named Credential, which injects the X-Api-Key header. Set the API key
 * on the ApiNinjas External Credential's principal (parameter "ApiKey") in Setup.
 */
public with sharing class QuoteService {
    private static final String QUOTES_ENDPOINT = 'callout:ApiNinjas/v2/quotes';

    /**
     * Returns quotes matching the given filter. A null filter returns the API default (one quote).
     */
    public static List<QuoteData> getQuotes(QuoteFilter filter) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(QUOTES_ENDPOINT + (filter != null ? filter.toQueryString() : ''));
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(20000);

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new QuoteException(res);
        }

        return (List<QuoteData>) JSON.deserialize(res.getBody(), List<QuoteData>.class);
    }

    /**
     * Returns quotes matching all of the given categories (e.g. 'wisdom', 'success').
     */
    public static List<QuoteData> getQuotesByCategory(String category) {
        QuoteFilter filter = new QuoteFilter();
        filter.categories = new List<String>{ category };
        return getQuotes(filter);
    }

    /**
     * Returns quotes whose author name partially matches the given name (e.g. 'Einstein').
     */
    public static List<QuoteData> getQuotesByAuthor(String author) {
        QuoteFilter filter = new QuoteFilter();
        filter.author = author;
        return getQuotes(filter);
    }

    /**
     * A single quote as returned by the API. 'work' may be empty.
     */
    public class QuoteData {
        public String quote;
        public String author;
        public String work;
        public List<String> categories;
    }

    /**
     * Query parameters for /v2/quotes. All are optional; resultLimit, resultOffset and safe
     * are premium-only on API Ninjas.
     */
    public class QuoteFilter {
        public List<String> categories;
        public List<String> excludeCategories;
        public String author;
        public String work;
        public Integer resultLimit;
        public Integer resultOffset;
        public Boolean safe;

        @TestVisible
        private String toQueryString() {
            List<String> params = new List<String>();
            addParam(params, 'categories', joinValues(categories));
            addParam(params, 'exclude_categories', joinValues(excludeCategories));
            addParam(params, 'author', author);
            addParam(params, 'work', work);
            addParam(params, 'limit', resultLimit != null ? String.valueOf(resultLimit) : null);
            addParam(params, 'offset', resultOffset != null ? String.valueOf(resultOffset) : null);
            addParam(params, 'safe', safe != null ? String.valueOf(safe) : null);
            return params.isEmpty() ? '' : '?' + String.join(params, '&');
        }

        private String joinValues(List<String> values) {
            if (values == null) {
                return null;
            }
            List<String> cleaned = new List<String>();
            for (String value : values) {
                if (String.isNotBlank(value)) {
                    cleaned.add(value.trim().toLowerCase());
                }
            }
            return String.join(cleaned, ',');
        }

        private void addParam(List<String> params, String name, String value) {
            if (String.isNotBlank(value)) {
                params.add(name + '=' + EncodingUtil.urlEncode(value.trim(), 'UTF-8'));
            }
        }
    }

    /**
     * Thrown when a callout fails or the API reports an error.
     * The built-in constructors (message, cause) still work for non-HTTP errors.
     */
    public class QuoteException extends Exception {
        public Integer statusCode { get; private set; }
        public String error { get; private set; }
        public String responseBody { get; private set; }

        public QuoteException(HttpResponse res) {
            this.statusCode = res.getStatusCode();
            this.responseBody = res.getBody();
            try {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(this.responseBody);
                this.error = (String) body.get('error');
            } catch (Exception e) {
                // Body isn't a JSON object (e.g. an HTML error page); leave error null.
            }
            this.setMessage(
                'API Ninjas Quotes request failed (HTTP ' +
                this.statusCode +
                ')' +
                (this.error != null ? ': ' + this.error : '')
            );
        }
    }
}
