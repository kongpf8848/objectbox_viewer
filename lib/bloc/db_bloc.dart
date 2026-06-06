import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/objectbox_model.dart';
import '../services/objectbox_service.dart';
import '../services/objectbox_crud_service.dart';

// View mode for selected entity
enum EntityViewMode { data, schema }

// Events
sealed class DbEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class OpenDatabase extends DbEvent {
  final String path;
  OpenDatabase(this.path);

  @override
  List<Object?> get props => [path];
}

class SelectEntity extends DbEvent {
  final EntityInfo entity;
  SelectEntity(this.entity);

  @override
  List<Object?> get props => [entity];
}

class SelectViewMode extends DbEvent {
  final EntityViewMode mode;
  SelectViewMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

class RefreshData extends DbEvent {}

class CloseDatabase extends DbEvent {}

class DeleteObjects extends DbEvent {
  final EntityInfo entity;
  final List<int> objectIds;
  DeleteObjects(this.entity, this.objectIds);

  @override
  List<Object?> get props => [entity, objectIds];
}

class UpdateObject extends DbEvent {
  final EntityInfo entity;
  final int objectId;
  final Map<String, dynamic> values;
  UpdateObject(this.entity, this.objectId, this.values);

  @override
  List<Object?> get props => [entity, objectId, values];
}

// State
sealed class DbState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DbInitial extends DbState {}

class DbLoading extends DbState {}

class DbLoaded extends DbState {
  final String dbPath;
  final ObjectBoxModel model;
  final Map<String, int> fileInfo;
  final EntityInfo? selectedEntity;
  final List<EntityRow>? rows;
  final String? error;
  final EntityViewMode viewMode;

  final bool isWriting;
  final String? crudMessage;

  DbLoaded({
    required this.dbPath,
    required this.model,
    required this.fileInfo,
    this.selectedEntity,
    this.rows,
    this.error,
    this.viewMode = EntityViewMode.data,
    this.isWriting = false,
    this.crudMessage,
  });

  /// True when the model was discovered without objectbox-model.json
  bool get isDiscovered => model.discovered;

  DbLoaded copyWith({
    EntityInfo? selectedEntity,
    List<EntityRow>? rows,
    String? error,
    EntityViewMode? viewMode,
    bool? isWriting,
    String? crudMessage,
    bool clearRows = false,
    bool clearError = false,
    bool clearCrudMessage = false,
  }) {
    return DbLoaded(
      dbPath: dbPath,
      model: model,
      fileInfo: fileInfo,
      selectedEntity: selectedEntity ?? this.selectedEntity,
      rows: clearRows ? null : (rows ?? this.rows),
      error: clearError ? null : (error ?? this.error),
      viewMode: viewMode ?? this.viewMode,
      isWriting: isWriting ?? this.isWriting,
      crudMessage: clearCrudMessage ? null : (crudMessage ?? this.crudMessage),
    );
  }

  @override
  List<Object?> get props => [
    dbPath,
    model,
    selectedEntity,
    rows,
    error,
    fileInfo,
    viewMode,
    isWriting,
    crudMessage,
  ];
}

class DbError extends DbState {
  final String message;
  DbError(this.message);

  @override
  List<Object?> get props => [message];
}

// BLoC
class DbBloc extends Bloc<DbEvent, DbState> {
  final ObjectBoxService _service = ObjectBoxService();
  final ObjectBoxCrudService _crudService = ObjectBoxCrudService();

  DbBloc() : super(DbInitial()) {
    on<OpenDatabase>(_onOpenDatabase);
    on<SelectEntity>(_onSelectEntity);
    on<SelectViewMode>(_onSelectViewMode);
    on<RefreshData>(_onRefreshData);
    on<CloseDatabase>(_onCloseDatabase);
    on<DeleteObjects>(_onDeleteObjects);
    on<UpdateObject>(_onUpdateObject);
  }

