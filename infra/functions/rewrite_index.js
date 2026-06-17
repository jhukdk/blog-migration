// CloudFront viewer-request function (cloudfront-js-2.0).
// Pretty-URL rewrite: Hugo emits pretty URLs as directories
// (e.g. /2022/01/21/slug/ -> .../index.html); S3 has no directory-index
// concept, so map directory-style paths to index.html.
function handler(event) {
    var request = event.request;

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
