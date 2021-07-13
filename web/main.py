from flask import Flask, send_file, redirect, request
from urllib.parse import urlencode
import os
import string

# `entrypoint` is not defined in app.yaml, so App Engine will look for an app
# called `app` in this file.
app = Flask(__name__)

if __name__ == '__main__':
    # This is used when running locally only.
    app.run(host='127.0.0.1', port=8080, debug=True)

# Files that the server is allowed to serve. Additional static files are
# served via directives in app.yaml.
VALID_FILES = [
    'workshops.html',
    'dark_mode.js',
    'dart-192.png',
    'embed-dart.html',
    'embed-flutter.html',
    'embed-flutter_showcase.html',
    'embed-html.html',
    'embed-inline.html',
    'embed-.html',
    'fav_icon.ico',
    'index.html',
    'inject_embed.dart.js',
    'robots.txt'
]

VALID_ROUTES = [
    'flutter',
    'dart',
    'html'
]

# File extensions and the mimetypes with which they should be served.
DEFAULT_CONTENT_TYPE = 'application/octet-stream'

CONTENT_TYPES = {
    '.css': 'text/css',
    '.html': 'text/html',
    '.ico': 'image/x-icon',
    '.js': 'application/javascript',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.txt': 'text/plain',
}


@app.route('/')
def index():
    return _serve_file('index.html')


@app.route('/<item_name>')
def item(item_name):
    # It's a known, valid file, so just serve it.
    if item_name in VALID_FILES:
        return _serve_file(item_name)

    # It's a known, valid route, so serve the index file.
    if item_name in VALID_ROUTES:
        return _serve_file('index.html')

    # It's a gist ID, so redirect to `/` and add the ID as a query param.
    if (len(item_name) == 32 or len(item_name) == 20) and all(c in string.hexdigits for c in item_name):
        args = request.args.copy()
        args['id'] = item_name
        url = '/?{}'.format(urlencode(args))
        return redirect(url, code=308)

    # Route doesn't match anything, so return a 404.
    return _serve_404()


# Temporary route to find out if we can sniff which host we are serving as.
@app.route("/hostname/")
def return_hostname():
    return "This is an example wsgi app served from {} to {}".format(socket.gethostname(), request.remote_addr)


def _serve_file(file_path):
    if not os.path.isfile(file_path):
        return _serve_404()
    file_name, file_ext = os.path.splitext(file_path)
    mimetype = CONTENT_TYPES.get(file_ext, DEFAULT_CONTENT_TYPE)
    return send_file(file_path, mimetype=mimetype)


def _serve_404():
    return '<html><h1>404: Not found</h1></html>', 404
