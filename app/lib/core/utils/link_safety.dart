/// Client-side mirror of the backend link checks, used before opening an external application link.
/// It produces cautious warnings only — never a claim that a listing is fraudulent.
class LinkCheck {
  const LinkCheck(this.flags);
  final List<String> flags;
  bool get ok => flags.isEmpty;
}

const _shorteners = {'bit.ly', 'tinyurl.com', 'goo.gl', 't.co', 'cutt.ly', 'rb.gy', 'shorturl.at', 'is.gd', 'ow.ly', 'tiny.cc'};
const _messaging = ['wa.me', 'chat.whatsapp.com', 't.me', 'api.whatsapp.com'];

bool domainMatches(String host, String domain) {
  final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final d = domain.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  return h == d || h.endsWith('.$d');
}

LinkCheck checkLink(String? url, {List<String> officialDomains = const []}) {
  final flags = <String>[];
  if (url == null || url.isEmpty) return const LinkCheck(['No official link provided']);
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return const LinkCheck(['Link is not a valid web address']);
  final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (u.scheme != 'https') flags.add('Link is not secure (no HTTPS)');
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) flags.add('Link uses a raw IP address');
  if (host.split('.').any((p) => p.startsWith('xn--'))) flags.add('Link uses look-alike characters');
  if (_shorteners.contains(host)) flags.add('Shortened link hides the real destination');
  if (_messaging.any((m) => domainMatches(host, m))) flags.add('Opens a messaging chat instead of a website');
  if (officialDomains.isNotEmpty && !officialDomains.any((d) => domainMatches(host, d))) {
    flags.add("Not on the organisation's official domain");
  }
  return LinkCheck(flags);
}
