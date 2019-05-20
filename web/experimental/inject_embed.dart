import 'dart:html';

import 'package:html_unescape/html_unescape.dart';

/// Replaces all code snippets marked with the 'dartpad-embed' class with an
/// instance of DartPad.
void main() {
  var hosts = querySelectorAll('.dartpad-embed');
  for (var host in hosts) {
    _injectEmbed(host);
  }
}

/// Replaces [host] with an instance of DartPad as an embedded iframe.
///
/// Code snippets are assumed to be a div containing `pre` and `code` tags:
///
/// <div class="dartpad-embed">
///   <pre>
///     <code>
///       void main() => print("Hello, World!");
///     </code>
///   </pre>
/// </div>
void _injectEmbed(DivElement host) {
  if (host.children.length != 1) {
    return;
  }

  var preElement = host.children.first;
  if (preElement.children.length != 1) {
    return;
  }

  var codeElement = preElement.children.first;
  var code = HtmlUnescape().convert(codeElement.innerHtml);
  if (code.isEmpty) {
    return;
  }
  InjectedEmbed(host, code);
}

/// Clears children in [host], instantiates an iframe, and sends it a message
/// with the source code when it's ready
class InjectedEmbed {
  final DivElement host;
  final String code;

  InjectedEmbed(this.host, this.code) {
    _init();
  }

  Future _init() async {
    host.children.clear();
    var iframe = IFrameElement()..setAttribute('src', 'embed-new.html?fw=true');
    host.children.add(iframe);

    window.addEventListener('message', (dynamic e) {
      if (e.data['type'] == 'ready') {
        var m = {'sourceCode': code, 'type': 'sourceCode'};
        iframe.contentWindow.postMessage(m, '*');
      }
    });
  }
}