  Future<void> _onOpenDatabase(
    OpenDatabase event,
    Emitter<DbState> emit,
  ) async {
    emit(DbLoading());
    try {
      final model = await _service.openDatabase(event.path);
      final fileInfo = await _service.getDbFileInfo(event.path);

      // Open CRUD store
      String? crudWarning;
      try {
        await _crudService.openStore(event.path, model);
      } catch (e, st) {
        // CRUD store open failure shouldn't block read-only access
        crudWarning = 'Write mode unavailable: $e';
        print('━━━ CRUD Store Open Failed ━━━');
        print('Error: $e');
        print('Stack: $st');
      }

      emit(
        DbLoaded(
          dbPath: event.path,
          model: model,
          fileInfo: fileInfo,
          crudMessage: crudWarning,
        ),
      );
    } catch (e) {
      emit(DbError(e.toString()));
    }
  }

  Future<void> _onSelectEntity(
    SelectEntity event,
    Emitter<DbState> emit,
  ) async {
    final current = state;
    if (current is! DbLoaded) return;

    emit(
      current.copyWith(
        selectedEntity: event.entity,
        clearRows: true,
        clearError: true,
      ),
    );

    // Load data if in data mode (default)
    if (current.viewMode == EntityViewMode.data) {
      try {
        final rows = await _service.readEntityData(
          current.dbPath,
          event.entity,
        );
        emit(
          current.copyWith(
            selectedEntity: event.entity,
            rows: rows,
            clearError: true,
          ),
        );
      } catch (e) {
        emit(
          current.copyWith(selectedEntity: event.entity, error: e.toString()),
        );
      }
    }
  }

  Future<void> _onSelectViewMode(
    SelectViewMode event,
    Emitter<DbState> emit,
  ) async {
    final current = state;
    if (current is! DbLoaded || current.selectedEntity == null) return;

    emit(
      current.copyWith(viewMode: event.mode, clearRows: true, clearError: true),
    );

    // Load data if switching to data mode
    if (event.mode == EntityViewMode.data) {
      try {
        final rows = await _service.readEntityData(
          current.dbPath,
          current.selectedEntity!,
        );
        emit(
          current.copyWith(viewMode: event.mode, rows: rows, clearError: true),
        );
      } catch (e) {
        emit(current.copyWith(viewMode: event.mode, error: e.toString()));
      }
    }
  }

  Future<void> _onRefreshData(RefreshData event, Emitter<DbState> emit) async {
    final current = state;
    if (current is! DbLoaded || current.selectedEntity == null) return;
    add(SelectEntity(current.selectedEntity!));
  }

  Future<void> _onCloseDatabase(
    CloseDatabase event,
    Emitter<DbState> emit,
  ) async {
    _crudService.closeStore();
    emit(DbInitial());
  }

  Future<void> _onDeleteObjects(
    DeleteObjects event,
    Emitter<DbState> emit,
  ) async {
    final current = state;
    if (current is! DbLoaded) return;

    emit(current.copyWith(isWriting: true, clearCrudMessage: true));

    try {
      // Ensure CRUD store is open
      if (!_crudService.isOpen) {
        await _crudService.openStore(current.dbPath, current.model);
      }

      final count = await _crudService.deleteObjects(
        event.entity,
        event.objectIds,
      );

      emit(
        current.copyWith(
          isWriting: false,
          crudMessage: 'Deleted $count object${count != 1 ? "s" : ""}',
        ),
      );

      // Auto-refresh after delete
      add(SelectEntity(event.entity));
    } catch (e) {
      emit(current.copyWith(isWriting: false, error: 'Delete failed: $e'));
    }
  }

  Future<void> _onUpdateObject(
    UpdateObject event,
    Emitter<DbState> emit,
  ) async {
    final current = state;
    if (current is! DbLoaded) return;

    emit(current.copyWith(isWriting: true, clearCrudMessage: true));

    try {
      // Ensure CRUD store is open
      if (!_crudService.isOpen) {
        await _crudService.openStore(current.dbPath, current.model);
      }

      await _crudService.updateObject(
        event.entity,
        event.objectId,
        event.values,
      );

      emit(
        current.copyWith(
          isWriting: false,
          crudMessage: 'Updated object #${event.objectId}',
        ),
      );

      // Auto-refresh after update
      add(SelectEntity(event.entity));
    } catch (e) {
      emit(current.copyWith(isWriting: false, error: 'Update failed: $e'));
    }
  }

  /// Get the CRUD service (for backup check before writes).
  ObjectBoxCrudService get crudService => _crudService;
}
