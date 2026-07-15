// CloudFront viewer-request function (cloudfront-js-2.0).
// 1. Canonical-host redirect: www.jhuk.tech -> jhuk.tech (301).
// 2. Landing-page redirect: / -> /posts/ (301).
// 3. Pretty-URL rewrite: Hugo emits pretty URLs as directories
//    (e.g. /2022/01/21/slug/ -> .../index.html); S3 has no directory-index
//    concept, so map directory-style paths to index.html.
// Only one function may be associated per event type, so all concerns live here.

// Reconstruct the query string from the parsed querystring object.
function buildQueryString(querystring) {
    var qs = '';
    for (var key in querystring) {
        qs += (qs ? '&' : '?') + key;
        if (querystring[key].value !== '') {
            qs += '=' + querystring[key].value;
        }
    }
    return qs;
}

function redirect301(location) {
    return {
        statusCode: 301,
        statusDescription: 'Moved Permanently',
        headers: {
            location: { value: location }
        }
    };
}

function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;

    // --- Canonical host + landing-page redirects ---
    // The landing page goes to the post list; resolving the target path first
    // collapses www root -> apex /posts/ into a single 301.
    var target = request.uri === '/' ? '/posts/' : request.uri;
    if (host === 'www.jhuk.tech' || target !== request.uri) {
        return redirect301('https://jhuk.tech' + target + buildQueryString(request.querystring));
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
