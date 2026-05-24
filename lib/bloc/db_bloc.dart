import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../models/objectbox_model.dart';
import '../services/objectbox_service.dart';

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

  DbLoaded({
    required this.dbPath,
    required this.model,
    required this.fileInfo,
    this.selectedEntity,
    this.rows,
    this.error,
    this.viewMode = EntityViewMode.data,
  });

  /// True when the model was discovered without objectbox-model.json
  bool get isDiscovered => model.discovered;

  DbLoaded copyWith({
    EntityInfo? selectedEntity,
    List<EntityRow>? rows,
    String? error,
    EntityViewMode? viewMode,
    bool clearRows = false,
    bool clearError = false,
  }) {
    return DbLoaded(
      dbPath: dbPath,
      model: model,
      fileInfo: fileInfo,
      selectedEntity: selectedEntity ?? this.selectedEntity,
      rows: clearRows ? null : (rows ?? this.rows),
      error: clearError ? null : (error ?? this.error),
      viewMode: viewMode ?? this.viewMode,
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

  DbBloc() : super(DbInitial()) {
    on<OpenDatabase>(_onOpenDatabase);
    on<SelectEntity>(_onSelectEntity);
    on<SelectViewMode>(_onSelectViewMode);
    on<RefreshData>(_onRefreshData);
    on<CloseDatabase>(_onCloseDatabase);
  }

  Future<void> _onOpenDatabase(
    OpenDatabase event,
    Emitter<DbState> emit,
  ) async {
    emit(DbLoading());
    try {
      final model = await _service.openDatabase(event.path);
      final fileInfo = await _service.getDbFileInfo(event.path);
      emit(DbLoaded(dbPath: event.path, model: model, fileInfo: fileInfo));
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
    emit(DbInitial());
  }
}
