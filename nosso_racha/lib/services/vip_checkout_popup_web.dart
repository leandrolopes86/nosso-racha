import 'package:web/web.dart' as web;

Object? openVipCheckoutPopup() => web.window.open(
  'about:blank',
  'nossoRachaVipCheckout',
  'popup,width=480,height=800,resizable=yes,scrollbars=yes',
);

bool vipCheckoutPopupIsClosed(Object? popup) =>
    popup == null || (popup as web.Window).closed;

void navigateVipCheckoutPopup(Object? popup, String url) {
  final window = popup as web.Window;
  window.location.href = url;
  window.focus();
}

void closeVipCheckoutPopup(Object? popup) {
  if (popup != null) (popup as web.Window).close();
}
