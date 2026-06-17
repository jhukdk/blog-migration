// CloudFront viewer-request function (cloudfront-js-2.0).
// 1. Canonical-host redirect: www.jhuk.tech -> jhuk.tech (301).
// 2. Pretty-URL rewrite: Hugo emits pretty URLs as directories
//    (e.g. /2022/01/21/slug/ -> .../index.html); S3 has no directory-index
//    concept, so map directory-style paths to index.html.
// Only one function may be associated per event type, so both concerns live here.
function handler(event) {
    var request = event.request;

    // --- Canonical host redirect (must run before any URI rewriting) ---
    var host = request.headers.host.value;
    if (host === 'www.jhuk.tech') {
        // Reconstruct the query string from the parsed querystring object.
        var qs = '';
        for (var key in request.querystring) {
            qs += (qs ? '&' : '?') + key;
            if (request.querystring[key].value !== '') {
                qs += '=' + request.querystring[key].value;
            }
        }
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: {
                location: { value: 'https://jhuk.tech' + request.uri + qs }
            }
        };
    }

    // --- Pretty-URL rewrite ---
    var uri = request.uri;

    if (uri.endsWith('/')) {
        // /posts/  ->  /posts/index.html
        request.uri = uri + 'index.html';
    } else if (!uri.includes('.')) {
        // /posts  ->  /posts/index.html  (extensionless = a directory)
        request.uri = uri + '/index.html';
    }
    // Paths with an extension (e.g. /404.html, /img.png, /index.json) pass through.

    return request;
}
