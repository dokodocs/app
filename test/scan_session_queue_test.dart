import 'package:dokodocs/features/scan/providers/scan_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 2 queue: per-page processing state and path-keyed replacement — the
/// invariants that keep the background auto-crop safe against reorder/delete
/// happening while a page is still being processed.
void main() {
  late ProviderContainer container;
  late ScanSessionNotifier session;

  setUp(() {
    container = ProviderContainer();
    session = container.read(scanSessionProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('setProcessing marks the right page and anyProcessing reflects it', () {
    session.addPaths(['a.jpg', 'b.jpg']);
    expect(session.anyProcessing, isFalse);
    session.setProcessing('b.jpg', true);
    final pages = container.read(scanSessionProvider);
    expect(pages[0].processing, isFalse);
    expect(pages[1].processing, isTrue);
    expect(session.anyProcessing, isTrue);
    session.setProcessing('b.jpg', false);
    expect(session.anyProcessing, isFalse);
  });

  test('replacePath swaps the page in place and clears processing', () {
    session.addPaths(['a.jpg', 'b.jpg']);
    session.setProcessing('a.jpg', true);
    session.replacePath('a.jpg', 'a_cropped.jpg');
    final pages = container.read(scanSessionProvider);
    expect(pages[0].imagePath, 'a_cropped.jpg');
    expect(pages[0].processing, isFalse);
    expect(pages[1].imagePath, 'b.jpg');
  });

  test('replacePath is a no-op when the page was deleted meanwhile', () {
    session.addPaths(['a.jpg', 'b.jpg']);
    session.setProcessing('a.jpg', true);
    session.removeAt(0); // user deletes while the crop is in flight
    session.replacePath('a.jpg', 'a_cropped.jpg');
    final pages = container.read(scanSessionProvider);
    expect(pages.length, 1);
    expect(pages[0].imagePath, 'b.jpg');
  });

  test('replacePath still targets the right page after a reorder', () {
    session.addPaths(['a.jpg', 'b.jpg', 'c.jpg']);
    session.setProcessing('c.jpg', true);
    session.reorder(2, 0); // c moves to the front while processing
    session.replacePath('c.jpg', 'c_cropped.jpg');
    final pages = container.read(scanSessionProvider);
    expect(pages[0].imagePath, 'c_cropped.jpg');
    expect(pages[0].processing, isFalse);
  });

  test('setProcessing on a deleted path is a no-op', () {
    session.addPaths(['a.jpg']);
    session.removeAt(0);
    session.setProcessing('a.jpg', false); // must not throw
    expect(container.read(scanSessionProvider), isEmpty);
  });
}
