import 'package:web/web.dart' as web;

/// Updates dynamic browser tab Favicon and Apple Touch Icon using package:web
void updateWebFavicon(String iconPathOrId) {
  String targetHref;
  switch (iconPathOrId) {
    case 'neon':
      targetHref = 'favicon_neon.png';
      break;
    case 'stealth':
      targetHref = 'favicon_stealth.png';
      break;
    case 'silver':
      targetHref = 'favicon_silver.png';
      break;
    case 'classic':
      targetHref = 'favicon.png';
      break;
    default:
      if (iconPathOrId.startsWith('data:') ||
          iconPathOrId.startsWith('blob:') ||
          iconPathOrId.startsWith('http://') ||
          iconPathOrId.startsWith('https://') ||
          iconPathOrId.startsWith('assets/')) {
        targetHref = iconPathOrId;
      } else {
        targetHref = 'favicon.png';
      }
      break;
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final hrefWithBuster = targetHref.contains('?')
      ? '$targetHref&t=$timestamp'
      : '$targetHref?t=$timestamp';

  // 1. Update existing favicon links
  final iconElements = web.document.querySelectorAll('link[rel*="icon"]');
  var foundIcon = false;
  for (var i = 0; i < iconElements.length; i++) {
    final el = iconElements.item(i);
    if (el != null) {
      (el as web.HTMLLinkElement).href = hrefWithBuster;
      foundIcon = true;
    }
  }

  // If no icon link was found, dynamically create and append one
  if (!foundIcon) {
    final link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = 'icon';
    link.type = 'image/png';
    link.href = hrefWithBuster;
    web.document.head?.appendChild(link);
  }

  // 2. Also update apple-touch-icon
  final touchElements = web.document.querySelectorAll('link[rel="apple-touch-icon"]');
  for (var i = 0; i < touchElements.length; i++) {
    final el = touchElements.item(i);
    if (el != null) {
      (el as web.HTMLLinkElement).href = hrefWithBuster;
    }
  }
}
