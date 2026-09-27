import 'package:nursing_clinical_core/core/sync/sync_service.dart';

final class FakeClinicalSyncCoordinator implements ClinicalSyncCoordinator {
  FakeClinicalSyncCoordinator({
    ClinicalSyncStatus? localStatus,
    ClinicalSyncStatus? syncStatus,
    List<ClinicalSyncStatus>? progressStatuses,
  }) : localStatusValue =
           localStatus ??
           const ClinicalSyncStatus(
             state: ClinicalSyncState.offlineAvailable,
             hasLocalContent: true,
             contentVersion: 'clinical-release-v1-test',
           ),
       syncStatusValue =
           syncStatus ??
           const ClinicalSyncStatus(
             state: ClinicalSyncState.current,
             hasLocalContent: true,
             contentVersion: 'clinical-release-v1-test',
           ),
       progressStatuses = progressStatuses ?? const <ClinicalSyncStatus>[];

  ClinicalSyncStatus localStatusValue;
  ClinicalSyncStatus syncStatusValue;
  List<ClinicalSyncStatus> progressStatuses;
  int localStatusCalls = 0;
  int syncCalls = 0;

  @override
  Future<ClinicalSyncStatus> localStatus() async {
    localStatusCalls += 1;
    return localStatusValue;
  }

  @override
  Future<ClinicalSyncStatus> syncIfNeeded({
    void Function(ClinicalSyncStatus status)? onStatus,
  }) async {
    syncCalls += 1;
    for (final status in progressStatuses) {
      onStatus?.call(status);
    }
    return syncStatusValue;
  }
}
