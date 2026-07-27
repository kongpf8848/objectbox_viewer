import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox_viewer/bloc/db_bloc.dart';
import 'package:objectbox_viewer/main.dart';
import 'package:objectbox_viewer/models/objectbox_model.dart';
import 'package:objectbox_viewer/widgets/home_page.dart';

ObjectBoxModel _emptyModel() => ObjectBoxModel(
  entities: const [],
  indexes: const [],
  relations: const [],
  lastEntityId: 0,
  lastEntityUid: 0,
  lastIndexId: 0,
  lastIndexUid: 0,
  lastRelationId: 0,
  lastRelationUid: 0,
  modelVersion: 0,
);

void main() {
  testWidgets('App starts without error', (WidgetTester tester) async {
    await tester.pumpWidget(const ObjectBoxViewerApp());
    expect(find.text('ObjectBox Viewer'), findsWidgets);
  });

  test('CRUD message is only shown once when later states retain it', () {
    final loaded = DbLoaded(
      dbPath: 'test-db',
      model: _emptyModel(),
      fileInfo: const {},
      crudMessage: 'Deleted 1 object',
    );

    expect(shouldShowCrudMessage(DbInitial(), loaded), isTrue);
    expect(
      shouldShowCrudMessage(loaded, loaded.copyWith(rows: const [])),
      isFalse,
    );
  });
}
